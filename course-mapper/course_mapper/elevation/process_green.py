"""
Processing pipeline for green elevation and contour generation.
"""
import logging
from typing import Optional
import numpy as np
from shapely.geometry import Polygon, MultiPolygon
import struct

from course_mapper.elevation.models import ElevationGrid
from course_mapper.elevation.provider import get_elevation_provider
from course_mapper.db import db
from course_mapper.config import settings

logger = logging.getLogger(__name__)


def pack_float32_array(arr: np.ndarray) -> bytes:
    """
    Pack a numpy float32 array into bytes (row-major order).
    
    Args:
        arr: 2D numpy array of float32 values
        
    Returns:
        Packed bytes representation
    """
    # Flatten to row-major order and pack as float32
    flattened = arr.flatten('C')  # 'C' = row-major (default)
    return flattened.astype(np.float32).tobytes()


def unpack_float32_array(data: bytes, rows: int, cols: int) -> np.ndarray:
    """
    Unpack bytes into a numpy float32 array (row-major order).
    
    Args:
        data: Packed bytes representation
        rows: Number of rows
        cols: Number of columns
        
    Returns:
        2D numpy array of float32 values
    """
    arr = np.frombuffer(data, dtype=np.float32)
    return arr.reshape((rows, cols), order='C')  # 'C' = row-major


def compute_gradient(elevations: np.ndarray, resolution_m: float) -> tuple:
    """
    Compute gradient (dz/dx, dz/dy) from elevation grid.
    
    Args:
        elevations: 2D array of elevation values
        resolution_m: Grid cell size in meters
        
    Returns:
        Tuple of (dz/dx, dz/dy) arrays (both in m/m, i.e., dimensionless)
    """
    # Compute gradients using numpy
    dy, dx = np.gradient(elevations, resolution_m, resolution_m)
    
    # Note: np.gradient returns derivatives in array index order
    # dy is the gradient along the first axis (rows, north-south)
    # dx is the gradient along the second axis (cols, east-west)
    
    return dx, dy  # Return in (dx, dy) order for clarity


def compute_slope_magnitude(dx: np.ndarray, dy: np.ndarray) -> np.ndarray:
    """
    Compute slope magnitude from gradient components.
    
    Slope magnitude = sqrt(dx^2 + dy^2), expressed as percent.
    
    Args:
        dx: Gradient in x direction (east-west)
        dy: Gradient in y direction (north-south)
        
    Returns:
        Slope magnitude as percent (0-100+)
    """
    # Slope magnitude = sqrt(dx^2 + dy^2) * 100 (convert to percent)
    slope = np.sqrt(dx**2 + dy**2) * 100.0
    return slope.astype(np.float32)


def compute_aspect(dx: np.ndarray, dy: np.ndarray) -> np.ndarray:
    """
    Compute aspect (direction of maximum descent) from gradient.
    
    Aspect is the direction water would flow (downhill).
    Returns angle in radians, where:
    - 0 = North
    - π/2 = East
    - π = South
    - 3π/2 = West
    
    Args:
        dx: Gradient in x direction (east-west, positive = east)
        dy: Gradient in y direction (north-south, positive = south in array coords)
        
    Returns:
        Aspect angle in radians (0-2π)
    """
    # Aspect = atan2(dx, dy)
    # But we need to handle the coordinate system:
    # - dy positive = south (increasing row index)
    # - dx positive = east (increasing col index)
    # - Aspect should point in direction of maximum descent
    
    # Compute angle: atan2(dx, dy) gives angle from north
    # Negative dy (going north) = 0 radians
    # Positive dx (going east) = positive angle
    aspect = np.arctan2(dx, -dy)  # Negative dy because north is "up"
    
    # Normalize to [0, 2π)
    aspect = np.where(aspect < 0, aspect + 2 * np.pi, aspect)
    
    return aspect.astype(np.float32)


def get_largest_polygon(geometry: Polygon | MultiPolygon) -> Polygon:
    """
    Extract the largest polygon from a MultiPolygon or return the polygon.
    
    Args:
        geometry: Polygon or MultiPolygon
        
    Returns:
        Largest polygon
    """
    if isinstance(geometry, MultiPolygon):
        # Find polygon with largest area
        largest = max(geometry.geoms, key=lambda p: p.area)
        return largest
    return geometry


def process_green_feature(
    course_feature_id: int,
    resolution_m: Optional[float] = None
) -> None:
    """
    Process a green feature: sample elevation, compute slopes/aspects, store in DB.
    
    Args:
        course_feature_id: ID of the course_feature row (must be feature_type='green')
        resolution_m: Grid resolution in meters (defaults to config value)
    """
    logger.info(f"Processing green feature {course_feature_id} at {resolution_m or settings.green_elevation_resolution_m}m resolution")
    
    # Get resolution
    resolution = resolution_m or settings.green_elevation_resolution_m
    
    # Step 1: Load the course feature
    query = """
    SELECT id, course_id, feature_type, ST_AsText(geom) as geom_wkt
    FROM course_features
    WHERE id = %s;
    """
    
    results = db.execute_query(query, (course_feature_id,))
    if not results:
        raise ValueError(f"Course feature {course_feature_id} not found")
    
    feature = results[0]
    
    if feature['feature_type'] != 'green':
        raise ValueError(f"Feature {course_feature_id} is not a green (type: {feature['feature_type']})")
    
    # Step 2: Parse geometry
    from shapely import wkt
    geometry = wkt.loads(feature['geom_wkt'])
    
    # Step 3: Extract largest polygon
    polygon = get_largest_polygon(geometry)
    
    logger.info(f"Processing green polygon with area: {polygon.area:.6f} square degrees")
    
    # Step 4: Sample elevation grid
    provider = get_elevation_provider()
    elevation_grid = provider.sample_grid(polygon, resolution)
    
    logger.info(f"Sampled elevation grid: {elevation_grid.rows}x{elevation_grid.cols}")
    logger.info(f"Elevation range: {elevation_grid.elevations.min():.2f}m - {elevation_grid.elevations.max():.2f}m")
    
    # Step 5: Compute gradients
    dx, dy = compute_gradient(elevation_grid.elevations, resolution)
    
    # Step 6: Compute slope magnitude and aspect
    slopes = compute_slope_magnitude(dx, dy)
    aspects = compute_aspect(dx, dy)
    
    logger.info(f"Slope range: {slopes.min():.2f}% - {slopes.max():.2f}%")
    
    # Step 7: Pack arrays for storage
    elevations_bytes = pack_float32_array(elevation_grid.elevations)
    slopes_bytes = pack_float32_array(slopes)
    aspects_bytes = pack_float32_array(aspects)
    
    # Step 8: Store or update in database (upsert behavior: delete old, insert new)
    # Delete existing record if present
    delete_query = """
    DELETE FROM green_elevation
    WHERE course_feature_id = %s;
    """
    db.execute_command(delete_query, (course_feature_id,))
    
    # Insert new record
    insert_query = """
    INSERT INTO green_elevation (
        course_feature_id, grid_rows, grid_cols,
        origin_lat, origin_lon, resolution_m,
        elevations, slopes, aspects
    )
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s);
    """
    
    db.execute_command(
        insert_query,
        (
            course_feature_id,
            elevation_grid.rows,
            elevation_grid.cols,
            elevation_grid.origin_lat,
            elevation_grid.origin_lon,
            elevation_grid.resolution_m,
            elevations_bytes,
            slopes_bytes,
            aspects_bytes
        )
    )
    
    logger.info(f"✅ Successfully processed green feature {course_feature_id}")

