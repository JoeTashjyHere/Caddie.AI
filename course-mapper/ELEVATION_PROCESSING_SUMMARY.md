# Green Elevation + Contour Processing - Implementation Summary

## ✅ All Tasks Completed

### 1. Elevation Provider Abstraction ✅

**Files**: 
- `course_mapper/elevation/models.py` - Data models (`ElevationGrid` dataclass)
- `course_mapper/elevation/provider.py` - Provider abstraction and implementations

**Interface**:
```python
class ElevationProvider(Protocol):
    def sample_grid(polygon: Polygon, resolution_m: float) -> ElevationGrid
```

**Implemented Providers**:
1. **SyntheticElevationProvider** - Generates realistic sloped plane for testing
2. **MapboxElevationProvider** - Stub for Mapbox Terrain-RGB tiles
3. **USGSElevationProvider** - Stub for USGS 3DEP services

**Factory Function**:
```python
provider = get_elevation_provider()  # Reads ELEVATION_PROVIDER env var
```

---

### 2. Database Schema ✅

**File**: `db/add_green_elevation.sql`

```sql
CREATE TABLE green_elevation (
    id SERIAL PRIMARY KEY,
    course_feature_id INTEGER NOT NULL UNIQUE,
    grid_rows INTEGER NOT NULL,
    grid_cols INTEGER NOT NULL,
    origin_lat DOUBLE PRECISION NOT NULL,
    origin_lon DOUBLE PRECISION NOT NULL,
    resolution_m DOUBLE PRECISION NOT NULL,
    elevations BYTEA NOT NULL,      -- Packed float32 array (row-major)
    slopes BYTEA,                   -- Optional: slope magnitudes (percent)
    aspects BYTEA,                  -- Optional: aspect angles (radians)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

**Indexes**:
- `idx_green_elevation_feature_id` - Fast lookups by course_feature_id

**Storage Format**:
- Elevations stored as packed float32 BYTEA (4 bytes per value)
- Row-major order: `[row0_col0, row0_col1, ..., rowN_colM]`
- Size = `grid_rows * grid_cols * 4` bytes

**Migration**:
```bash
python scripts/run_migration.py db/add_green_elevation.sql
```

---

### 3. Processing Pipeline ✅

**File**: `course_mapper/elevation/process_green.py`

**Main Function**:
```python
process_green_feature(course_feature_id: int, resolution_m: Optional[float] = None)
```

**Pipeline Steps**:

1. **Load green feature** from `course_features` table
   - Validates `feature_type='green'`
   - Extracts polygon geometry (uses largest if MultiPolygon)

2. **Sample elevation grid** via configured provider
   - Creates grid at specified resolution (default 1.0m)
   - Returns `ElevationGrid` with elevations and metadata

3. **Compute gradients** using numpy
   - `dx, dy = np.gradient(elevations, resolution_m)`
   - Returns dz/dx (east-west) and dz/dy (north-south)

4. **Derive slope magnitude** (percent)
   - `slope = sqrt(dx² + dy²) * 100`

5. **Derive aspect** (direction of maximum descent, radians)
   - `aspect = atan2(dx, -dy)` normalized to [0, 2π]
   - 0 = North, π/2 = East, π = South, 3π/2 = West

6. **Pack and store** in database
   - Upsert behavior: deletes existing record, inserts new
   - Stores as packed float32 BYTEA arrays

---

### 4. CLI Tool ✅

**File**: `scripts/process_greens.py`

**Usage Examples**:

```bash
# Process all greens for a course
python scripts/process_greens.py --course-id 1

# Process specific green feature
python scripts/process_greens.py --feature-id 5

# Custom resolution
python scripts/process_greens.py --course-id 1 --resolution-m 0.5

# Dry run (list greens)
python scripts/process_greens.py --course-id 1 --dry-run
```

**Features**:
- Batch processing for all greens in a course
- Single feature processing
- Progress logging with success/error counts
- Dry run mode for listing greens

---

### 5. API Endpoints ✅

**File**: `course_mapper/api/server.py`

**New Endpoint**:

**GET `/greens/{course_feature_id}/elevation`**

**Query Parameters**:
- `downsample` (int, default=1) - Downsample factor (2 = half resolution)
- `include_slopes` (bool, default=true) - Include slope magnitude data
- `include_aspects` (bool, default=false) - Include aspect angle data

**Response Format**:
```json
{
  "grid_rows": 50,
  "grid_cols": 50,
  "origin_lat": 36.568,
  "origin_lon": -121.95,
  "resolution_m": 1.0,
  "elevations": [[100.5, 100.3, ...], ...],
  "elevation_min": 98.2,
  "elevation_max": 102.1,
  "elevation_mean": 100.5,
  "slopes": [[2.5, 2.3, ...], ...],
  "slope_min": 0.1,
  "slope_max": 5.2,
  "slope_mean": 2.1,
  "aspects": [[0.5, 0.7, ...], ...]  // Optional
}
```

**Example**:
```bash
curl "http://localhost:8081/greens/1/elevation?downsample=2&include_slopes=true"
```

---

### 6. Configuration ✅

**File**: `course_mapper/config.py` (updated)

**Environment Variables**:

```env
# Elevation provider: 'synthetic', 'mapbox', or 'usgs'
ELEVATION_PROVIDER=synthetic

# For Mapbox (if using real elevation):
MAPBOX_API_KEY=pk.your_key_here
# OR
ELEVATION_API_KEY=pk.your_key_here

# Default resolution for green grids
GREEN_ELEVATION_RESOLUTION_M=1.0
```

---

## 📋 Final Schema

### `green_elevation` Table

```sql
CREATE TABLE green_elevation (
    id SERIAL PRIMARY KEY,
    course_feature_id INTEGER NOT NULL UNIQUE,
    grid_rows INTEGER NOT NULL,
    grid_cols INTEGER NOT NULL,
    origin_lat DOUBLE PRECISION NOT NULL,
    origin_lon DOUBLE PRECISION NOT NULL,
    resolution_m DOUBLE PRECISION NOT NULL,
    elevations BYTEA NOT NULL,  -- float32 array, row-major
    slopes BYTEA,               -- Optional: percent (float32)
    aspects BYTEA,              -- Optional: radians 0-2π (float32)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

**Constraints**:
- `grid_rows > 0`, `grid_cols > 0`, `resolution_m > 0`
- Unique constraint on `course_feature_id` (upsert behavior)

---

## 🎯 Main Function Entry Points

### Processing Pipeline

**Python Path**: `course_mapper.elevation.process_green.process_green_feature`

```python
from course_mapper.elevation.process_green import process_green_feature

# Process a single green
process_green_feature(course_feature_id=1, resolution_m=1.0)
```

### CLI Script

**File**: `scripts/process_greens.py`

```bash
# Process all greens for a course
python scripts/process_greens.py --course-id 1

# Process single green
python scripts/process_greens.py --feature-id 5
```

---

## 📝 Example: East Potomac Golf Links

### 1. Find Course ID

```bash
# List courses to find ID
python scripts/segment_course.py --list-courses
# (Assume course_id = 1 for East Potomac)
```

### 2. Ensure Green Features Exist

```bash
# Segment course features first (if not done)
python scripts/segment_course.py --course-id 1
```

### 3. Process Greens

```bash
# Process all greens at default resolution (1.0m)
python scripts/process_greens.py --course-id 1

# Or with custom resolution (0.5m for higher detail)
python scripts/process_greens.py --course-id 1 --resolution-m 0.5

# Process a specific green feature
python scripts/process_greens.py --feature-id 5 --resolution-m 0.5
```

### 4. View Results

```bash
# Get elevation data (full resolution)
curl "http://localhost:8081/greens/5/elevation?include_slopes=true"

# Get downsampled data for faster rendering
curl "http://localhost:8081/greens/5/elevation?downsample=4&include_slopes=true&include_aspects=true"
```

---

## 📁 Files Created

### Core Modules
- `course_mapper/elevation/__init__.py`
- `course_mapper/elevation/models.py` - ElevationGrid dataclass
- `course_mapper/elevation/provider.py` - Provider abstraction and implementations
- `course_mapper/elevation/process_green.py` - Processing pipeline

### Database
- `db/add_green_elevation.sql` - Schema migration

### Scripts
- `scripts/process_greens.py` - CLI tool for batch processing

### Updated Files
- `course_mapper/config.py` - Added elevation provider settings
- `course_mapper/api/server.py` - Added `/greens/{id}/elevation` endpoint
- `README.md` - Added green elevation processing documentation

---

## 🔧 Technical Details

### Elevation Grid Storage

- **Format**: Packed float32 BYTEA (4 bytes per value)
- **Order**: Row-major (C-order): `[row0_col0, row0_col1, ..., rowN_colM]`
- **Size Calculation**: `grid_rows * grid_cols * 4` bytes
- **Example**: 50×50 grid = 10,000 bytes = ~10 KB

### Slope Calculation

- **Method**: Gradient magnitude from elevation grid
- **Units**: Percent (0-100+)
- **Formula**: `slope = sqrt((dz/dx)² + (dz/dy)²) * 100`

### Aspect Calculation

- **Method**: Direction of maximum descent
- **Units**: Radians (0-2π)
- **Convention**: 
  - 0 = North
  - π/2 = East
  - π = South
  - 3π/2 = West

### Coordinate System

- **Input**: WGS84 (EPSG:4326) polygons
- **Grid Origin**: Top-left corner (northwest) of bounding box
- **Resolution**: Meters (converted from degrees using latitude-dependent scaling)

---

## ✅ All Requirements Met

- ✅ Elevation provider abstraction with Protocol interface
- ✅ ElevationGrid dataclass with metadata
- ✅ Database schema with proper storage (BYTEA)
- ✅ Processing pipeline with gradient/slope/aspect computation
- ✅ CLI tool for batch and single-feature processing
- ✅ API endpoint for debugging/UI visualization
- ✅ Comprehensive error handling and logging
- ✅ Type hints throughout
- ✅ Configuration via environment variables
- ✅ Documentation in README

**Status**: ✅ Complete and ready for testing



