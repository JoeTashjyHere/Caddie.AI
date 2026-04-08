# Caddie.AI Product Architecture & Implementation Plan

**Document Version:** 1.0  
**Date:** March 2025  
**Status:** Planning / Design Only — No Code Changes

---

## PART 1 — CURRENT STATE AUDIT

### 1.1 Current App Architecture

**Entry point:** `CaddieAIApp.swift` (@main)

**Root view:** `ContentView.swift` — TabView with **3 tabs**:
- **Tab 0 (Caddie):** `CaddieHomeView` — main AI caddie (shot + putt)
- **Tab 1 (History):** `HistoryView` — past recommendations
- **Tab 2 (Profile):** `ProfileView` — user profile, clubs, risk settings

**Note:** `PlayView` exists in the codebase but is **not** in the main TabView. `HomeView` also exists and references `RoundPlayView`. The Play/round experience is reachable via `HomeView` or similar flows, but the primary navigation is Caddie-first.

**Environment objects (app-level):**
- `LocationService`, `ProfileViewModel`, `ScoreTrackingService`, `CourseService`, `FeedbackService`
- `HistoryStore`, `UserProfileStore`, `UserIdentityStore`, `SessionStore`
- `RecommendationDiagnosticsStore`

**Onboarding:** Full-screen cover `OnboardingCoordinatorView` when `!userProfileStore.isOnboardingComplete`. Multi-step: basics, golf snapshot, bag, risk profile, putting tendencies, finish.

---

### 1.2 Current Main Tabs

| Tab | View | Purpose |
|-----|------|---------|
| Caddie | CaddieHomeView | Photo capture → Shot or Putt recommendation |
| History | HistoryView | List of HistoryItem (shot/putt), tap for detail + feedback |
| Profile | ProfileView | UserProfile edit, clubs, risk, putting tendencies |

**Play** is implemented (`PlayView`, `RoundPlayView`, `CourseViewModel`) but not exposed as a top-level tab. It provides:
- Nearby course list (location-based)
- Course selection → Start Round
- RoundPlayView: hole-by-hole scoring, AI caddie, putting, distances

---

### 1.3 Current Shot Flow

1. User taps **"Take Photo for Shot Recommendation"** in CaddieHomeView
2. `CaddieCameraCaptureView` captures image
3. `ContextConfirmSheet` collects:
   - Course name (manual text), city, state (required)
   - Hole number (1–18)
   - Distance (yards)
   - Shot type (Approach, Tee, etc.)
   - Lie (Fairway, Rough, Bunker, Tee)
   - Hazards (free text)
4. `CaddieShotViewModel.getShotRecommendation`:
   - Builds `ShotContext` (weather via Open-Meteo, elevation via Open-Meteo, target from CourseMapper if available)
   - Calls `RecommenderService.getRecommendation` (photo + context)
5. `RecommenderService` chain: Photo → AI Vision (OpenAI via backend) → Text AI → Offline fallback
6. Result in `CaddieRecommendationOverlay`; saved to `HistoryStore`; analytics sent

**Key constraint:** Shot flow **requires** a photo. There is no "Quick Mode" (no-photo) path today.

---

### 1.4 Current Putt Flow

1. User taps **"Green Reader"** in CaddieHomeView
2. Camera captures image
3. `CaddieShotViewModel.getPuttingRecommendation`:
   - If course/hole/location available: `APIService.analyzePutting` (backend `api/putting/analyze`)
   - Else: `OpenAIClient.completeWithVision` with green-read prompt
4. Result in `CaddieRecommendationOverlay`; saved to history; analytics sent

**Putting** uses photo + optional course/hole/location. Course-mapper has `/greens/{id}/read` for elevation-based green reading, but the main app uses backend putting analysis.

---

### 1.5 Current History System

**Storage:** `HistoryStore` — `[HistoryItem]` in UserDefaults, max 200 items.

**HistoryItem fields:**
- id, createdAt, type (.shot / .putt)
- courseName, distanceYards, shotType, lie, hazards
- recommendationText, rawAIResponse, thumbnailData
- recommendationId, feedback (RecommendationFeedbackRecord)
- shotMetadata (ShotHistoryMetadata), puttMetadata (PuttHistoryMetadata)

**Operations:** add, upsertFeedback, load from UserDefaults.

**Display:** `HistoryView` lists items; `HistoryDetailView` shows full details and feedback form.

**Limitation:** No round-level grouping, no handicap summary, no trend analysis. Recommendations are stored per-event, not linked to rounds.

---

### 1.6 Current Profile System

**UserProfile** (onboarding / UserProfileStore):
- Basic: firstName, lastName, email, phone
- Golf: averageScore, yearsPlaying, golfGoal, seriousness
- Risk: greenRiskPreference, riskOffTee, riskAroundHazards
- Putting: puttingTendencies
- Clubs: clubDistances (Driver, 7i, PW required; ClubDistance: clubTypeId, distanceYards, shotPreference, confidenceLevel, notes)

**PlayerProfile** (used by RecommenderService):
- Derived from UserProfile via `ProfileViewModel.applyUserProfile`
- name, handedness, skillLevel, clubs, golfGoal, puttingTendencies, greenRiskPreference

**Persistence:** UserDefaults (`caddie_user_profile`). Onboarding completion requires firstName, email, greenRiskPreference, and Driver/7i/PW.

---

### 1.7 Current Course / Location Architecture

**CourseService:**
- `getNearbyCourses(at:)` → Node backend `api/courses?lat=&lon=`, fallback to `CourseMapperService`
- `searchCourses(query:lat:lon:)` → Node backend `api/courses?query=`
- Current/suggested course in UserDefaults

**Course model:** id, name, location (Coordinate), par. No tee sets, no hole-by-hole data in the iOS model.

**LocationService:** CoreLocation, coordinate updates. Simulator: mock Pebble Beach after 1–2 seconds.

**CourseMapperService** (FastAPI, localhost:8081):
- `fetchNearbyCourses(lat, lon, radius_km)` — OSM-based
- `fetchCourseHoles(courseId)`, `fetchHoleLayout(courseId, holeNumber)`, `fetchGreenContours`
- Uses PostGIS, OSM ingestion, satellite segmentation, green elevation

**Hole detection:** `CaddieShotViewModel.checkCurrentHole(at:)` uses CourseMapper green polygons to suggest hole when user near green. Currently limited to CourseMapper data.

---

### 1.8 Current Backend Dependencies

**Node backend** (`https://caddie-ai-backend.onrender.com`):
- `GET api/courses` — nearby (lat, lon) or search (query, lat, lon)
- `GET api/insights/course` — course insights (courseId, userId?)
- `POST api/openai/complete` — shot recommendation (system, user, hasPhoto, context)
- `POST api/putting/analyze` — putting analysis (multipart: photo, courseId, holeNumber, lat, lon, metadata)
- `POST api/feedback/caddie` — open-ended feedback
- `POST api/analytics/recommendation` — recommendation events
- `POST api/analytics/feedback` — recommendation feedback
- `POST api/analytics/events` — general analytics

**Course-mapper (FastAPI):** localhost:8081 / device IP
- OSM + PostGIS for courses, holes, geometries
- Green contours, elevation, green reading API

**External:** Open-Meteo (weather, elevation). No Golf API CSV or Google Places today.

---

### 1.9 Reuse, Extend, Refactor

| Area | Reuse | Extend | Refactor |
|------|-------|--------|----------|
| **Caddie tab** | CaddieHomeView, CaddieShotViewModel, RecommenderService, ContextConfirmSheet | Add Quick Mode (no photo); enrich context with Golf API + Google | ContextConfirmSheet may need tee/hole/round context when in Play |
| **Play tab** | PlayView, RoundPlayView, CourseViewModel, ScoreTrackingService, Round model | Add as Tab 0; tee selection, 9/18; map; "Get Caddie" / "Get Putting Read" | Play not in TabView; needs promotion |
| **History** | HistoryStore, HistoryItem, HistoryView, HistoryDetailView | Round grouping, handicap, trends, practice insights | HistoryItem not round-linked; need RoundSessionId |
| **Profile** | UserProfile, UserProfileStore, ProfileView, onboarding | Minor additions only | Keep as-is |
| **Course** | CourseService, Course model, CourseMapperService | Golf API CSV as canonical; Google Places for search; matching layer | Course model lacks tee/hole geometry |
| **Recommendation** | RecommenderService, CaddiePromptBuilder, ShotContext, APIService | Enrich with course intelligence (hazards, geometry, pars) | Backend needs course context payload |
| **Putting** | APIService.analyzePutting, PuttingRead | Enrich with Golf API, location, weather | Same pipeline, richer input |
| **Analytics** | AnalyticsService, FeedbackService, RecommendationDiagnosticsStore | Round-level events, handicap events | Extend event schema |

---

### 1.10 Where Current Architecture Will Not Support the New Design

1. **No Quick Mode:** Shot flow requires photo. Need a parallel path with same context but no photo.
2. **Play not primary:** Play is buried; needs to be Tab 0 with full round flow.
3. **Course search:** Backend/course-mapper use lat/lon or OSM; no Google Places autocomplete or place-based search.
4. **No Golf API CSV:** No canonical course intelligence (pars, tees, hazards, geometry). Course model is minimal.
5. **No tee selection:** Round starts with course only; no tee set or 9/18 choice in UI.
6. **History not round-aware:** Recommendations not linked to rounds; no round summary or handicap.
7. **No course matching:** No mapping between Google Place result and Golf API / internal course record.
8. **Hole par is stub:** Round uses default par 4 per hole; no hole-level par from course data.

---

## PART 2 — TARGET PRODUCT ARCHITECTURE

### 2.1 Tab Structure

| Tab | Purpose | Primary Entry |
|-----|---------|---------------|
| **Play** | Live round: course, tee, 9/18, map, score, Get Caddie, Get Putting Read | Tab 0 |
| **Caddie** | Quick utility: shot (Photo/Quick) and Green Reader without round | Tab 1 |
| **History** | Past recommendations, round summaries, insights | Tab 2 |
| **Profile** | User profile, bag, risk, onboarding reset | Tab 3 |

---

### 2.2 Play Tab

**Purpose:** Primary live-round experience. User selects course, tee, round length; sees map; tracks score; gets AI recommendations in context.

**Key journeys:**
1. Start round: location → nearby courses → select course → select tee → select 9/18 → begin
2. During round: view map, update score, tap "Get Caddie Recommendation" (Photo/Quick) or "Get Putting Read"
3. End round: summary, score to par, optional handicap

**Primary screens:**
- PlayHomeView (course selection, tee, 9/18, start)
- RoundPlayView (active round: map, score, recommendation triggers)
- RoundSummaryView (end of round)

**Shared dependencies:** LocationService, CourseService (extended), ScoreTrackingService, ActiveRoundStore (new), RecommenderService, APIService.

**Interactions:** Course search (Google Places), course resolve (Golf API), recommendation (enriched context), putting (enriched), analytics (round-scoped).

---

### 2.3 Caddie Tab

**Purpose:** Quick AI access without round mode. For practice or ad-hoc use.

**Key journeys:**
1. Shot: Choose Photo Mode or Quick Mode → (optional photo) → confirm context → get recommendation
2. Green Reader: Capture putt photo → get read

**Primary screens:**
- CaddieHomeView (Photo/Quick choice, Green Reader)
- ContextConfirmSheet (course, hole, distance, lie, etc.)
- CaddieRecommendationOverlay

**Shared dependencies:** CaddieShotViewModel, RecommenderService, CourseService, LocationService, HistoryStore.

**Interactions:** Same recommendation pipeline as Play; context can be inferred from location/course when available.

---

### 2.4 History Tab

**Purpose:** Past recommendations, round summaries, insights, trends.

**Key journeys:**
1. View recommendation history (filter by type, course, date)
2. View round summary (score, par, putts, etc.)
3. (Later) Handicap summary, practice suggestions, trends

**Primary screens:**
- HistoryView (list: recommendations + rounds)
- HistoryDetailView (recommendation detail + feedback)
- RoundSummaryDetailView (round stats)

**Shared dependencies:** HistoryStore, ScoreTrackingService (rounds), backend analytics.

**Interactions:** Local storage + optional backend sync for rounds and recommendations.

---

### 2.5 Profile Tab

**Purpose:** User identity, bag, risk profile. Mostly unchanged.

**Key journeys:**
1. Edit basic info, golf snapshot, bag, risk, putting
2. Reset onboarding (dev)

**Primary screens:** ProfileView (unchanged structure)

**Shared dependencies:** UserProfileStore, ProfileViewModel.

---

### 2.6 State Architecture

| State Type | Examples | Where | Persistence |
|------------|----------|-------|-------------|
| **Global app** | userId, sessionId, onboardingComplete | UserIdentityStore, SessionStore, UserProfileStore | UserDefaults |
| **Per-user/profile** | UserProfile, PlayerProfile | UserProfileStore, ProfileViewModel | UserDefaults |
| **Per-round/session** | ActiveRound, currentHole, scores, course, tee | ScoreTrackingService, ActiveRoundStore (new) | UserDefaults (round in progress) |
| **Recommendation** | HistoryItem | HistoryStore | UserDefaults |
| **Course cache** | Recent courses, Google↔Golf mapping | CourseService, backend | UserDefaults / Postgres |
| **Analytics** | Events, feedback | AnalyticsService, FeedbackService | Backend |

**Recommendation:** Introduce `ActiveRoundContext` (or extend `ScoreTrackingService`) to hold: course, tee, 9/18, current hole, scores, and pass this into recommendation flows when in Play mode.

---

## PART 3 — DATA ARCHITECTURE

### 3.1 New / Extended Models

| Model | Purpose | Where | Cached | Data Source |
|-------|---------|-------|--------|-------------|
| **RoundSession** | Active or completed round | iOS + Backend | Local (active), Remote (completed) | User, ScoreTrackingService |
| **ActiveCourseContext** | Course + tee + 9/18 for current round | iOS | In-memory | CourseService, Golf API |
| **HoleContext** | Hole number, par, yardages, hazards | iOS | Per-round | Golf API CSV |
| **TeeSelection** | Tee name, color, total yards, rating, slope | iOS | Per-course | Golf API CSV |
| **ScoreEntry** | Hole number, strokes, putts, fairway, GIR | iOS | Per-round | User input |
| **RecommendationContext** | Extended ShotContext with course intelligence | iOS | No | Golf API, location, weather |
| **PuttingContext** | Ball/hole coords, green data, weather | iOS | No | Golf API, course-mapper, location |
| **CourseSearchResult** | Normalized search hit (name, placeId, coords, city) | iOS | Short-lived | Google Places |
| **CourseMatchMapping** | Google placeId ↔ Golf API course_id | Backend Postgres | Yes | Matching layer |
| **PracticeInsight** | Suggested focus areas from history | Backend | No | Analytics |
| **HandicapSummary** | Index, trend, recent scores | Backend | Yes | Round data |

### 3.2 RoundSession (Extended Round)

```text
RoundSession:
  id, userId, courseId, courseName
  teeId, teeName, totalYards
  roundLength: 9 | 18
  startedAt, completedAt
  holes: [HoleScore]
  totalScore, par, scoreVsPar
  recommendationsDuringRound: [recommendationId]
```

### 3.3 CourseSearchResult (from Google)

```text
CourseSearchResult:
  placeId, name, formattedAddress
  lat, lon, city, state
  types (from Google)
```

### 3.4 CourseMatchMapping (Backend)

```text
course_place_mappings:
  google_place_id, golf_api_course_id
  confidence, matched_at
```

---

## PART 4 — THIRD-PARTY DATA INTEGRATION ARCHITECTURE

### 4.1 Provider Roles

| Provider | Role | When Used |
|----------|------|-----------|
| **Google Places API** | Search, autocomplete, place identity | User searches for course; nearby search |
| **Golf API CSV** | Canonical course intelligence (pars, tees, holes, hazards) | After course selected; recommendation enrichment |
| **iPhone location** | User position, nearby bias, hole detection | Always when authorized |

### 4.2 Search / Autocomplete

- **Provider:** Google Places API (Autocomplete, Place Details, Nearby Search)
- **Backend:** New endpoints `api/courses/search` (autocomplete), `api/courses/details` (place details)
- **iOS:** Calls backend only; never calls Google directly (API key stays server-side)
- **Request:** query, lat, lon (for bias)
- **Response:** Normalized `CourseSearchResult[]` (name, placeId, lat, lon, city, state)

### 4.3 Canonical Course Intelligence

- **Provider:** Golf API CSV (ingested into Postgres)
- **Backend:** Tables for courses, tees, holes, coordinates
- **When:** After user selects a course from Google search → backend resolves placeId to Golf API course_id via matching layer
- **iOS:** Receives enriched course (id, name, tees, holes, par) from backend

### 4.4 Matching: Google Place → Golf API

- **Flow:** User selects "Pebble Beach Golf Links" from Google → backend has mapping or runs matcher → returns Golf API course_id
- **Storage:** `course_place_mappings` in Postgres
- **Cache:** Matched pairs cached; future searches for same place are instant

### 4.5 What Gets Cached

| Data | Where | TTL / Strategy |
|------|-------|----------------|
| Google Place → Golf API mapping | Postgres | Permanent once matched |
| Golf API course details | Postgres | Source of truth; no TTL |
| Nearby courses (resolved) | iOS UserDefaults | Session |
| User's current course | iOS | Until changed |

### 4.6 What Gets Fetched Live

- Autocomplete results (per keystroke, debounced)
- Place details (on selection)
- Weather, elevation (per recommendation)
- Hole layout from course-mapper (when available)

### 4.7 Backend Mediation

- **All** Google and Golf API access goes through backend
- iOS calls: `api/courses/search`, `api/courses/details`, `api/courses/nearby`, `api/courses/{id}` (enriched)
- Backend: holds Google API key, Golf API data; performs matching; returns normalized responses

---

## PART 5 — GOLF API CSV INGESTION PLAN

### 5.1 Assumptions

- Golf API provides CSV with courses, tees, holes, coordinates
- Structure to be inspected; common patterns: course_id, course_name, tee_color, hole, par, yards, lat, lon

### 5.2 Recommended Table Schema (Postgres)

```sql
-- golf_courses: canonical course records
golf_courses (
  id UUID PRIMARY KEY,
  external_id TEXT UNIQUE,  -- Golf API course ID
  name TEXT NOT NULL,
  city TEXT,
  state TEXT,
  country TEXT DEFAULT 'USA',
  lat DOUBLE PRECISION,
  lon DOUBLE PRECISION,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
);

-- golf_tees: tee sets per course
golf_tees (
  id UUID PRIMARY KEY,
  course_id UUID REFERENCES golf_courses(id),
  name TEXT,  -- e.g. "Blue", "White"
  color TEXT,
  total_yards INT,
  rating DECIMAL,
  slope INT,
  created_at TIMESTAMPTZ
);

-- golf_holes: hole-level data per course (not per tee, if same)
golf_holes (
  id UUID PRIMARY KEY,
  course_id UUID REFERENCES golf_courses(id),
  hole_number INT CHECK (hole_number BETWEEN 1 AND 18),
  par INT CHECK (par BETWEEN 3 AND 6),
  handicap INT,
  created_at TIMESTAMPTZ,
  UNIQUE(course_id, hole_number)
);

-- golf_tee_hole_yardages: yards per tee per hole
golf_tee_hole_yardages (
  id UUID PRIMARY KEY,
  tee_id UUID REFERENCES golf_tees(id),
  hole_id UUID REFERENCES golf_holes(id),
  yards INT,
  UNIQUE(tee_id, hole_id)
);

-- golf_hole_coordinates: green center, hazards (optional)
golf_hole_coordinates (
  id UUID PRIMARY KEY,
  hole_id UUID REFERENCES golf_holes(id),
  green_center_lat DOUBLE PRECISION,
  green_center_lon DOUBLE PRECISION,
  hazard_geojson JSONB  -- optional
);
```

### 5.3 Import Pipeline

1. **Inspect CSV:** Column names, sample rows, encoding
2. **Extract script:** Parse CSV → normalize (trim, validate)
3. **Upsert:** Insert or update golf_courses, golf_tees, golf_holes, golf_tee_hole_yardages
4. **Dedup:** Match on (external_id) for courses; (course_id, hole_number) for holes
5. **Indexes:** name (gin/trigram), lat/lon (btree or PostGIS), course_id, hole lookups

### 5.4 Normalization Strategy

- Course names: trim, lowercase for matching; preserve display name
- Coordinates: validate range; store as double
- Pars: 3–6 only
- Yards: positive integers

### 5.5 Deduping Strategy

- Courses: external_id unique
- Holes: (course_id, hole_number) unique
- Tees: (course_id, name) unique per course

### 5.6 Updates

- Full refresh: truncate + re-import (or upsert by external_id)
- Incremental: if Golf API supports "updated since" — not assumed for V1

### 5.7 Critical vs Optional Fields (V1)

**Critical:** course id, name, city, state, lat, lon; hole par; tee yardages  
**Optional:** rating, slope, handicap, hazard coordinates

### 5.8 Raw vs Transformed

- Store normalized/cleaned in main tables
- Keep raw CSV or import log for debugging (optional)

---

## PART 6 — GOOGLE PLACES INTEGRATION PLAN

### 6.1 Backend Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `api/courses/autocomplete` | GET | query, lat, lon → suggestions |
| `api/courses/details` | GET | placeId → full place details |
| `api/courses/nearby` | GET | lat, lon, radius → nearby (Google Nearby Search or hybrid) |

### 6.2 Request / Response (iOS)

**Autocomplete request:** `?query=pebble&lat=36.57&lon=-121.95`  
**Response:** `[{ placeId, name, formattedAddress, lat, lon, city, state }]`

**Details request:** `?placeId=ChIJ...`  
**Response:** `{ placeId, name, formattedAddress, lat, lon, city, state, types }`

### 6.3 Place Fields That Matter

- placeId (required for matching)
- name, formattedAddress
- geometry.location (lat, lon)
- address_components (city, state)
- types (establishment, point_of_interest)

### 6.4 Storing Google Place IDs

- In `course_place_mappings`: google_place_id + golf_api_course_id
- Never expose raw API key to iOS

### 6.5 Efficiency

- Debounce autocomplete (300–500 ms)
- Cache recent place details in memory
- Use lat/lon bias to prefer nearby results

---

## PART 7 — COURSE MATCHING LAYER PLAN

### 7.1 Matching Algorithm

1. **Input:** Google Place (placeId, name, lat, lon, city, state)
2. **Lookup:** Check `course_place_mappings` for placeId → return if exists
3. **Match:** If not, find Golf API courses within:
   - Name similarity (Levenshtein, trigram, or fuzzy)
   - Distance threshold (e.g. &lt; 2 km)
   - City/state match (bonus)
4. **Score:** Confidence = f(name_sim, distance, city_match)
5. **Threshold:** Confidence >= 0.8 → auto-match; 0.5–0.8 → suggest; &lt; 0.5 → no match

### 7.2 Multiple Matches

- Return top 3 with confidence; let user pick
- Store chosen mapping for future

### 7.3 No Good Match

- Allow "Use without course data" — recommendations work with location/weather only
- Option to report / suggest manual mapping (later)

### 7.4 Manual Fallback

- Admin or user can link placeId to course_id manually (future)
- For MVP: auto-match or skip enrichment

### 7.5 Storage

```sql
course_place_mappings (
  google_place_id TEXT PRIMARY KEY,
  golf_api_course_id UUID REFERENCES golf_courses(id),
  confidence DECIMAL,
  matched_at TIMESTAMPTZ,
  source TEXT  -- 'auto' | 'manual'
);
```

---

## PART 8 — RECOMMENDATION ENGINE INTEGRATION PLAN

### 8.1 Shot Recommendation Enrichment

**Current context:** distance, lie, weather, elevation, hazards (text), profile

**Add:**
- Tee info (yards to green, par)
- Hole geometry (front/center/back if available)
- Green coordinates (for distance calc)
- Points of interest / hazards from Golf API (structured)
- Course name, hole number (already present)

### 8.2 Putting Recommendation Enrichment

**Current:** Photo, optional course/hole/location

**Add:**
- Golf API hole par, green location
- Course-mapper green contours (when available)
- Weather, elevation
- Ball/hole coordinates from user or map

### 8.3 Automatic vs User-Confirmed

| Field | Automatic | User-Confirmed |
|-------|-----------|----------------|
| Course | From active round or location | Caddie tab: manual or pick from nearby |
| Hole | From GPS (when confident) | User can override |
| Distance | From GPS to green | User can override |
| Lie | From photo (Photo Mode) | User selects (Quick Mode) |
| Hazards | From Golf API + photo | User can add |

### 8.4 Recommendation Speed

- Prefetch course/hole data when round starts
- Cache weather/elevation for 5–10 min
- Keep prompt size reasonable; avoid large payloads
- Consider async "thinking" indicator for &gt; 3 s

### 8.5 V1 vs Later

**V1:** Course name, hole, par, distance, weather, elevation, hazards (text), profile  
**Later:** Structured hazard list, hole geometry, front/center/back, green contours

---

## PART 9 — PLAY TAB ARCHITECTURE

### 9.1 Entry Flow

1. User opens Play tab
2. If no round: show course selection (nearby from location or search)
3. User selects course → tee selection → 9/18
4. Tap "Start Round" → RoundPlayView

### 9.2 Nearby Course Suggestion

- Use iPhone location
- Backend: `api/courses/nearby?lat=&lon=` (uses Google or hybrid with Golf API)
- Display: list with distance, name
- Tap to select

### 9.3 Tee Selection Flow

- After course selected, fetch tees from backend (Golf API)
- Display: Blue, White, Red, etc. with total yards
- User picks one

### 9.4 Round Length Selection

- Choice: 18 holes, Front 9, Back 9
- Affects which holes are shown and scored

### 9.5 Active Round Model

- `ScoreTrackingService.currentRound` (extend Round) + `ActiveRoundContext`
- Course, tee, 9/18, current hole, scores, startedAt

### 9.6 Score Tracking Model

- Reuse `Round`, `HoleScore`
- Par per hole from Golf API (replace stub)
- Live score to par

### 9.7 Map / Location Model

- MapKit or similar: show user position
- MVP: Simple pin; optional course outline (later)
- Update on location change

### 9.8 Recommendation Triggers

- Top button: "Get Caddie Recommendation"
  - **Photo Mode:** Take photo → ContextConfirmSheet (prefilled) → recommend
  - **Quick Mode:** No photo → ContextConfirmSheet (prefilled) → recommend
- Second button: "Get Putting Read" → photo → putting flow

### 9.9 Hole Progression

- Manual: user taps Next/Prev hole
- Optional: auto-advance when near next tee (later)
- MVP: manual only

### 9.10 Automatic vs User-Confirmed

- **Auto:** Course from selection, tee, 9/18, hole from UI
- **User:** Score entry, photo capture, distance override if needed
- **MVP:** Keep it simple; avoid auto-hole detection complexity

### 9.11 MVP vs Later

**MVP:** Course select, tee select, 9/18, manual hole, score, Get Caddie (Photo/Quick), Get Putting Read, round summary  
**Later:** Live map with hole boundaries, auto hole detection, handicap calc, social

---

## PART 10 — CADDIE TAB ARCHITECTURE

### 10.1 Photo Mode

- Same as current: take photo → ContextConfirmSheet → recommend
- Context can be prefilled from location/course when available

### 10.2 Quick Mode

- No photo
- ContextConfirmSheet: course, hole, distance, lie, shot type, hazards
- Same backend call; `hasPhoto: false`
- RecommenderService handles no-photo path (text-only prompt)

### 10.3 Green Reader

- Same as current: photo → putting analysis
- Enrich with course/hole/location when available

### 10.4 Inferred vs Manual

- **Inferred:** Course from CourseService.currentCourse, hole from session, location from LocationService
- **Manual:** User fills any missing fields in ContextConfirmSheet

### 10.5 Difference from Play

- Caddie: no active round; context is ad-hoc
- Play: round context; course, tee, hole, score all in scope

---

## PART 11 — HISTORY TAB ARCHITECTURE

### 11.1 Data to Show

**MVP:**
- Recommendation list (current)
- Round list (from ScoreTrackingService.rounds)
- Round detail: score, par, holes, date

**Later:**
- Handicap summary
- Recommendation helpfulness
- Trends by distance, lie, shot type
- Practice suggestions
- Friends comparison (social)

### 11.2 Highest-Value Insights

1. Round summary (score vs par, putts)
2. Recommendation history with feedback
3. Handicap trend (when available)

### 11.3 MVP First

- Round list + round detail
- Link recommendations to round when applicable (RoundSessionId in HistoryItem)
- Keep current recommendation list and detail view

### 11.4 Future Features

- Practice suggestions from usage patterns
- Handicap index and trend
- Social/friends comparison
- Export rounds

---

## PART 12 — PROFILE TAB ARCHITECTURE

### 12.1 What Stays the Same

- Basic info, golf snapshot, bag, risk profile, putting tendencies
- Onboarding flow
- Reset onboarding (dev)

### 12.2 Additional Fields (If They Improve Recommendations)

- **Handicap index:** Would improve club selection; add only if we have round data to compute or user enters
- **Home course:** Could bias course search; low priority
- **Avoid:** Extra friction (e.g. many new required fields)

### 12.3 What NOT to Add

- Unnecessary optional fields that add friction
- Duplicate of data we can infer (e.g. skill from average score)

---

## PART 13 — TECHNICAL IMPLEMENTATION PLAN

### Phase 1: Golf API CSV Ingestion
- **Scope:** Inspect CSV, design schema, create tables, ingestion script, indexes
- **Files:** Backend: new migrations, scripts
- **Dependencies:** None
- **Risk:** Low
- **MVP:** Clean golf course DB

### Phase 2: Google Places Integration
- **Scope:** Backend endpoints (autocomplete, details, nearby), env for API key
- **Files:** Backend: routes, Google client
- **Dependencies:** Phase 1 (optional; can run in parallel)
- **Risk:** Low
- **MVP:** App can search courses via backend

### Phase 3: Course Matching Layer
- **Scope:** Matching logic, course_place_mappings table, resolution endpoint
- **Files:** Backend: matching service, migrations
- **Dependencies:** Phase 1, 2
- **Risk:** Medium (matching accuracy)
- **MVP:** User selects course → we know Golf API course_id

### Phase 4: Recommendation Engine Enrichment
- **Scope:** Pass course intelligence to shot/putt pipelines
- **Files:** Backend: openai/complete, putting/analyze; iOS: CaddiePromptBuilder, ShotContext
- **Dependencies:** Phase 3
- **Risk:** Medium
- **MVP:** Recommendations are course-aware

### Phase 5: Play Tab Setup + Active Round
- **Scope:** Add Play as Tab 0, course selection (new search), tee selection, 9/18, start round
- **Files:** ContentView, PlayView, new TeeSelectionView, CourseViewModel, backend course endpoints
- **Dependencies:** Phase 2, 3
- **Risk:** Medium
- **MVP:** User can start a round with course + tee + 9/18

### Phase 6: Score Tracking + Hole Progression + Round Summary
- **Scope:** Hole par from Golf API, score entry, round completion, summary view
- **Files:** RoundPlayView, RoundViewModel, ScoreTrackingService, Round model
- **Dependencies:** Phase 5
- **Risk:** Low
- **MVP:** Full round flow with score to par

### Phase 7: History Insights + Polish
- **Scope:** Round list in History, round detail, link recommendations to rounds
- **Files:** HistoryView, HistoryStore, Round model
- **Dependencies:** Phase 6
- **Risk:** Low
- **MVP:** History shows rounds and recommendations

### Phase 8 (Parallel): Quick Mode
- **Scope:** No-photo shot recommendation path
- **Files:** CaddieShotViewModel, ContextConfirmSheet, RecommenderService, backend
- **Dependencies:** None (can start early)
- **Risk:** Low
- **MVP:** User can get recommendation without photo

---

## PART 14 — MVP VS LATER

| Feature | MVP | Later |
|---------|-----|-------|
| Live map | Simple pin | Hole boundaries, auto-zoom |
| Auto hole detection | No | Yes |
| Social/friends | No | Yes |
| Handicap calc | No | Yes |
| Practice insights | No | Yes |
| Course strategy overlays | No | Yes |
| Tee selection | Yes | — |
| 9/18 selection | Yes | — |
| Quick Mode | Yes | — |
| Photo Mode | Yes | — |
| Google Places search | Yes | — |
| Golf API enrichment | Yes | — |

---

## PART 15 — RISKS / DESIGN TRADEOFFS

### 15.1 Technical Risks
- **Course matching accuracy:** Fuzzy matching may fail; need fallback and manual path
- **Golf API CSV quality:** Inconsistent data; robust parsing and validation
- **Backend latency:** Multiple providers (Google, Golf API, OpenAI) → optimize, cache, parallelize

### 15.2 UX Risks
- **In-round friction:** Too many taps (course, tee, hole) → minimize steps
- **Recommendation delay:** User waits → show loading, consider streaming
- **Location denial:** Graceful degradation (manual course, no nearby)

### 15.3 Product Complexity
- **Scope creep:** Stick to MVP; defer social, handicap, practice insights
- **Two modes (Photo/Quick):** Clear labeling to avoid confusion

### 15.4 Dependency Risk
- **Google API:** Key, quota, cost
- **Golf API:** CSV availability, format changes
- **Course-mapper:** Optional; can run without for MVP

### 15.5 Data Quality Risk
- **Golf API coverage:** Not all courses; handle missing gracefully
- **Google vs Golf name mismatch:** Matching may fail; allow "use without course data"

### 15.6 Simplify Aggressively
- Manual hole selection (no auto-detection in MVP)
- Simple map (pin only)
- No handicap in MVP
- No social in MVP

### 15.7 Avoid in Early Versions
- Complex map overlays
- Real-time hole detection
- Multiplayer or social
- Advanced analytics dashboards

---

## PART 16 — FINAL RECOMMENDATION

### 16.1 Recommended Architecture

- **4 tabs:** Play, Caddie, History, Profile
- **Play as Tab 0:** Primary entry for rounds
- **Backend mediates:** Google Places + Golf API; iOS never calls them directly
- **Course matching:** Persist mappings; match on name + coords + city
- **Recommendation:** Enrich with course intelligence; support Photo and Quick Mode
- **History:** Add rounds; link recommendations to rounds when in Play

### 16.2 Recommended Implementation Order

1. Phase 1: Golf API CSV ingestion  
2. Phase 2: Google Places integration  
3. Phase 3: Course matching layer  
4. Phase 8: Quick Mode (parallel)  
5. Phase 5: Play tab setup + active round  
6. Phase 4: Recommendation enrichment  
7. Phase 6: Score + hole progression + summary  
8. Phase 7: History insights  

### 16.3 Single Most Important Thing to Get Right First

**Course matching (Phase 3).** If we cannot reliably map "Pebble Beach" from Google to our Golf API record, enrichment fails and recommendations stay generic. Invest in matching quality and fallbacks.

### 16.4 Three Biggest Mistakes to Avoid

1. **Overbuilding the map:** A simple "you are here" pin is enough for MVP. Fancy hole boundaries and auto-detection can wait.
2. **Skipping Quick Mode:** Many users will want a recommendation without taking a photo. Implement it early.
3. **Tight coupling to Golf API:** Design for missing data. If a course has no Golf API record, recommendations should still work with location, weather, and manual context.

---

## APPENDIX: Files Likely Impacted by Phase

| Phase | iOS Files | Backend / Other |
|-------|-----------|-----------------|
| 1 | — | Migrations, ingestion script |
| 2 | CourseService, CourseViewModel | routes, Google client |
| 3 | CourseService | matching service, mappings |
| 4 | CaddiePromptBuilder, ShotContext, CaddieShotViewModel | openai/complete, putting/analyze |
| 5 | ContentView, PlayView, CourseViewModel, new TeeSelectionView | course endpoints |
| 6 | RoundPlayView, RoundViewModel, ScoreTrackingService, Round | — |
| 7 | HistoryView, HistoryStore | — |
| 8 | CaddieShotViewModel, ContextConfirmSheet, RecommenderService | openai/complete |

---

*End of document. No code has been implemented. This is a planning artifact only.*
