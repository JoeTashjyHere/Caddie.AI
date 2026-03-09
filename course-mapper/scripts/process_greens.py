#!/usr/bin/env python3
"""
CLI script to process green elevation data for golf courses.

Usage:
    python scripts/process_greens.py --course-id 1
    python scripts/process_greens.py --feature-id 5
    python scripts/process_greens.py --course-id 1 --resolution-m 0.5
"""
import sys
import os
import argparse
import logging

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from course_mapper.elevation.process_green import process_green_feature
from course_mapper.db import db
from course_mapper.config import settings

logging.basicConfig(
    level=getattr(logging, settings.log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def get_green_features_for_course(course_id: int) -> list:
    """
    Get all green feature IDs for a course.
    
    Args:
        course_id: Course ID
        
    Returns:
        List of course_feature IDs that are greens
    """
    query = """
    SELECT id, hole_number
    FROM course_features
    WHERE course_id = %s AND feature_type = 'green'
    ORDER BY hole_number NULLS FIRST, id;
    """
    
    results = db.execute_query(query, (course_id,))
    return [row['id'] for row in results]


def main():
    parser = argparse.ArgumentParser(
        description='Process green elevation data and compute slopes/aspects',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process all greens for a course
  python scripts/process_greens.py --course-id 1
  
  # Process a specific green feature
  python scripts/process_greens.py --feature-id 5
  
  # Use custom resolution
  python scripts/process_greens.py --course-id 1 --resolution-m 0.5
  
  # List greens for a course (dry run)
  python scripts/process_greens.py --course-id 1 --dry-run
        """
    )
    
    parser.add_argument(
        '--course-id',
        type=int,
        help='Course ID - process all greens for this course'
    )
    
    parser.add_argument(
        '--feature-id',
        type=int,
        help='Specific course_feature ID to process'
    )
    
    parser.add_argument(
        '--resolution-m',
        type=float,
        default=None,
        help=f'Grid resolution in meters (default: {settings.green_elevation_resolution_m})'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='List greens to process without actually processing'
    )
    
    args = parser.parse_args()
    
    # Determine what to process
    feature_ids = []
    
    if args.feature_id:
        feature_ids = [args.feature_id]
        logger.info(f"Processing single green feature: {args.feature_id}")
    elif args.course_id:
        feature_ids = get_green_features_for_course(args.course_id)
        if not feature_ids:
            logger.error(f"No green features found for course_id={args.course_id}")
            sys.exit(1)
        logger.info(f"Found {len(feature_ids)} green features for course_id={args.course_id}")
    else:
        parser.error("Must provide either --course-id or --feature-id")
    
    # Dry run: just list
    if args.dry_run:
        logger.info("DRY RUN - Would process the following green features:")
        for fid in feature_ids:
            # Get feature details
            query = """
            SELECT id, course_id, hole_number
            FROM course_features
            WHERE id = %s;
            """
            result = db.execute_query(query, (fid,))
            if result:
                hole = result[0].get('hole_number', 'N/A')
                logger.info(f"  - Feature ID {fid} (hole: {hole})")
        return
    
    # Process each green
    resolution = args.resolution_m or settings.green_elevation_resolution_m
    logger.info(f"Using resolution: {resolution}m")
    
    success_count = 0
    error_count = 0
    
    for feature_id in feature_ids:
        try:
            logger.info(f"Processing green feature {feature_id}...")
            process_green_feature(feature_id, resolution_m=resolution)
            success_count += 1
            logger.info(f"✅ Successfully processed feature {feature_id}")
        except Exception as e:
            error_count += 1
            logger.error(f"❌ Error processing feature {feature_id}: {e}", exc_info=True)
    
    # Summary
    logger.info("")
    logger.info("=" * 60)
    logger.info(f"Processing complete: {success_count} succeeded, {error_count} failed")
    logger.info("=" * 60)


if __name__ == "__main__":
    main()



