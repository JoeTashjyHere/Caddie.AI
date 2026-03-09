"""
Data models for elevation grids and related structures.
"""
from dataclasses import dataclass
from typing import Optional
import numpy as np
from shapely.geometry import Polygon


@dataclass
class ElevationGrid:
    """
    Represents a sampled elevation grid over a polygon region.
    
    Attributes:
        elevations: 2D numpy array of elevation values in meters (float32)
        origin_lat: Latitude of the top-left corner (northwest corner) of the grid
        origin_lon: Longitude of the top-left corner of the grid
        resolution_m: Grid cell size in meters
        polygon: Original polygon that was sampled
        metadata: Optional metadata dict (EPSG, CRS info, etc.)
    """
    elevations: np.ndarray  # Shape: (rows, cols), dtype: float32
    origin_lat: float
    origin_lon: float
    resolution_m: float
    polygon: Polygon
    metadata: Optional[dict] = None
    
    @property
    def rows(self) -> int:
        """Number of rows in the grid."""
        return self.elevations.shape[0]
    
    @property
    def cols(self) -> int:
        """Number of columns in the grid."""
        return self.elevations.shape[1]
    
    @property
    def shape(self) -> tuple:
        """Grid shape (rows, cols)."""
        return self.elevations.shape
    
    def get_cell_center(self, row: int, col: int) -> tuple[float, float]:
        """
        Get the geographic coordinates of a grid cell center.
        
        Args:
            row: Row index (0-based, from north to south)
            col: Column index (0-based, from west to east)
            
        Returns:
            Tuple of (latitude, longitude)
        """
        # Approximate: 1 degree latitude ≈ 111,000 meters
        # 1 degree longitude ≈ 111,000 * cos(latitude) meters
        lat_offset = (row + 0.5) * self.resolution_m / 111000.0
        lon_offset = (col + 0.5) * self.resolution_m / (111000.0 * abs(abs(self.origin_lat) * 3.14159 / 180))
        
        lat = self.origin_lat - lat_offset  # Negative because row increases southward
        lon = self.origin_lon + lon_offset  # Positive because col increases eastward
        
        return (lat, lon)



