# Caddie.AI — 30-Day Execution Blueprint

**Document Version:** 1.0  
**Date:** March 2025  
**Status:** Execution Planning — No Code Changes  
**Target:** Near-final product in 30 days

---

## PART 1 — VALIDATE THE EXISTING ARCHITECTURE PLAN

### 1.1 What Is Already Aligned With the Real Codebase

| Plan Element | Codebase Reality | Alignment |
|--------------|------------------|-----------|
| 3 tabs (Caddie, History, Profile) | ContentView has exactly these; Play not in TabView | ✓ Correct |
| PlayView, RoundPlayView exist | Both exist; PlayView has course selection, RoundPlayView has scoring | ✓ Correct |
| CaddieHomeView: Photo required for shot | No Quick Mode; ContextConfirmSheet requires course, city, state, hole, distance | ✓ Correct |
| CourseService → Node backend, fallback CourseMapper | Confirmed; getNearbyCourses, searchCourses | ✓ Correct |
| Course model: id, name, location, par | No tee sets, no hole-level data | ✓ Correct |
| HoleLayout, HoleLayoutResponse | Exists; greens, fairways, bunkers, water, tees as GeoJSON | ✓ Correct |
| CaddieShotViewModel.checkCurrentHole | Exists; uses CourseMapperService.fetchHoleLayout, point-in-polygon + 50yd green center | ✓ Correct |
| LocationService | CoreLocation, simulator mock Pebble Beach | ✓ Correct |
| ScoreTrackingService, Round, HoleScore | Round has holes with par 4 stub; no hole-level par from course | ✓ Correct |
| HistoryStore, HistoryItem | UserDefaults, max 200; no round linkage | ✓ Correct |
| CourseMapView | Exists; shows course pins, centers on user; no user location annotation on map | Partial — needs user pin |
| RoundPlayView distances | Stub values (145, 152, 160) — not GPS-based | ✗ Must fix |
| Par per hole | Hardcoded 4 | ✗ Must fix |

### 1.2 Assumptions Needing Correction

1. **"Manual hole selection only for MVP"** — User requires automatic hole detection. The plan’s "later" designation is wrong. `checkCurrentHole` already exists in CaddieShotViewModel; it must be integrated into RoundPlayView/ActiveRoundContext.

2. **"Simple map (pin only)"** — User requires live-updating map with user location. CourseMapView exists but does not show user as annotation. Must add user location pin and live updates.

3. **"Distance from user"** — Currently distance is user-entered in ContextConfirmSheet. RoundPlayView uses stub distances. Automatic distance (user → green center) must be the source of truth.

4. **Course ID mismatch** — CourseMapper uses OSM-derived course IDs. Node backend returns Course with its own id. Golf API will add a third ID space. The plan must define a unified ID strategy: **Golf API course_id is canonical**; Google placeId maps to it; CourseMapper can be matched via name+coords when needed.

5. **Hole detection performance** — Current `checkCurrentHole` loops 1–18 and calls `fetchHoleLayout` per hole (18 network calls). This is too slow for live rounds. Hole geometries must be **prefetched at round start** and cached in memory.

### 1.3 Strongest Existing Systems to Leverage

| System | Strength | Leverage |
|--------|----------|----------|
| **HoleLayout + GeoJSON parsing** | Full polygon support, green center, front/back | Use for hole detection and distance; extend to consume Golf API coords if needed |
| **CaddieShotViewModel.checkCurrentHole** | Point-in-polygon, green-center proximity | Move into shared HoleDetectionEngine; prefetch layouts |
| **CourseMapperService** | fetchHoleLayout, fetchNearbyCourses | Keep as geometry source when Golf API lacks polygons; need ID mapping |
| **LocationService** | CoreLocation, debouncing possible | Use for continuous location; ensure startUpdating runs during round |
| **RecommenderService** | Photo + context → AI; fallback chain | Extend with course intelligence; add Quick Mode path |
| **buildShotContext** | Weather, elevation, target from CourseMapper | Extend to use Golf API green coords when available |
| **ScoreTrackingService** | Round state, persistence | Extend Round with tee, 9/18, courseId; add par per hole |
| **RoundViewModel** | currentHole, scores, nextHole/prevHole | Add auto hole detection subscription; add distance engine |
| **CourseMapView** | Map, course pins, region updates | Add user annotation; add hole boundary overlay for current hole |

### 1.4 Critical Missing Systems for 30-Day Build

1. **ActiveRoundContext** — Single source of truth for: course, tee, 9/18, current hole, hole geometries (cached), distances (live). Does not exist.

2. **HoleDetectionEngine** — Centralized service: subscribes to location, uses cached hole geometries, emits current hole + confidence. Partially exists in CaddieShotViewModel; must be extracted and used by RoundPlayView.

3. **DistanceEngine** — Computes user → green center (and front/back) from cached hole data. Does not exist.

4. **Course Intelligence Service (Backend)** — Resolves Google placeId → Golf API course; returns tees, holes, pars, green coordinates. Does not exist.

5. **Golf API CSV ingestion** — No pipeline. Must be built first.

6. **Google Places backend** — No autocomplete/details/nearby. Must be built.

7. **Quick Mode** — No no-photo path. Must be added.

8. **Round–Recommendation linkage** — HistoryItem has no roundId. Must add.

9. **Live map with user location** — CourseMapView lacks user annotation. Must add.

10. **Tee selection, 9/18 selection** — Not in UI. Must add.

---

## PART 2 — DEFINE THE FINAL PRODUCT STATE TARGET

### 2.1 30-Day "Near-Final" Product State

By Day 30, the app must deliver:

---

### PLAY TAB

| Capability | Target State |
|------------|--------------|
| **Course discovery** | Location-based nearby courses (Google Places Nearby + bias); search fallback (Google Autocomplete) |
| **Course selection** | User taps course from list or search result; backend resolves to Golf API course |
| **Tee selection** | After course selected, fetch tees from backend; user picks Blue/White/Red etc. |
| **Round length** | User selects: 18 holes, Front 9, or Back 9 |
| **Live-updating map** | Map shows: user location (live pin), current hole boundary (green/fairway), hole number label |
| **Live user location** | CoreLocation updates during round; map recenters/zooms appropriately |
| **Automatic hole detection** | Engine determines current hole from user position (nearest green / point-in-polygon); suggests hole change when user moves |
| **Automatic distance calculation** | Distance to green center (and front/back when available) computed from GPS; displayed as source of truth |
| **Hole progression** | Auto-suggest when hole changes; user can accept or manually override (Next/Prev) |
| **Score tracking** | Per-hole strokes, par from Golf API; live score to par |
| **Get Caddie Recommendation** | Photo Mode + Quick Mode; context prefilled from ActiveRoundContext (course, hole, distance, lie inferred) |
| **Get Putting Read** | Photo capture; context from round (course, hole, location) |
| **Round summary** | At round end: total score, par, score vs par, putts, optional handicap placeholder |

---

### CADDIE TAB

| Capability | Target State |
|------------|--------------|
| **Shot recommendation** | Photo Mode (existing flow); Quick Mode (no photo, manual context) |
| **Green Reader** | Photo → putting analysis; location/course inferred when available |
| **Context inference** | If user has recent course/location, prefill ContextConfirmSheet |

---

### HISTORY TAB

| Capability | Target State |
|------------|--------------|
| **Round history** | List of completed rounds with date, course, score, par |
| **Round detail** | Hole-by-hole scores, total, putts, score vs par |
| **Recommendation history** | Existing list; link to round when applicable (roundId) |
| **Recommendation detail** | Existing; feedback form |
| **Performance insights** | Basic: rounds played, avg score, recommendation count by type |
| **Practice recommendations** | Simple: "You've had X approach shots from 100–150y; consider practicing 9i" |
| **Handicap-related** | If ≥3 rounds: display "Handicap Index (est.): X" using basic formula; no full USGA calc |

---

### PROFILE TAB

| Capability | Target State |
|------------|--------------|
| **Current profile** | Unchanged: basics, golf snapshot, bag, risk, putting |
| **Strategic additions** | Handicap index (optional manual entry) if improves recommendations |
| **Inferred fields** | Skill from average score (already used); no new inference for 30-day |

---

### 2.2 "Working at Optimal State" Definition

- **Play:** User can start a round in under 60 seconds (location → nearby → select → tee → 9/18 → start). During round: map shows position, hole and distance update automatically, one tap to Get Caddie or Get Putting Read with prefilled context.
- **Caddie:** Standalone use works; Quick Mode available; both modes produce course-aware recommendations when context is provided.
- **History:** Rounds and recommendations visible; basic insights and practice hint.
- **Profile:** No regression; optional handicap field if time permits.

---

## PART 3 — SYSTEM ARCHITECTURE REQUIRED

### 3.1 Subsystem Overview

| Subsystem | Purpose | Where | Depends On | Frontend/Backend |
|-----------|---------|-------|------------|------------------|
| **ActiveRoundContext** | Holds course, tee, 9/18, current hole, cached hole data, live distances | iOS | CourseService, LocationService, HoleDetectionEngine, DistanceEngine | iOS |
| **CourseIntelligenceService** | Resolves placeId → Golf API course; returns tees, holes, pars, green coords | Backend | Golf API DB, course_place_mappings, Google Places | Backend |
| **CourseMatchingLayer** | Matches Google Place to Golf API record; persists mapping | Backend | golf_courses, Google Places | Backend |
| **MapLocationEngine** | Provides map region, user annotation, hole overlay; consumes location | iOS | LocationService, ActiveRoundContext | iOS |
| **HoleDetectionEngine** | Subscribes to location; uses cached geometries; emits current hole + confidence | iOS | LocationService, ActiveRoundContext (hole cache) | iOS |
| **DistanceEngine** | Computes user → green center, front, back from cached hole data | iOS | LocationService, ActiveRoundContext (hole cache) | iOS |
| **RecommendationEnrichmentPipeline** | Injects course intelligence into shot/putt requests | iOS + Backend | ActiveRoundContext, CourseIntelligenceService | Both |
| **ScoreTrackingService** (extended) | Round state, par per hole, round summary | iOS | ActiveRoundContext | iOS |
| **HistoryStore** (extended) | Recommendations + rounds; roundId linkage | iOS | ScoreTrackingService, HistoryStore | iOS |

### 3.2 ActiveRoundContext (Detailed)

**Purpose:** Single source of truth for active round. Holds everything needed for map, hole detection, distance, and recommendation prefill.

**Fields:**
- `courseId`, `courseName`, `placeId`
- `teeId`, `teeName`, `totalYards`
- `roundLength`: .full18 | .front9 | .back9
- `currentHole`: Int (1–18)
- `holeData`: [HoleData] — cached at round start; each has holeNumber, par, greenCenter, greenFront?, greenBack?, polygon? (for detection)
- `liveDistances`: DistanceSnapshot? — front, center, back to green
- `scores`: [Int: Int]
- `startedAt`: Date

**Responsibilities:**
- Load hole data from backend when round starts
- Expose currentHole for UI
- Feed HoleDetectionEngine and DistanceEngine
- Provide prefill for ContextConfirmSheet

**Lives in:** iOS; new `ActiveRoundContext.swift` or extend `ScoreTrackingService` with a dedicated `ActiveRoundStore`.

### 3.3 HoleDetectionEngine

**Purpose:** Determine which hole the user is on from GPS.

**Algorithm:**
1. Prefer point-in-polygon: if user inside any green polygon, that hole.
2. Else: nearest green center within 80 yards.
3. Emit (hole, confidence). Confidence high if inside polygon or &lt;30yd to center; medium if 30–80yd; low otherwise.
4. When confidence high and hole != currentHole: suggest hole change (pendingHoleSuggestion).
5. Debounce: 3–5 second window to avoid jitter.

**Inputs:** Location updates, cached hole geometries (from ActiveRoundContext).
**Outputs:** `currentHole`, `confidence`, `pendingHoleSuggestion`.

**Lives in:** iOS; new `HoleDetectionEngine.swift` or inside `ActiveRoundContext`.

### 3.4 DistanceEngine

**Purpose:** Compute distance from user to green (center, front, back).

**Algorithm:**
1. Get user location, current hole’s green center (and front/back if available).
2. CLLocation.distance(from:) → meters → yards.
3. Update every 2–3 seconds when location changes.
4. Emit DistanceSnapshot(frontYards, centerYards, backYards).

**Inputs:** Location, ActiveRoundContext.holeData for current hole.
**Outputs:** DistanceSnapshot.

**Lives in:** iOS; new `DistanceEngine.swift` or inside `ActiveRoundContext`.

### 3.5 CourseIntelligenceService (Backend)

**Purpose:** Serve course metadata to iOS.

**Endpoints:**
- `GET /api/courses/nearby?lat=&lon=` — Google Nearby Search + match to Golf API; return enriched list
- `GET /api/courses/autocomplete?query=&lat=&lon=` — Google Autocomplete
- `GET /api/courses/details?placeId=` — Place details + resolve to Golf API
- `GET /api/courses/:golfCourseId` — Full course: tees, holes (par, green_center_lat/lon)
- `GET /api/courses/:golfCourseId/holes/:holeNumber/layout` — Optional: GeoJSON from CourseMapper when mapped

**Lives in:** Backend (Node).

### 3.6 CourseMatchingLayer (Backend)

**Purpose:** Map Google placeId → Golf API course_id.

**Logic:** Name similarity + distance + city/state; persist in course_place_mappings.
**Lives in:** Backend.

### 3.7 MapLocationEngine

**Purpose:** Drive the live map UI.

**Responsibilities:**
- Show user location as annotation
- Show current hole boundary (green polygon) when available
- Adjust region to keep user + current hole in view
- Update on location and hole change

**Lives in:** iOS; extend `CourseMapView` or new `RoundMapView`.

---

## PART 4 — GOLF API CSV + GOOGLE PLACES + LOCATION EXECUTION PLAN

### Phase A — Golf API CSV Ingestion

**Step 1: Inspect CSV**
- Obtain sample Golf API CSV
- Document columns: course_id, course_name, city, state, lat, lon, tee_name, hole, par, yards, green_lat, green_lon (or equivalent)
- Identify which fields exist; plan for missing (e.g. green coords from tee + bearing if needed)

**Step 2: Postgres Schema**
```sql
-- golf_courses
CREATE TABLE golf_courses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  city TEXT,
  state TEXT,
  country TEXT DEFAULT 'USA',
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_golf_courses_name ON golf_courses USING gin(name gin_trgm_ops);
CREATE INDEX idx_golf_courses_lat_lon ON golf_courses(lat, lon);
CREATE INDEX idx_golf_courses_external_id ON golf_courses(external_id);

-- golf_tees
CREATE TABLE golf_tees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES golf_courses(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT,
  total_yards INT,
  rating DECIMAL,
  slope INT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(course_id, name)
);
CREATE INDEX idx_golf_tees_course_id ON golf_tees(course_id);

-- golf_holes
CREATE TABLE golf_holes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES golf_courses(id) ON DELETE CASCADE,
  hole_number INT NOT NULL CHECK (hole_number BETWEEN 1 AND 18),
  par INT NOT NULL CHECK (par BETWEEN 3 AND 6),
  handicap INT,
  green_center_lat DOUBLE PRECISION,
  green_center_lon DOUBLE PRECISION,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(course_id, hole_number)
);
CREATE INDEX idx_golf_holes_course_id ON golf_holes(course_id);
CREATE INDEX idx_golf_holes_course_number ON golf_holes(course_id, hole_number);

-- golf_tee_hole_yardages
CREATE TABLE golf_tee_hole_yardages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tee_id UUID NOT NULL REFERENCES golf_tees(id) ON DELETE CASCADE,
  hole_id UUID NOT NULL REFERENCES golf_holes(id) ON DELETE CASCADE,
  yards INT NOT NULL,
  UNIQUE(tee_id, hole_id)
);
```

**Step 3: Ingestion Script**
- Node or Python script
- Parse CSV, normalize (trim, validate lat/lon, par 3–6)
- Upsert golf_courses by external_id
- Upsert golf_tees by (course_id, name)
- Upsert golf_holes by (course_id, hole_number)
- Upsert golf_tee_hole_yardages
- Log errors; support idempotent re-run

**Step 4: Green Coordinates**
- If CSV has green_lat/green_lon: use directly
- If not: check Golf API docs for alternate fields; or use CourseMapper as fallback (requires course ID mapping)

**Deliverable:** Populated golf_courses, golf_tees, golf_holes, golf_tee_hole_yardages with indexes.

---

### Phase B — Google Places Integration

**Step 1: Backend Endpoints**
- `GET /api/courses/autocomplete?query=&lat=&lon=` — Calls Google Places Autocomplete (type=establishment), returns normalized `[{placeId, name, formattedAddress, lat, lon, city, state}]`
- `GET /api/courses/details?placeId=` — Place Details; same shape
- `GET /api/courses/nearby?lat=&lon=&radius_km=` — Nearby Search (type=golf_course or keyword); same shape

**Step 2: Env Var**
- `GOOGLE_PLACES_API_KEY` in backend env; never exposed to iOS

**Step 3: Normalized Response**
```json
{
  "courses": [
    {
      "placeId": "ChIJ...",
      "name": "Pebble Beach Golf Links",
      "formattedAddress": "...",
      "lat": 36.57,
      "lon": -121.95,
      "city": "Pebble Beach",
      "state": "CA"
    }
  ]
}
```

**Step 4: Place ID Storage**
- Stored in course_place_mappings when matched
- Returned to iOS in course selection response

**Deliverable:** iOS can search and select courses via backend; backend holds API key.

---

### Phase C — Course Matching Layer

**Step 1: Matching Algorithm**
1. On place selection: lookup course_place_mappings by placeId
2. If found: return golf_course_id
3. Else: query golf_courses within 2km of (lat, lon)
4. Score: name similarity (Levenshtein or trigram) + distance + city/state match
5. If best score >= 0.8: auto-match, insert mapping
6. If 0.5–0.8: return top 3 for user disambiguation
7. If < 0.5: return null; allow "use without course data"

**Step 2: Persistence**
```sql
CREATE TABLE course_place_mappings (
  google_place_id TEXT PRIMARY KEY,
  golf_course_id UUID NOT NULL REFERENCES golf_courses(id),
  confidence DECIMAL NOT NULL,
  matched_at TIMESTAMPTZ DEFAULT now(),
  source TEXT DEFAULT 'auto'
);
```

**Step 3: Fallback**
- When no match: recommendations still work with location, weather, manual context
- UI: "Course data unavailable; recommendations will use location only"

**Deliverable:** Reliable mapping; cached for future searches.

---

### Phase D — Course Intelligence in Recommendations

**Step 1: Backend Payload**
- Extend `api/openai/complete` and `api/putting/analyze` to accept: courseId, holeNumber, par, greenCenter, hazards (from Golf API), front/center/back yards
- Backend fetches from golf_holes if courseId provided

**Step 2: iOS Prefill**
- From ActiveRoundContext: courseName, hole, distance (center), par, hazards
- Pass to CaddiePromptBuilder and ShotContext

**Step 3: Prompt Enrichment**
- Add to system/user prompt: "Hole X, Par Y. Distance to green center: Z yards. Hazards: [list]. Green coordinates: ..."

**Deliverable:** Recommendations are course-aware.

---

## PART 5 — PLAY TAB IMPLEMENTATION ARCHITECTURE

### 5.1 Entry Flow

1. User opens Play tab
2. If no round: show PlayHomeView
3. Location requested; nearby courses fetched (api/courses/nearby)
4. User selects course → TeeSelectionView (fetch tees from api/courses/:id)
5. User selects tee → RoundLengthView (18 / Front 9 / Back 9)
6. Tap Start Round → ActiveRoundContext initialized; hole data fetched; RoundPlayView presented

### 5.2 Location-Based Nearby Course Flow

- On appear: LocationService.startUpdating()
- Call api/courses/nearby?lat=&lon= with user location
- Backend: Google Nearby Search + match to Golf API; return enriched list
- Display: name, distance, city
- Tap to select

### 5.3 Search Fallback

- Search bar in PlayHomeView
- Debounced (400ms) call to api/courses/autocomplete
- On select: api/courses/details?placeId= → resolve to Golf API
- If resolved: proceed to tee selection
- If not: "Use without course data" or show manual course entry

### 5.4 Tee Selection

- After course selected: GET api/courses/:id → tees array
- Display: name, total yards, rating/slope if available
- User picks one

### 5.5 Front/Back/18 Logic

- Store in ActiveRoundContext.roundLength
- Filter holes: .front9 → 1–9; .back9 → 10–18; .full18 → 1–18
- Hole progression and score tracking respect filter

### 5.6 Active Round Model

- ActiveRoundContext holds full state
- ScoreTrackingService.currentRound synced from ActiveRoundContext
- Round model extended: courseId, teeId, teeName, roundLength, holePars: [Int]

### 5.7 Live Map Architecture

- RoundMapView (or extended CourseMapView):
  - Map(coordinateRegion, annotationItems) with user location + hole overlay
  - User annotation: custom MKAnnotation or MapPin at LocationService.coordinate
  - Hole overlay: current hole’s green polygon (from cached HoleLayout) as MKPolygon overlay
  - Region: center on user; span to include current green; update on location change
- LocationService: keep startUpdating() active during round (no 30s stop)
- Update frequency: location every 5–10s acceptable; map animates smoothly

### 5.8 Location Update Handling

- LocationService.$coordinate
- On update: feed HoleDetectionEngine, DistanceEngine
- Map: update user annotation position
- Debounce map region changes (avoid jitter)

### 5.9 Automatic Hole Detection

- HoleDetectionEngine subscribes to location
- Uses ActiveRoundContext.holeData (cached at round start)
- For each hole: check point-in-polygon (if polygon) or distance to green center
- Emit currentHole + confidence
- When hole changes and confidence high: set pendingHoleSuggestion
- UI: banner "Moved to hole X? [Accept] [Dismiss]"
- Accept: update currentHole, clear suggestion
- Dismiss: keep current hole; optionally suppress for 2 min

### 5.10 Automatic Distance Calculation

- DistanceEngine: user location → green center (and front/back)
- Update every 2–3s
- Display: "Front 142 | Center 152 | Back 161 yds"
- Use center as default for recommendation prefill
- Source of truth: no manual override unless user explicitly edits (rare)

### 5.11 Hole Progression Logic

- **Auto-suggest:** HoleDetectionEngine sets pendingHoleSuggestion
- **Manual:** Next/Prev buttons always available
- **After scoring:** Optional auto-advance to next hole (configurable; default on)
- **Back 9 start:** If roundLength .back9, start at hole 10

### 5.12 Score Tracking

- Per-hole strokes; par from ActiveRoundContext.holeData
- Live total, score to par
- Persist to ScoreTrackingService

### 5.13 Recommendation Triggers

- "Get Caddie Recommendation" → action sheet: Photo Mode | Quick Mode
- Photo Mode: camera → ContextConfirmSheet (prefilled: course, hole, distance, lie default)
- Quick Mode: ContextConfirmSheet (prefilled) → no photo
- "Get Putting Read" → camera → putting flow (prefilled)

### 5.14 Recommendation Prefill Logic

- From ActiveRoundContext: courseName, courseId, hole, distance (center), par
- Lie: default "Fairway"; user can change
- Hazards: from Golf API if available; else empty
- City/state: from course metadata

### 5.15 Fail-Safe / Manual Override

- **Wrong hole:** User taps hole selector, manually picks correct hole
- **Wrong distance:** Show manual override in ContextConfirmSheet (prefilled but editable)
- **No location:** Manual course/hole/distance entry
- **No course match:** "Use without course data" — recommendations with location + weather only
- **Hole detection uncertain:** Show "Select hole" prompt; manual selection

---

## PART 6 — CADDIE TAB IMPLEMENTATION ARCHITECTURE

### 6.1 Photo Mode Shot Recommendation

- Unchanged flow: Take photo → ContextConfirmSheet → recommend
- Prefill: if CourseService.currentCourse and LocationService.coordinate, use for course/hole/distance
- Otherwise: manual entry

### 6.2 Quick Mode Shot Recommendation

- New entry: "Quick Mode" (no photo)
- ContextConfirmSheet: course, hole, distance, shot type, lie, hazards — all manual or inferred
- Backend: same endpoint, hasPhoto: false
- RecommenderService: text-only prompt path

### 6.3 Green Reader Flow

- Unchanged: photo → putting analysis
- Enrich: courseId, holeNumber, lat, lon when available

### 6.4 Location/Course Inference

- When user has CourseService.currentCourse (from recent Play or Caddie): prefill course
- When LocationService has coordinate: use for nearby course suggestion
- When ActiveRoundContext exists (round in progress): full prefill

### 6.5 Manual Context Fallback

- Any field can be manually edited in ContextConfirmSheet
- Required: course name, city, state, hole, distance for shot

### 6.6 Difference from Play

- Caddie: no active round; context is ad-hoc or inferred
- Play: full round context; everything prefilled from ActiveRoundContext

---

## PART 7 — HISTORY TAB IMPLEMENTATION ARCHITECTURE

### 7.1 Recommendation History

- Existing list; add roundId when recommendation was during a round
- Filter by round (future)
- Detail + feedback unchanged

### 7.2 Round History

- List from ScoreTrackingService.rounds
- Display: date, course, score, par, score vs par
- Tap → RoundSummaryDetailView

### 7.3 Round Summaries

- Hole-by-hole scores, par, total
- Putts, fairways, GIR if captured
- Score vs par

### 7.4 Recommendation Helpfulness

- Use existing feedback (helpful/not, reason)
- Display in recommendation detail
- Aggregate: "X% of recommendations marked helpful"

### 7.5 Insights by Distance / Lie / Shot Type

- Query HistoryStore; group by distance bucket, lie, shot type
- Simple counts: "You've had 12 approach shots from 100–150y"
- Practice recommendation: "Consider practicing 9i–PW from 120y"

### 7.6 Practice Recommendations

- Based on history: most common distance, lie, shot type
- One-line suggestion: "Practice 8i from 150y — you've used it often"

### 7.7 Handicap-Related Summaries

- If ≥3 rounds: compute simple differential (score - rating) * 113 / slope; average lowest 3 * 0.96
- Display: "Handicap Index (est.): 12.4"
- Disclaimer: "Estimated; not official USGA"

### 7.8 Storage

| Data | Local | Remote |
|------|-------|--------|
| Recommendations | HistoryStore (UserDefaults) | api/analytics/recommendation |
| Rounds | ScoreTrackingService (UserDefaults) | api/rounds (new) |
| Round–recommendation link | HistoryItem.roundId | In event payload |

### 7.9 Recommendation–Round Linkage

- When saving HistoryItem during round: set roundId = ActiveRoundContext.roundId
- HistoryItem model: add roundId: UUID?
- Round detail view: show linked recommendations

---

## PART 8 — PROFILE TAB IMPLEMENTATION ARCHITECTURE

### 8.1 What Stays As-Is

- Basic info, golf snapshot, bag, risk, putting tendencies
- Onboarding flow
- Reset onboarding (dev)

### 8.2 Additional Data for Recommendation Accuracy

- **Handicap index (optional):** Manual entry; improves club selection
- Add only if time permits in Week 4

### 8.3 Inferred vs Manual

- Skill from average score (existing)
- No new inference for 30-day

### 8.4 Editable During/After Rounds

- Profile editable anytime
- No round-specific profile changes

---

## PART 9 — 30-DAY EXECUTION PLAN

### Week 1: Foundation — Data & Backend

| Day | Systems | Backend | iOS | DB | Testing | Milestone |
|-----|---------|---------|-----|-----|---------|-----------|
| 1 | Golf API CSV | — | — | Inspect CSV; finalize schema | — | Schema ready |
| 2 | Golf API CSV | Ingestion script | — | Run migration; ingest | Verify row counts | golf_courses populated |
| 3 | Google Places | Autocomplete, details, nearby endpoints | — | — | Postman tests | Search works via backend |
| 4 | Course matching | Matching logic; course_place_mappings | — | Create table | Match test courses | placeId → golf_course_id |
| 5 | Course intelligence | GET /courses/:id (tees, holes, green coords) | — | — | Integration test | Full course payload |
| 6 | Recommendation enrichment | Extend openai/complete, putting/analyze | — | — | Test with course context | Backend ready |
| 7 | — | Polish; env vars; deploy | — | — | E2E backend | **Week 1: Backend complete** |

**Files impacted (Week 1):** Backend: migrations, routes, services, Google client. No iOS yet.

---

### Week 2: Play Tab — Structure & Data Flow

| Day | Systems | Backend | iOS | DB | Testing | Milestone |
|-----|---------|---------|-----|-----|---------|-----------|
| 8 | Tab structure | — | ContentView: add Play as Tab 0; PlayHomeView | — | Build | 4 tabs |
| 9 | Course selection | — | CourseService: new endpoints (autocomplete, nearby, details); CourseViewModel | — | Mock backend | Course selection UI |
| 10 | Tee + 9/18 | — | TeeSelectionView; RoundLengthView; ActiveRoundContext (stub) | — | — | Start round flow |
| 11 | ActiveRoundContext | — | Full implementation; fetch hole data at start | — | Unit test | Hole data cached |
| 12 | HoleDetectionEngine | — | Extract from CaddieShotViewModel; use cached data | — | Simulator location | Hole detection works |
| 13 | DistanceEngine | — | New service; user → green center | — | Unit test | Distances live |
| 14 | RoundPlayView integration | — | Wire ActiveRoundContext, HoleDetectionEngine, DistanceEngine | — | Manual test | **Week 2: Play structure + engines** |

**Files impacted (Week 2):** ContentView, PlayView, PlayHomeView, TeeSelectionView, CourseService, CourseViewModel, ActiveRoundContext, HoleDetectionEngine, DistanceEngine, RoundPlayView, RoundViewModel.

---

### Week 3: Play Tab — Map, UI, Recommendations

| Day | Systems | Backend | iOS | DB | Testing | Milestone |
|-----|---------|---------|-----|-----|---------|-----------|
| 15 | Live map | — | RoundMapView: user pin, hole overlay, region updates | — | Device test | Map with user + hole |
| 16 | Hole progression UI | — | Auto-suggest banner; Next/Prev; accept/dismiss | — | — | Progression works |
| 17 | Score tracking | — | Par from hole data; score to par; persist | — | — | Score flow complete |
| 18 | Recommendation prefill | — | ContextConfirmSheet prefill from ActiveRoundContext | — | — | Prefill in Play |
| 19 | Quick Mode | — | CaddieShotViewModel; RecommenderService; ContextConfirmSheet | Backend: hasPhoto | — | Quick Mode works |
| 20 | Get Caddie / Get Putting Read | — | Wire buttons; Photo/Quick choice; putting flow | — | E2E | **Week 3: Play complete** |
| 21 | Round summary | — | RoundSummaryView; complete round flow | — | — | Round end-to-end |

**Files impacted (Week 3):** RoundMapView, RoundPlayView, RoundViewModel, ContextConfirmSheet, CaddieShotViewModel, RecommenderService, RoundSummaryView.

---

### Week 4: History, Caddie, Profile, Polish

| Day | Systems | Backend | iOS | DB | Testing | Milestone |
|-----|---------|---------|-----|-----|---------|-----------|
| 22 | History rounds | — | HistoryView: round list; RoundSummaryDetailView | — | — | Round history |
| 23 | Recommendation–round link | — | HistoryItem.roundId; link when in round | — | — | Linked history |
| 24 | History insights | — | Practice recommendation; handicap est. | — | — | Insights |
| 25 | Caddie tab | — | Photo/Quick choice; prefill from location | — | — | Caddie complete |
| 26 | Profile | — | Optional handicap field | — | — | Profile done |
| 27 | Backend sync | api/rounds (save rounds) | Round sync on complete | — | — | Rounds persisted |
| 28 | QA pass | — | Full flow testing | — | Manual + automated | **Week 4: Feature complete** |
| 29 | Bug fixes | — | — | — | — | Stability |
| 30 | Polish | — | — | — | — | **Ship** |

**Files impacted (Week 4):** HistoryView, HistoryStore, HistoryItem, RoundSummaryDetailView, CaddieHomeView, ProfileView, backend rounds API.

---

## PART 10 — CRITICAL PATH + BLOCKERS

### 10.1 Critical Path (Must Build First)

1. **Golf API CSV ingestion** — Without course/hole data, nothing works.
2. **Google Places + course matching** — Without search and resolution, users cannot select courses.
3. **ActiveRoundContext + hole data fetch** — Without cached hole geometries, hole detection and distance fail.
4. **HoleDetectionEngine** — Depends on hole data; blocks map overlay and auto-progression.
5. **DistanceEngine** — Depends on hole data; blocks recommendation prefill.
6. **Recommendation enrichment** — Depends on course resolution; blocks course-aware recommendations.

### 10.2 Dependency Failure Risks

| Risk | Mitigation |
|------|------------|
| Golf API CSV lacks green coords | Use CourseMapper as fallback; build golf_course_id ↔ course_mapper_id mapping for known courses |
| Google API quota/cost | Monitor usage; cache aggressively; limit autocomplete frequency |
| Course matching accuracy low | Implement user disambiguation (top 3); allow "use without course data" |
| Hole detection slow (18 API calls) | Prefetch all hole layouts at round start; cache in memory |
| Location permission denied | Graceful degradation: manual course/hole/distance |

### 10.3 Validate Immediately

- **Day 1:** Obtain Golf API CSV; confirm green_center or equivalent exists.
- **Day 2:** Run ingestion on sample; verify data quality.
- **Day 3:** Google Places API key; test autocomplete and nearby.
- **Day 4:** Match 5 real courses (Pebble Beach, etc.); verify mapping.

### 10.4 Proof-of-Concept Spikes

- **Spike 1 (Day 2):** Hole detection with prefetched data — fetch 18 layouts once, run point-in-polygon in-memory; measure latency.
- **Spike 2 (Day 5):** Distance calculation — CLLocation.distance for user to green center; verify accuracy.
- **Spike 3 (Day 7):** End-to-end: search course → select → tee → start round → see hole + distance.

---

## PART 11 — TESTING / QA STRATEGY

### 11.1 Unit / Integration Tests

| Area | Test |
|------|------|
| Location | Mock CLLocation; verify coordinate propagation |
| Nearby courses | Mock api/courses/nearby; verify list display |
| Google Place matching | Mock matching service; verify golf_course_id returned |
| Golf API resolution | Mock api/courses/:id; verify tees, holes, green coords |
| Hole detection | Given user coord + hole polygons, verify correct hole |
| Distance | Given user + green center, verify yards |
| Score tracking | Round start, log hole, complete; verify state |
| Recommendation | Mock RecommenderService; verify prefill |
| History | Add item with roundId; verify linkage |

### 11.2 Manual Real-World Testing

| Scenario | Steps |
|----------|-------|
| Location | Real device at golf course; verify location updates |
| Nearby courses | Real device; verify nearby list |
| Course search | Type course name; verify autocomplete |
| Full round | Start round, play 2–3 holes, get recommendation, putt, score, complete |
| Hole detection | Walk between holes; verify auto-suggest |
| Distance | Stand at known yardage; verify display |
| Map | Verify user pin moves; hole overlay visible |
| Quick Mode | Caddie tab, Quick Mode, manual context, verify recommendation |

### 11.3 Simulator Testing

- Use GPX file or custom location for "walking" between holes
- Mock backend for offline development
- Test hole detection with simulated coordinates

---

## PART 12 — WHAT NOT TO GET WRONG

### 12.1 Location Drift

- **Risk:** GPS drift places user on wrong hole.
- **Avoid:** Use confidence thresholds; require sustained position (3–5s) before suggesting hole change; always allow manual override.

### 12.2 Wrong Hole Detection

- **Risk:** User on hole 7, app shows hole 8.
- **Avoid:** Prefer point-in-polygon over distance-only; use 80yd max for distance fallback; show "Confirm hole?" when uncertain.

### 12.3 Wrong Course Matching

- **Risk:** "Pebble Beach" matches wrong course.
- **Avoid:** Name + distance + city/state; confidence threshold; user disambiguation when ambiguous.

### 12.4 Recommendation Latency

- **Risk:** User waits >5s; abandons.
- **Avoid:** Show loading immediately; stream if possible; cache weather/elevation; keep prompt lean.

### 12.5 Map Over-Complexity

- **Risk:** Map too busy; performance issues.
- **Avoid:** Show only current hole overlay; avoid rendering all 18 holes; simplify polygon if needed.

### 12.6 User Trust Loss from Bad Automation

- **Risk:** Wrong hole/distance; user loses trust.
- **Avoid:** Always show manual override; "Tap to correct" on hole/distance; never hide manual controls.

### 12.7 Data Quality Mismatch (Google vs Golf API)

- **Risk:** Google has "Pebble Beach Golf Links"; Golf API has "Pebble Beach"; no match.
- **Avoid:** Fuzzy matching; normalize names; allow manual mapping (admin) for top courses.

### 12.8 Overcomplicating UX During Live Round

- **Risk:** Too many taps; user frustrated.
- **Avoid:** One tap to Get Caddie; one tap to Get Putting Read; prefill everything; minimal confirmation.

---

## PART 13 — FINAL RECOMMENDATION

### 13.1 Recommended Final Architecture

- **4 tabs:** Play (0), Caddie (1), History (2), Profile (3)
- **ActiveRoundContext** as single source for round state
- **HoleDetectionEngine** and **DistanceEngine** as shared services
- **Backend** mediates Google Places + Golf API; course matching persisted
- **Map** shows user + current hole; live updates
- **Recommendations** enriched with course intelligence; Photo + Quick Mode

### 13.2 Exact Implementation Order

1. Golf API CSV ingestion (Days 1–2)
2. Google Places backend (Day 3)
3. Course matching (Day 4)
4. Course intelligence API (Day 5)
5. Recommendation enrichment backend (Day 6)
6. Play tab structure + ActiveRoundContext (Days 8–11)
7. HoleDetectionEngine + DistanceEngine (Days 12–13)
8. Live map (Day 15)
9. Hole progression + score (Days 16–17)
10. Recommendation prefill + Quick Mode (Days 18–19)
11. Get Caddie / Putting Read wiring (Day 20)
12. Round summary (Day 21)
13. History (Days 22–24)
14. Caddie + Profile polish (Days 25–26)
15. Backend sync + QA (Days 27–30)

### 13.3 Single Most Important Subsystem

**Course matching (Google placeId → Golf API course_id).** If this fails, course intelligence fails, hole data fails, and recommendations stay generic. Invest in matching quality and fallbacks from Day 4.

### 13.4 Top 5 Execution Priorities

1. **Golf API CSV with green coordinates** — Verify on Day 1; block if missing.
2. **ActiveRoundContext + hole data prefetch** — Enables hole detection and distance.
3. **HoleDetectionEngine with cached data** — No 18-call loop; must use prefetch.
4. **Live map with user location** — Core to "live-round operating system."
5. **Recommendation prefill** — Minimize taps during round.

### 13.5 Top 5 Things That Can Wait Until After Launch (Only If Necessary)

1. **CourseMapper polygon overlay** — If Golf API has green center only, use distance-based hole detection; polygons are nice-to-have.
2. **Handicap index display** — Can ship with "Coming soon" if time runs out.
3. **Practice recommendations** — Simple version first; sophisticated logic later.
4. **Backend round sync** — Rounds can be local-only for launch; sync in v1.1.
5. **Social/friends comparison** — Explicitly out of 30-day scope.

---

*End of 30-Day Execution Blueprint. No code has been implemented. This is a planning artifact only.*
