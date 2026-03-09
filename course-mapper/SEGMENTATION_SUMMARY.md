# Satellite Imagery Segmentation Pipeline - Implementation Summary

## Overview

Complete end-to-end pipeline for fetching satellite imagery, segmenting golf course features (greens, fairways, bunkers), and storing as PostGIS polygons.

---

## Database Schema

### `course_features` Table

**Location**: `db/add_course_features.sql`

```sql
CREATE TABLE course_features (
    id SERIAL PRIMARY KEY,
    course_id INTEGER NOT NULL,
    hole_number INTEGER NULL,  -- NULL for course-level features
    feature_type TEXT NOT NULL CHECK (feature_type IN ('green', 'fairway', 'bunker', 'water', 'rough', 'tee_box')),
    geom GEOMETRY(MultiPolygon, 4326) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

**Indexes**:
- `idx_course_features_course_id_type` - B-tree on (course_id, feature_type)
- `idx_course_features_geom` - GIST index on geometry
- `idx_course_features_hole_number` - Partial index on hole_number

**Migration**:
```bash
python scripts/run_migration.py db/add_course_features.sql
```

---

## Segmentation Pipeline

### Main Function

**Location**: `course_mapper/imagery/segment_course.py`

```python
def run_course_segmentation(
    course_id: int,
    bounding_box_km: Optional[float] = None,
    min_area_pixels: Optional[int] = None
) -> None
```

### Pipeline Steps

1. **Load course from database**
   - Queries `courses` table by ID
   - Extracts location from `location` (geography) or `geom` (geometry) field

2. **Calculate bounding box**
   - Creates square bounding box around course location
   - Default: 2 km × 2 km (configurable)

3. **Fetch satellite imagery**
   - Uses pluggable provider abstraction (Mapbox/Google)
   - Downloads 2048×2048 pixel image at zoom level 18

4. **Segment features**
   - Converts RGB → HSV color space
   - Color-based segmentation:
     - **Greens**: Dark, rich green (HSV: H=35-85, high saturation)
     - **Fairways**: Lighter green (HSV: H=30-90, less saturated)
     - **Bunkers**: Light, sandy tones (LAB: high L, yellow-brown)
   - Morphological operations to clean masks
   - Filters small areas (< 100 pixels default)

5. **Convert to polygons**
   - Extracts contours from binary masks
   - Maps pixel coordinates → geographic coordinates
   - Creates Shapely Polygon objects
   - Combines into MultiPolygon per feature type

6. **Store in database**
   - Deletes existing features for course (upsert behavior)
   - Inserts new features with SRID 4326

---

## Imagery Providers

**Location**: `course_mapper/imagery/providers.py`

### Abstract Base Class
```python
class ImageryProvider(ABC):
    @abstractmethod
    def fetch_image(bounds, zoom_level, width, height) -> np.ndarray
```

### Implemented Providers

1. **MapboxProvider**
   - Uses Mapbox Static Images API
   - Satellite style: `mapbox/satellite-v9`
   - Requires `MAPBOX_API_KEY`

2. **GoogleMapsProvider**
   - Uses Google Maps Static API
   - Maptype: `satellite`
   - Requires `GOOGLE_MAPS_API_KEY`

### Factory Function
```python
provider = get_imagery_provider()  # Reads IMAGERY_PROVIDER env var
```

---

## CLI Script

**Location**: `scripts/segment_course.py`

### Usage Examples

```bash
# Segment by course ID
python scripts/segment_course.py --course-id 1

# Segment by course name (partial match)
python scripts/segment_course.py --course-name "Pebble Beach"

# List available courses
python scripts/segment_course.py --list-courses

# Custom bounding box size
python scripts/segment_course.py --course-id 1 --bbox-km 3.0

# Custom minimum polygon area
python scripts/segment_course.py --course-id 1 --min-area 200
```

### Configuration Required

```env
# .env file
IMAGERY_PROVIDER=mapbox  # or 'google'
MAPBOX_API_KEY=pk.your_key_here
# OR
GOOGLE_MAPS_API_KEY=your_key_here

# Optional
SEGMENTATION_BOUNDING_BOX_KM=2.0
SEGMENTATION_MIN_AREA_PIXELS=100
```

---

## API Endpoints

### Debug Endpoint

**GET `/courses/{course_id}/features`**

Returns GeoJSON FeatureCollection with all segmented features:

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": { ... },
      "properties": {
        "id": 1,
        "feature_type": "green",
        "hole_number": null
      }
    }
  ]
}
```

### Updated Layout Endpoint

**GET `/courses/{course_id}/holes/{hole_number}/layout`**

Now merges data from:
- `hole_geometries` table (OSM/manual data)
- `course_features` table (satellite segmentation)

Features include `source` property: `'osm'` or `'satellite'`

---

## Configuration

### Environment Variables

```env
# Required for segmentation
IMAGERY_PROVIDER=mapbox                    # 'mapbox' or 'google'
MAPBOX_API_KEY=pk.your_key_here           # For Mapbox
GOOGLE_MAPS_API_KEY=your_key_here          # For Google Maps

# Optional segmentation settings
SEGMENTATION_BOUNDING_BOX_KM=2.0           # Bounding box size
SEGMENTATION_MIN_AREA_PIXELS=100           # Min polygon area filter
```

### Settings in `config.py`

- `imagery_provider: str` - Provider name
- `mapbox_api_key: Optional[str]` - Mapbox key
- `google_maps_api_key: Optional[str]` - Google key
- `segmentation_bounding_box_km: float` - Bounding box size (default 2.0)
- `segmentation_min_area_pixels: int` - Min area filter (default 100)

---

## Files Created

### Database
- `db/add_course_features.sql` - Migration for course_features table

### Core Pipeline
- `course_mapper/imagery/__init__.py`
- `course_mapper/imagery/providers.py` - Provider abstraction
- `course_mapper/imagery/segment_course.py` - Main segmentation pipeline

### Scripts
- `scripts/segment_course.py` - CLI for running segmentation
- `scripts/run_migration.py` - Helper for running migrations

### Updated Files
- `course_mapper/config.py` - Added imagery provider settings
- `course_mapper/api/server.py` - Added `/courses/{id}/features` endpoint, updated layout endpoint
- `README.md` - Added segmentation pipeline documentation

---

## Segmentation Algorithm Details

### Color Thresholds

**Greens**:
- HSV: H ∈ [35, 85], S > 40, V ∈ [30, 180]
- Morphology: Close + Open (5×5 ellipse)
- Median blur: 5×5

**Fairways**:
- HSV: H ∈ [30, 90], S > 20, V ∈ [80, 255]
- Excludes green mask areas
- Median blur: 5×5

**Bunkers**:
- LAB color space: L > 150 (lightness)
- Yellow/brown: b > 130, a ∈ [110, 150]
- Morphology: Close (5×5 ellipse)
- Median blur: 7×7 (larger for noise reduction)

### Coordinate Conversion

Pixel → Geographic:
- X: `lon = min_lon + (x / width) * (max_lon - min_lon)`
- Y: `lat = max_lat - (y / height) * (max_lat - min_lat)` (Y is flipped)

---

## Error Handling

- **Missing API key**: Clear error message with setup instructions
- **Course not found**: ValueError with course ID
- **No location data**: Error if `location` and `geom` are both NULL
- **Imagery fetch failure**: Detailed error with provider name
- **No features segmented**: Warning logged, graceful return
- **Invalid polygons**: Skipped with warning log

---

## Testing Checklist

- [ ] Run migration: `python scripts/run_migration.py db/add_course_features.sql`
- [ ] Set `IMAGERY_PROVIDER` and API key in `.env`
- [ ] List courses: `python scripts/segment_course.py --list-courses`
- [ ] Segment a course: `python scripts/segment_course.py --course-id 1`
- [ ] Verify features in database: `SELECT * FROM course_features WHERE course_id = 1;`
- [ ] Test debug endpoint: `curl http://localhost:8081/courses/1/features`
- [ ] Visualize GeoJSON in mapping tool (e.g., geojson.io)

---

## Next Steps / Improvements

1. **Refine color thresholds** based on real imagery
2. **Add water detection** (currently stubbed)
3. **Implement hole-specific segmentation** (assign features to holes)
4. **Add ML-based segmentation** option (TensorFlow/PyTorch model)
5. **Support additional providers** (Bing, ArcGIS, etc.)
6. **Add progress tracking** for large courses
7. **Implement feature refinement** (smoothing, simplification)

---

**Status**: ✅ Complete and ready for testing



