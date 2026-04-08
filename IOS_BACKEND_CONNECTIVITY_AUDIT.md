# iOS → Render Backend Connectivity Audit

**Date:** March 2025  
**Objective:** Identify why the iOS app fails to connect to the deployed Render backend. Analysis only — no code changes.

---

## PART 1 — BASE URL USAGE

### Every file and location where base URL appears

| File | Location | Current Value | Notes |
|------|----------|---------------|-------|
| **APIService.swift** | `APIConfig.baseURLString` (line 13) | `https://caddie-ai-backend.onrender.com` | ✅ Single source for main backend |
| **APIService.swift** | `APIService.baseURLString` (line 21) | Same as APIConfig | Alias |
| **APIService.swift** | `baseURL` (line 22) | URL from APIConfig | Used by APIService, CourseService, OpenAIClient |
| **PlayModeService.swift** | `baseURL` computed (lines 15–21) | **DEBUG:** `http://localhost:8080` ❌<br>**RELEASE:** `https://caddie-ai-backend.onrender.com` ✅ | **CRITICAL: DEBUG uses localhost** |
| **CourseMapperService.swift** | `baseURL` computed (lines 16–24) | **Simulator:** `http://localhost:8081` ❌<br>**Physical device:** `http://192.168.1.151:8081` ❌ | **CRITICAL: Never uses Render; HTTP only** |
| **AILogger.swift** | line 156 | `APIConfig.baseURLString` | Analytics endpoint |
| **CourseIntelligenceView.swift** | line 777 | `APIConfig.baseURLString` | Image URL construction |
| **PhotoCaptureView.swift** | line 776 | `APIConfig.baseURLString` | Image URL construction |

### Summary

- **localhost still used:** YES — PlayModeService (DEBUG), CourseMapperService (simulator + device)
- **Render URL correctly set:** YES — in APIConfig and PlayModeService (Release only)
- **Conflicting base URLs:** YES — PlayModeService and CourseMapperService use different logic and never point to Render in many build/config combinations

---

## PART 2 — RENDER BACKEND CONFIG

### Endpoint alignment

| iOS Endpoint (PlayModeService) | Backend Route (expected) | Query/body | Status |
|-------------------------------|--------------------------|------------|--------|
| `GET /api/courses/autocomplete` | `/api/courses/autocomplete` | `query`, `lat`, `lon` | ✅ Aligned (WEEK2_READINESS_REPORT) |
| `GET /api/courses/nearby` | `/api/courses/nearby` | `lat`, `lon`, `radius_km` | ✅ Aligned |
| `POST /api/courses/resolve` | `/api/courses/resolve` | Body: `{ placeId, courseId? }` | ✅ Aligned |
| `GET /api/courses/:id` | `/api/courses/:id` | — | ✅ Aligned |

### Path consistency

- PlayModeService uses `api/courses/autocomplete`, `api/courses/nearby`, `api/courses/resolve`, `api/courses/{id}` — matches spec.
- Backend accepts both `query` and `q` for autocomplete (WEEK2_READINESS_REPORT).

### CourseService vs PlayModeService

- **CourseService** (Home tab, Start Round): `GET /api/courses?lat=&lon=` or `?query=` — legacy endpoint; uses APIService (Render).
- **PlayModeService** (Play tab): autocomplete, nearby, resolve, fetch — uses its own base URL (localhost in DEBUG).

---

## PART 3 — NETWORK REQUEST VALIDATION

### Flow: PlayCourseSelectionView → PlayModeViewModel → PlayModeService

1. **PlayCourseSelectionView** `.task` / `.refreshable` → `onLoadNearby(lat, lon)`
2. **PlayModeView** passes `onLoadNearby: { await vm.fetchNearby(lat: $0, lon: $1) }`
3. **PlayModeViewModel.fetchNearby** → `playModeService.nearby(lat:lat, lon:lon)`
4. **PlayModeService.nearby**:
   - **URL:** `{baseURL}/api/courses/nearby?lat={lat}&lon={lon}&radius_km=10`
   - **baseURL in DEBUG:** `http://localhost:8080` → device/simulator cannot reach host machine
   - **baseURL in RELEASE:** `https://caddie-ai-backend.onrender.com` → correct
   - **Method:** GET
   - **Headers:** None (default URLSession)
   - **Timeout:** URLSession default (~60s)

### Where the request fails

| Scenario | baseURL | Result |
|----------|---------|--------|
| DEBUG build, Simulator | `http://localhost:8080` | Simulator can reach host → may work if backend runs locally |
| DEBUG build, Physical device | `http://localhost:8080` | **FAIL** — device cannot reach developer machine |
| RELEASE build, any | `https://caddie-ai-backend.onrender.com` | Should work if Render is up |

### Failure modes

1. **Never sent:** Unlikely; URL construction is straightforward.
2. **Rejected by iOS:** Possible if HTTP used where ATS requires HTTPS (see Part 4).
3. **Timeout:** Likely on Render cold start (first request can take 30–60s).
4. **Error response:** 503 if Google Places key missing; 404 for invalid course ID.

### PlayModeService has no logging

- No `DebugLogging.logAPI` calls.
- Errors are thrown; ViewModel catches and sets `autocompleteSuggestions = []` or `nearbySuggestions = []` with no user feedback.

---

## PART 4 — ATS (APP TRANSPORT SECURITY)

### Current state

- **Info.plist:** No `NSAppTransportSecurity` or `NSExceptionDomains`.
- **Entitlements:** `com.apple.security.network.client` = true (allows outbound network).

### ATS behavior (default)

- Default ATS requires HTTPS.
- **HTTP is blocked** unless an exception is added.

### Affected services

| Service | URL | ATS impact |
|---------|-----|------------|
| PlayModeService (DEBUG) | `http://localhost:8080` | localhost often exempt; simulator may work |
| CourseMapperService | `http://localhost:8081` or `http://192.168.1.151:8081` | **Blocked** — HTTP to non-localhost |
| APIService / APIConfig | `https://caddie-ai-backend.onrender.com` | ✅ HTTPS — allowed |
| PlayModeService (RELEASE) | `https://caddie-ai-backend.onrender.com` | ✅ HTTPS — allowed |

### Conclusion

- Render URLs use HTTPS → no ATS issue.
- CourseMapperService uses HTTP → will be blocked by ATS on device.
- localhost HTTP may work in simulator due to ATS exceptions for local development.

---

## PART 5 — ERROR HANDLING + LOGGING

### Current error handling

| Component | On failure | User-visible | Logging |
|-----------|------------|-------------|---------|
| PlayModeViewModel.fetchAutocomplete | Sets `autocompleteSuggestions = []` | Empty list, no message | None |
| PlayModeViewModel.fetchNearby | Sets `nearbySuggestions = []` | "Search for a course or enable location..." | None |
| PlayModeViewModel.selectPlace | Sets `resolveError` | Red error text | None |
| PlayModeViewModel.prefetchCourseIfNeeded | Sets `prefetchError` | Not clearly surfaced in UI | None |
| PlayModeService | Throws | Caught by ViewModel | None |
| CourseService | Falls back to CourseMapperService, then `[]` | Empty or fallback | `print()` only |
| APIService | Throws, retries 502/503/504 | Varies by caller | DebugLogging (DEBUG only) |

### Recommendations

1. **Logging:** Add `DebugLogging.logAPI` (or equivalent) in PlayModeService for URL, method, status, and errors.
2. **User feedback:** Show a toast/banner when autocomplete or nearby fails (e.g. "Could not load courses. Check connection.").
3. **Differentiate errors:** Distinguish network failure, timeout, and 503 (service unavailable) for better UX and debugging.

---

## PART 6 — RENDER-SPECIFIC RISKS

### Cold start

- Render free tier spins down after inactivity.
- First request can take 30–60+ seconds.
- **PlayModeService:** Uses default URLSession timeout (~60s) — may be sufficient but borderline.
- **APIService:** `requestTimeout = 20` — may be too short for cold start.

### Timeout handling

| Service | Timeout | Retry |
|---------|---------|-------|
| PlayModeService | Default (~60s) | None |
| APIService | 20s (some endpoints), 10s (analytics) | Yes for 502/503/504 |
| CourseMapperService | Default | None |

### Retry logic

- PlayModeService: no retry.
- CourseMapperService: no retry.
- APIService: retries 502/503/504 up to 2 times with exponential backoff.

---

## PART 7 — ROOT CAUSE + FIX PLAN

### Part A — Root cause of failure

**Primary:** PlayModeService uses `http://localhost:8080` in DEBUG builds. Any DEBUG run (especially on a physical device) will fail to reach the backend.

**Secondary:**
1. CourseMapperService never uses Render; it uses localhost or a hardcoded LAN IP over HTTP.
2. Silent error handling: autocomplete/nearby failures show empty results with no explanation.
3. No logging in PlayModeService makes debugging difficult.
4. Possible timeout on Render cold start with default or short timeouts.

### Part B — Exact files causing issue

| File | Issue |
|------|-------|
| `ios/Services/PlayModeService.swift` | DEBUG → localhost:8080; no timeout; no retry; no logging |
| `ios/Services/CourseMapperService.swift` | Always localhost/LAN; HTTP; never production |
| `ios/ViewModels/PlayModeViewModel.swift` | Swallows errors; no user feedback for autocomplete/nearby |
| `ios/Services/APIService.swift` | 20s timeout may be short for Render cold start |

### Part C — What needs to be changed

1. **PlayModeService.swift**
   - Use `APIConfig.baseURLString` (or equivalent) for all builds, or at least for production testing.
   - Remove DEBUG → localhost so production testing works in Xcode.
   - Add explicit timeout (e.g. 45–60s) for cold start.
   - Add DebugLogging for requests and errors.

2. **CourseMapperService.swift**
   - For production: use Render backend if course-mapper is deployed there, or a configurable base URL.
   - If course-mapper stays local: document that it is dev-only; ensure it is not used for critical Play Mode flows.

3. **PlayModeViewModel.swift**
   - Surface network errors (e.g. `nearbyError`, `autocompleteError`) instead of silently clearing results.
   - Show a user-visible message when requests fail.

4. **APIService.swift** (optional)
   - Consider increasing timeout for health/course endpoints to 45–60s for Render cold start.

5. **Info.plist** (if keeping HTTP for local dev)
   - Add ATS exception only for localhost if needed; do not relax ATS for production URLs.

### Part D — Priority order of fixes

| Priority | Fix | Impact |
|----------|-----|--------|
| P0 | PlayModeService: use Render URL in all builds (or make DEBUG configurable) | Unblocks production testing |
| P0 | PlayModeService: add logging for requests/responses/errors | Enables debugging |
| P1 | PlayModeViewModel: surface errors to user | Better UX and feedback |
| P1 | PlayModeService: set explicit timeout (e.g. 45s) | Handles Render cold start |
| P2 | CourseMapperService: production URL or document as dev-only | Avoids confusion and ATS issues |
| P2 | APIService: consider longer timeout for cold start | Reduces spurious failures |

### Part E — Risks remaining

1. **Google Places API key:** Backend may return 503 if key is missing; iOS will see empty results.
2. **Render cold start:** First request after idle can still time out; consider a warming request or longer timeout.
3. **CourseMapperService:** If used in production flows, HTTP and local URLs will fail; needs a production strategy.
4. **No retry in PlayModeService:** Transient failures require a manual retry by the user.

---

*End of audit. No code changes applied.*
