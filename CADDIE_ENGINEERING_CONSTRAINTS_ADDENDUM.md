# Caddie.AI — Engineering Constraints & Gotchas Addendum

**Document Version:** 1.0  
**Date:** March 2025  
**Status:** Planning Addendum — No Code Changes  
**Purpose:** Explicit constraints and mitigation strategies before Week 1 build spec

---

## PART 1 — Top Product / Engineering Risks

### Ranked by Impact

| Rank | Risk | Why It Matters |
|------|------|----------------|
| **1** | **GPS drift causing wrong hole/distance** | Wrong hole detection → wrong distance → wrong recommendation → user gets bad advice. User loses trust immediately. Unlike a slow load, a wrong recommendation can actively hurt the round. Trust is the product. |
| **2** | **Recommendation latency from live fetches** | User taps "Get Caddie" and waits 5+ seconds → feels broken. During a round, users expect instant access. Every extra network call at tap-time compounds. Slow = unreliable in the user's mind. |
| **3** | **Silent automation with low confidence** | App auto-switches to wrong hole without asking → user scores wrong hole → round data corrupted. Or app prefills wrong distance → wrong club. Silent mistakes destroy trust faster than asking for confirmation. |
| **4** | **Course matching poisoning downstream** | Wrong Google Place → Golf API match → wrong course, wrong tees, wrong holes, wrong pars. All downstream intelligence is poisoned. But: most US courses will match; over-indexing on edge cases slows the build. |
| **5** | **Map jitter / visual instability** | Map jumps around with every GPS update → disorienting. User can't orient. Undermines the "live round operating system" feel. |
| **6** | **Over-fetching causing latency** | Trying to enrich at recommendation-time with weather, elevation, course details → multiple round-trips → slow. Prefetch should do the work; tap-time should be minimal. |
| **7** | **Missing manual override paths** | User knows they're on hole 7 but app says 8. No quick way to fix → frustration. Every inferred field must have a visible, fast override. |
| **8** | **Map as science project** | Building hole boundaries for all 18, fancy overlays, real-time course rendering → scope creep. Map should support the round, not become the round. |

---

## PART 2 — GPS Drift Mitigation Strategy

### 2.1 Hole Detection

| Problem | Mitigation |
|---------|------------|
| Drift places user in wrong green polygon | **Never auto-apply hole change with low confidence.** Emit confidence: HIGH (inside polygon or &lt;25yd to center), MEDIUM (25–60yd), LOW (&gt;60yd or ambiguous). |
| Drift causes hole to flip between 7 and 8 | **Require sustained position.** Hole change only after user has been in new hole's zone for 5–8 seconds. Debounce detection; ignore single noisy readings. |
| User between holes (walking) | **Hold last confident hole.** When confidence drops (user between green and next tee), keep current hole. Do not suggest change until user is clearly in new zone. |
| Multiple holes in range | **Prefer point-in-polygon over distance.** If inside polygon, confidence HIGH. If distance-only, require &lt;30yd to single nearest green; if two greens within 40yd, confidence LOW — do not auto-suggest. |
| Silent force | **Never silently force.** When confidence is MEDIUM or LOW, emit `pendingHoleSuggestion` only — user must tap Accept. When HIGH and sustained, can auto-apply but show brief "Switched to hole X" toast; user can tap to undo within 3 seconds. |

**Confidence thresholds:**
- **HIGH:** Inside green polygon, OR &lt;25yd to exactly one green center with no other green within 50yd.
- **MEDIUM:** 25–60yd to nearest green; or inside polygon but detection ran only 1–2 cycles.
- **LOW:** &gt;60yd to all greens; or ambiguous (two greens similarly close).

**Rule:** Only HIGH + sustained (5–8s) triggers auto-apply. MEDIUM/LOW always requires user confirmation.

**Cooldown after manual override:** If the user manually changes the hole (via picker or Next/Prev):
- Suppress automatic hole detection changes for a cooldown window: **2–5 minutes** OR until user has moved **>120m** from the position at override time.
- Hole detection may still run silently during the cooldown but must NOT auto-switch or suggest changes.
- This prevents the system from immediately "fighting" the user's manual override.

---

### 2.2 Map Updates

| Problem | Mitigation |
|---------|------------|
| Map jumps with every GPS update | **Debounce region updates.** Location updates every 1–5s; map region should update at most every 3–5s. Use running average or exponential smoothing for region center. |
| User pin jitter | **Smooth user annotation position.** Don't redraw pin on every raw coordinate. Use 2–3 second window: average of last N readings, or only update when displacement &gt;10m. |
| Zoom/span instability | **Stable span.** Keep map span relatively fixed during round (e.g. 0.003–0.005 lat/lon). Recenter on user when they drift &gt;50m from center, but avoid constant zoom changes. |
| Orientation loss | **North-up, minimal rotation.** Avoid rotating map with user heading unless explicitly requested. Stable north-up reduces disorientation. |

**Implementation notes:**
- LocationService: continue emitting raw coordinates for engines.
- Map layer: consume coordinates via a **MapStabilizer** that debounces (3s), optionally smooths, and emits stabilized position for annotation and region.
- Region: update center when smoothed position moves &gt;30m; keep span constant unless user zooms.

---

### 2.3 Distance Calculation

| Problem | Mitigation |
|---------|------------|
| Noisy coordinates inflate/deflate distance | **Smooth before compute.** Feed distance engine a stabilized position (same as map), not raw GPS. |
| Single bad reading = wrong distance | **Temporal smoothing.** Use last 3–5 readings; take median distance or average. Reject outliers (e.g. if new reading is 2x previous, ignore for one cycle). |
| Distance jumps 20 yards between readings | **Display smoothing.** Even if internal value updates, consider dampening displayed value: only update UI when change &gt;3 yards, or use 1–2 second delay before showing new value. |
| Wrong hole → wrong green → wrong distance | **Hole correctness first.** Distance is only as good as hole detection. If hole confidence is LOW, show distance with disclaimer: "~X yds (confirm hole)" or gray out. |

**Rule:** Distance engine consumes stabilized location. Display can add one more layer of smoothing for UX.

---

### 2.4 User Override Paths

Every inferred field must have a **fast, visible** override. No digging through menus.

| Field | Override Path | Location |
|-------|---------------|----------|
| **Hole** | Tap hole number in header → picker 1–18. One tap to open, one tap to select. | RoundPlayView header |
| **Distance** | In ContextConfirmSheet: distance field is editable. Prefilled but user can change. | Recommendation flow |
| **Course** | "Change course" in round setup; or "Edit" on course card before starting. During round: "Edit round" sheet. | PlayHomeView, RoundPlayView |
| **Tee** | "Change tee" before round start. During round: "Edit round" sheet (rare). | TeeSelectionView, EditRoundSheet |
| **Hole (when suggested)** | "Accept" or "Dismiss" on suggestion banner. Dismiss = keep current hole. | RoundPlayView banner |
| **Current hole (quick)** | Next / Prev buttons always visible. Manual override without confirmation. | RoundPlayView |

**Principle:** Override should be **one or two taps** from the main round view. No more than that.

---

### 2.5 Round Scoring Context

- **Score entry** is always tied to the **displayed** current hole (which may be user-overridden). Never score to a silently inferred hole.
- When user taps "Save score," we use `currentHole` from state — which may have been manually set. No background hole detection overwriting during score entry.
- **Pause hole detection** during active score entry (e.g. 10 seconds after score sheet opens) to avoid mid-tap switch.

---

## PART 3 — Prefetch / Cache Strategy for Live Recommendations

### 3.1 MUST PREFETCH (Required Before Round UI Appears)

These **must** be available before RoundPlayView appears. The round must not start until these are loaded:

| Data | Source | Storage | Used For |
|------|--------|---------|----------|
| Course metadata (id, name, placeId, city, state) | Already selected | ActiveRoundContext | All |
| Tee selection (id, name, total yards) | Already selected | ActiveRoundContext | All |
| Round length (9/18) | Already selected | ActiveRoundContext | Hole filter |
| Hole numbers (1–18 or 1–9 or 10–18) | GET /courses/:id | ActiveRoundContext.holeData | Hole detection, distance, prefill |
| Par per hole | From holeData | ActiveRoundContext.holeData | Score, prefill |
| Green center coordinates (lat, lon) per hole | From holeData | ActiveRoundContext.holeData | Distance, prefill |
| Basic hole distance information (front/center/back if available) | From tee + hole data | ActiveRoundContext.holeData | Prefill |
| Hazards / POIs (if lightweight) | From holeData if available | ActiveRoundContext.holeData | Prefill |
| ActiveRoundContext initialization | — | In-memory | All round state |

**Rule:** If any MUST PREFETCH item fails or times out, the round can still start with degraded data (e.g. par 4 default, distance from green center only). Never block the round UI from appearing.

---

### 3.2 NICE TO PREFETCH (Opportunistic)

These should be fetched when possible but **must NOT delay round start**:

| Data | Source | Notes |
|------|--------|-------|
| Hole polygons (green geometry) | GET /courses/:id/holes/:n/layout OR CourseMapper | Improves hole detection accuracy; fallback to distance-only if missing |
| Richer geometry overlays | CourseMapper | Map visuals; not required for scoring or recommendations |
| Extra CourseMapper features | CourseMapper API | Front/back green points, hazard polygons; nice-to-have |

**Rule:** If geometry fetch takes too long (e.g. >3 seconds), the round should start anyway. Use green center coordinates for distance and distance-based hole detection. Polygons can be fetched in background and applied when available.

---

### 3.3 Cached at Course Selection

When user selects a course (before tee selection):

| Data | Source | Storage | Used For |
|------|--------|---------|----------|
| Google placeId → Golf API course_id | Matching layer | course_place_mappings (backend); return to iOS | Resolution |
| Tees for course | GET /courses/:id | In-memory until round start | TeeSelectionView |
| Course details (name, city, state) | From selection response | In-memory | Prefill, display |

**Note:** Tee list is fetched at course selection so tee picker is instant. No fetch at "Start Round" for tees.

---

### 3.4 Cached Per Hole

| Data | When | Storage | Notes |
|------|------|---------|-------|
| Hole layout (polygon) | Round start (opportunistic) | ActiveRoundContext | NICE TO PREFETCH; may be empty |
| Green center | Round start | ActiveRoundContext | MUST PREFETCH |
| Front/center/back yardages | From tee + hole data at round start | ActiveRoundContext | If available from Golf API |

**No per-hole network fetches during the round.** Everything comes from the initial prefetch (or graceful fallback).

---

### 3.5 Refreshed in Background (Weather / Elevation)

**Rules:**

1. **Fetch at round start.** Weather and elevation are fetched once when the round begins.
2. **Refresh on hole change:** When the user moves to a new hole, check: if last fetch >10 minutes old → refresh. Otherwise use cached value.
3. **Failure handling:** Weather/elevation fetch failures must NOT block recommendations. Use cached values or defaults (e.g. 70°F, 5 mph wind, 0 ft elevation). Never block the round.

| Data | Trigger | Fallback if Fetch Fails |
|------|---------|-------------------------|
| **Weather** (wind, temp) | Round start; hole change if >10 min since last fetch | Use last cached; or defaults |
| **Elevation delta** | Round start; hole change if >10 min since last fetch | Use 0; or last cached |
| **Distance** (user → green) | Every 2–3s from location | Derived from cached green + location; no fetch |

**When user taps "Get Caddie,"** use the **cached** weather/elevation. Do not fetch at tap-time.

---

### 3.6 Fetched Only On-Demand (At Recommendation Time)

| Data | When | Why |
|------|------|-----|
| **AI recommendation** | User taps "Get Caddie" | Cannot prefetch; requires user intent |
| **Putting analysis** | User taps "Get Putting Read" | Requires photo; cannot prefetch |
| **Feedback submission** | User submits feedback | Async; not latency-critical |

**Rule:** At the moment the user taps for a recommendation, the **only** network call should be the recommendation/putting API itself. Everything else is already in memory or cache.

---

### 3.7 Keeping Recommendation Latency Low

| Principle | Implementation |
|-----------|----------------|
| **Prefetch aggressively** | Round start = load everything. Course selection = load tees. |
| **No tap-time enrichment** | Backend receives full context from iOS. iOS has already assembled from cache. |
| **Single round-trip** | One POST to api/openai/complete or api/putting/analyze. No chained calls. |
| **Timeout** | 15–20s max; show "Taking longer than usual" after 5s; allow cancel. |
| **Offline fallback** | If network fails, use offline club suggestion (existing) with cached context. |
| **Avoid over-fetch** | Don't prefetch weather for all 18 holes. One snapshot, refresh on timer. Don't prefetch recommendation for "next shot" — only on tap. |

**Target:** Tap to recommendation display in **&lt;3 seconds** under normal conditions. Prefetch is the primary lever.

---

## PART 4 — Course Matching Risk Treatment

### 4.1 Optimize for the Common Case

- **Most US courses exist in Golf API.** Assume matching will succeed for the majority.
- **Design for success path first.** Happy path: user selects course → match found → full intelligence. Optimize this path.
- **Don't over-build edge-case handling.** A manual "report no match" flow is fine. A complex disambiguation UI for 1% of cases is not.

### 4.2 Matching Logic (Robust but Not Paranoid)

| Scenario | Behavior |
|----------|----------|
| **Exact placeId in mappings** | Return cached golf_course_id. No re-match. |
| **New placeId, clear match** | Name similarity high + distance &lt;1km + city match → auto-match. Insert mapping. |
| **New placeId, ambiguous** | 2–3 candidates with similar scores → return top 3 for user pick. Store chosen mapping. |
| **New placeId, no good match** | Return null. iOS shows "Course data unavailable; recommendations will use location only." User can still play. |
| **Name mismatch** | "Pebble Beach Golf Links" vs "Pebble Beach" — normalize (remove "Golf Links," trim). Use trigram or Levenshtein. |

### 4.3 Fallback Behavior

- **No match:** Recommendations still work. Context: location, weather, manual course name, manual hole/distance. No course intelligence (par, hazards, geometry). Graceful degradation.
- **Wrong match:** User can override course in "Edit round." Rare; don't build complex correction flows for launch.
- **Cache mappings aggressively.** Once matched, never re-match. Reduces API calls and ensures consistency.

### 4.4 Priority

- Course matching is **important** but **not** the top risk. Implement it well, test with 20–30 real courses, then move on.
- If matching fails for a course, the app still works. If GPS drift causes wrong hole, the app gives bad advice. Prioritize accordingly.

---

## PART 5 — Launch Principles

1. **Never block the round.** The round experience must NEVER be blocked by a failing smart feature. If hole detection fails → user can manually select hole. If Golf API course match fails → round still works using location + manual hole/distance. If weather API fails → recommendations continue using default weather assumptions. If course geometry is missing → distance is calculated to green center only. If map overlay fails → scoring and recommendation flows still function. Graceful degradation is mandatory.

2. **Trust over automation.** Never silently change hole, distance, or course with low confidence. Suggest; let user confirm. When confidence is high and sustained, auto-apply is OK but show brief feedback.

3. **Prefetch everything possible.** By round start, MUST PREFETCH data is in memory. NICE TO PREFETCH must not delay round start. By recommendation tap, weather and elevation are cached. Tap-time = one API call.

4. **Every inferred field has a one-tap override.** Hole, distance, course, tee. No digging. Override is always visible when the field is displayed.

5. **Stabilize before display.** Raw GPS → stabilized for map and distance. Debounce map updates. Smooth distance display. Reduce jitter at all costs.

6. **Confidence is visible.** When hole detection is uncertain, show "Confirm hole?" or gray the hole indicator. When distance is derived from low-confidence hole, qualify it. Don't pretend certainty.

7. **Map supports the round.** User location, current hole, distance, recommendation access. No fancy overlays for launch. Extensible later.

8. **Graceful degradation.** No course match → still works. No hole geometry → distance from green center only. No weather → use defaults. Never block the user.

9. **Single round-trip at recommendation time.** Assemble context from cache. One POST. No chained fetches. No "get weather then get elevation then get recommendation."

10. **Sustained position for hole change.** 5–8 seconds in new zone before suggesting or auto-applying. Ignore single noisy readings.

11. **Optimize for the common case.** Most courses match. Most holes detect correctly. Most recommendations are fast. Build for that; handle edge cases without over-investing.

---

## PART 6 — Operational Metrics for Play Mode

The system should track the following analytics for Play mode to evaluate whether automation is actually working in real rounds:

| Metric | Purpose |
|--------|---------|
| Hole auto-detection suggestions shown | How often the system suggests a hole change |
| Hole auto-detection accepted | How often users accept the suggestion |
| Hole auto-detection dismissed | How often users dismiss (indicates possible wrong suggestion) |
| Manual hole overrides | Count of manual hole changes; high count may indicate detection issues |
| Average recommendation latency | Time from tap to recommendation display |
| % recommendations using fully cached context | Whether prefetch is working; 100% is ideal |
| Rounds completed without manual hole correction | Proxy for hole detection accuracy |
| Recommendation API response time | Backend latency; separate from total round-trip |

These metrics will help evaluate whether automation is trustworthy and whether prefetch/cache strategy is effective.

---

*End of Engineering Constraints & Gotchas Addendum. No code has been implemented. Week 1 build spec to follow.*
