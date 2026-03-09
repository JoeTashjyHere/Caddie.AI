# Implementation Status - Course Mapper Integration

## ✅ Completed Tasks

### iOS Implementation

1. **✅ Fixed GeoJSON Parsing** (`ios/Models/HoleLayout.swift`)
   - Handles complex nested coordinate arrays
   - Supports Point, Polygon, and MultiPolygon geometries
   - Recursive parsing for variable-depth structures
   - Proper coordinate conversion (GeoJSON [lon, lat] → MapKit lat/lon)

2. **✅ Updated ShotContext** (`ios/Models/ShotContext.swift`)
   - Added `distanceToGreenCenter: Double?`
   - Added `distanceToFront: Double?`
   - Added `distanceToBack: Double?`
   - Added `hasWaterLeft: Bool`
   - Added `hasBunkerRight: Bool`
   - Added `hasWaterRight: Bool`
   - Added `hasBunkerLeft: Bool`
   - All fields properly encoded/decoded

3. **✅ Updated CourseService** (`ios/Services/CourseService.swift`)
   - Added fallback to CourseMapperService when Node backend fails
   - Graceful degradation chain: Node → CourseMapper → Local fallback
   - Proper error handling at each level

4. **✅ Created HoleMapView** (`ios/Features/Round/HoleMapView.swift`)
   - MapKit integration for hole display
   - User location tracking
   - Green center pin annotation
   - Distance bubble display
   - Polygon overlays for greens, fairways, bunkers, water
   - Automatic region calculation from hole geometries

### Backend Implementation

5. **✅ FastAPI Server** (`course-mapper/course_mapper/api/server.py`)
   - All endpoints implemented
   - Proper error handling
   - GeoJSON conversion from PostGIS

---

## 🚧 Remaining Tasks (Need Manual Completion)

### iOS Tasks

#### 1. Refine HoleMapView Implementation
The current `HoleMapView.swift` uses iOS 17+ Map APIs. For broader compatibility, consider using `UIViewRepresentable` with `MKMapView`:

```swift
struct HoleMapView: UIViewRepresentable {
    let holeLayout: HoleLayout?
    let userLocation: CLLocationCoordinate2D?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .hybrid
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Add polygons, annotations, etc.
    }
}
```

#### 2. Update RoundPlayView
Add `HoleMapView` to `RoundPlayView.swift`:

```swift
// In RoundPlayView body
VStack {
    // Map at top
    HoleMapView(
        courseId: course.id,
        holeNumber: roundViewModel.currentHole,
        holeLayout: holeLayout,  // Fetch from CourseMapperService
        userLocation: locationService.lastLocation?.coordinate
    )
    .frame(height: 300)
    
    // Existing content below
    // ...
}
```

#### 3. Fetch Hole Layout in RoundViewModel
Add method to fetch and cache hole layouts:

```swift
@Published var holeLayouts: [Int: HoleLayout] = [:]

func fetchHoleLayout(courseId: String, holeNumber: Int) async {
    do {
        let response = try await CourseMapperService.shared.fetchHoleLayout(
            courseId: courseId,
            holeNumber: holeNumber
        )
        let layout = HoleLayout(from: response)
        holeLayouts[holeNumber] = layout
    } catch {
        print("Error fetching hole layout: \(error)")
    }
}
```

#### 4. Update RecommenderService
Modify `askCaddie` to include GPS distances:

```swift
// In RecommenderService or PlayViewModel
var context = ShotContext(
    // ... existing fields ...
    distanceToGreenCenter: holeLayout?.greenCenter.map { 
        calculateDistance(from: userLocation, to: $0) 
    },
    distanceToFront: holeLayout?.greenFront.map { 
        calculateDistance(from: userLocation, to: $0) 
    },
    distanceToBack: holeLayout?.greenBack.map { 
        calculateDistance(from: userLocation, to: $0) 
    },
    hasWaterLeft: detectWaterLeft(userLocation, holeLayout),
    hasBunkerRight: detectBunkerRight(userLocation, holeLayout)
)
```

#### 5. Hazard Detection
Add helper methods to detect hazards:

```swift
func detectWaterLeft(userLocation: CLLocationCoordinate2D, layout: HoleLayout?) -> Bool {
    guard let layout = layout,
          let greenCenter = layout.greenCenter else { return false }
    
    // Calculate line from user to green
    let bearing = calculateBearing(from: userLocation, to: greenCenter)
    let leftBearing = (bearing - 90).truncatingRemainder(dividingBy: 360)
    
    // Check if water polygons are on the left side
    // This is simplified - real implementation would check polygon intersections
    return layout.waterPolygons.contains { polygon in
        isPolygonOnBearing(polygon, from: userLocation, bearing: leftBearing)
    }
}
```

#### 6. UI Improvements (18Birdies Style)
Update `RoundPlayView` header:

```swift
HStack {
    VStack(alignment: .leading) {
        Text("Hole \(roundViewModel.currentHole)")
            .font(.system(size: 24, weight: .bold))
        Text("Par \(currentHolePar)")
            .font(.system(size: 18, weight: .medium))
    }
    Spacer()
    // Tee selection, handicap, etc.
}
.padding()
.background(GolfTheme.cream)
```

### Backend Tasks

#### 7. Expand Layout Endpoint
Update `course_mapper/course_mapper/api/server.py` to merge OSM and satellite data:

```python
@app.get("/courses/{course_id}/holes/{hole_number}/layout", response_model=HoleLayoutResponse)
async def get_hole_layout(course_id: str, hole_number: int):
    # ... existing OSM query ...
    
    # TODO: Merge with satellite data if available
    # from course_mapper.etl.satellite_processing import SatelliteProcessor
    # satellite_features = await fetch_satellite_features(course_id, hole_number)
    # Merge OSM and satellite geometries
    
    return layout
```

#### 8. Improve DB Helpers
Add helper functions to `course_mapper/course_mapper/db.py`:

```python
def get_hole_geometries(hole_id: str) -> List[Dict]:
    """Get all geometries for a hole, grouped by type."""
    query = """
    SELECT geom_type, ST_AsGeoJSON(geometry) as geojson
    FROM hole_geometries
    WHERE hole_id = %s;
    """
    return db.execute_query(query, (hole_id,))

def get_green_center(hole_id: str) -> Optional[Tuple[float, float]]:
    """Get green center coordinate."""
    query = """
    SELECT ST_X(ST_Centroid(geometry)) as lon, 
           ST_Y(ST_Centroid(geometry)) as lat
    FROM hole_geometries
    WHERE hole_id = %s AND geom_type = 'green'
    LIMIT 1;
    """
    result = db.execute_query(query, (hole_id,))
    if result:
        return (result[0]['lon'], result[0]['lat'])
    return None
```

#### 9. Example Course Fetch Script
Create `course-mapper/scripts/fetch_example_course.py`:

```python
#!/usr/bin/env python3
"""
Example script to fetch and cache one real course from OSM.
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from course_mapper.etl.osm_ingest import OSMGolfIngester

def main():
    ingester = OSMGolfIngester()
    
    # Pebble Beach area
    course_ids = ingester.ingest_courses_in_bounds(
        min_lat=36.55,
        min_lon=-121.98,
        max_lat=36.59,
        max_lon=-121.93
    )
    
    print(f"Ingested {len(course_ids)} courses")
    for course_id in course_ids:
        print(f"  - Course ID: {course_id}")

if __name__ == "__main__":
    main()
```

---

## 📋 Configuration Checklist

### Required Setup

- [ ] Install PostgreSQL + PostGIS
- [ ] Create database and run migrations
- [ ] Set environment variables in `course-mapper/.env`
- [ ] Install Python dependencies: `pip install -r requirements.txt`
- [ ] Start FastAPI server: `uvicorn course_mapper.api.server:app --port 8081`
- [ ] Update `CourseMapperService.swift` with your Mac's IP for device testing
- [ ] Test `/health` endpoint from iOS app
- [ ] Ingest a test course using OSM script

### Testing Steps

1. **Backend Testing**
   ```bash
   # Test health check
   curl http://localhost:8081/health
   
   # Test nearby courses
   curl "http://localhost:8081/courses/nearby?lat=36.568&lon=-121.95&radius_km=10"
   ```

2. **iOS Testing**
   - Open app on simulator
   - Navigate to course selection
   - Verify courses load from course-mapper API
   - Start a round
   - Verify hole map displays
   - Check distance calculations

---

## 📁 Files Created/Modified

### Created Files
- `course-mapper/course_mapper/__init__.py`
- `course-mapper/course_mapper/config.py`
- `course-mapper/course_mapper/db.py`
- `course-mapper/course_mapper/etl/osm_ingest.py`
- `course-mapper/course_mapper/etl/satellite_processing.py`
- `course-mapper/course_mapper/etl/elevation_processing.py`
- `course-mapper/course_mapper/api/server.py`
- `course-mapper/db/schema.sql`
- `course-mapper/requirements.txt`
- `course-mapper/README.md`
- `ios/Models/HoleLayout.swift`
- `ios/Services/CourseMapperService.swift`
- `ios/Features/Round/HoleMapView.swift`

### Modified Files
- `ios/Models/ShotContext.swift` - Added GPS distance fields
- `ios/Services/CourseService.swift` - Added course-mapper fallback

---

## 🔧 Key Integration Points

### Data Flow

```
User Location
    ↓
LocationService.lastLocation
    ↓
RoundPlayView → HoleMapView
    ↓
CourseMapperService.fetchHoleLayout()
    ↓
FastAPI /courses/{id}/holes/{number}/layout
    ↓
PostGIS Database → GeoJSON Response
    ↓
HoleLayout (parsed polygons)
    ↓
MapKit Display + Distance Calculations
    ↓
ShotContext (with GPS distances)
    ↓
RecommenderService → AI Recommendations
```

### Distance Calculation

Distances are calculated in real-time as user location updates:
1. User location changes → `LocationService` updates
2. `HoleMapView` recalculates distances to green center/front/back
3. Distances stored in `ShotContext`
4. Passed to AI for context-aware recommendations

---

## 🚀 Next Steps

1. **Complete HoleMapView Integration**
   - Test MapKit polygon rendering
   - Verify distance calculations
   - Add smooth animations

2. **Test with Real Course Data**
   - Ingest a course from OSM
   - Verify geometries display correctly
   - Test on physical device with GPS

3. **Refine Hazard Detection**
   - Implement polygon intersection checks
   - Calculate left/right relative to target line
   - Add visual indicators on map

4. **Optimize Performance**
   - Cache hole layouts
   - Reduce API calls
   - Optimize polygon rendering

---

**Status**: Core infrastructure complete. Ready for testing and refinement.

**Last Updated**: December 2024

