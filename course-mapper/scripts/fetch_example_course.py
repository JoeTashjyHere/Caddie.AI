#!/usr/bin/env python3
"""
Example script to fetch and cache one real course from OSM.

Usage:
    python scripts/fetch_example_course.py
"""
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from course_mapper.etl.osm_ingest import OSMGolfIngester
from course_mapper.db import db

def main():
    print("🏌️  Fetching golf courses from OpenStreetMap...")
    print("")
    
    ingester = OSMGolfIngester()
    
    # Example: Pebble Beach area (Monterey, CA)
    print("📍 Searching in Pebble Beach area...")
    print("   Bounds: 36.55°N to 36.59°N, 121.98°W to 121.93°W")
    print("")
    
    course_ids = ingester.ingest_courses_in_bounds(
        min_lat=36.55,
        min_lon=-121.98,
        max_lat=36.59,
        max_lon=-121.93
    )
    
    print(f"✅ Ingested {len(course_ids)} courses into database")
    print("")
    
    if course_ids:
        print("📋 Course IDs:")
        for course_id in course_ids:
            print(f"   - {course_id}")
        print("")
        print("💡 Next steps:")
        print("   1. Query course details:")
        print(f"      SELECT * FROM courses WHERE id = '{course_ids[0]}';")
        print("   2. Add hole geometries manually or via satellite processing")
        print("   3. Test API endpoint:")
        print(f"      curl http://localhost:8081/courses/{course_ids[0]}/holes")
    else:
        print("⚠️  No courses found. Try a different location or check OSM data availability.")
        print("")
        print("💡 Example locations to try:")
        print("   - St. Andrews, Scotland: 56.34°N, -2.818°W")
        print("   - Augusta, GA: 33.502°N, -82.021°W")
        print("   - Your local area: Find bounding box on OpenStreetMap")


if __name__ == "__main__":
    main()



