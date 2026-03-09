"""
FastAPI server for course-mapper API.

Provides endpoints for:
- Finding nearby courses
- Getting hole layouts (GeoJSON)
- Green contours and elevation data
"""
import logging
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import json
from shapely import wkt
from shapely.geometry import mapping

from course_mapper.config import settings
from course_mapper.db import db
from course_mapper.elevation.process_green import unpack_float32_array
from course_mapper.api import green_reading
import numpy as np

logging.basicConfig(level=getattr(logging, settings.log_level))
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Caddie.AI Course Mapper API",
    description="API for golf course mapping and GPS tracking",
    version="0.1.0"
)

# CORS middleware for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to specific domains
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include green reading router
app.include_router(green_reading.router)


# Pydantic models for API responses
class CourseSummary(BaseModel):
    id: str
    name: str
    distance_km: float
    city: Optional[str] = None
    country: Optional[str] = None


class Hole(BaseModel):
    number: int
    par: Optional[int] = None
    handicap: Optional[int] = None
    tee_yardages: Optional[dict] = None


class GeoJSONGeometry(BaseModel):
    type: str
    coordinates: List


class GeoJSONFeature(BaseModel):
    type: str = "Feature"
    geometry: GeoJSONGeometry
    properties: dict = {}


class GeoJSONFeatureCollection(BaseModel):
    type: str = "FeatureCollection"
    features: List[GeoJSONFeature]


class HoleLayoutResponse(BaseModel):
    greens: List[GeoJSONFeature] = []
    fairways: List[GeoJSONFeature] = []
    bunkers: List[GeoJSONFeature] = []
    water: List[GeoJSONFeature] = []
    tees: List[GeoJSONFeature] = []


class GreenContourResponse(BaseModel):
    contour_raster_url: Optional[str] = None
    metadata: dict = {}


def geometry_to_geojson(geom_wkt: str) -> Optional[dict]:
    """Convert PostGIS geometry WKT to GeoJSON."""
    try:
        geom = wkt.loads(geom_wkt)
        return mapping(geom)
    except Exception as e:
        logger.error(f"Error converting geometry to GeoJSON: {e}")
        return None


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    try:
        db.check_postgis()
        return {"status": "ok", "service": "course-mapper-api"}
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=503, detail="Database connection failed")


@app.get("/courses/nearby", response_model=List[CourseSummary])
async def get_nearby_courses(
    lat: float = Query(..., description="Latitude"),
    lon: float = Query(..., description="Longitude"),
    radius_km: float = Query(10.0, description="Search radius in kilometers")
):
    """
    Find courses near a location.
    
    Returns list of courses sorted by distance.
    """
    try:
        query = """
        SELECT 
            id,
            name,
            city,
            country,
            ST_Distance(
                location,
                ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography
            ) / 1000.0 AS distance_km
        FROM courses
        WHERE ST_DWithin(
            location,
            ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography,
            %s * 1000
        )
        ORDER BY distance_km
        LIMIT 50;
        """
        
        results = db.execute_query(query, (lon, lat, lon, lat, radius_km))
        
        courses = []
        for row in results:
            courses.append(CourseSummary(
                id=str(row['id']),
                name=row['name'],
                distance_km=float(row['distance_km']),
                city=row.get('city'),
                country=row.get('country')
            ))
        
        return courses
        
    except Exception as e:
        logger.error(f"Error fetching nearby courses: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/courses/{course_id}/holes", response_model=List[Hole])
async def get_course_holes(course_id: str):
    """Get all holes for a course."""
    try:
        query = """
        SELECT number, par, handicap, tee_yardages
        FROM holes
        WHERE course_id = %s
        ORDER BY number;
        """
        
        results = db.execute_query(query, (course_id,))
        
        holes = []
        for row in results:
            holes.append(Hole(
                number=row['number'],
                par=row.get('par'),
                handicap=row.get('handicap'),
                tee_yardages=row.get('tee_yardages')
            ))
        
        return holes
        
    except Exception as e:
        logger.error(f"Error fetching holes: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/courses/{course_id}/holes/{hole_number}/layout", response_model=HoleLayoutResponse)
async def get_hole_layout(course_id: str, hole_number: int):
    """
    Get hole layout as GeoJSON features grouped by geometry type.
    
    Merges data from:
    - hole_geometries table (OSM/manual data)
    - course_features table (satellite segmentation)
    
    Returns greens, fairways, bunkers, water hazards, and tee boxes.
    """
    try:
        layout = HoleLayoutResponse()
        
        # Get hole ID if holes table exists
        hole_id = None
        try:
            hole_query = """
            SELECT id FROM holes
            WHERE course_id = %s AND number = %s;
            """
            hole_results = db.execute_query(hole_query, (course_id, hole_number))
            if hole_results:
                hole_id = str(hole_results[0]['id'])
        except Exception as e:
            logger.debug(f"Holes table query failed (may not exist): {e}")
        
        # Get geometries from hole_geometries table (OSM/manual)
        if hole_id:
            geom_query = """
            SELECT geom_type, ST_AsText(geometry) as geom_wkt
            FROM hole_geometries
            WHERE hole_id = %s;
            """
            geom_results = db.execute_query(geom_query, (hole_id,))
            
            for row in geom_results:
                geom_type = row['geom_type']
                geom_wkt = row['geom_wkt']
                geojson_geom = geometry_to_geojson(geom_wkt)
                
                if not geojson_geom:
                    continue
                
                feature = GeoJSONFeature(
                    geometry=GeoJSONGeometry(
                        type=geojson_geom['type'],
                        coordinates=geojson_geom['coordinates']
                    ),
                    properties={'type': geom_type, 'source': 'osm'}
                )
                
                # Add to appropriate list
                if geom_type == 'green':
                    layout.greens.append(feature)
                elif geom_type == 'fairway':
                    layout.fairways.append(feature)
                elif geom_type == 'bunker':
                    layout.bunkers.append(feature)
                elif geom_type == 'water':
                    layout.water.append(feature)
                elif geom_type == 'tee_box':
                    layout.tees.append(feature)
        
        # Get geometries from course_features table (satellite segmentation)
        # Try hole-specific first, then fall back to course-level
        feature_query = """
        SELECT feature_type, ST_AsGeoJSON(geom) as geojson
        FROM course_features
        WHERE course_id = %s 
          AND (hole_number = %s OR hole_number IS NULL)
          AND feature_type IN ('green', 'fairway', 'bunker', 'water', 'tee_box')
        ORDER BY hole_number NULLS LAST;
        """
        
        try:
            feature_results = db.execute_query(feature_query, (course_id, hole_number))
            
            for row in feature_results:
                geom_type = row['feature_type']
                geojson_str = row['geojson']
                
                try:
                    geojson_data = json.loads(geojson_str)
                    feature = GeoJSONFeature(
                        geometry=GeoJSONGeometry(
                            type=geojson_data['type'],
                            coordinates=geojson_data['coordinates']
                        ),
                        properties={'type': geom_type, 'source': 'satellite'}
                    )
                    
                    # Add to appropriate list (only if not already present from OSM)
                    if geom_type == 'green' and not layout.greens:
                        layout.greens.append(feature)
                    elif geom_type == 'fairway' and not layout.fairways:
                        layout.fairways.append(feature)
                    elif geom_type == 'bunker':
                        layout.bunkers.append(feature)
                    elif geom_type == 'water':
                        layout.water.append(feature)
                    elif geom_type == 'tee_box' and not layout.tees:
                        layout.tees.append(feature)
                        
                except Exception as e:
                    logger.warning(f"Error parsing GeoJSON for {geom_type}: {e}")
                    continue
                    
        except Exception as e:
            logger.debug(f"course_features table query failed (may not exist): {e}")
        
        return layout
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching hole layout: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/courses/{course_id}/features")
async def get_course_features(course_id: str):
    """
    Get all course features (GeoJSON) for a course.
    
    Debug endpoint for visualizing segmented course features.
    Returns GeoJSON FeatureCollection with all greens, fairways, bunkers, etc.
    """
    try:
        # Get features from course_features table
        query = """
        SELECT 
            id,
            feature_type,
            hole_number,
            ST_AsGeoJSON(geom) as geojson
        FROM course_features
        WHERE course_id = %s
        ORDER BY feature_type, hole_number NULLS FIRST;
        """
        
        results = db.execute_query(query, (course_id,))
        
        if not results:
            # Return empty FeatureCollection
            return {
                "type": "FeatureCollection",
                "features": []
            }
        
        features = []
        for row in results:
            try:
                geojson_data = json.loads(row['geojson'])
                feature = {
                    "type": "Feature",
                    "geometry": geojson_data,
                    "properties": {
                        "id": row['id'],
                        "feature_type": row['feature_type'],
                        "hole_number": row.get('hole_number')
                    }
                }
                features.append(feature)
            except Exception as e:
                logger.warning(f"Error parsing GeoJSON for feature {row['id']}: {e}")
                continue
        
        return {
            "type": "FeatureCollection",
            "features": features
        }
        
    except Exception as e:
        logger.error(f"Error fetching course features: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/courses/{course_id}/holes/{hole_number}/green-contours", response_model=GreenContourResponse)
async def get_green_contours(course_id: str, hole_number: int):
    """
    Get green contour data and elevation statistics.
    
    Returns contour raster URL and metadata (slope, elevation stats).
    """
    try:
        # Get hole ID
        hole_query = """
        SELECT id FROM holes
        WHERE course_id = %s AND number = %s;
        """
        hole_results = db.execute_query(hole_query, (course_id, hole_number))
        
        if not hole_results:
            raise HTTPException(status_code=404, detail=f"Hole {hole_number} not found")
        
        hole_id = str(hole_results[0]['id'])
        
        # Get contour data
        contour_query = """
        SELECT contour_raster_url, metadata
        FROM green_contours
        WHERE hole_id = %s;
        """
        contour_results = db.execute_query(contour_query, (hole_id,))
        
        if not contour_results:
            return GreenContourResponse()  # Return empty if no contours
        
        row = contour_results[0]
        return GreenContourResponse(
            contour_raster_url=row.get('contour_raster_url'),
            metadata=row.get('metadata') or {}
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching green contours: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/greens/{course_feature_id}/elevation")
async def get_green_elevation(
    course_feature_id: int,
    downsample: int = Query(1, description="Downsample factor (1 = full resolution, 2 = half, etc.)"),
    include_slopes: bool = Query(True, description="Include slope magnitude data"),
    include_aspects: bool = Query(False, description="Include aspect angle data")
):
    """
    Get elevation grid and derived slope/aspect data for a green feature.
    
    Returns grid metadata and optionally downsampled elevation, slope, and aspect arrays.
    Useful for rendering heatmaps or contour overlays in the app.
    """
    try:
        # Get elevation data
        query = """
        SELECT 
            grid_rows, grid_cols,
            origin_lat, origin_lon,
            resolution_m,
            elevations,
            slopes,
            aspects
        FROM green_elevation
        WHERE course_feature_id = %s;
        """
        
        results = db.execute_query(query, (course_feature_id,))
        
        if not results:
            raise HTTPException(
                status_code=404,
                detail=f"Elevation data not found for green feature {course_feature_id}. Run processing first."
            )
        
        row = results[0]
        
        # Unpack elevation data
        rows = int(row['grid_rows'])
        cols = int(row['grid_cols'])
        elevations = unpack_float32_array(row['elevations'], rows, cols)
        
        # Downsample if requested
        if downsample > 1:
            elevations = elevations[::downsample, ::downsample]
            rows = elevations.shape[0]
            cols = elevations.shape[1]
        
        # Build response
        response = {
            "grid_rows": rows,
            "grid_cols": cols,
            "origin_lat": float(row['origin_lat']),
            "origin_lon": float(row['origin_lon']),
            "resolution_m": float(row['resolution_m']) * downsample,  # Adjust resolution for downsampling
            "elevations": elevations.tolist(),  # Convert to list for JSON serialization
            "elevation_min": float(elevations.min()),
            "elevation_max": float(elevations.max()),
            "elevation_mean": float(elevations.mean())
        }
        
        # Include slopes if requested and available
        if include_slopes and row.get('slopes'):
            slopes = unpack_float32_array(row['slopes'], int(row['grid_rows']), int(row['grid_cols']))
            if downsample > 1:
                slopes = slopes[::downsample, ::downsample]
            response["slopes"] = slopes.tolist()
            response["slope_min"] = float(slopes.min())
            response["slope_max"] = float(slopes.max())
            response["slope_mean"] = float(slopes.mean())
        
        # Include aspects if requested and available
        if include_aspects and row.get('aspects'):
            aspects = unpack_float32_array(row['aspects'], int(row['grid_rows']), int(row['grid_cols']))
            if downsample > 1:
                aspects = aspects[::downsample, ::downsample]
            response["aspects"] = aspects.tolist()
        
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching green elevation: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "server:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=True
    )

