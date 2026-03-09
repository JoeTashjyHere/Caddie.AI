# Green Reading API - Implementation Summary

## ✅ All Tasks Completed

### 1. Green Reading Algorithm ✅

**File**: `course_mapper/elevation/green_reading.py`

**Core Functions**:
- `latlon_to_grid()` - Converts geographic coordinates to grid row/col indices
- `grid_to_latlon()` - Converts grid indices back to geographic coordinates
- `compute_break_path()` - Integrates break path using slope/aspect data
- `compute_aim_line()` - Main function computing aim line and offset
- `compute_fall_line_from_hole()` - Traces downhill path from hole
- `get_slope_at_position()` - Gets slope at any geographic position

**Algorithm**:
The break path uses a simple integration method:
1. At each step, combines movement toward the hole (90-70%) with downhill movement (10-30%)
2. Break factor scales with local slope (more break on steeper areas)
3. Iteratively steps along the path until reaching the hole
4. Computes perpendicular offset from direct line for aim adjustment

---

### 2. API Endpoint ✅

**File**: `course_mapper/api/green_reading.py`

**Endpoint**: `POST /greens/{course_feature_id}/read`

**Request Model** (`GreenReadRequest`):
```python
{
    "ball_lat": float,
    "ball_lon": float,
    "hole_lat": float,
    "hole_lon": float
}
```

**Response Model** (`GreenReadResponse`):
```python
{
    "aim_line": [{"lat": float, "lon": float}, ...],
    "fall_line_from_hole": [{"lat": float, "lon": float}, ...] | null,
    "aim_offset_feet": float,
    "ball_slope_percent": float,
    "hole_slope_percent": float,
    "max_slope_along_line": float | null,
    "debug_info": dict | null
}
```

**Query Parameters**:
- `include_fall_line` (bool, default=true) - Include fall line in response
- `include_debug` (bool, default=false) - Include debug information

---

### 3. iOS SwiftUI Example ✅

**File**: `ios/GreenReadingView.swift`

**Features**:
- Input fields for green ID, ball position, hole position
- API integration using URLSession
- Visualization using Canvas API (iOS 15+)
- Displays:
  - Blue line: Aim line (break path)
  - Orange line: Fall line (downhill path)
  - Gray dashed line: Direct line
  - White circle: Ball position
  - Black circle: Hole position
- Shows aim offset, slopes, and statistics

**Usage**:
1. Enter green feature ID
2. Enter ball and hole coordinates
3. Tap "Get Green Read"
4. View visualization and statistics

---

### 4. Documentation ✅

**Files Updated**:
- `README.md` - Added "Green Reading API & Mobile Integration" section
- `ios/README.md` - iOS integration guide

---

## 📋 Core Algorithm

### Break Path Computation

The algorithm uses a heuristic integration method:

```python
for each step:
    # Get direction toward hole
    dir_to_hole = normalize(hole_position - current_position)
    
    # Get slope and gradient at current position
    slope, dx, dy = get_slope_at_grid_point(...)
    
    # Combine movement: weighted average
    # break_factor scales with slope (more break on steeper greens)
    effective_break = break_factor * (slope / 10.0)
    
    move_direction = (1 - effective_break) * dir_to_hole + 
                     effective_break * downhill_gradient
    
    # Step in that direction
    current_position += move_direction * step_size
```

**Parameters**:
- `break_factor`: 0.3 (30% downhill, 70% toward hole)
- `step_size_m`: 0.1 meters
- `max_iterations`: 1000

### Aim Offset Calculation

Computed as perpendicular distance from direct line at the start:
- Cross product of direct line vector and first step vector
- Converted from grid units to feet
- Positive = right of direct line, negative = left

---

## 🎯 API Endpoint Details

### Request

```bash
POST /greens/1/read
Content-Type: application/json

{
  "ball_lat": 36.568,
  "ball_lon": -121.95,
  "hole_lat": 36.5681,
  "hole_lon": -121.949
}
```

### Response

```json
{
  "aim_line": [
    {"lat": 36.568, "lon": -121.95},
    {"lat": 36.56802, "lon": -121.9498},
    ...
    {"lat": 36.5681, "lon": -121.949}
  ],
  "fall_line_from_hole": [
    {"lat": 36.5681, "lon": -121.949},
    {"lat": 36.56812, "lon": -121.9491},
    ...
  ],
  "aim_offset_feet": 2.5,
  "ball_slope_percent": 1.2,
  "hole_slope_percent": 0.8,
  "max_slope_along_line": 2.1,
  "debug_info": {
    "grid_rows": 50,
    "grid_cols": 50,
    "resolution_m": 1.0,
    "aim_line_length_points": 25,
    "fall_line_length_points": 50
  }
}
```

---

## 📱 iOS Integration

### SwiftUI Example Location

**File**: `ios/GreenReadingView.swift`

### Visualization

The view uses SwiftUI `Canvas` to render:
- **Aim Line** (blue): Break path from ball to hole
- **Fall Line** (orange): Downhill path from hole
- **Direct Line** (gray dashed): Straight path (reference)
- **Ball** (white circle): Starting position
- **Hole** (black circle): Target position

### Coordinate Transformation

Simplified 2D projection:
- Normalizes lat/lon to view coordinates
- Scales and centers within canvas bounds
- Flips Y-axis (north = up)

**Note**: For production, use proper map projections (e.g., Web Mercator) and integrate with MapKit.

---

## 📁 Files Created

### Backend
- `course_mapper/elevation/green_reading.py` - Core algorithm
- `course_mapper/api/green_reading.py` - FastAPI router

### iOS
- `ios/GreenReadingView.swift` - Complete SwiftUI example
- `ios/README.md` - iOS integration guide

### Documentation
- Updated `README.md` - Green reading section
- `GREEN_READING_SUMMARY.md` - This file

---

## 🚀 Usage Example

### 1. Process Green Elevation (if not done)

```bash
python scripts/process_greens.py --feature-id 1
```

### 2. Call API

```bash
curl -X POST http://localhost:8081/greens/1/read \
  -H "Content-Type: application/json" \
  -d '{
    "ball_lat": 36.568,
    "ball_lon": -121.95,
    "hole_lat": 36.5681,
    "hole_lon": -121.949
  }'
```

### 3. iOS Integration

1. Open `ios/GreenReadingView.swift` in Xcode
2. Ensure FastAPI server is running
3. Enter green ID and coordinates
4. Tap "Get Green Read"
5. View visualization

---

## 🔧 Algorithm Tuning

The algorithm can be tuned via parameters in `compute_break_path()`:

- **`break_factor`**: Default 0.3 (higher = more break)
- **`step_size_m`**: Default 0.1m (smaller = smoother path)
- **`max_iterations`**: Default 1000 (more = longer paths)

These can be made configurable via API parameters if needed.

---

## ✅ All Requirements Met

- ✅ Green reading algorithm using elevation/slope data
- ✅ Coordinate transformation (lat/lon ↔ grid)
- ✅ Break path computation (heuristic, explainable)
- ✅ Aim offset calculation (feet)
- ✅ Fall line computation
- ✅ FastAPI endpoint with Pydantic models
- ✅ iOS SwiftUI example with visualization
- ✅ Comprehensive documentation
- ✅ Type hints throughout
- ✅ Error handling and logging

**Status**: ✅ Complete and ready for testing



