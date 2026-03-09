"""
Configuration management for course-mapper service.
Loads from environment variables with sensible defaults.
"""
import os
from typing import Optional
from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""
    
    # Database
    database_url: str = Field(
        default="postgresql://postgres:postgres@localhost:5432/caddie_golf",
        description="PostgreSQL connection string with PostGIS extension"
    )
    
    # OpenAI API (for future AI features)
    openai_api_key: Optional[str] = Field(
        default=None,
        description="OpenAI API key for AI features"
    )
    
    # Overpass API (for OSM data)
    overpass_api_url: str = Field(
        default="https://overpass-api.de/api/interpreter",
        description="Overpass API endpoint for OSM queries"
    )
    
    # Satellite imagery API
    imagery_provider: str = Field(
        default="mapbox",
        description="Imagery provider: 'mapbox' or 'google'"
    )
    
    satellite_api_key: Optional[str] = Field(
        default=None,
        description="Satellite imagery provider API key (generic)"
    )
    
    mapbox_api_key: Optional[str] = Field(
        default=None,
        description="Mapbox API key"
    )
    
    google_maps_api_key: Optional[str] = Field(
        default=None,
        description="Google Maps API key"
    )
    
    # Segmentation settings
    segmentation_bounding_box_km: float = Field(
        default=2.0,
        description="Bounding box size in kilometers around course location"
    )
    
    segmentation_min_area_pixels: int = Field(
        default=100,
        description="Minimum polygon area in pixels to filter noise"
    )
    
    # Elevation/LIDAR API
    elevation_provider: str = Field(
        default="synthetic",
        description="Elevation provider: 'synthetic', 'mapbox', or 'usgs'"
    )
    
    elevation_api_key: Optional[str] = Field(
        default=None,
        description="Elevation data provider API key (for Mapbox, etc.)"
    )
    
    # Green processing settings
    green_elevation_resolution_m: float = Field(
        default=1.0,
        description="Default resolution in meters for green elevation grids"
    )
    
    # Storage
    contour_storage_url: str = Field(
        default="file://./storage/contours",
        description="URL or path for storing contour rasters"
    )
    
    # API Server
    api_host: str = Field(
        default="0.0.0.0",
        description="FastAPI server host"
    )
    
    api_port: int = Field(
        default=8081,
        description="FastAPI server port (8081 to avoid conflict with Node backend)"
    )
    
    # Logging
    log_level: str = Field(
        default="INFO",
        description="Logging level"
    )
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


# Global settings instance
settings = Settings()

