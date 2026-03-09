"""
Helper functions for common database queries related to courses and holes.
"""
import logging
from typing import List, Dict, Optional, Tuple
from course_mapper.db import db

logger = logging.getLogger(__name__)


def get_hole_geometries(hole_id: str) -> List[Dict]:
    """
    Get all geometries for a hole, grouped by type.
    
    Args:
        hole_id: UUID of the hole
        
    Returns:
        List of dictionaries with geom_type and geometry WKT
    """
    query = """
    SELECT geom_type, ST_AsText(geometry) as geom_wkt
    FROM hole_geometries
    WHERE hole_id = %s
    ORDER BY geom_type;
    """
    return db.execute_query(query, (hole_id,))


def get_green_center(hole_id: str) -> Optional[Tuple[float, float]]:
    """
    Get green center coordinate (centroid of green geometry).
    
    Args:
        hole_id: UUID of the hole
        
    Returns:
        Tuple of (longitude, latitude) or None if no green found
    """
    query = """
    SELECT ST_X(ST_Centroid(geometry)) as lon, 
           ST_Y(ST_Centroid(geometry)) as lat
    FROM hole_geometries
    WHERE hole_id = %s AND geom_type = 'green'
    LIMIT 1;
    """
    result = db.execute_query(query, (hole_id,))
    if result:
        return (float(result[0]['lon']), float(result[0]['lat']))
    return None


def get_hole_bounds(hole_id: str) -> Optional[Dict]:
    """
    Get bounding box of all geometries for a hole.
    
    Args:
        hole_id: UUID of the hole
        
    Returns:
        Dictionary with min_lat, max_lat, min_lon, max_lon or None
    """
    query = """
    SELECT 
        ST_YMin(ST_Extent(geometry)) as min_lat,
        ST_YMax(ST_Extent(geometry)) as max_lat,
        ST_XMin(ST_Extent(geometry)) as min_lon,
        ST_XMax(ST_Extent(geometry)) as max_lon
    FROM hole_geometries
    WHERE hole_id = %s;
    """
    result = db.execute_query(query, (hole_id,))
    if result and result[0].get('min_lat'):
        return {
            'min_lat': float(result[0]['min_lat']),
            'max_lat': float(result[0]['max_lat']),
            'min_lon': float(result[0]['min_lon']),
            'max_lon': float(result[0]['max_lon'])
        }
    return None


def get_course_location(course_id: str) -> Optional[Tuple[float, float]]:
    """
    Get course location coordinates.
    
    Args:
        course_id: UUID of the course
        
    Returns:
        Tuple of (longitude, latitude) or None
    """
    query = """
    SELECT ST_X(location::geometry) as lon, 
           ST_Y(location::geometry) as lat
    FROM courses
    WHERE id = %s;
    """
    result = db.execute_query(query, (course_id,))
    if result:
        return (float(result[0]['lon']), float(result[0]['lat']))
    return None


def get_holes_for_course(course_id: str) -> List[Dict]:
    """
    Get all holes for a course with their details.
    
    Args:
        course_id: UUID of the course
        
    Returns:
        List of hole dictionaries with number, par, handicap, etc.
    """
    query = """
    SELECT id, number, par, handicap, tee_yardages
    FROM holes
    WHERE course_id = %s
    ORDER BY number;
    """
    return db.execute_query(query, (course_id,))


def hole_has_geometry(hole_id: str, geom_type: str) -> bool:
    """
    Check if a hole has a specific geometry type.
    
    Args:
        hole_id: UUID of the hole
        geom_type: Type to check (green, fairway, bunker, etc.)
        
    Returns:
        True if geometry exists, False otherwise
    """
    query = """
    SELECT COUNT(*) as count
    FROM hole_geometries
    WHERE hole_id = %s AND geom_type = %s;
    """
    result = db.execute_query(query, (hole_id, geom_type))
    if result:
        return int(result[0]['count']) > 0
    return False


def get_green_bounds(hole_id: str) -> Optional[Dict]:
    """
    Get bounding box of green geometry only.
    
    Args:
        hole_id: UUID of the hole
        
    Returns:
        Dictionary with min_lat, max_lat, min_lon, max_lon or None
    """
    query = """
    SELECT 
        ST_YMin(ST_Extent(geometry)) as min_lat,
        ST_YMax(ST_Extent(geometry)) as max_lat,
        ST_XMin(ST_Extent(geometry)) as min_lon,
        ST_XMax(ST_Extent(geometry)) as max_lon
    FROM hole_geometries
    WHERE hole_id = %s AND geom_type = 'green';
    """
    result = db.execute_query(query, (hole_id,))
    if result and result[0].get('min_lat'):
        return {
            'min_lat': float(result[0]['min_lat']),
            'max_lat': float(result[0]['max_lat']),
            'min_lon': float(result[0]['min_lon']),
            'max_lon': float(result[0]['max_lon'])
        }
    return None



