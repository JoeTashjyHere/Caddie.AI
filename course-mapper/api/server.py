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
    
    Returns greens, fairways, bunkers, water hazards, and tee boxes.
    """
    try:
        # Get hole ID
        hole_query = """
        SELECT id FROM holes
        WHERE course_id = %s AND number = %s;
        """
        hole_results = db.execute_query(hole_query, (course_id, hole_number))
        
        if not hole_results:
            raise HTTPException(status_code=404, detail=f"Hole {hole_number} not found for course {course_id}")
        
        hole_id = str(hole_results[0]['id'])
        
        # Get geometries grouped by type
        geom_query = """
        SELECT geom_type, ST_AsText(geometry) as geom_wkt
        FROM hole_geometries
        WHERE hole_id = %s;
        """
        geom_results = db.execute_query(geom_query, (hole_id,))
        
        # Organize by type
        layout = HoleLayoutResponse()
        
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
                properties={'type': geom_type}
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
        
        return layout
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching hole layout: {e}")
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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "server:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=True
    )



