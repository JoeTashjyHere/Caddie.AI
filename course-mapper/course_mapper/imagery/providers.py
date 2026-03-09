"""
Pluggable imagery provider abstraction for fetching satellite imagery.
Supports Mapbox, Google, Bing, and other tile services.
"""
import logging
from abc import ABC, abstractmethod
from typing import Tuple, Optional
from io import BytesIO
import numpy as np
from PIL import Image
import requests

from course_mapper.config import settings

logger = logging.getLogger(__name__)


class ImageryProvider(ABC):
    """Abstract base class for imagery providers."""
    
    @abstractmethod
    def fetch_image(
        self,
        bounds: Tuple[float, float, float, float],  # min_lat, min_lon, max_lat, max_lon
        zoom_level: int = 18,
        width: int = 2048,
        height: int = 2048
    ) -> np.ndarray:
        """
        Fetch satellite imagery for a bounding box.
        
        Args:
            bounds: Geographic bounds (min_lat, min_lon, max_lat, max_lon)
            zoom_level: Tile zoom level
            width: Image width in pixels
            height: Image height in pixels
            
        Returns:
            RGB image array (H, W, 3) as numpy array
        """
        pass


class MapboxProvider(ImageryProvider):
    """Mapbox Static Images API provider."""
    
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or settings.mapbox_api_key or settings.satellite_api_key
        if not self.api_key:
            raise ValueError("Mapbox API key required. Set MAPBOX_API_KEY or SATELLITE_API_KEY in .env")
        self.base_url = "https://api.mapbox.com/styles/v1/mapbox/satellite-v9/static"
    
    def fetch_image(
        self,
        bounds: Tuple[float, float, float, float],
        zoom_level: int = 18,
        width: int = 2048,
        height: int = 2048
    ) -> np.ndarray:
        """Fetch satellite imagery from Mapbox."""
        min_lat, min_lon, max_lat, max_lon = bounds
        
        # Calculate center and bbox
        center_lat = (min_lat + max_lat) / 2
        center_lon = (min_lon + max_lon) / 2
        
        # Mapbox format: [min_lon,min_lat,max_lon,max_lat]
        bbox = f"{min_lon},{min_lat},{max_lon},{max_lat}"
        
        url = f"{self.base_url}/{bbox}/{width}x{height}@{2}x"
        params = {
            "access_token": self.api_key
        }
        
        logger.info(f"Fetching Mapbox imagery: {url[:100]}...")
        
        try:
            response = requests.get(url, params=params, timeout=30)
            response.raise_for_status()
            
            # Load image
            img = Image.open(BytesIO(response.content))
            img_rgb = img.convert('RGB')
            
            # Convert to numpy array
            img_array = np.array(img_rgb, dtype=np.uint8)
            
            logger.info(f"Successfully fetched image: {img_array.shape}")
            return img_array
            
        except Exception as e:
            logger.error(f"Error fetching Mapbox imagery: {e}")
            raise


class GoogleMapsProvider(ImageryProvider):
    """Google Maps Static API provider."""
    
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or settings.google_maps_api_key or settings.satellite_api_key
        if not self.api_key:
            raise ValueError("Google Maps API key required. Set GOOGLE_MAPS_API_KEY or SATELLITE_API_KEY in .env")
        self.base_url = "https://maps.googleapis.com/maps/api/staticmap"
    
    def fetch_image(
        self,
        bounds: Tuple[float, float, float, float],
        zoom_level: int = 18,
        width: int = 2048,
        height: int = 2048
    ) -> np.ndarray:
        """Fetch satellite imagery from Google Maps."""
        min_lat, min_lon, max_lat, max_lon = bounds
        center_lat = (min_lat + max_lat) / 2
        center_lon = (min_lon + max_lon) / 2
        
        params = {
            "center": f"{center_lat},{center_lon}",
            "zoom": zoom_level,
            "size": f"{width}x{height}",
            "maptype": "satellite",
            "key": self.api_key
        }
        
        logger.info(f"Fetching Google Maps imagery for center: {center_lat}, {center_lon}")
        
        try:
            response = requests.get(self.base_url, params=params, timeout=30)
            response.raise_for_status()
            
            img = Image.open(BytesIO(response.content))
            img_rgb = img.convert('RGB')
            img_array = np.array(img_rgb, dtype=np.uint8)
            
            logger.info(f"Successfully fetched Google Maps image: {img_array.shape}")
            return img_array
            
        except Exception as e:
            logger.error(f"Error fetching Google Maps imagery: {e}")
            raise


def get_imagery_provider() -> ImageryProvider:
    """
    Factory function to get the configured imagery provider.
    
    Checks IMAGERY_PROVIDER env var and returns appropriate provider.
    """
    provider_name = settings.imagery_provider.lower() if hasattr(settings, 'imagery_provider') else 'mapbox'
    
    if provider_name == 'mapbox':
        return MapboxProvider()
    elif provider_name == 'google':
        return GoogleMapsProvider()
    else:
        raise ValueError(f"Unknown imagery provider: {provider_name}. Set IMAGERY_PROVIDER to 'mapbox' or 'google'")

