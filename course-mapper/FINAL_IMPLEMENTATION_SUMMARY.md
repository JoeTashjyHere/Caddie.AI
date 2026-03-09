# 🎯 Satellite Imagery Segmentation Pipeline - Complete Implementation

## ✅ All Tasks Completed

### 1. Database Schema ✅

**File**: `db/add_course_features.sql`

```sql
CREATE TABLE course_features (
    id SERIAL PRIMARY KEY,
    course_id INTEGER NOT NULL,
    hole_number INTEGER NULL,
    feature_type TEXT NOT NULL CHECK (feature_type IN ('green', 'fairway', 'bunker', 'water', 'rough', 'tee_box')),
    geom GEOMETRY(MultiPolygon, 4326) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

**Indexes**:
- B-tree on (course_id, feature_type)
- GIST on geometry
- Partial index on hole_number

**Migration Command**:
```bash
python scripts/run_migration.py db/add_course_features.sql
```

---

### 2. Imagery Provider Abstraction ✅

**File**: `course_mapper/imagery/providers.py`

- Abstract base class `ImageryProvider`
- `MapboxProvider` - Mapbox Static Images API
- `GoogleMapsProvider` - Google Maps Static API
- Factory function `get_imagery_provider()` reads `IMAGERY_PROVIDER` env var

---

### 3. Segmentation Pipeline ✅

**File**: `course_mapper/imagery/segment_course.py`

**Main Function**:
```python
run_course_segmentation(course_id: int, bounding_box_km: Optional[float] = None, min_area_pixels: Optional[int] = None)
```

**Pipeline Steps**:
1. Load course location from database
2. Calculate bounding box (configurable size)
3. Fetch satellite imagery via provider
4. Segment features using color-based CV:
   - Greens: HSV filtering + morphological ops
   - Fairways: Lighter green areas
   - Bunkers: LAB color space for sand detection
5. Convert masks → polygons (Shapely)
6. Store as MultiPolygon in PostGIS

---

### 4. CLI Script ✅

**File**: `scripts/segment_course.py`

**Usage**:
```bash
# Segment by ID
python scripts/segment_course.py --course-id 1

# Segment by name
python scripts/segment_course.py --course-name "Pebble Beach"

# List courses
python scripts/segment_course.py --list-courses

# Custom options
python scripts/segment_course.py --course-id 1 --bbox-km 3.0 --min-area 200
```

---

### 5. Debug API Endpoint ✅

**GET `/courses/{course_id}/features`**

Returns GeoJSON FeatureCollection:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {...},
      "properties": {
        "id": 1,
        "feature_type": "green",
        "hole_number": null
      }
    }
  ]
}
```

---

### 6. Updated Layout Endpoint ✅

**GET `/courses/{course_id}/holes/{hole_number}/layout`**

Now merges:
- `hole_geometries` (OSM/manual data)
- `course_features` (satellite segmentation)

---

## 📋 Configuration

### Required Environment Variables

```env
# Imagery provider (choose one)
IMAGERY_PROVIDER=mapbox  # or 'google'
MAPBOX_API_KEY=pk.your_key_here
# OR
GOOGLE_MAPS_API_KEY=your_key_here

# Optional settings
SEGMENTATION_BOUNDING_BOX_KM=2.0
SEGMENTATION_MIN_AREA_PIXELS=100
```

---

## 🚀 Quick Start

1. **Run migration**:
   ```bash
   python scripts/run_migration.py db/add_course_features.sql
   ```

2. **Configure .env**:
   ```env
   IMAGERY_PROVIDER=mapbox
   MAPBOX_API_KEY=your_key
   ```

3. **Segment a course**:
   ```bash
   python scripts/segment_course.py --course-id 1
   ```

4. **View results**:
   ```bash
   curl http://localhost:8081/courses/1/features
   ```

---

## 📁 Files Created/Modified

### Created
- `db/add_course_features.sql` - Database schema
- `course_mapper/imagery/__init__.py`
- `course_mapper/imagery/providers.py` - Provider abstraction
- `course_mapper/imagery/segment_course.py` - Main pipeline
- `scripts/segment_course.py` - CLI script
- `scripts/run_migration.py` - Migration helper
- `SEGMENTATION_SUMMARY.md` - Detailed documentation

### Modified
- `course_mapper/config.py` - Added imagery provider settings
- `course_mapper/api/server.py` - Added debug endpoint, updated layout endpoint
- `README.md` - Added segmentation pipeline section

---

## 🎨 Segmentation Algorithm

- **Color-based CV** using OpenCV
- **HSV filtering** for greens/fairways
- **LAB color space** for bunkers (sand detection)
- **Morphological operations** for noise reduction
- **Contour extraction** → Shapely polygons
- **Coordinate transformation** pixel → geographic

---

## ✅ All Requirements Met

- ✅ Schema with proper indexes
- ✅ Pluggable imagery provider abstraction
- ✅ Complete segmentation pipeline
- ✅ CLI script with course ID/name lookup
- ✅ Debug API endpoint
- ✅ Merged layout endpoint (OSM + satellite)
- ✅ Type hints throughout
- ✅ Comprehensive error handling and logging
- ✅ Configuration via environment variables

**Ready for production testing!**
