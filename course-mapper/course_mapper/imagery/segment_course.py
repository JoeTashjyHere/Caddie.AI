"""
Course segmentation pipeline.

Fetches satellite imagery for a golf course and segments greens, fairways,
and bunkers using computer vision techniques, then stores as PostGIS polygons.
"""
import logging
from typing import Tuple, Dict, List, Optional
import numpy as np
import cv2
from shapely.geometry import Polygon, MultiPolygon
from shapely.ops import unary_union

from course_mapper.config import settings
from course_mapper.db import db
from course_mapper.imagery.providers import get_imagery_provider

logger = logging.getLogger(__name__)


def calculate_bounding_box(
    lat: float,
    lon: float,
    size_km: float = 2.0
) -> Tuple[float, float, float, float]:
    """
    Calculate bounding box around a point.
    
    Args:
        lat: Center latitude
        lon: Center longitude
        size_km: Size of bounding box in kilometers
        
    Returns:
        Tuple of (min_lat, min_lon, max_lat, max_lon)
    """
    # Approximate: 1 degree latitude ≈ 111 km
    # 1 degree longitude ≈ 111 km * cos(latitude)
    lat_offset = size_km / 111.0
    lon_offset = size_km / (111.0 * abs(abs(lat) * 3.14159 / 180))
    
    min_lat = lat - lat_offset
    max_lat = lat + lat_offset
    min_lon = lon - lon_offset
    max_lon = lon + lon_offset
    
    return (min_lat, min_lon, max_lat, max_lon)


def segment_course_features(image: np.ndarray) -> Dict[str, np.ndarray]:
    """
    Segment golf course features from satellite imagery using color-based CV.
    
    Uses HSV color space and morphological operations to identify:
    - Greens (dark, rich green)
    - Fairways (lighter green)
    - Bunkers (light, sandy tones)
    
    Args:
        image: RGB image array (H, W, 3) as numpy array
        
    Returns:
        Dictionary mapping feature type to binary mask array
    """
    logger.info(f"Segmenting features from image shape: {image.shape}")
    
    # Convert to HSV color space
    hsv = cv2.cvtColor(image, cv2.COLOR_RGB2HSV)
    h, s, v = cv2.split(hsv)
    
    height, width = image.shape[:2]
    
    # Initialize masks
    green_mask = np.zeros((height, width), dtype=np.uint8)
    fairway_mask = np.zeros((height, width), dtype=np.uint8)
    bunker_mask = np.zeros((height, width), dtype=np.uint8)
    
    # GREEN SEGMENTATION
    # Greens are typically darker, richer green (higher saturation)
    # HSV range for green: H ~35-85 (but in OpenCV H is 0-179, so divide by 2)
    green_lower = np.array([35, 40, 30])  # Lower bound for green
    green_upper = np.array([85, 255, 180])  # Upper bound for green
    green_mask_raw = cv2.inRange(hsv, green_lower, green_upper)
    
    # Morphological operations to clean up green mask
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    green_mask = cv2.morphologyEx(green_mask_raw, cv2.MORPH_CLOSE, kernel)
    green_mask = cv2.morphologyEx(green_mask, cv2.MORPH_OPEN, kernel)
    
    # Remove small noise
    green_mask = cv2.medianBlur(green_mask, 5)
    
    # FAIRWAY SEGMENTATION
    # Fairways are lighter green, less saturated than greens
    fairway_lower = np.array([30, 20, 80])  # Lighter, less saturated
    fairway_upper = np.array([90, 255, 255])
    fairway_mask_raw = cv2.inRange(hsv, fairway_lower, fairway_upper)
    
    # Remove green areas from fairway (greens are darker)
    fairway_mask_raw = cv2.bitwise_and(fairway_mask_raw, cv2.bitwise_not(green_mask))
    
    # Morphological operations
    fairway_mask = cv2.morphologyEx(fairway_mask_raw, cv2.MORPH_CLOSE, kernel)
    fairway_mask = cv2.medianBlur(fairway_mask, 5)
    
    # BUNKER SEGMENTATION
    # Bunkers are light, sandy/brown tones
    # Convert to LAB color space for better sand detection
    lab = cv2.cvtColor(image, cv2.COLOR_RGB2LAB)
    l, a, b = cv2.split(lab)
    
    # Sand/bunker colors: high L (lightness), low-medium a, medium-high b
    # In LAB: L=lightness, a=green-red, b=blue-yellow
    # Sand is typically: high L, low a (not green or red), high b (yellow)
    bunker_mask_raw = np.zeros((height, width), dtype=np.uint8)
    
    # Light areas (L > 150)
    light_mask = l > 150
    
    # Yellow/brown areas (b > 130, a between 110-150)
    sand_color_mask = np.logical_and(
        np.logical_and(b > 130, a > 110),
        a < 150
    )
    
    bunker_mask_raw = np.logical_and(light_mask, sand_color_mask).astype(np.uint8) * 255
    
    # Morphological operations for bunkers
    bunker_mask = cv2.morphologyEx(bunker_mask_raw, cv2.MORPH_CLOSE, kernel)
    bunker_mask = cv2.medianBlur(bunker_mask, 7)  # Larger kernel for bunkers
    
    masks = {
        'green': green_mask,
        'fairway': fairway_mask,
        'bunker': bunker_mask
    }
    
    logger.info(f"Segmented features: green={np.sum(green_mask > 0)}px, "
                f"fairway={np.sum(fairway_mask > 0)}px, "
                f"bunker={np.sum(bunker_mask > 0)}px")
    
    return masks


def mask_to_polygons(
    mask: np.ndarray,
    bounds: Tuple[float, float, float, float],
    min_area_pixels: int = 100
) -> List[Polygon]:
    """
    Convert binary mask to Shapely polygons in geographic coordinates.
    
    Args:
        mask: Binary mask array (H, W)
        bounds: Geographic bounds (min_lat, min_lon, max_lat, max_lon)
        min_area_pixels: Minimum polygon area in pixels
        
    Returns:
        List of Polygon objects in geographic coordinates
    """
    min_lat, min_lon, max_lat, max_lon = bounds
    height, width = mask.shape
    
    # Find contours
    contours, _ = cv2.findContours(
        mask.astype(np.uint8),
        cv2.RETR_EXTERNAL,
        cv2.CHAIN_APPROX_SIMPLE
    )
    
    polygons = []
    
    for contour in contours:
        if len(contour) < 3:
            continue
        
        # Calculate area
        area = cv2.contourArea(contour)
        if area < min_area_pixels:
            continue
        
        # Convert contour points to geographic coordinates
        coords = []
        for point in contour:
            x, y = point[0]
            
            # Map pixel coordinates to geographic
            # x=0 -> min_lon, x=width -> max_lon
            # y=0 -> max_lat (top), y=height -> min_lat (bottom)
            lon = min_lon + (x / width) * (max_lon - min_lon)
            lat = max_lat - (y / height) * (max_lat - min_lat)
            
            coords.append((lon, lat))
        
        # Create polygon (close the ring)
        if len(coords) >= 3:
            try:
                poly = Polygon(coords)
                if poly.is_valid and poly.area > 0:
                    polygons.append(poly)
            except Exception as e:
                logger.warning(f"Invalid polygon created: {e}")
    
    logger.info(f"Converted mask to {len(polygons)} polygons")
    return polygons


def polygons_to_multipolygon(polygons: List[Polygon]) -> MultiPolygon:
    """
    Combine multiple polygons into a MultiPolygon.
    
    Args:
        polygons: List of Polygon objects
        
    Returns:
        MultiPolygon containing all polygons
    """
    if not polygons:
        raise ValueError("Cannot create MultiPolygon from empty polygon list")
    
    if len(polygons) == 1:
        # Return as MultiPolygon for consistency
        return MultiPolygon([polygons[0]])
    
    return MultiPolygon(polygons)


def store_course_features(
    course_id: int,
    features: Dict[str, List[Polygon]],
    hole_number: Optional[int] = None
) -> None:
    """
    Store segmented course features in the database.
    
    Args:
        course_id: Course ID from courses table
        features: Dictionary mapping feature_type to list of polygons
        hole_number: Optional hole number (NULL for course-level features)
    """
    logger.info(f"Storing features for course_id={course_id}, hole_number={hole_number}")
    
    # Delete existing features for this course/hole combination
    if hole_number is None:
        delete_query = """
        DELETE FROM course_features
        WHERE course_id = %s AND hole_number IS NULL;
        """
        db.execute_command(delete_query, (course_id,))
    else:
        delete_query = """
        DELETE FROM course_features
        WHERE course_id = %s AND hole_number = %s;
        """
        db.execute_command(delete_query, (course_id, hole_number))
    
    # Insert new features
    for feature_type, polygons in features.items():
        if not polygons:
            continue
        
        try:
            # Combine polygons into MultiPolygon
            multipoly = polygons_to_multipolygon(polygons)
            
            # Convert to WKT
            wkt_geom = multipoly.wkt
            
            # Insert into database
            insert_query = """
            INSERT INTO course_features (course_id, hole_number, feature_type, geom)
            VALUES (%s, %s, %s, ST_SetSRID(ST_GeomFromText(%s), 4326));
            """
            
            db.execute_command(
                insert_query,
                (course_id, hole_number, feature_type, wkt_geom)
            )
            
            logger.info(f"Stored {len(polygons)} {feature_type} polygons for course {course_id}")
            
        except Exception as e:
            logger.error(f"Error storing {feature_type} features: {e}")
            raise


def run_course_segmentation(
    course_id: int,
    bounding_box_km: Optional[float] = None,
    min_area_pixels: Optional[int] = None
) -> None:
    """
    Main pipeline: fetch imagery, segment features, store in database.
    
    Args:
        course_id: Course ID from courses table
        bounding_box_km: Size of bounding box in kilometers (defaults to config)
        min_area_pixels: Minimum polygon area in pixels (defaults to config)
    """
    logger.info(f"Starting segmentation pipeline for course_id={course_id}")
    
    # Get configuration
    bbox_size = bounding_box_km or settings.segmentation_bounding_box_km
    min_area = min_area_pixels or settings.segmentation_min_area_pixels
    
    # Step 1: Load course from database
    # Try multiple approaches to get location
    course_query = """
    SELECT 
        id, 
        name,
        CASE 
            WHEN location IS NOT NULL THEN ST_Y(location::geometry)
            WHEN geom IS NOT NULL THEN ST_Y(ST_Centroid(geom))
            ELSE NULL
        END as lat,
        CASE 
            WHEN location IS NOT NULL THEN ST_X(location::geometry)
            WHEN geom IS NOT NULL THEN ST_X(ST_Centroid(geom))
            ELSE NULL
        END as lon
    FROM courses
    WHERE id = %s;
    """
    
    course_results = db.execute_query(course_query, (course_id,))
    if not course_results:
        raise ValueError(f"Course with id={course_id} not found")
    
    course = course_results[0]
    course_name = course['name']
    
    # Handle potential None values
    if course.get('lat') is None or course.get('lon') is None:
        raise ValueError(f"Course {course_id} ({course_name}) has no location data. Ensure 'location' or 'geom' field is populated.")
    
    lat = float(course['lat'])
    lon = float(course['lon'])
    
    logger.info(f"Found course: {course_name} at ({lat}, {lon})")
    
    # Step 2: Calculate bounding box
    bounds = calculate_bounding_box(lat, lon, bbox_size)
    logger.info(f"Bounding box: {bounds}")
    
    # Step 3: Fetch satellite imagery
    try:
        provider = get_imagery_provider()
        image = provider.fetch_image(bounds, zoom_level=18, width=2048, height=2048)
        logger.info(f"Fetched image: {image.shape}")
    except Exception as e:
        logger.error(f"Failed to fetch imagery: {e}")
        raise ValueError(f"Imagery fetch failed: {e}. Check IMAGERY_PROVIDER and API key configuration.")
    
    # Step 4: Segment features
    masks = segment_course_features(image)
    
    # Step 5: Convert masks to polygons
    all_features = {}
    for feature_type, mask in masks.items():
        polygons = mask_to_polygons(mask, bounds, min_area)
        if polygons:
            all_features[feature_type] = polygons
    
    if not all_features:
        logger.warning("No features segmented. Check image quality and color thresholds.")
        return
    
    # Step 6: Store in database
    store_course_features(course_id, all_features, hole_number=None)
    
    logger.info(f"✅ Segmentation complete for course {course_name} (id={course_id})")
    logger.info(f"   Features stored: {list(all_features.keys())}")

