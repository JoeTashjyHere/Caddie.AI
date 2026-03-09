#!/usr/bin/env python3
"""
CLI script to segment a golf course from satellite imagery.

Usage:
    python scripts/segment_course.py --course-id 1
    python scripts/segment_course.py --course-name "Pebble Beach"
    python scripts/segment_course.py --course-id 1 --bbox-km 3.0
"""
import sys
import os
import argparse
import logging

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from course_mapper.imagery.segment_course import run_course_segmentation
from course_mapper.db import db
from course_mapper.config import settings
from typing import Optional

logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def find_course_by_name(course_name: str) -> Optional[int]:
    """
    Find course ID by name (case-insensitive partial match).
    
    Args:
        course_name: Course name to search for
        
    Returns:
        Course ID or None if not found
    """
    query = """
    SELECT id, name
    FROM courses
    WHERE LOWER(name) LIKE LOWER(%s)
    LIMIT 1;
    """
    
    results = db.execute_query(query, (f"%{course_name}%",))
    if results:
        return results[0]['id']
    return None


def main():
    parser = argparse.ArgumentParser(
        description='Segment golf course features from satellite imagery',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Segment by course ID
  python scripts/segment_course.py --course-id 1
  
  # Segment by course name
  python scripts/segment_course.py --course-name "Pebble Beach"
  
  # Use custom bounding box size
  python scripts/segment_course.py --course-id 1 --bbox-km 3.0
  
  # Set minimum polygon area
  python scripts/segment_course.py --course-id 1 --min-area 200
        """
    )
    
    parser.add_argument(
        '--course-id',
        type=int,
        help='Course ID from database'
    )
    
    parser.add_argument(
        '--course-name',
        type=str,
        help='Course name (partial match, case-insensitive)'
    )
    
    parser.add_argument(
        '--bbox-km',
        type=float,
        default=None,
        help=f'Bounding box size in kilometers (default: {settings.segmentation_bounding_box_km})'
    )
    
    parser.add_argument(
        '--min-area',
        type=int,
        default=None,
        help=f'Minimum polygon area in pixels (default: {settings.segmentation_min_area_pixels})'
    )
    
    parser.add_argument(
        '--list-courses',
        action='store_true',
        help='List all available courses and exit'
    )
    
    args = parser.parse_args()
    
    # List courses if requested
    if args.list_courses:
        print("Available courses:")
        print("-" * 60)
        query = """
        SELECT id, name, city, country
        FROM courses
        ORDER BY name
        LIMIT 50;
        """
        courses = db.execute_query(query)
        for course in courses:
            location = f"{course.get('city', '')}, {course.get('country', '')}" if course.get('city') else ""
            print(f"ID: {course['id']:3d} | {course['name']:40s} | {location}")
        return
    
    # Determine course ID
    course_id = None
    
    if args.course_id:
        course_id = args.course_id
    elif args.course_name:
        course_id = find_course_by_name(args.course_name)
        if not course_id:
            logger.error(f"Course not found: {args.course_name}")
            logger.info("Use --list-courses to see available courses")
            sys.exit(1)
        logger.info(f"Found course: {args.course_name} (ID: {course_id})")
    else:
        parser.error("Must provide either --course-id or --course-name")
    
    # Check configuration
    has_mapbox = hasattr(settings, 'mapbox_api_key') and settings.mapbox_api_key
    has_google = hasattr(settings, 'google_maps_api_key') and settings.google_maps_api_key
    has_satellite = hasattr(settings, 'satellite_api_key') and settings.satellite_api_key
    
    if not (has_mapbox or has_google or has_satellite):
        logger.error("❌ No imagery API key configured!")
        logger.error("   Set one of:")
        logger.error("   - MAPBOX_API_KEY=... for Mapbox")
        logger.error("   - GOOGLE_MAPS_API_KEY=... for Google Maps")
        logger.error("   - SATELLITE_API_KEY=... (generic)")
        sys.exit(1)
    
    provider_name = settings.imagery_provider if hasattr(settings, 'imagery_provider') else 'mapbox'
    logger.info(f"Using imagery provider: {provider_name}")
    
    # Run segmentation
    try:
        logger.info(f"Starting segmentation for course_id={course_id}")
        
        run_course_segmentation(
            course_id=course_id,
            bounding_box_km=args.bbox_km,
            min_area_pixels=args.min_area
        )
        
        logger.info("✅ Segmentation complete!")
        
    except Exception as e:
        logger.error(f"❌ Segmentation failed: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

