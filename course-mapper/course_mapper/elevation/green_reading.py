"""
Green reading algorithm: computes aim line and break path using elevation/slope data.
"""
import logging
from typing import List, Tuple, Optional
import numpy as np
from shapely.geometry import Point

from course_mapper.elevation.process_green import unpack_float32_array
from course_mapper.db import db

logger = logging.getLogger(__name__)


def latlon_to_grid(
    lat: float,
    lon: float,
    origin_lat: float,
    origin_lon: float,
    resolution_m: float
) -> Tuple[int, int]:
    """
    Convert geographic coordinates to grid row/col indices.
    
    Args:
        lat: Latitude
        lon: Longitude
        origin_lat: Grid origin latitude (northwest corner)
        origin_lon: Grid origin longitude (northwest corner)
        resolution_m: Grid cell size in meters
        
    Returns:
        Tuple of (row, col) indices
    """
    # Calculate offsets in degrees
    lat_offset = origin_lat - lat  # Positive = south of origin
    lon_offset = lon - origin_lon  # Positive = east of origin
    
    # Convert to meters
    # 1 degree latitude ≈ 111,000 meters
    # 1 degree longitude ≈ 111,000 * cos(latitude) meters
    avg_lat = (origin_lat + lat) / 2
    lat_m = lat_offset * 111000.0
    lon_m = lon_offset * 111000.0 * abs(abs(avg_lat) * 3.14159 / 180)
    
    # Convert to grid indices
    row = int(round(lat_m / resolution_m))
    col = int(round(lon_m / resolution_m))
    
    return row, col


def grid_to_latlon(
    row: int,
    col: int,
    origin_lat: float,
    origin_lon: float,
    resolution_m: float
) -> Tuple[float, float]:
    """
    Convert grid row/col indices to geographic coordinates.
    
    Args:
        row: Row index (0 = north, increases southward)
        col: Column index (0 = west, increases eastward)
        origin_lat: Grid origin latitude
        origin_lon: Grid origin longitude
        resolution_m: Grid cell size in meters
        
    Returns:
        Tuple of (latitude, longitude)
    """
    # Convert indices to meters
    lat_m = row * resolution_m
    lon_m = col * resolution_m
    
    # Convert to degrees
    lat_offset_deg = lat_m / 111000.0
    # Use origin latitude for longitude conversion (approximate)
    lon_offset_deg = lon_m / (111000.0 * abs(abs(origin_lat) * 3.14159 / 180))
    
    # Calculate final coordinates
    lat = origin_lat - lat_offset_deg  # Negative because row increases southward
    lon = origin_lon + lon_offset_deg  # Positive because col increases eastward
    
    return lat, lon


def get_slope_at_grid_point(
    slopes: np.ndarray,
    aspects: np.ndarray,
    row: int,
    col: int,
    rows: int,
    cols: int
) -> Tuple[float, float, float]:
    """
    Get slope magnitude and gradient components at a grid point.
    
    Args:
        slopes: Slope magnitude array (percent)
        aspects: Aspect angle array (radians)
        row: Row index
        col: Column index
        rows: Total number of rows
        cols: Total number of columns
        
    Returns:
        Tuple of (slope_percent, dx_component, dy_component)
        where dx/dy are normalized gradient components
    """
    # Clamp indices to valid range
    row = max(0, min(rows - 1, row))
    col = max(0, min(cols - 1, col))
    
    slope = float(slopes[row, col])
    aspect = float(aspects[row, col])
    
    # Convert aspect angle to gradient components
    # aspect = 0 = north (dy negative), aspect = π/2 = east (dx positive)
    dx = np.sin(aspect)  # East component
    dy = -np.cos(aspect)  # North component (negative because aspect points downhill)
    
    return slope, dx, dy


def compute_break_path(
    ball_row: float,
    ball_col: float,
    hole_row: float,
    hole_col: float,
    slopes: np.ndarray,
    aspects: np.ndarray,
    rows: int,
    cols: int,
    resolution_m: float,
    step_size_m: float = 0.1,
    max_iterations: int = 1000,
    break_factor: float = 0.3
) -> List[Tuple[float, float]]:
    """
    Compute the break path from ball to hole using slope/aspect data.
    
    Uses a simple integration method that combines:
    - Movement toward the hole
    - Downhill movement along the gradient
    
    Args:
        ball_row: Starting row (float for sub-grid precision)
        ball_col: Starting column
        hole_row: Target row
        hole_col: Target column
        slopes: Slope magnitude array
        aspects: Aspect angle array
        rows: Grid rows
        cols: Grid columns
        resolution_m: Grid resolution in meters
        step_size_m: Step size for integration (meters)
        max_iterations: Maximum path points
        break_factor: How much the ball breaks (0-1, higher = more break)
        
    Returns:
        List of (row, col) positions along the path
    """
    path = []
    current_row = float(ball_row)
    current_col = float(ball_col)
    
    path.append((current_row, current_col))
    
    for i in range(max_iterations):
        # Check if we've reached the hole (within one grid cell)
        dist_to_hole = np.sqrt((current_row - hole_row)**2 + (current_col - hole_col)**2)
        if dist_to_hole * resolution_m < 0.1:  # Within 0.1m
            path.append((hole_row, hole_col))
            break
        
        # Get direction toward hole (normalized)
        dir_to_hole_row = hole_row - current_row
        dir_to_hole_col = hole_col - current_col
        dist_to_hole_grid = np.sqrt(dir_to_hole_row**2 + dir_to_hole_col**2)
        
        if dist_to_hole_grid < 0.01:  # Very close, stop
            break
        
        dir_to_hole_row /= dist_to_hole_grid
        dir_to_hole_col /= dist_to_hole_grid
        
        # Get slope and gradient at current position
        int_row = int(round(current_row))
        int_col = int(round(current_col))
        
        slope, dx, dy = get_slope_at_grid_point(slopes, aspects, int_row, int_col, rows, cols)
        
        # Combine movement: (1 - break_factor) toward hole + break_factor downhill
        # The break factor scales with slope (more break on steeper slopes)
        slope_normalized = min(slope / 10.0, 1.0)  # Normalize to 0-1 (assuming max 10% slope)
        effective_break = break_factor * slope_normalized
        
        # Movement direction = weighted combination
        move_row = (1 - effective_break) * dir_to_hole_row + effective_break * dy
        move_col = (1 - effective_break) * dir_to_hole_col + effective_break * dx
        
        # Normalize movement vector
        move_mag = np.sqrt(move_row**2 + move_col**2)
        if move_mag > 0:
            move_row /= move_mag
            move_col /= move_mag
        
        # Step in grid space
        step_grid = step_size_m / resolution_m
        current_row += move_row * step_grid
        current_col += move_col * step_grid
        
        path.append((current_row, current_col))
    
    return path


def compute_aim_line(
    ball_lat: float,
    ball_lon: float,
    hole_lat: float,
    hole_lon: float,
    origin_lat: float,
    origin_lon: float,
    resolution_m: float,
    slopes: np.ndarray,
    aspects: np.ndarray,
    rows: int,
    cols: int
) -> Tuple[List[Tuple[float, float]], float]:
    """
    Compute the aim line (break path) and aim offset.
    
    Args:
        ball_lat: Ball latitude
        ball_lon: Ball longitude
        hole_lat: Hole latitude
        hole_lon: Hole longitude
        origin_lat: Grid origin latitude
        origin_lon: Grid origin longitude
        resolution_m: Grid resolution
        slopes: Slope magnitude array
        aspects: Aspect angle array
        rows: Grid rows
        cols: Grid columns
        
    Returns:
        Tuple of:
        - List of (lat, lon) points along the aim line
        - Aim offset in feet (positive = right of direct line, negative = left)
    """
    # Convert to grid coordinates
    ball_row, ball_col = latlon_to_grid(ball_lat, ball_lon, origin_lat, origin_lon, resolution_m)
    hole_row, hole_col = latlon_to_grid(hole_lat, hole_lon, origin_lat, origin_lon, resolution_m)
    
    # Compute break path
    path_grid = compute_break_path(
        float(ball_row), float(ball_col),
        float(hole_row), float(hole_col),
        slopes, aspects, rows, cols, resolution_m
    )
    
    # Convert path back to lat/lon
    aim_line = []
    for row, col in path_grid:
        lat, lon = grid_to_latlon(int(round(row)), int(round(col)), origin_lat, origin_lon, resolution_m)
        aim_line.append((lat, lon))
    
    # Calculate aim offset at the start (perpendicular distance from direct line)
    # Direct line: ball to hole
    direct_row = hole_row - ball_row
    direct_col = hole_col - ball_col
    
    if len(path_grid) > 1:
        # First step direction
        first_step_row = path_grid[1][0] - path_grid[0][0]
        first_step_col = path_grid[1][1] - path_grid[0][1]
        
        # Calculate perpendicular offset
        # Cross product to find perpendicular component
        cross = direct_row * first_step_col - direct_col * first_step_row
        offset_grid = abs(cross) / np.sqrt(direct_row**2 + direct_col**2) if (direct_row**2 + direct_col**2) > 0 else 0
        
        # Convert to feet
        offset_feet = (offset_grid * resolution_m) / 0.3048  # meters to feet
        
        # Determine sign (positive = right, negative = left)
        # Use the cross product sign
        if cross < 0:
            offset_feet = -offset_feet
    else:
        offset_feet = 0.0
    
    return aim_line, offset_feet


def compute_fall_line_from_hole(
    hole_lat: float,
    hole_lon: float,
    origin_lat: float,
    origin_lon: float,
    resolution_m: float,
    slopes: np.ndarray,
    aspects: np.ndarray,
    rows: int,
    cols: int,
    distance_m: float = 5.0,
    step_size_m: float = 0.1
) -> List[Tuple[float, float]]:
    """
    Compute fall line (downhill path) from the hole.
    
    Args:
        hole_lat: Hole latitude
        hole_lon: Hole longitude
        origin_lat: Grid origin latitude
        origin_lon: Grid origin longitude
        resolution_m: Grid resolution
        slopes: Slope magnitude array
        aspects: Aspect angle array
        rows: Grid rows
        cols: Grid columns
        distance_m: How far to trace the fall line (meters)
        step_size_m: Step size for integration
        
    Returns:
        List of (lat, lon) points along the fall line
    """
    hole_row, hole_col = latlon_to_grid(hole_lat, hole_lon, origin_lat, origin_lon, resolution_m)
    
    fall_line = []
    current_row = float(hole_row)
    current_col = float(hole_col)
    
    fall_line.append((hole_lat, hole_lon))
    
    steps = int(distance_m / step_size_m)
    
    for _ in range(steps):
        int_row = int(round(current_row))
        int_col = int(round(current_col))
        
        # Get gradient direction
        _, dx, dy = get_slope_at_grid_point(slopes, aspects, int_row, int_col, rows, cols)
        
        # Move downhill (opposite of gradient, since gradient points uphill)
        step_grid = step_size_m / resolution_m
        current_row += -dy * step_grid
        current_col += -dx * step_grid
        
        # Convert to lat/lon
        lat, lon = grid_to_latlon(int(round(current_row)), int(round(current_col)), origin_lat, origin_lon, resolution_m)
        fall_line.append((lat, lon))
        
        # Check bounds
        if int_row < 0 or int_row >= rows or int_col < 0 or int_col >= cols:
            break
    
    return fall_line


def get_slope_at_position(
    lat: float,
    lon: float,
    origin_lat: float,
    origin_lon: float,
    resolution_m: float,
    slopes: np.ndarray,
    rows: int,
    cols: int
) -> float:
    """Get slope at a specific geographic position."""
    row, col = latlon_to_grid(lat, lon, origin_lat, origin_lon, resolution_m)
    row = max(0, min(rows - 1, row))
    col = max(0, min(cols - 1, col))
    return float(slopes[row, col])



