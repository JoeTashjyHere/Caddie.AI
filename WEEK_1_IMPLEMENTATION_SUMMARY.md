# Caddie.AI Week 1 Implementation Summary

**Date:** March 2025  
**Scope:** Backend foundational infrastructure only. No Play tab UI, map, hole detection, or recommendation enrichment.

---

## 1. What Was Implemented

### Part 1 — Database Schema

- **Postgres + PostGIS** (required)
- **Tables:**
  - `golf_clubs` — Venue from clubs.csv (ClubID, name, address, city, state, lat/lon, location geography)
  - `golf_courses` — Course layout from courses.csv (CourseID, club_id, course_name, num_holes, lat/lon, location)
  - `golf_course_holes` — Par, handicap per hole (from courses.csv Par1..Par18, Hcp1..Hcp18)
  - `golf_tees` — Tee sets from tees.csv
  - `golf_tee_hole_lengths` — Yardage per tee per hole (from tees.csv Length1..Length18)
  - `golf_hole_pois` — POI geometry from coordinates.csv (CourseID, Hole, POI, Location, lat, lon)
  - `course_place_mappings` — Google Place ID → golf_courses

- **Indexes:** Trigram on names, GIST on location, compound indexes for tee+hole lookups
- **Course center:** Precomputed from green POI centroid (Green C) or fallback to club lat/lon

### Part 2 — CSV Ingestion

- **Script:** `backend/scripts/ingest.js`
- **Order:** clubs → courses → holes → tees → tee_hole_lengths → pois → course center
- **Features:** Idempotent, dry-run, progress reporting, validation logging
- **Mappings:**
  - clubs.csv → golf_clubs
  - courses.csv → golf_courses + golf_course_holes
  - tees.csv → golf_tees + golf_tee_hole_lengths (meters→yards when MeasureUnit=m)
  - coordinates.csv → golf_hole_pois (uses CourseID; POIs per course)

### Part 3 — Google Places Backend

- **Endpoints:** `/api/courses/autocomplete`, `/api/courses/details`, `/api/courses/nearby`
- **Env:** `GOOGLE_PLACES_API_KEY` (never exposed to client)
- **Normalized response:** placeId, name, formattedAddress, lat, lon, city, state

### Part 4 — Course Matching

- **Flow:** Check course_place_mappings → fetch Place Details → query golf_courses within 2km (PostGIS ST_DWithin) → score by name, distance, city, state
- **Club→course:** Match to golf_courses (which have location from centroid or club). If one course at club: auto-resolve. If multiple: return candidates for disambiguation.
- **Endpoints:** `GET /api/courses/details?placeId=&resolve=1`, `POST /api/courses/resolve`

### Part 5 — Course Intelligence Endpoints

- `GET /api/courses/:id` — Full MUST PREFETCH payload (course, club, tees, holes, green centers, yardages)
- `GET /api/courses/:id/tees`
- `GET /api/courses/:id/holes`
- `GET /api/courses/:id/holes/:number/layout` — POI layout (polygons future enhancement)

### Part 6 — Testing / Validation

- `npm run migrate` — Apply schema
- `npm run validate` — Row counts and sample queries
- `npm run ingest:dry` — Dry-run ingestion

---

## 2. Files Created

| Path | Purpose |
|------|---------|
| `backend/migrations/001_golf_schema.sql` | PostGIS + golf schema |
| `backend/scripts/ingest.js` | CSV ingestion pipeline |
| `backend/scripts/run-migrations.js` | Run migrations |
| `backend/scripts/validate-ingestion.js` | Post-ingestion validation |
| `backend/services/googlePlaces.js` | Google Places API |
| `backend/services/courseMatching.js` | Place → course matching |
| `backend/services/courseIntelligence.js` | Course payload assembly |
| `backend/routes/courses.js` | Course API routes |
| `backend/.env.example` | Env template |

---

## 3. Files Modified

| Path | Changes |
|------|---------|
| `backend/package.json` | Added csv-parse, dotenv; ingest, migrate, validate scripts |
| `backend/index.js` | dotenv, dbPool as app.set; courses router; legacy /api/courses preserved |

---

## 4. Database Schema

See `backend/migrations/001_golf_schema.sql`. Key points:

- `CREATE EXTENSION postgis;` and `pg_trgm`
- `golf_clubs.location`, `golf_courses.location`, `golf_hole_pois.location` as GEOGRAPHY(POINT, 4326)
- GIST indexes for spatial queries
- Compound index on `golf_tee_hole_lengths(tees_id, hole_number)`

---

## 5. Ingestion Commands

```bash
cd backend

# 1. Run migrations (requires Postgres with PostGIS)
DATABASE_URL=postgresql://user:pass@localhost:5432/caddie npm run migrate

# 2. Dry-run (no DB writes)
npm run ingest:dry -- --data-dir=/path/to/coursedb_america

# 3. Full ingestion
DATABASE_URL=postgresql://... npm run ingest -- --data-dir=/path/to/coursedb_america

# 4. Validate
DATABASE_URL=postgresql://... npm run validate
```

---

## 6. Assumptions / CSV Ambiguity

1. **coordinates.csv uses CourseID** (not ClubID). The file header is `CourseID,Hole,POI,...`. POIs are per course. When a club has multiple courses, each course has its own POIs.

2. **Green center:** We use POI="Green" and Location="C" (center) for course centroid. If missing, fallback to club lat/lon.

3. **Invalid hole numbers:** Some coordinates have hole numbers outside 1–18 (e.g. 27-hole layouts). These rows are skipped and logged.

4. **tees_id:** Composite `CourseID-TeeID` used as unique tees_id (TeeID alone can repeat across courses).

5. **9-hole courses:** Only holes 1–9 created for num_holes=9. Tee lengths for holes 10–18 are skipped.

---

## 7. Blockers / Questions for User

1. **API key:** `GOOGLE_PLACES_API_KEY` must be set in `.env`. Do not commit the key. Use `backend/.env.example` as template.

2. **Postgres + PostGIS:** Local or cloud Postgres must have PostGIS installed. For Render/Railway, use a Postgres add-on with PostGIS.

3. **Data path:** Ingestion expects `--data-dir` pointing to a folder with `clubs.csv`, `courses.csv`, `tees.csv`, `coordinates.csv`.

4. **Hole layout polygons:** The layout endpoint returns POI points only. Full polygon geometry for point-in-polygon hole detection is a future enhancement when data is available.
