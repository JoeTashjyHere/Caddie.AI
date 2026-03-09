"""
Elevation provider abstraction for fetching elevation data from various sources.
"""
import logging
from abc import ABC, abstractmethod
from typing import Protocol, Optional
import numpy as np
from shapely.geometry import Polygon

from course_mapper.elevation.models import ElevationGrid
from course_mapper.config import settings

logger = logging.getLogger(__name__)


class ElevationProvider(Protocol):
    """
    Protocol for elevation data providers.
    
    Implementations should provide a method to sample elevation data
    over a polygon region at a specified resolution.
    """
    
    @abstractmethod
    def sample_grid(
        self,
        polygon: Polygon,
        resolution_m: float = 1.0
    ) -> ElevationGrid:
        """
        Sample elevation data for a polygon region.
        
        Args:
            polygon: Shapely polygon in WGS84 (EPSG:4326)
            resolution_m: Desired grid resolution in meters
            
        Returns:
            ElevationGrid with sampled elevation data
        """
        ...


class SyntheticElevationProvider:
    """
    Synthetic elevation provider for testing.
    
    Generates a sloped plane with realistic green-like contours.
    Useful for development/testing when real elevation APIs are unavailable.
    """
    
    def sample_grid(
        self,
        polygon: Polygon,
        resolution_m: float = 1.0
    ) -> ElevationGrid:
        """
        Generate a synthetic elevation grid with realistic green slopes.
        
        Creates a sloped plane with some gentle undulations to simulate
        a real green surface.
        """
        # Get bounding box
        minx, miny, maxx, maxy = polygon.bounds
        origin_lon = minx
        origin_lat = maxy  # Top-left corner (northwest)
        
        # Calculate grid dimensions in meters
        # Approximate: 1 degree ≈ 111 km
        width_deg = maxx - minx
        height_deg = maxy - miny
        
        width_m = width_deg * 111000.0 * abs(abs((miny + maxy) / 2) * 3.14159 / 180)
        height_m = height_deg * 111000.0
        
        # Calculate grid size
        cols = int(np.ceil(width_m / resolution_m))
        rows = int(np.ceil(height_m / resolution_m))
        
        logger.info(f"Generating synthetic elevation grid: {rows}x{cols} at {resolution_m}m resolution")
        
        # Create coordinate arrays
        x = np.linspace(0, width_m, cols)
        y = np.linspace(0, height_m, rows)
        X, Y = np.meshgrid(x, y)
        
        # Generate synthetic elevation: sloped plane with gentle undulations
        # Base elevation (meters)
        base_elevation = 100.0
        
        # Create a sloped plane (lower in one corner, simulating a green)
        # Slope: -2% gradient from northwest to southeast
        slope_x = -0.02 * X / width_m  # 2% slope in X direction
        slope_y = -0.015 * Y / height_m  # 1.5% slope in Y direction
        
        # Add gentle undulations (sinusoidal waves to simulate green contours)
        wave_x = 0.05 * np.sin(2 * np.pi * X / (width_m / 2))
        wave_y = 0.03 * np.sin(2 * np.pi * Y / (height_m / 2))
        
        # Combine components
        elevations = (base_elevation + 
                     slope_x * 10 +  # Scale to meters
                     slope_y * 10 +
                     wave_x +
                     wave_y)
        
        # Ensure minimum elevation
        elevations = np.maximum(elevations, base_elevation - 5)
        
        # Convert to float32 for storage efficiency
        elevations = elevations.astype(np.float32)
        
        return ElevationGrid(
            elevations=elevations,
            origin_lat=origin_lat,
            origin_lon=origin_lon,
            resolution_m=resolution_m,
            polygon=polygon,
            metadata={
                'provider': 'synthetic',
                'description': 'Synthetic sloped plane for testing'
            }
        )


class MapboxElevationProvider:
    """
    Mapbox Elevation API provider.
    
    Fetches elevation data from Mapbox's elevation tile service.
    Requires MAPBOX_API_KEY to be set.
    """
    
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or settings.mapbox_api_key or settings.elevation_api_key
        if not self.api_key:
            raise ValueError("Mapbox API key required. Set MAPBOX_API_KEY or ELEVATION_API_KEY in .env")
        self.base_url = "https://api.mapbox.com/v4/mapbox.terrain-rgb"
    
    def sample_grid(
        self,
        polygon: Polygon,
        resolution_m: float = 1.0
    ) -> ElevationGrid:
        """
        Fetch elevation data from Mapbox terrain-rgb tiles.
        
        Note: This is a stub implementation. Mapbox terrain-rgb tiles
        encode elevation in RGB values. A full implementation would:
        1. Calculate required tile bounds and zoom level
        2. Fetch terrain-rgb tiles
        3. Decode RGB values to elevation (formula: -10000 + (R*256*256 + G*256 + B)*0.1)
        4. Resample to desired grid resolution
        
        For now, falls back to synthetic provider.
        """
        logger.warning("Mapbox elevation provider not fully implemented, using synthetic data")
        synthetic = SyntheticElevationProvider()
        return synthetic.sample_grid(polygon, resolution_m)


class USGSElevationProvider:
    """
    USGS 3D Elevation Program (3DEP) provider.
    
    Fetches elevation data from USGS public elevation services.
    No API key required.
    """
    
    def sample_grid(
        self,
        polygon: Polygon,
        resolution_m: float = 1.0
    ) -> ElevationGrid:
        """
        Fetch elevation data from USGS 3DEP services.
        
        Note: This is a stub implementation. A full implementation would:
        1. Query USGS 3DEP API for available datasets
        2. Request elevation data for bounding box
        3. Resample to desired grid resolution
        
        For now, falls back to synthetic provider.
        """
        logger.warning("USGS elevation provider not fully implemented, using synthetic data")
        synthetic = SyntheticElevationProvider()
        return synthetic.sample_grid(polygon, resolution_m)


def get_elevation_provider() -> ElevationProvider:
    """
    Factory function to get the configured elevation provider.
    
    Checks ELEVATION_PROVIDER env var and returns appropriate provider.
    Defaults to 'synthetic' for development/testing.
    """
    provider_name = getattr(settings, 'elevation_provider', 'synthetic').lower()
    
    if provider_name == 'synthetic':
        return SyntheticElevationProvider()
    elif provider_name == 'mapbox':
        return MapboxElevationProvider()
    elif provider_name == 'usgs':
        return USGSElevationProvider()
    else:
        logger.warning(f"Unknown elevation provider: {provider_name}, using synthetic")
        return SyntheticElevationProvider()



