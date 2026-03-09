"""
FastAPI router for green reading API endpoints.
"""
import logging
from typing import List, Optional
from fastapi import APIRouter, HTTPException, Path
from pydantic import BaseModel

from course_mapper.elevation.green_reading import (
    compute_aim_line,
    compute_fall_line_from_hole,
    get_slope_at_position
)
from course_mapper.elevation.process_green import unpack_float32_array
from course_mapper.db import db

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/greens", tags=["green-reading"])


# Request/Response models
class GreenReadRequest(BaseModel):
    """Request model for green reading."""
    ball_lat: float
    ball_lon: float
    hole_lat: float
    hole_lon: float


class Point2D(BaseModel):
    """2D point with lat/lon."""
    lat: float
    lon: float


class GreenReadResponse(BaseModel):
    """Response model for green reading."""
    aim_line: List[Point2D]
    fall_line_from_hole: Optional[List[Point2D]] = None
    aim_offset_feet: float
    ball_slope_percent: float
    hole_slope_percent: float
    max_slope_along_line: Optional[float] = None
    debug_info: Optional[dict] = None


@router.post("/{course_feature_id}/read", response_model=GreenReadResponse)
async def read_green(
    course_feature_id: int = Path(..., description="Course feature ID for the green"),
    request: GreenReadRequest = ...,
    include_fall_line: bool = True,
    include_debug: bool = False
):
    """
    Compute green reading: aim line, break path, and putting guidance.
    
    Uses stored elevation/slope/aspect data to compute:
    - Aim line (break path from ball to hole)
    - Fall line (downhill path from hole)
    - Aim offset (left/right adjustment in feet)
    - Slope information at ball and hole
    """
    try:
        # Load elevation data for this green
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
                detail=f"Elevation data not found for green feature {course_feature_id}. "
                       "Run processing first using: python scripts/process_greens.py --feature-id {course_feature_id}"
            )
        
        row = results[0]
        
        # Unpack arrays
        rows = int(row['grid_rows'])
        cols = int(row['grid_cols'])
        origin_lat = float(row['origin_lat'])
        origin_lon = float(row['origin_lon'])
        resolution_m = float(row['resolution_m'])
        
        slopes = unpack_float32_array(row['slopes'], rows, cols)
        aspects = unpack_float32_array(row['aspects'], rows, cols)
        
        # Validate inputs are within reasonable bounds
        # (Basic check - could be improved with actual polygon bounds)
        ball_lat, ball_lon = request.ball_lat, request.ball_lon
        hole_lat, hole_lon = request.hole_lat, request.hole_lon
        
        # Compute aim line
        aim_line_latlon, aim_offset_feet = compute_aim_line(
            ball_lat, ball_lon,
            hole_lat, hole_lon,
            origin_lat, origin_lon,
            resolution_m,
            slopes, aspects,
            rows, cols
        )
        
        # Convert to response format
        aim_line_points = [Point2D(lat=lat, lon=lon) for lat, lon in aim_line_latlon]
        
        # Compute fall line if requested
        fall_line_points = None
        if include_fall_line:
            fall_line_latlon = compute_fall_line_from_hole(
                hole_lat, hole_lon,
                origin_lat, origin_lon,
                resolution_m,
                slopes, aspects,
                rows, cols
            )
            fall_line_points = [Point2D(lat=lat, lon=lon) for lat, lon in fall_line_latlon]
        
        # Get slopes at ball and hole
        ball_slope = get_slope_at_position(
            ball_lat, ball_lon,
            origin_lat, origin_lon,
            resolution_m,
            slopes,
            rows, cols
        )
        
        hole_slope = get_slope_at_position(
            hole_lat, hole_lon,
            origin_lat, origin_lon,
            resolution_m,
            slopes,
            rows, cols
        )
        
        # Compute max slope along the aim line
        max_slope = None
        if include_debug or True:  # Always compute for now
            max_slope_val = 0.0
            for lat, lon in aim_line_latlon:
                slope = get_slope_at_position(lat, lon, origin_lat, origin_lon, resolution_m, slopes, rows, cols)
                max_slope_val = max(max_slope_val, slope)
            max_slope = max_slope_val
        
        # Build debug info if requested
        debug_info = None
        if include_debug:
            debug_info = {
                "grid_rows": rows,
                "grid_cols": cols,
                "resolution_m": resolution_m,
                "aim_line_length_points": len(aim_line_points),
                "fall_line_length_points": len(fall_line_points) if fall_line_points else 0
            }
        
        return GreenReadResponse(
            aim_line=aim_line_points,
            fall_line_from_hole=fall_line_points,
            aim_offset_feet=aim_offset_feet,
            ball_slope_percent=ball_slope,
            hole_slope_percent=hole_slope,
            max_slope_along_line=max_slope,
            debug_info=debug_info
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error computing green read: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error computing green read: {str(e)}")



