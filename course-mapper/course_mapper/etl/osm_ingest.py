"""
OSM (OpenStreetMap) data ingestion pipeline.

Fetches golf course features from Overpass API and normalizes them
into our database schema (courses, holes, hole_geometries).
"""
import logging
from typing import List, Dict, Optional, Tuple
import requests
import overpy
from shapely.geometry import Point, Polygon, MultiPolygon
from shapely import wkt
import json

from course_mapper.config import settings
from course_mapper.db import db

logger = logging.getLogger(__name__)


class OSMGolfIngester:
    """Ingest golf course data from OpenStreetMap via Overpass API."""
    
    def __init__(self, overpass_url: Optional[str] = None):
        self.overpass_url = overpass_url or settings.overpass_api_url
        self.api = overpy.Overpass(url=self.overpass_url)
    
    def fetch_courses_in_bounds(
        self,
        min_lat: float,
        min_lon: float,
        max_lat: float,
        max_lon: float
    ) -> List[Dict]:
        """
        Fetch all golf courses in a bounding box.
        
        Args:
            min_lat: Minimum latitude
            min_lon: Minimum longitude
            max_lat: Maximum latitude
            max_lon: Maximum longitude
            
        Returns:
            List of course dictionaries with OSM data
        """
        query = f"""
        [out:json][timeout:25];
        (
          way["golf"="course"]({min_lat},{min_lon},{max_lat},{max_lon});
          relation["golf"="course"]({min_lat},{min_lon},{max_lat},{max_lon});
        );
        out body;
        >;
        out skel qt;
        """
        
        try:
            logger.info(f"Fetching courses in bounds: ({min_lat}, {min_lon}) to ({max_lat}, {max_lon})")
            result = self.api.query(query)
            
            courses = []
            for way in result.ways:
                course_data = {
                    'osm_id': way.id,
                    'osm_type': 'way',
                    'name': way.tags.get('name', 'Unnamed Golf Course'),
                    'latitude': None,
                    'longitude': None,
                    'tags': dict(way.tags),
                    'nodes': [node.id for node in way.nodes]
                }
                
                # Calculate centroid from way nodes
                if way.nodes:
                    lats = [float(node.lat) for node in way.nodes]
                    lons = [float(node.lon) for node in way.nodes]
                    course_data['latitude'] = sum(lats) / len(lats)
                    course_data['longitude'] = sum(lons) / len(lons)
                
                courses.append(course_data)
            
            for relation in result.relations:
                # For relations, try to get location from members
                # This is simplified - real implementation would handle multipolygons
                course_data = {
                    'osm_id': relation.id,
                    'osm_type': 'relation',
                    'name': relation.tags.get('name', 'Unnamed Golf Course'),
                    'latitude': None,
                    'longitude': None,
                    'tags': dict(relation.tags),
                    'members': len(relation.members)
                }
                courses.append(course_data)
            
            logger.info(f"Found {len(courses)} courses in OSM")
            return courses
            
        except Exception as e:
            logger.error(f"Error fetching courses from OSM: {e}")
            return []
    
    def fetch_holes_for_course(
        self,
        course_osm_id: int,
        course_location: Tuple[float, float],
        radius_km: float = 2.0
    ) -> List[Dict]:
        """
        Fetch golf holes near a course location.
        
        Args:
            course_osm_id: OSM ID of the course
            course_location: (lat, lon) tuple
            radius_km: Search radius in kilometers
            
        Returns:
            List of hole dictionaries
        """
        lat, lon = course_location
        # Approximate bounding box from center point and radius
        # 1 degree ≈ 111 km
        lat_offset = radius_km / 111.0
        lon_offset = radius_km / (111.0 * abs(abs(lat)))
        
        query = f"""
        [out:json][timeout:25];
        (
          way["golf"="hole"]({lat - lat_offset},{lon - lon_offset},{lat + lat_offset},{lon + lon_offset});
          node["golf"="hole"]({lat - lat_offset},{lon - lon_offset},{lat + lat_offset},{lon + lon_offset});
        );
        out body;
        >;
        out skel qt;
        """
        
        try:
            result = self.api.query(query)
            holes = []
            
            for way in result.ways:
                hole_data = {
                    'osm_id': way.id,
                    'osm_type': 'way',
                    'number': self._extract_hole_number(way.tags),
                    'par': self._extract_par(way.tags),
                    'tags': dict(way.tags),
                    'nodes': [{'lat': float(node.lat), 'lon': float(node.lon)} for node in way.nodes]
                }
                holes.append(hole_data)
            
            logger.info(f"Found {len(holes)} holes near course {course_osm_id}")
            return holes
            
        except Exception as e:
            logger.error(f"Error fetching holes: {e}")
            return []
    
    def _extract_hole_number(self, tags: Dict) -> Optional[int]:
        """Extract hole number from OSM tags."""
        for key in ['ref', 'hole', 'golf:hole']:
            if key in tags:
                try:
                    return int(tags[key])
                except ValueError:
                    pass
        return None
    
    def _extract_par(self, tags: Dict) -> Optional[int]:
        """Extract par from OSM tags."""
        for key in ['par', 'golf:par']:
            if key in tags:
                try:
                    return int(tags[key])
                except ValueError:
                    pass
        return None
    
    def normalize_course(self, osm_data: Dict) -> Dict:
        """
        Normalize OSM course data into our schema format.
        
        Args:
            osm_data: Raw OSM course data
            
        Returns:
            Normalized course dictionary
        """
        return {
            'name': osm_data.get('name', 'Unnamed Golf Course'),
            'raw_osm_id': f"{osm_data['osm_type']}/{osm_data['osm_id']}",
            'latitude': osm_data.get('latitude'),
            'longitude': osm_data.get('longitude'),
            'country': osm_data.get('tags', {}).get('addr:country'),
            'city': osm_data.get('tags', {}).get('addr:city'),
        }
    
    def save_course_to_db(self, normalized_course: Dict) -> Optional[str]:
        """
        Save a normalized course to the database.
        
        Args:
            normalized_course: Normalized course dictionary
            
        Returns:
            UUID of the created course, or None if failed
        """
        if not normalized_course.get('latitude') or not normalized_course.get('longitude'):
            logger.warning(f"Course {normalized_course['name']} missing location, skipping")
            return None
        
        lat = normalized_course['latitude']
        lon = normalized_course['longitude']
        
        insert_query = """
        INSERT INTO courses (name, country, city, location, raw_osm_id)
        VALUES (%s, %s, %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s)
        RETURNING id;
        """
        
        try:
            with db.get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute(
                    insert_query,
                    (
                        normalized_course['name'],
                        normalized_course.get('country'),
                        normalized_course.get('city'),
                        lon,  # PostGIS uses (lon, lat)
                        lat,
                        normalized_course.get('raw_osm_id')
                    )
                )
                result = cursor.fetchone()
                if result:
                    course_id = str(result[0])
                    logger.info(f"Saved course {normalized_course['name']} with ID {course_id}")
                    return course_id
        except Exception as e:
            logger.error(f"Error saving course to DB: {e}")
        
        return None
    
    def ingest_courses_in_bounds(
        self,
        min_lat: float,
        min_lon: float,
        max_lat: float,
        max_lon: float
    ) -> List[str]:
        """
        Complete pipeline: fetch courses from OSM and save to database.
        
        Args:
            min_lat, min_lon, max_lat, max_lon: Bounding box
            
        Returns:
            List of created course UUIDs
        """
        courses = self.fetch_courses_in_bounds(min_lat, min_lon, max_lat, max_lon)
        course_ids = []
        
        for osm_course in courses:
            normalized = self.normalize_course(osm_course)
            course_id = self.save_course_to_db(normalized)
            if course_id:
                course_ids.append(course_id)
        
        logger.info(f"Ingested {len(course_ids)} courses into database")
        return course_ids


def ingest_course_example():
    """
    Example usage: Ingest courses for Pebble Beach area.
    """
    ingester = OSMGolfIngester()
    
    # Pebble Beach bounding box (approximately)
    pebble_beach_bounds = {
        'min_lat': 36.55,
        'min_lon': -121.98,
        'max_lat': 36.59,
        'max_lon': -121.93
    }
    
    course_ids = ingester.ingest_courses_in_bounds(**pebble_beach_bounds)
    print(f"Ingested {len(course_ids)} courses")


if __name__ == "__main__":
    ingest_course_example()



