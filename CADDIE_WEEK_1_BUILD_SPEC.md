# Caddie.AI — Week 1 Build Spec

**Document Version:** 1.0  
**Date:** March 2025  
**Status:** Implementation Plan — No Code Yet  
**Scope:** Backend foundational infrastructure for Play mode

---

## 1. Week 1 Goals

Week 1 must accomplish:

| Goal | Deliverable |
|------|-------------|
| **1. Golf course intelligence database** | Postgres schema deployed; tables for courses, tees, holes, hole_geometry, course_place_mappings |
| **2. CSV ingestion pipeline** | Script(s) that load courses.csv, coordinates.csv, tees.csv, clubs.csv into the database |
| **3. Google Places integration** | Backend endpoints that call Google Places API; API key from env; normalized responses |
| **4. Course matching layer** | Logic to match Google Place → Golf API course; persist in course_place_mappings |
| **5. Backend course intelligence endpoints** | API endpoints that serve course details, tees, holes, green coordinates for Play mode |

**Out of scope for Week 1:** iOS UI, Play tab, map, hole detection, recommendation enrichment. This week is backend-only.

**Constraints from addendum:**
- Never block the round: endpoints must degrade gracefully when data is missing
- MUST PREFETCH data must be available from these endpoints
- Caching strategy must align with prefetch requirements

---

## 2. Database Architecture

### 2.0 PostGIS Requirement

**PostGIS is required** for the Week 1 database foundation. It is not optional.

**Setup:** `CREATE EXTENSION postgis;` (run once per database)

**Why PostGIS is required:**
- **Course proximity search** — Find courses within N km of user location; ST_DWithin and spatial indexes are efficient
- **Google Place ↔ Golf API matching** — Distance between Google Place coordinates and Golf API course location is a core matching signal
- **Future hole detection** — Point-in-polygon and distance-to-point queries for automatic hole detection
- **Future distance calculations** — User-to-green distance; spatial functions handle geodesic distance correctly
- **Future geometry handling** — Hole polygons, green boundaries, hazard zones will use PostGIS types

Without PostGIS, proximity and matching logic would require manual haversine implementations and lack optimized spatial indexing.

---

### 2.1 Table: `courses`

Canonical golf course records from Golf API CSV.

| Column | Type | Constraints | Notes |
|--------|------|--------------|-------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | Internal ID; exposed to API |
| external_id | TEXT | UNIQUE, NOT NULL | Golf API course ID; used for dedup |
| name | TEXT | NOT NULL | Display name |
| city | TEXT | | |
| state | TEXT | | 2-letter or full |
| country | TEXT | DEFAULT 'USA' | |
| lat | DOUBLE PRECISION | | Redundant with location; kept for compatibility |
| lon | DOUBLE PRECISION | | |
| location | GEOGRAPHY(POINT, 4326) | NOT NULL | PostGIS point; computed during ingestion |
| created_at | TIMESTAMPTZ | DEFAULT now() | |
| updated_at | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_courses_external_id` ON courses(external_id) — lookup by Golf API ID
- `idx_courses_name_trgm` ON courses USING gin(name gin_trgm_ops) — name search (requires pg_trgm)
- `idx_courses_location` ON courses USING GIST(location) — **spatial index for proximity and matching**
- `idx_courses_city_state` ON courses(city, state) — matching

**Note:** `location` is populated during ingestion. See Section 3.5 for course center computation. `lat`/`lon` are derived from `location` for API responses and backward compatibility.

---

### 2.2 Table: `tees`

Tee sets per course.

| Column | Type | Constraints | Notes |
|--------|------|--------------|-------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | |
| course_id | UUID | NOT NULL, REFERENCES courses(id) ON DELETE CASCADE | |
| name | TEXT | NOT NULL | e.g. "Blue", "White", "Red" |
| color | TEXT | | Optional |
| total_yards | INT | | Sum of hole yardages |
| rating | DECIMAL(4,1) | | USGA rating |
| slope | INT | | Slope rating |
| created_at | TIMESTAMPTZ | DEFAULT now() | |
| updated_at | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_tees_course_id` ON tees(course_id) — fetch tees by course

**Unique:** (course_id, name) — one tee set per name per course

---

### 2.3 Table: `holes`

Hole-level data per course (par, handicap). Par is same across tees; yardage varies.

| Column | Type | Constraints | Notes |
|--------|------|--------------|-------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | |
| course_id | UUID | NOT NULL, REFERENCES courses(id) ON DELETE CASCADE | |
| hole_number | INT | NOT NULL, CHECK (hole_number BETWEEN 1 AND 18) | |
| par | INT | NOT NULL, CHECK (par BETWEEN 3 AND 6) | |
| handicap | INT | CHECK (handicap BETWEEN 1 AND 18) | Stroke index |
| created_at | TIMESTAMPTZ | DEFAULT now() | |
| updated_at | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_holes_course_id` ON holes(course_id)
- `idx_holes_course_number` ON holes(course_id, hole_number) — hole lookup

**Unique:** (course_id, hole_number)

---

### 2.4 Table: `tee_hole_yardages`

Yardage per tee per hole. Links tees to holes with distance.

| Column | Type | Constraints | Notes |
|--------|------|--------------|-------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | |
| tee_id | UUID | NOT NULL, REFERENCES tees(id) ON DELETE CASCADE | |
| hole_id | UUID | NOT NULL, REFERENCES holes(id) ON DELETE CASCADE | |
| yards | INT | NOT NULL, CHECK (yards > 0) | Tee to green |
| created_at | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_tee_hole_yardages_tee_id` ON tee_hole_yardages(tee_id)
- `idx_tee_hole_yardages_hole_id` ON tee_hole_yardages(hole_id)
- `idx_tee_hole_yardages_tee_hole` ON tee_hole_yardages(tee_id, hole_id) — **compound index for primary lookup pattern**

**Why the compound index matters:** The app will most often look up yardage by (tee_id, hole_id) when building the full course payload. A compound index on (tee_id, hole_id) makes this lookup fast and supports efficient JOINs when assembling holes with yardages by tee. Without it, separate indexes on tee_id and hole_id may require less efficient index scans.

**Unique:** (tee_id, hole_id)

---

### 2.5 Table: `hole_geometry`

Green center coordinates and optional polygon geometry. **Critical for hole detection and distance.**

| Column | Type | Constraints | Notes |
|--------|------|--------------|-------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | |
| hole_id | UUID | NOT NULL, REFERENCES holes(id) ON DELETE CASCADE, UNIQUE | One geometry per hole |
| green_center_lat | DOUBLE PRECISION | | **MUST for distance** |
| green_center_lon | DOUBLE PRECISION | | **MUST for distance** |
| green_front_lat | DOUBLE PRECISION | | Optional; front of green |
| green_front_lon | DOUBLE PRECISION | | |
| green_back_lat | DOUBLE PRECISION | | Optional |
| green_back_lon | DOUBLE PRECISION | | |
| geometry_geojson | JSONB | | Optional; polygon for point-in-polygon detection |
| created_at | TIMESTAMPTZ | DEFAULT now() | |
| updated_at | TIMESTAMPTZ | DEFAULT now() | |

**Indexes:**
- `idx_hole_geometry_hole_id` ON hole_geometry(hole_id)
- `idx_hole_geometry_green_center` ON hole_geometry(green_center_lat, green_center_lon) — **supports distance lookups and geometry queries**

**Why the green center index matters:** Future hole distance lookups (user location → nearest green) and geometry-based queries will filter or sort by green coordinates. This index speeds retrieval of green coordinate data when building hole payloads and supports proximity-based hole detection.

**Constraint:** green_center_lat/lon must be valid (-90 to 90, -180 to 180). At least green_center must be populated for hole to support distance calculation.

---

### 2.6 Table: `course_place_mappings`

Maps Google Place ID to Golf API course. Persisted so matching happens once.

| Column | Type | Constraints | Notes |
|--------|------|--------------|-------|
| google_place_id | TEXT | PRIMARY KEY | From Google Places API |
| golf_course_id | UUID | NOT NULL, REFERENCES courses(id) ON DELETE CASCADE | |
| confidence | DECIMAL(3,2) | NOT NULL, CHECK (confidence >= 0 AND confidence <= 1) | Match confidence |
| matched_at | TIMESTAMPTZ | DEFAULT now() | |
| source | TEXT | DEFAULT 'auto' | 'auto' or 'manual' |

**Indexes:**
- `idx_course_place_mappings_golf_course_id` ON course_place_mappings(golf_course_id) — reverse lookup

---

### 2.7 Extensions (Required)

- `CREATE EXTENSION postgis;` — **Required.** Spatial types and indexes for courses.location; proximity search; matching; future hole detection and distance.
- `CREATE EXTENSION pg_trgm;` — For trigram similarity on course names (matching and search)

PostGIS is a Week 1 requirement. Database setup must include PostGIS before running migrations.

---

## 3. CSV Ingestion System

### 3.1 Input Files

| File | Expected Content | Maps To |
|------|------------------|---------|
| courses.csv | course_id, course_name, city, state, country, etc. | courses |
| coordinates.csv | course_id, hole_number, lat, lon (green center or tee) | hole_geometry |
| tees.csv | course_id, tee_name, tee_color, total_yards, rating, slope | tees |
| clubs.csv | May contain hole yardages per tee; or separate structure | tee_hole_yardages |

**Day 1 task:** Inspect actual CSV structure. Column names and structure may differ. This spec assumes common patterns; adjust mapping after inspection.

---

### 3.2 Ingestion Script Architecture

**Recommended approach:** Node.js or Python script(s) runnable via CLI.

**Phases:**

1. **Parse & validate** — Read each CSV; validate encoding (UTF-8); detect delimiter (comma, semicolon)
2. **Normalize** — Trim whitespace; validate numeric ranges; reject invalid rows; log errors
3. **Resolve IDs** — Build in-memory map: external_id → internal UUID for courses, tees, holes
4. **Upsert in order** — courses → holes → tees → tee_hole_yardages → hole_geometry
5. **Report** — Rows inserted, updated, skipped, failed

**Id mapping strategy:**
- **courses:** external_id (from CSV) → generate or lookup existing by external_id; use UUID for id
- **holes:** (course_id, hole_number) → lookup course by external_id, then upsert hole
- **tees:** (course_id, tee_name) → same
- **tee_hole_yardages:** (tee_id, hole_id) → resolve via tee name + course, hole number
- **hole_geometry:** hole_id → one row per hole; upsert by hole_id

**Deduplication:**
- courses: ON CONFLICT (external_id) DO UPDATE
- holes: ON CONFLICT (course_id, hole_number) DO UPDATE
- tees: ON CONFLICT (course_id, name) DO UPDATE (add unique constraint)
- tee_hole_yardages: ON CONFLICT (tee_id, hole_id) DO UPDATE
- hole_geometry: ON CONFLICT (hole_id) DO UPDATE (hole_id unique)

---

### 3.3 Data Validation Strategy

| Field | Validation | On Failure |
|-------|------------|------------|
| lat, lon | -90 ≤ lat ≤ 90, -180 ≤ lon ≤ 180 | Skip row; log |
| par | 3 ≤ par ≤ 6 | Default 4; log |
| hole_number | 1 ≤ hole_number ≤ 18 | Skip row; log |
| yards | > 0, < 1000 | Skip row; log |
| course name | Not empty after trim | Skip row; log |
| external_id | Not empty | Skip row; log |

**Logging:** Write validation errors to `ingestion_errors.log` with row number and reason. Do not fail entire run for single bad rows.

---

### 3.4 Ingestion Order

1. **courses** — Insert/update all courses first (with initial lat/lon from source)
2. **holes** — Insert holes (depend on courses)
3. **tees** — Insert tees (depend on courses)
4. **tee_hole_yardages** — Insert yardages (depend on tees and holes)
5. **hole_geometry** — Insert geometry (depend on holes)
6. **Recompute course center** — Update courses.location (and lat/lon) from hole_geometry green centers (see Section 3.5)

**Coordinates:** If coordinates.csv has (course_id, hole_number, lat, lon), map to hole_geometry. If it has multiple points per hole (tee, green center, etc.), use type column or naming to distinguish. Green center is required for distance; others optional.

---

### 3.5 Precompute Course Center During Ingestion

**Problem:** Source course lat/lon may point to clubhouse, parking lot, or first tee — not the geometric center of play. This hurts Google Places matching accuracy and nearby course queries.

**Solution:** After hole_geometry is loaded, compute a more accurate course center for each course:

1. **When green centers are available:** Compute centroid (average of green_center_lat, green_center_lon) across all holes for that course. Update courses.location with `ST_SetSRID(ST_MakePoint(avg_lon, avg_lat), 4326)::geography` and sync lat/lon.
2. **When green centers are NOT available:** Fall back to source course lat/lon from courses.csv. Use `ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography` for location.

**Why this matters:**
- **Google Places matching accuracy** — Matching uses distance between Google Place and Golf API course. A centroid of greens is closer to the "true" course location than a clubhouse or noisy point.
- **Nearby course queries** — Proximity search returns courses ordered by distance; accurate center improves ranking.
- **More reliable course location** — Centroid represents the playing area; source data can be inconsistent.

**Implementation:** Run as final step after hole_geometry ingestion. Only update courses that have at least one hole with valid green_center_lat/lon.

---

### 3.6 Dry-Run Mode

**Flag:** `--dry-run` (or `-n`)

**Behavior:**
- Parse and validate all CSV files
- Apply mapping logic and resolve IDs
- Report what would be inserted/updated (counts per table)
- **Do not write to the database**

**Output format:**
```
[DRY RUN] Would insert: 1,234 courses, 22,212 holes, 3,702 tees, ...
[DRY RUN] Would update: 0 courses, ...
[DRY RUN] Would skip: 12 rows (validation errors)
[DRY RUN] No database changes made.
```

**Why this is useful:**
- **Safer CSV testing** — Test new CSV files or schema changes without modifying production data
- **Easier debugging of schema mapping** — Verify mapping logic before committing
- **Easier validation before full production ingest** — Run dry-run on full dataset to catch issues early

---

### 3.7 Progress Reporting

**During ingestion:** Emit progress output so long-running imports can be monitored.

**By file:**
- `Processing courses.csv: 10,000 / 42,000 rows (24%)`
- `Processing holes.csv: 180,000 / 360,000 rows (50%)`
- etc.

**Frequency:** Every N rows (e.g. 1,000 or 5,000) or every N seconds, whichever is more frequent. Avoid flooding logs.

**Why this matters:**
- **Long CSV imports are easier to monitor** — 100k+ row imports can take minutes; progress confirms the script is running
- **Debugging becomes much easier** — If a failure occurs, progress shows which file and approximate row
- **Helps identify where failures occur** — "Processed 10,000 / 42,000" then crash narrows the problem

---

### 3.8 Script Output

- Summary: X courses, Y holes, Z tees inserted/updated
- Error count and log file path
- Progress output during run (see Section 3.7)
- Optional: Export sample of ingested data for verification

---

## 4. Google Places Integration

### 4.1 Environment

- `GOOGLE_PLACES_API_KEY` — Required; loaded from environment; never logged or exposed to client
- Backend only; iOS never calls Google directly

---

### 4.2 Endpoints to Implement

| Endpoint | Google API Used | Purpose |
|----------|-----------------|---------|
| Autocomplete | Places Autocomplete | User types "Pebble" → suggestions |
| Place Details | Place Details | User selects suggestion → full place info |
| Nearby Search | Places Nearby Search | Location-based course discovery |

---

### 4.3 Autocomplete

**Backend route:** `GET /api/courses/autocomplete?query=&lat=&lon=`

**Google call:** Places Autocomplete API with:
- input: query
- types: establishment (or no type to allow golf courses)
- locationbias: circle around (lat, lon) with radius ~50km if lat/lon provided

**Normalized response:**
```json
{
  "suggestions": [
    {
      "placeId": "ChIJ...",
      "name": "Pebble Beach Golf Links",
      "formattedAddress": "1700 17 Mile Dr, Pebble Beach, CA 93953",
      "lat": 36.5674,
      "lon": -121.9500,
      "city": "Pebble Beach",
      "state": "CA"
    }
  ]
}
```

**Fields to extract:** place_id, description or structured_formatting.main_text, geometry.location, address_components (for city, state)

---

### 4.4 Place Details

**Backend route:** `GET /api/courses/details?placeId=`

**Google call:** Place Details API with place_id; fields: place_id, name, formatted_address, geometry, address_components

**Normalized response:** Same shape as autocomplete suggestion (single object).

---

### 4.5 Nearby Search

**Backend route:** `GET /api/courses/nearby?lat=&lon=&radius_km=`

**Google call:** Places Nearby Search with:
- location: (lat, lon)
- radius: radius_km * 1000 (meters)
- type: golf_course OR keyword: "golf course"

**Normalized response:** Array of same shape as autocomplete. Include placeId for each so iOS can pass to details or matching.

---

### 4.6 Error Handling

- Google API errors (quota, invalid key): Return 503 with message "Course search temporarily unavailable"
- Never expose API key in error messages
- Timeout: 5s for Google calls; return 504 if exceeded

---

## 5. Course Matching Layer

### 5.1 Purpose

When user selects a course from Google (placeId), resolve to Golf API course (courses.id) so we can serve tees, holes, green coordinates.

---

### 5.2 Matching Flow

1. **Lookup:** Check course_place_mappings for google_place_id
2. **If found:** Return golf_course_id; done
3. **If not found:** Fetch Place Details (if not already have name, lat, lon, city, state)
4. **Match:** Query courses within 2km of (lat, lon) using PostGIS: `ST_DWithin(courses.location, ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography, 2000)` — leverages GIST index for efficient proximity search
5. **Score** each candidate:
   - name_similarity: trigram or Levenshtein (normalize: lowercase, remove "Golf Links", "Golf Club", etc.)
   - distance_km: `ST_Distance(courses.location, point) / 1000` (PostGIS geography; meters → km)
   - city_match: 1 if city matches, 0 otherwise
   - state_match: 1 if state matches, 0 otherwise
6. **Confidence:** weighted combination; e.g. 0.5*name + 0.3*(1 - distance/2) + 0.1*city + 0.1*state
7. **Thresholds:**
   - confidence ≥ 0.8: auto-match; insert mapping; return course_id
   - 0.5 ≤ confidence < 0.8: return top 3 candidates for disambiguation
   - confidence < 0.5: return null; "Course data unavailable"

---

### 5.3 Name Normalization

- Lowercase
- Remove common suffixes: "Golf Links", "Golf Club", "Country Club", "Golf Course"
- Trim
- For similarity: use pg_trgm similarity() or Levenshtein distance

---

### 5.4 Persistence

- On auto-match: INSERT INTO course_place_mappings (google_place_id, golf_course_id, confidence, source)
- On user disambiguation: INSERT with chosen golf_course_id
- Never overwrite existing mapping (placeId is primary key)

---

### 5.5 Integration Point

Matching is invoked when:
- User selects from autocomplete → backend calls details → matching → returns course_id + full course payload
- User selects from nearby → backend has placeId → matching → returns course_id + full course payload

Endpoint that performs matching: `POST /api/courses/resolve` or embedded in `GET /api/courses/details?placeId=&resolve=1`

---

## 6. Backend API Endpoints

### 6.1 Endpoint Summary

| Method | Path | Purpose |
|--------|------|---------|
| GET | /api/courses/autocomplete | Search suggestions |
| GET | /api/courses/details | Place details + optional resolve to Golf API |
| GET | /api/courses/nearby | Nearby courses (Google) |
| GET | /api/courses/:id | Full course + tees + holes + green coords (MUST PREFETCH payload) |
| GET | /api/courses/:id/tees | Tees for course |
| GET | /api/courses/:id/holes | Holes with par, green center, yardages by tee |
| GET | /api/courses/:id/holes/:number/layout | Hole geometry (NICE TO PREFETCH; optional) |

---

### 6.2 GET /api/courses/:id

**Purpose:** Single payload for round setup. Must include everything needed for MUST PREFETCH.

**Response:**
```json
{
  "id": "uuid",
  "name": "Pebble Beach Golf Links",
  "city": "Pebble Beach",
  "state": "CA",
  "lat": 36.5674,
  "lon": -121.9500,
  "tees": [
    {
      "id": "uuid",
      "name": "Blue",
      "totalYards": 7075,
      "rating": 75.5,
      "slope": 145
    }
  ],
  "holes": [
    {
      "holeNumber": 1,
      "par": 4,
      "handicap": 5,
      "greenCenter": { "lat": 36.568, "lon": -121.949 },
      "greenFront": { "lat": 36.5682, "lon": -121.949 },
      "greenBack": { "lat": 36.5678, "lon": -121.949 },
      "yardagesByTee": {
        "Blue": 495,
        "White": 460
      }
    }
  ]
}
```

**Source:** courses + tees + holes + tee_hole_yardages + hole_geometry. Single query or joined query.

**Graceful degradation:** If hole_geometry missing for a hole, omit greenCenter/greenFront/greenBack; iOS will use course center or manual distance. If no tees, return empty array. Never 500.

---

### 6.3 GET /api/courses/:id/tees

**Purpose:** Tee list for tee selection UI.

**Response:** Array of { id, name, totalYards, rating, slope }

---

### 6.4 GET /api/courses/:id/holes

**Purpose:** Hole data with par, green center, yardages. Supports distance engine and hole detection.

**Response:** Array of { holeNumber, par, handicap, greenCenter: {lat, lon}, greenFront?, greenBack?, yardagesByTee: { teeName: yards } }

---

### 6.5 GET /api/courses/:id/holes/:number/layout

**Purpose:** NICE TO PREFETCH. Optional polygon geometry for point-in-polygon hole detection.

**Response:** { greenPolygon: GeoJSON, fairwayPolygon?: GeoJSON, ... } or 404 if not available.

**Note:** May be populated from CourseMapper or future pipeline. Week 1 can return 404; iOS will use distance-based detection.

---

### 6.6 Resolve Flow (Google → Golf API)

When iOS has placeId and needs course_id:

**Option A:** `GET /api/courses/details?placeId=&resolve=1` — Returns place details + resolved course (if match found)

**Option B:** `POST /api/courses/resolve` — Body: { placeId }; returns { courseId, course, matched } or { candidates } or { error: "no match" }

Recommendation: Option A for simplicity. Backend fetches details, runs matching, returns unified payload.

---

## 7. Caching Strategy

### 7.1 Backend Caching

| Data | Cache? | TTL | Location |
|------|-------|-----|----------|
| course_place_mappings | N/A | Permanent | Postgres; lookup is fast |
| courses, tees, holes, hole_geometry | No | N/A | Postgres is source of truth; queries are cheap |
| Google Place Details | Optional | 1 hour | In-memory cache keyed by placeId; reduces Google API calls |

**Recommendation:** No Redis for Week 1. Postgres is sufficient. Add in-memory cache for Place Details if Google quota is a concern.

---

### 7.2 iOS Caching (Future; Document for Week 2)

Per addendum prefetch strategy:

| Data | When Cached | Storage |
|------|-------------|---------|
| Course details (full payload) | At course selection | In-memory until round start |
| Tees | At course selection | In-memory |
| Hole data (par, green center, yardages) | At round start (MUST PREFETCH) | ActiveRoundContext |
| Hole layout (polygon) | At round start (NICE TO PREFETCH) | ActiveRoundContext; optional |
| placeId → courseId | Returned from backend; store in mapping | In-memory for session |

**Backend responsibility:** Serve full payload in single GET /courses/:id so iOS can prefetch once at round start. No per-hole fetches.

---

### 7.3 Alignment with Addendum

- **MUST PREFETCH** data (course, tee, holes, par, green center, yardages) must be available from GET /courses/:id in one call
- **NICE TO PREFETCH** (hole layout/polygon) is separate endpoint; iOS can fetch in background without blocking round start
- Backend must not require multiple round-trips for round setup

---

## 8. Testing Plan

### 8.1 CSV Ingestion Tests

| Test | Description |
|------|-------------|
| **Ingestion success** | Run script on sample CSV; verify row counts in each table |
| **Dry-run mode** | Run with --dry-run; verify no DB writes, correct reported counts |
| **Progress reporting** | Run on large CSV; verify progress output (e.g. "Processed 10,000 / 42,000 rows") |
| **Course center precomputation** | Ingest course with hole_geometry; verify courses.location and lat/lon reflect centroid of green centers |
| **Deduplication** | Run script twice; verify no duplicate courses/holes/tees |
| **Validation** | Feed invalid rows (bad lat, bad par); verify they are skipped and logged |
| **Idempotency** | Re-run after partial run; verify no errors, correct final state |
| **Green center presence** | Verify hole_geometry has green_center_lat/lon for holes that should have it |

---

### 8.2 Course Search Tests

| Test | Description |
|------|-------------|
| **Autocomplete** | Query "Pebble"; verify suggestions returned with placeId, name, lat, lon |
| **Autocomplete with bias** | Pass lat/lon; verify nearby courses appear first |
| **Place details** | Pass placeId from autocomplete; verify full details |
| **Nearby search** | Pass lat/lon near known course; verify course in results |
| **Error handling** | Invalid API key; verify 503, no key exposure |

---

### 8.3 Course Matching Tests

| Test | Description |
|------|-------------|
| **Exact match** | PlaceId for "Pebble Beach Golf Links"; verify correct course_id returned |
| **Proximity query** | Matching uses PostGIS ST_DWithin for courses within 2km; verify GIST index used |
| **Name variant** | "Pebble Beach" vs "Pebble Beach Golf Links"; verify match |
| **Persistence** | Match once; query again with same placeId; verify instant return from mappings |
| **No match** | PlaceId for non-golf place; verify null or "no match" |
| **Ambiguous** | Two courses with similar names nearby; verify disambiguation candidates returned |

---

### 8.4 Hole Data Tests

| Test | Description |
|------|-------------|
| **GET /courses/:id** | Verify full payload: tees, holes, green center, yardages |
| **GET /courses/:id/holes** | Verify par, greenCenter for each hole |
| **GET /courses/:id/tees** | Verify tee list |
| **Missing geometry** | Course with no hole_geometry; verify 200 with null greenCenter; no 500 |
| **Hole layout 404** | GET /courses/:id/holes/1/layout when not populated; verify 404 |

---

### 8.5 Manual Verification

- Ingest real Golf API CSV; spot-check 5 courses in DB
- Search for "Pebble Beach" via autocomplete; select; verify resolve works
- Call GET /courses/:id for resolved course; verify holes have green coordinates

---

## 9. Week 1 Deliverables Checklist

- [ ] Postgres schema deployed (migrations) with **PostGIS extension required**
- [ ] CSV ingestion script runs successfully
- [ ] Ingestion script supports **--dry-run** mode (validate, report, no DB writes)
- [ ] Ingestion script emits **progress reporting** (e.g. "Processed 10,000 / 42,000 rows")
- [ ] **Course center precomputed** from hole_geometry green centers (or fallback to source lat/lon)
- [ ] courses, tees, holes, tee_hole_yardages, hole_geometry populated
- [ ] course_place_mappings table created (empty until first match)
- [ ] Google Places: autocomplete, details, nearby endpoints
- [ ] GOOGLE_PLACES_API_KEY in env
- [ ] Course matching logic implemented
- [ ] GET /api/courses/:id returns full payload
- [ ] GET /api/courses/:id/tees, /holes, /holes/:n/layout
- [ ] Resolve flow (placeId → courseId) working
- [ ] Tests passing
- [ ] Documentation for API endpoints

---

*End of Week 1 Build Spec. No code has been implemented. Plan to be reviewed before implementation.*
