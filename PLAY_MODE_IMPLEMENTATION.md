# Play Mode Implementation — Week 2

## Part A — Files Created/Updated

### Created (iOS)
| File | Purpose |
|------|---------|
| `ios/Models/PlayModeModels.swift` | PlaceSuggestion, FullCoursePayload, PlaySession, RoundType, CaddieRecommendationV1 |
| `ios/Services/PlayModeService.swift` | autocomplete, nearby, resolve, fetchCourse API calls |
| `ios/Services/PlayModeRecommendationEngine.swift` | V1 distance→club mapping, hazard-aware target advice |
| `ios/Services/DistanceEngine.swift` | Haversine yards, front/center/back green distances |
| `ios/Services/LocationSmoothing.swift` | GPS smoothing (avg last N, ignore jumps >50m) |
| `ios/ViewModels/PlayModeViewModel.swift` | Flow state, course selection, round setup, hole view |
| `ios/Features/Play/PlayModeView.swift` | Tab entry, screen routing |
| `ios/Features/Play/PlayCourseSelectionView.swift` | Search + nearby, place selection |
| `ios/Features/Play/PlayRoundSetupView.swift` | Tee + round type selection |
| `ios/Features/Play/PlayHoleView.swift` | Hole info, distances, map, Get Caddie, hole nav |
| `ios/Features/Play/PlaySimpleMapView.swift` | Map: user, green, hazards |

### Updated (iOS)
| File | Change |
|------|--------|
| `ios/ContentView.swift` | Added Play tab (tag 1), renumbered History (2), Profile (3) |
| `ios/Caddie.ai.xcodeproj/project.pbxproj` | Added new files to project |

### Updated (Backend)
| File | Change |
|------|--------|
| `backend/services/courseIntelligence.js` | Added `pois` array to each hole in full course payload |

---

## Part B — Frontend Architecture (Play Mode)

```
Play Tab
  └── PlayModeView (NavigationStack)
        ├── PlayCourseSelectionView (Screen 1)
        │     ├── Search bar → autocomplete
        │     ├── Nearby list (on load + pull refresh)
        │     └── PlaceRow → selectPlace → resolve
        ├── PlayRoundSetupView (Screen 2)
        │     ├── Tee picker
        │     ├── Round type (18 / Front 9 / Back 9)
        │     └── Start Round → confirmRoundSetup
        └── PlayHoleView (Screen 3)
              ├── Hole header (number, par, yardage)
              ├── Distance section (front/center/back)
              ├── PlaySimpleMapView (user, green, hazards)
              ├── Get Caddie Recommendation button
              └── Previous / Next hole
```

**State flow:** `PlayModeViewModel` holds `screen`, `session`, `coursePayload`. Course data is prefetched once when entering round setup or hole view.

---

## Part C — Backend Changes

- **courseIntelligence.js:** Each hole in `getFullCoursePayload` now includes a `pois` array (POI type, location label, lat, lon) for hazard-aware recommendations.

No new endpoints. Uses existing:
- `GET /api/courses/autocomplete`
- `GET /api/courses/nearby`
- `POST /api/courses/resolve`
- `GET /api/courses/:id`

---

## Part D — State Management Approach

- **PlayModeViewModel:** Single source of truth for Play flow
  - `screen`: courseSelection | roundSetup | holeView
  - `session`: PlaySession (courseId, teeId, roundType, currentHole, userPosition)
  - `coursePayload`: FullCoursePayload (prefetched, in memory)
  - `distanceToGreen`, `distanceToFront`, `distanceToBack`: derived from user position
  - `currentRecommendation`: CaddieRecommendationV1

- **LocationSmoothing:** Rolling buffer of last 5 coordinates; ignores jumps >50m; used for hole view.

- **No persistence:** Session is in-memory. Back button clears and returns to course selection.

---

## Part E — Recommendation Logic Implementation

**PlayModeRecommendationEngine** (V1, no AI):

1. **Club selection:** Uses `PlayerProfile.clubs`; finds club whose carry ± buffer matches distance. Fallback: distance ranges (e.g. >200→Driver, >140→5i, etc.).

2. **Target advice:** Based on hazards:
   - Water + bunker → center green
   - Water only → favor right
   - Bunker only → left of bunker
   - No hazards → center of green

3. **Rationale:** Concise text including club, target, and hazard avoidance.

**Input:** distanceToGreen, hole POIs (from prefetched payload), PlayerProfile.

**Output:** `CaddieRecommendationV1 { club, target, rationale }`.

---

## Part F — Known Limitations (Expected for V1)

| Limitation | Notes |
|------------|-------|
| No scoring | Per spec; not built |
| Manual hole progression | No auto-detection of hole change |
| Recommendation is rule-based | No AI call; uses profile clubs + distance |
| Location smoothing basic | 5-point average, 50m jump filter |
| Backend base URL | DEBUG uses localhost:8080; Release uses Render |
| Candidates disambiguation | Picks first candidate; no UI to choose |
| No hole layout polygons | Map shows points only (user, green, hazards) |
| LocationService stops after 30s | May need longer updates for full round |

---

## Success Criteria Met

- [x] User can select a course (autocomplete + nearby → resolve)
- [x] User can start a round (tee + round type)
- [x] User sees hole info (number, par, yardage, distances)
- [x] User gets a usable shot recommendation (club, target, rationale)

---

## How to Test

1. Start backend: `cd backend && npm start`
2. Build and run iOS app (Play tab)
3. Search "pebble" or use nearby (with location enabled)
4. Select a course → resolve
5. Choose tee and round type → Start Round
6. On hole view: enable location for distances; tap "Get Caddie Recommendation"
7. Use Previous/Next to change holes
