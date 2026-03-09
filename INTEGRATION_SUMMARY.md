# Course Mapper Integration Summary

## Overview

This document summarizes the course mapping pipeline integration into Caddie.AI. The system includes a Python backend with PostGIS for geospatial data and iOS integration for 18Birdies-style GPS tracking during rounds.

---

## Phase 1: Backend Course Mapper ✅ COMPLETED

### Files Created

#### Database & Configuration
- `course-mapper/db/schema.sql` - PostGIS database schema
- `course-mapper/course_mapper/config.py` - Configuration management
- `course-mapper/course_mapper/db.py` - Database connection helpers

#### ETL Pipelines
- `course-mapper/course_mapper/etl/osm_ingest.py` - OpenStreetMap data ingestion
- `course-mapper/course_mapper/etl/satellite_processing.py` - Satellite imagery processing (stub)
- `course-mapper/course_mapper/etl/elevation_processing.py` - Elevation/LIDAR processing (stub)

#### API Server
- `course-mapper/course_mapper/api/server.py` - FastAPI server with course endpoints

#### Setup Files
- `course-mapper/requirements.txt` - Python dependencies
- `course-mapper/README.md` - Setup and usage instructions

### Database Schema

**courses**
- `id` (UUID), `name`, `country`, `city`
- `location` (GEOGRAPHY POINT)
- `raw_osm_id` (TEXT)

**holes**
- `id` (UUID), `course_id` (FK)
- `number`, `par`, `handicap`
- `tee_yardages` (JSONB)

**hole_geometries**
- `id` (UUID), `hole_id` (FK)
- `geom_type` (green, fairway, bunker, water, tee_box, rough)
- `geometry` (GEOMETRY POLYGON)

**green_contours**
- `id` (UUID), `hole_id` (FK)
- `contour_raster_url` (TEXT)
- `metadata` (JSONB - slope, elevation stats)

### API Endpoints

1. `GET /health` - Health check
2. `GET /courses/nearby?lat=X&lon=Y&radius_km=10` - Find nearby courses
3. `GET /courses/{course_id}/holes` - Get all holes for a course
4. `GET /courses/{course_id}/holes/{hole_number}/layout` - Get hole layout (GeoJSON)
5. `GET /courses/{course_id}/holes/{hole_number}/green-contours` - Get green elevation data

---

## Phase 2: FastAPI Server ✅ COMPLETED

The FastAPI server is ready to run on port 8081 (to avoid conflict with Node backend on 8080).

**To start:**
```bash
cd course-mapper
uvicorn course_mapper.api.server:app --host 0.0.0.0 --port 8081
```

---

## Phase 3: iOS Integration 🚧 IN PROGRESS

### Files Created

1. **`ios/Models/HoleLayout.swift`** - GeoJSON models and MapKit polygon converters
2. **`ios/Services/CourseMapperService.swift`** - Service to call course-mapper API

### Files Modified (TODO)

#### Update `ios/Services/CourseService.swift`
- Add fallback to course-mapper API when Node backend is unavailable
- Map `CourseMapperCourse` to existing `Course` model

#### Update `ios/Features/Round/RoundPlayView.swift`
- Add MapKit map view showing hole layout
- Display user GPS location
- Show green center and distance
- Show hazard polygons

#### Update `ios/Models/ShotContext.swift`
- Add GPS-based distance fields:
  - `distanceToGreenCenter: Double?`
  - `distanceToFront: Double?`
  - `distanceToBack: Double?`
  - `hasWaterLeft: Bool`
  - `hasBunkerRight: Bool`

#### Create `ios/Features/Round/HoleMapView.swift` (NEW)
- MapKit view component for displaying hole layout
- User location tracking
- Distance calculations

---

## Configuration Required

### 1. Database Setup

```bash
# Install PostgreSQL + PostGIS
brew install postgresql postgis

# Create database
createdb caddie_golf

# Enable PostGIS
psql caddie_golf -c "CREATE EXTENSION postgis;"

# Run migrations
python -c "from course_mapper.db import db; db.run_migration('db/schema.sql')"
```

### 2. Environment Variables

Create `course-mapper/.env`:
```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/caddie_golf
OVERPASS_API_URL=https://overpass-api.de/api/interpreter
API_HOST=0.0.0.0
API_PORT=8081
```

### 3. iOS Configuration

Update `ios/Services/CourseMapperService.swift`:
- Line 11: Update IP address for physical device testing:
  ```swift
  return "http://YOUR_MAC_IP:8081"
  ```

---

## Data Flow

```
OSM Data (Overpass API)
    ↓
osm_ingest.py → Normalize → PostGIS Database
    ↓
FastAPI Server (Port 8081)
    ↓
CourseMapperService.swift → iOS App
    ↓
RoundPlayView → MapKit Map + GPS Tracking
```

---

## Remaining Tasks

### High Priority

1. **Fix GeoJSON Models** (`ios/Models/HoleLayout.swift`)
   - The GeoJSON coordinate parsing needs refinement for complex polygons
   - Test with real API responses

2. **Update CourseService** (`ios/Services/CourseService.swift`)
   - Integrate `CourseMapperService` as fallback
   - Merge results from both APIs

3. **Create HoleMapView** (`ios/Features/Round/HoleMapView.swift`)
   - MapKit view with hole layout overlays
   - User location tracking
   - Distance calculations

4. **Update RoundPlayView** (`ios/Features/Round/RoundPlayView.swift`)
   - Add MapKit map section
   - Fetch and display hole layout
   - Show GPS-based distances

5. **Update ShotContext** (`ios/Models/ShotContext.swift`)
   - Add GPS distance fields
   - Update RecommenderService to use GPS distances

### Medium Priority

6. **Test OSM Ingestion**
   - Run ingestion for a real course
   - Verify data in database

7. **Add MapKit Annotations**
   - Green center marker
   - Front/middle/back pin positions
   - Hazard warnings

### Low Priority (Future)

8. **Implement Satellite Segmentation**
   - Train/use ML model for feature extraction
   - Replace stub in `satellite_processing.py`

9. **Implement Elevation Processing**
   - Connect to DEM/LIDAR provider
   - Replace stub in `elevation_processing.py`

---

## Testing Checklist

- [ ] Start PostgreSQL and run migrations
- [ ] Start course-mapper FastAPI server
- [ ] Test `/health` endpoint
- [ ] Ingest a test course from OSM
- [ ] Test `/courses/nearby` endpoint
- [ ] Test `/courses/{id}/holes/{number}/layout` endpoint
- [ ] Update iOS app to use course-mapper API
- [ ] Test on simulator
- [ ] Test on physical iPhone
- [ ] Verify MapKit map displays correctly
- [ ] Verify GPS distances calculate correctly

---

## Known Issues & Limitations

1. **GeoJSON Parsing**: The coordinate parsing in `HoleLayout.swift` may need refinement for complex geometries
2. **Satellite Processing**: Currently stubbed - needs ML model implementation
3. **Elevation Data**: Currently stubbed - needs DEM/LIDAR provider integration
4. **OSM Data Quality**: OSM data varies - may need manual curation for production

---

## Next Steps

1. **Immediate**: Fix GeoJSON parsing and test with real API responses
2. **Short-term**: Complete MapKit integration in RoundPlayView
3. **Medium-term**: Test with real course data and refine UI
4. **Long-term**: Implement ML segmentation and elevation processing

---

## Support Files

- `course-mapper/README.md` - Backend setup guide
- `backend/QUICK_START.md` - Node backend quick start
- This file - Integration summary

---

**Last Updated**: December 2024
**Status**: Phase 1-2 Complete, Phase 3 In Progress

