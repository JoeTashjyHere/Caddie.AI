# Caddie.AI Course Mapper

A hybrid golf course mapping pipeline using OpenStreetMap data, satellite imagery, and elevation data to build rich course geometries for in-round GPS tracking.

## Architecture

- **Backend**: Python + PostGIS for geospatial data storage
- **ETL**: OSM ingestion, satellite segmentation, elevation processing
- **API**: FastAPI server providing course data to iOS app
- **Database**: PostgreSQL with PostGIS extension

## Setup

### 1. Install Dependencies

```bash
cd course-mapper
pip install -r requirements.txt
```

### 2. Set Up Database

Install PostgreSQL and PostGIS:

```bash
# macOS
brew install postgresql postgis

# Start PostgreSQL
brew services start postgresql

# Create database
createdb caddie_golf

# Enable PostGIS extension
psql caddie_golf -c "CREATE EXTENSION postgis;"
```

### 3. Configure Environment

Create a `.env` file in `course-mapper/`:

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/caddie_golf
OVERPASS_API_URL=https://overpass-api.de/api/interpreter
API_HOST=0.0.0.0
API_PORT=8081
```

### 4. Run Database Migrations

```bash
# Run base schema
python -c "from course_mapper.db import db; db.run_migration('db/schema.sql')"

# Run course_features table migration
python -c "from course_mapper.db import db; db.run_migration('db/add_course_features.sql')"

# Run green_elevation table migration
python -c "from course_mapper.db import db; db.run_migration('db/add_green_elevation.sql')"
```

Or use the helper script:
```bash
python scripts/run_migration.py db/add_course_features.sql
python scripts/run_migration.py db/add_green_elevation.sql
```

## Usage

### Run ETL for Example Course

```bash
# Ingest courses from OSM for Pebble Beach area
python -c "from course_mapper.etl.osm_ingest import ingest_course_example; ingest_course_example()"
```

### Start FastAPI Server

```bash
cd course-mapper
uvicorn course_mapper.api.server:app --host 0.0.0.0 --port 8081 --reload
```

Or use the convenience script:

```bash
python -m course_mapper.api.server
```

The API will be available at:
- **Local**: http://localhost:8081
- **Network**: http://YOUR_MAC_IP:8081

### API Endpoints

1. **GET /health** - Health check
2. **GET /courses/nearby?lat=36.57&lon=-121.95&radius_km=10** - Find nearby courses
3. **GET /courses/{course_id}/holes** - Get all holes for a course
4. **GET /courses/{course_id}/holes/{hole_number}/layout** - Get hole layout (GeoJSON, merges OSM + satellite data)
5. **GET /courses/{course_id}/holes/{hole_number}/green-contours** - Get green elevation data
6. **GET /courses/{course_id}/features** - Get all course features (GeoJSON, debug endpoint)
7. **GET /greens/{course_feature_id}/elevation** - Get green elevation grid and slope/aspect data
8. **POST /greens/{course_feature_id}/read** - Compute green reading (aim line, break path, putting guidance)

## Development

### Project Structure

```
course-mapper/
├── course_mapper/
│   ├── __init__.py
│   ├── config.py          # Configuration management
│   ├── db.py              # Database helpers
│   ├── etl/
│   │   ├── osm_ingest.py      # OSM data ingestion
│   │   ├── satellite_processing.py  # Satellite imagery (stub)
│   │   └── elevation_processing.py  # Elevation/LIDAR (stub)
│   └── api/
│       └── server.py      # FastAPI server
├── db/
│   └── schema.sql         # Database schema
├── requirements.txt
└── README.md
```

### Adding a New Course

1. **Fetch from OSM**:
   ```python
   from course_mapper.etl.osm_ingest import OSMGolfIngester
   
   ingester = OSMGolfIngester()
   course_ids = ingester.ingest_courses_in_bounds(
       min_lat=36.55,
       min_lon=-121.98,
       max_lat=36.59,
       max_lon=-121.93
   )
   ```

2. **Add hole geometries** (manual or via satellite processing):
   - Use `satellite_processing.py` to extract features
   - Or manually insert into `hole_geometries` table

3. **Add green contours** (if elevation data available):
   - Use `elevation_processing.py` to compute contours
   - Store raster URL in `green_contours` table

## Segmentation Pipeline

The segmentation pipeline automatically extracts greens, fairways, and bunkers from satellite imagery.

### Setup

1. **Configure Imagery Provider** in `.env`:
   ```env
   # Choose provider: 'mapbox' or 'google'
   IMAGERY_PROVIDER=mapbox
   
   # Set API key (provider-specific)
   MAPBOX_API_KEY=pk.your_mapbox_key_here
   # OR for Google Maps:
   # GOOGLE_MAPS_API_KEY=your_google_key_here
   
   # Optional: Adjust segmentation settings
   SEGMENTATION_BOUNDING_BOX_KM=2.0
   SEGMENTATION_MIN_AREA_PIXELS=100
   ```

2. **Run Migration** (if not already done):
   ```bash
   python -c "from course_mapper.db import db; db.run_migration('db/add_course_features.sql')"
   ```

### Usage

**Segment a course by ID:**
```bash
python scripts/segment_course.py --course-id 1
```

**Segment by course name:**
```bash
python scripts/segment_course.py --course-name "Pebble Beach"
```

**List available courses:**
```bash
python scripts/segment_course.py --list-courses
```

**Custom options:**
```bash
# Use larger bounding box (3 km instead of default 2 km)
python scripts/segment_course.py --course-id 1 --bbox-km 3.0

# Filter smaller polygons (min 200 pixels)
python scripts/segment_course.py --course-id 1 --min-area 200
```

### How It Works

1. **Fetches course location** from database (`location` or `geom` field)
2. **Calculates bounding box** around course (configurable size)
3. **Downloads satellite imagery** from configured provider (Mapbox/Google)
4. **Segments features** using color-based computer vision:
   - Greens: Dark, rich green (HSV filtering)
   - Fairways: Lighter green areas
   - Bunkers: Light, sandy tones
5. **Converts masks to polygons** in geographic coordinates
6. **Stores in database** as `GEOMETRY(MultiPolygon, 4326)` in `course_features` table

### Viewing Results

Use the debug API endpoint to view segmented features:
```bash
curl http://localhost:8081/courses/1/features
```

Returns GeoJSON FeatureCollection with all greens, fairways, and bunkers for visualization.

## Green Elevation Processing

The green elevation processing pipeline samples elevation data for greens, computes slopes and aspects (fall lines), and stores the data for putting guidance.

### Setup

1. **Configure Elevation Provider** in `.env`:
   ```env
   # Choose provider: 'synthetic' (for testing), 'mapbox', or 'usgs'
   ELEVATION_PROVIDER=synthetic
   
   # For Mapbox (if using real elevation data):
   # MAPBOX_API_KEY=pk.your_key_here
   # ELEVATION_API_KEY=pk.your_key_here  # Alternative env var name
   
   # Optional: Adjust default resolution
   GREEN_ELEVATION_RESOLUTION_M=1.0
   ```

2. **Run Migration** (if not already done):
   ```bash
   python scripts/run_migration.py db/add_green_elevation.sql
   ```

### Usage

**Process all greens for a course:**
```bash
python scripts/process_greens.py --course-id 1
```

**Process a specific green feature:**
```bash
python scripts/process_greens.py --feature-id 5
```

**Use custom resolution:**
```bash
python scripts/process_greens.py --course-id 1 --resolution-m 0.5
```

**Dry run (list greens without processing):**
```bash
python scripts/process_greens.py --course-id 1 --dry-run
```

### How It Works

1. **Loads green polygon** from `course_features` table (feature_type='green')
2. **Samples elevation grid** using configured elevation provider:
   - Synthetic: Generates realistic sloped plane for testing
   - Mapbox: Fetches from Mapbox Terrain-RGB tiles (stub implementation)
   - USGS: Fetches from USGS 3DEP services (stub implementation)
3. **Computes gradients** (dz/dx, dz/dy) using numpy
4. **Derives slope magnitude** (percent) and **aspect** (direction of maximum descent in radians)
5. **Stores in database** as packed float32 arrays in `green_elevation` table

### Viewing Results

Use the API endpoint to retrieve elevation data:
```bash
curl "http://localhost:8081/greens/1/elevation?downsample=2&include_slopes=true"
```

Returns JSON with:
- Grid metadata (rows, cols, origin, resolution)
- Elevation array (optionally downsampled)
- Slope array (percent)
- Aspect array (radians, optional)
- Statistics (min, max, mean)

### Example: East Potomac Golf Links

```bash
# First, find the course ID
# (assume course_id = 1 for East Potomac)

# Process all greens for the course
python scripts/process_greens.py --course-id 1 --resolution-m 1.0

# Or process a specific green feature
python scripts/process_greens.py --feature-id 5 --resolution-m 0.5

# View elevation data
curl "http://localhost:8081/greens/5/elevation?include_slopes=true"
```

## Green Reading API & Mobile Integration

The green reading API computes aim lines and break paths using stored elevation/slope data to provide putting guidance.

### API Endpoint

**POST** `/greens/{course_feature_id}/read`

**Request Body**:
```json
{
  "ball_lat": 36.568,
  "ball_lon": -121.95,
  "hole_lat": 36.5681,
  "hole_lon": -121.949
}
```

**Response**:
```json
{
  "aim_line": [
    {"lat": 36.568, "lon": -121.95},
    {"lat": 36.56802, "lon": -121.9498},
    ...
  ],
  "fall_line_from_hole": [
    {"lat": 36.5681, "lon": -121.949},
    ...
  ],
  "aim_offset_feet": 2.5,
  "ball_slope_percent": 1.2,
  "hole_slope_percent": 0.8,
  "max_slope_along_line": 2.1
}
```

### How It Works

1. **Loads elevation data** from `green_elevation` table for the specified green feature
2. **Projects ball/hole positions** into the elevation grid coordinate space
3. **Computes break path** using a heuristic algorithm that:
   - Samples slope/aspect vectors along the path
   - Combines movement toward the hole with downhill component
   - Iteratively steps along the break curve
4. **Computes fall line** by tracing the steepest descent path from the hole
5. **Calculates aim offset** as the perpendicular distance from the direct line (in feet)

### Algorithm Details

The algorithm uses a simple integration method:
- At each step, the ball moves in a direction that combines:
  - `(1 - break_factor)` toward the hole
  - `break_factor` downhill along the gradient
- The break factor scales with local slope (more break on steeper greens)
- Stops when the ball reaches the hole (within tolerance) or max iterations

This is a heuristic approach - not perfect physics, but explainable and tunable.

### iOS Integration Example

See `ios/GreenReadingView.swift` for a complete SwiftUI example that:
- Calls the green reading API
- Visualizes the aim line (blue) and fall line (orange)
- Displays aim offset and slope information
- Shows ball/hole positions on a 2D canvas

**Usage**:
```bash
# 1. Ensure FastAPI server is running
uvicorn course_mapper.api.server:app --host 0.0.0.0 --port 8081

# 2. Open iOS example in Xcode
# 3. Configure API URL (localhost for simulator, Mac IP for device)
# 4. Enter green feature ID and coordinates
# 5. Tap "Get Green Read" to visualize
```

### Example: Using the API

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

## iOS Client (Caddie Mode)

A complete SwiftUI iOS client is included in the `ios/` directory that demonstrates integration with the course-mapper API.

### Project Structure

```
ios/
├── CaddieAIApp.swift              # App entry point
├── Config.swift                   # Configuration (mock data, API URL)
├── Models/
│   ├── Course.swift               # Course model
│   ├── CourseFeature.swift        # Course feature model (GeoJSON)
│   └── GreenReading.swift         # Green reading request/response models
├── Networking/
│   ├── APIClient.swift            # API client with async/await
│   └── MockData.swift             # Mock data for previews
├── ViewModels/
│   ├── CaddieModeViewModel.swift  # Root view model
│   └── GreenCaddieViewModel.swift # Green reading view model
└── Views/
    └── CaddieMode/
        ├── CaddieModeRootView.swift    # Main screen with mode switching
        ├── TeeCaddieView.swift         # Tee mode view
        ├── ApproachCaddieView.swift    # Approach mode view
        └── GreenCaddieView.swift       # Green mode with interactive positioning
```

### Running the iOS App

1. **Open in Xcode**:
   - Create a new iOS app project in Xcode (iOS 15+)
   - Copy all files from `ios/` into your project
   - Ensure deployment target is iOS 15+ (for Canvas API)

2. **Configure API URL**:
   - Edit `ios/Config.swift`
   - For Simulator: `baseURL = "http://localhost:8081"`
   - For physical device: `baseURL = "http://YOUR_MAC_IP:8081"`

3. **Enable Mock Data** (optional, for previews):
   ```swift
   static let useMockData = true  // in Config.swift
   ```

4. **Run the app**:
   - Build and run in Simulator or device
   - Navigate between Tee, Approach, and Green modes
   - In Green mode, tap and drag to adjust ball/hole positions

### Caddie Modes

#### Tee Mode
- Shows hole layout diagram
- Displays suggested club and target distance
- Shows hazards (water, bunkers)
- Mock data for now, ready for backend integration

#### Approach Mode
- Shows last 100-150 yards to green
- Displays front/center/back yardages
- Shows suggested club with adjusted distance
- Ready for GPS-based distance calculations

#### Green Mode
- **Interactive ball/hole positioning**: Tap and drag to move positions
- **Live green reading**: Automatically calls API when positions change
- **Visualization**:
  - Blue line: Aim line (break path)
  - Orange line: Fall line (downhill)
  - Gray dashed: Direct line (reference)
  - White circle: Ball
  - Black circle: Hole
- **Bottom card shows**:
  - Aim offset (left/right in inches/feet)
  - Ball slope percentage
  - Hole slope percentage

### API Integration

The app uses `APIClient.shared` for all network requests:
- `fetchNearbyCourses(lat:lon:radiusKm:)` - Get courses near location
- `fetchCourseFeatures(courseId:)` - Get course features (GeoJSON)
- `getGreenRead(greenId:request:)` - Compute green reading

All methods use `async/await` and proper error handling.

### Example Usage

```swift
// Fetch nearby courses
let courses = try await APIClient.shared.fetchNearbyCourses(
    lat: 38.8706,
    lon: -77.0294,
    radiusKm: 10.0
)

// Get green reading
let request = GreenReadRequest(
    ballLat: 38.8706,
    ballLon: -77.0294,
    holeLat: 38.87061,
    holeLon: -77.02939
)
let response = try await APIClient.shared.getGreenRead(
    greenId: 1,
    request: request
)
```

## Integration with iOS App

The iOS app should point to this API at:
- **Simulator**: `http://localhost:8081`
- **Device**: `http://YOUR_MAC_IP:8081`

Update `Config.swift` in the iOS project to set the base URL.

## Notes

- **Satellite processing** is stubbed - implement ML model for segmentation
- **Elevation processing** - Green elevation processing is implemented with synthetic provider (real API integration stubbed for Mapbox/USGS)
- **OSM ingestion** is functional but may need refinement for edge cases
- Production deployment should use proper authentication and rate limiting

## License

Part of Caddie.AI project.

