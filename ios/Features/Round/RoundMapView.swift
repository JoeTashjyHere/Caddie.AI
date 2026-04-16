//
//  RoundMapView.swift
//  Caddie.ai
//
//  Full-screen satellite hole map with locked tee-to-green orientation.
//
//  ARCHITECTURE INVARIANTS (must not be violated):
//    • Tee  — always comes from HoleGeometry POI data (never user location)
//    • Green — always comes from HoleGeometry (greenCenter)
//    • Bearing — locked to tee → green vector, computed once per hole/tee-set change
//    • Camera — never reacts to user location; user location is display-only
//    • Distance — computed elsewhere (user → green), shown via parent view
//    • Heading — ALWAYS applied via animated MapCamera; no silent north-up fallback
//    • Re-lock — automatic on hole/tee/geometry/scenePhase change; manual via button
//    • Drift — detected on every camera-end event; auto-snaps back after 4s inactivity

import SwiftUI
import MapKit

// MARK: - Per-hole locked camera state

private struct HoleCameraState: Equatable {
    let holeNumber: Int
    let bearing: CLLocationDirection
    let tee: CLLocationCoordinate2D
    let greenCenter: CLLocationCoordinate2D
    let par: Int
    let teeSource: String
    let bearingQuality: String
    let cameraDistance: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.holeNumber == rhs.holeNumber &&
        lhs.bearing == rhs.bearing &&
        lhs.tee.latitude == rhs.tee.latitude &&
        lhs.tee.longitude == rhs.tee.longitude
    }
}

// MARK: - View

struct RoundMapView: View {

    // MARK: Inputs

    var holeNumber: Int
    var holeData: HoleData?
    var userCoordinate: CLLocationCoordinate2D?
    var selectedTeeSetId: String?

    // MARK: State

    @State private var position: MapCameraPosition = .automatic
    @State private var lockedState: HoleCameraState?
    @State private var headingDriftDetected = false
    @State private var autoRelockTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    /// Toggle for debug overlay (set true for testing, false for production)
    private let showDebugOverlay = false

    // MARK: Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            mapLayer

            if headingDriftDetected {
                relockButton
            }

            if showDebugOverlay, let s = lockedState {
                debugOverlay(state: s)
            }
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {

            // ── User dot (display only — never drives camera) ──────────────
            if let u = userCoordinate {
                Annotation("", coordinate: u) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 13, height: 13)
                        Circle()
                            .stroke(Color.white, lineWidth: 2.5)
                            .frame(width: 13, height: 13)
                    }
                }
            }

            // ── Green flag ─────────────────────────────────────────────────
            if let g = resolvedGreenCenter {
                Annotation("", coordinate: g) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                }
            }

            // ── Tee marker ─────────────────────────────────────────────────
            if let s = lockedState {
                Annotation("", coordinate: s.tee) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 18, height: 18)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                    }
                }
            }

            // ── Hole corridor line: tee → green (geographic coords) ────────
            if let s = lockedState {
                MapPolyline(coordinates: [s.tee, s.greenCenter])
                    .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .mapControls {
            MapCompass()
        }
        .ignoresSafeArea()
        .onAppear {
            lockCamera(animated: false)
        }
        .onChange(of: holeNumber) { _, _ in
            cancelAutoRelock()
            headingDriftDetected = false
            lockCamera(animated: true)
        }
        .onChange(of: geometryStabilityKey) { _, _ in
            cancelAutoRelock()
            headingDriftDetected = false
            lockCamera(animated: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                lockCamera(animated: false)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            validateCameraHeading(context.camera)
        }
    }

    // MARK: - Re-lock Button

    private var relockButton: some View {
        Button {
            headingDriftDetected = false
            cancelAutoRelock()
            lockCamera(animated: true)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Re-center Hole")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.65)))
        }
        .padding(.top, 10)
        .padding(.leading, 10)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Debug Overlay

    @ViewBuilder
    private func debugOverlay(state: HoleCameraState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("H\(state.holeNumber) \(state.teeSource)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
            Text("brg: \(String(format: "%.1f", state.bearing))°")
                .font(.system(size: 9, design: .monospaced))
            Text("q: \(state.bearingQuality)")
                .font(.system(size: 9, design: .monospaced))
            Text("dist: \(String(format: "%.0f", state.cameraDistance))m")
                .font(.system(size: 9, design: .monospaced))
        }
        .foregroundColor(.white)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.7)))
        .padding(.top, 50)
        .padding(.leading, 10)
        .allowsHitTesting(false)
    }

    // MARK: - Geometry Stability Key

    private var geometryStabilityKey: String {
        let g = resolvedGreenCenter.map { "\($0.latitude),\($0.longitude)" } ?? "nil"
        let teeId = selectedTeeSetId ?? "nil"
        let teeCoord = holeData?.geometry?.teeCoordinate(forTeeSetId: selectedTeeSetId)
        let t = teeCoord.map { "\($0.latitude),\($0.longitude)" } ?? "nil"
        return "\(holeNumber)|\(g)|\(teeId)|\(t)"
    }

    // MARK: - Tee/Green Resolution

    private var resolvedGreenCenter: CLLocationCoordinate2D? {
        holeData?.geometry?.greenCenter ?? holeData?.greenCenter
    }

    private struct TeeResolution {
        let coordinate: CLLocationCoordinate2D
        let source: String
    }

    private func resolvedTeeWithAudit(greenCenter: CLLocationCoordinate2D) -> TeeResolution {
        if let geom = holeData?.geometry {
            let coord = geom.teeCoordinate(forTeeSetId: selectedTeeSetId)
            let source = geom.teeSource(forTeeSetId: selectedTeeSetId)

            #if DEBUG
            print("[TEE RESOLUTION] hole=\(holeNumber) selectedTeeSetId=\(selectedTeeSetId ?? "nil") resolvedSource=\(source)")
            if let id = selectedTeeSetId {
                let matched = geom.holeTees.contains { $0.teeSetId == id }
                if !matched && !geom.holeTees.isEmpty {
                    print("[TEE RESOLUTION] ⚠️ selectedTeeSetId \(id) NOT FOUND in holeTees — fell through to: \(source)")
                }
            }
            #endif

            return TeeResolution(coordinate: coord, source: source)
        }
        return TeeResolution(coordinate: syntheticTee(from: greenCenter), source: "synthetic")
    }

    private func syntheticTee(from green: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude:  green.latitude  + (293.0 / 111_320.0),
            longitude: green.longitude
        )
    }

    // MARK: - Camera Heading Validation

    private func validateCameraHeading(_ camera: MapCamera) {
        guard let locked = lockedState else { return }
        let drift = abs(camera.heading - locked.bearing)
        let normalizedDrift = min(drift, 360 - drift)
        let drifted = normalizedDrift > 5

        withAnimation(.easeOut(duration: 0.2)) {
            headingDriftDetected = drifted
        }

        if drifted {
            scheduleAutoRelock()

            #if DEBUG
            print("[CAMERA DRIFT] ⚠️ heading=\(String(format: "%.1f", camera.heading))° expected=\(String(format: "%.1f", locked.bearing))° drift=\(String(format: "%.1f", normalizedDrift))°")
            #endif
        } else {
            cancelAutoRelock()
        }
    }

    // MARK: - Auto Re-lock (snaps back after user stops interacting)

    private func scheduleAutoRelock() {
        cancelAutoRelock()
        autoRelockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            headingDriftDetected = false
            lockCamera(animated: true)
        }
    }

    private func cancelAutoRelock() {
        autoRelockTask?.cancel()
        autoRelockTask = nil
    }

    // MARK: - Camera Lock (the single source of truth for orientation)

    private func lockCamera(animated: Bool) {
        guard let state = buildCameraState() else {
            #if DEBUG
            print("[ROUND MAP] ⚠️ No camera state for hole \(holeNumber) — missing green data")
            #endif
            return
        }
        lockedState = state
        let cam = computeCamera(from: state)

        withAnimation(.easeInOut(duration: animated ? 0.8 : 0.25)) {
            position = cam
        }

        #if DEBUG
        print("[MAP LOCK] ═══════════════════════════════════════")
        print("[MAP LOCK] hole=\(state.holeNumber) heading=\(String(format: "%.1f", state.bearing))° tee=\(state.teeSource) quality=\(state.bearingQuality)")
        print("[MAP LOCK] camera_type=MapCamera distance=\(String(format: "%.0f", state.cameraDistance))m animated=\(animated)")
        print("[MAP LOCK] fallback=\(state.bearingQuality == "FALLBACK_NORTH")")
        print("[HERNDON AUDIT] hole=\(state.holeNumber) teeSource=\(state.teeSource) bearing=\(String(format: "%.1f", state.bearing))° bearingSource=\(state.bearingQuality)")
        print("[MAP LOCK] ═══════════════════════════════════════")
        #endif
    }

    private func buildCameraState() -> HoleCameraState? {
        guard let greenCenter = resolvedGreenCenter else { return nil }
        let teeResult = resolvedTeeWithAudit(greenCenter: greenCenter)
        let bearing = bearingDegrees(from: teeResult.coordinate, to: greenCenter)
        let par = holeData?.par ?? 4

        let bearingQuality: String
        if teeResult.source == "synthetic" {
            bearingQuality = "FALLBACK_NORTH"
        } else if teeResult.source.contains("synth") {
            bearingQuality = "VALID_SYNTH"
        } else {
            bearingQuality = "VALID_REAL"
        }

        let holeDistance = CLLocation(latitude: teeResult.coordinate.latitude, longitude: teeResult.coordinate.longitude)
            .distance(from: CLLocation(latitude: greenCenter.latitude, longitude: greenCenter.longitude))

        let multiplier: Double
        switch par {
        case 3:  multiplier = 2.0
        case 5:  multiplier = 3.2
        default: multiplier = 2.6
        }
        let cameraDistance = max(holeDistance * multiplier, 350)

        #if DEBUG
        let geom = holeData?.geometry
        print("[HOLE GEOMETRY] ═══════════════════════════════════════")
        print("[HOLE GEOMETRY] Hole \(holeNumber) par=\(par)")
        print("[TEE AUDIT]  selectedTeeSetId: \(selectedTeeSetId ?? "nil")")
        print("[TEE AUDIT]  holeTees count: \(geom?.holeTees.count ?? 0)")
        if let geom {
            for ht in geom.holeTees {
                let matchTag = ht.teeSetId == selectedTeeSetId ? " ◄ SELECTED" : ""
                print("[TEE AUDIT]  tee[\(ht.teeName)]: (\(ht.coordinate.latitude), \(ht.coordinate.longitude)) synth=\(ht.isSynthesized)\(matchTag)")
            }
        }
        print("[TEE AUDIT]  teeFront: \(geom?.teeFront.map { "(\($0.latitude), \($0.longitude))" } ?? "nil")")
        print("[TEE AUDIT]  teeBack:  \(geom?.teeBack.map  { "(\($0.latitude), \($0.longitude))" } ?? "nil")")
        print("[TEE AUDIT]  → resolved: (\(teeResult.coordinate.latitude), \(teeResult.coordinate.longitude)) source=\(teeResult.source)")
        print("[HOLE GEOMETRY] greenCenter: (\(greenCenter.latitude), \(greenCenter.longitude))")
        print("[HOLE GEOMETRY] bearing: \(String(format: "%.1f", bearing))° quality=\(bearingQuality)")
        print("[HOLE GEOMETRY] holeDistance: \(String(format: "%.0f", holeDistance))m cameraDistance: \(String(format: "%.0f", cameraDistance))m")
        if bearingQuality == "FALLBACK_NORTH" {
            print("[ALIGNMENT HEALTH] ⚠️ FALLBACK TEE IN USE — bearing may not reflect real hole direction")
        }
        print("[HOLE GEOMETRY] ═══════════════════════════════════════")
        #endif

        return HoleCameraState(
            holeNumber:     holeNumber,
            bearing:        bearing,
            tee:            teeResult.coordinate,
            greenCenter:    greenCenter,
            par:            par,
            teeSource:      teeResult.source,
            bearingQuality: bearingQuality,
            cameraDistance:  cameraDistance
        )
    }

    // MARK: - Camera Computation (tee-at-bottom guarantee)

    private func computeCamera(from state: HoleCameraState) -> MapCameraPosition {
        let tee   = state.tee
        let green = state.greenCenter

        // Vector from tee → green (in coordinate space)
        let dLat = green.latitude  - tee.latitude
        let dLon = green.longitude - tee.longitude

        // Camera center: midpoint shifted 15% along the tee→green vector.
        // This places the focal point at 65% tee / 35% green, pushing the tee
        // into the bottom ~25% of the visible area and the green into the top ~20%.
        // The 15% value accounts for the bottom control bar that occludes ~10-15%
        // of the screen.
        let midLat = (tee.latitude  + green.latitude)  / 2
        let midLon = (tee.longitude + green.longitude) / 2
        let adjustedCenter = CLLocationCoordinate2D(
            latitude:  midLat + 0.15 * dLat,
            longitude: midLon + 0.15 * dLon
        )

        return .camera(MapCamera(
            centerCoordinate: adjustedCenter,
            distance:         state.cameraDistance,
            heading:          state.bearing,
            pitch:            0
        ))
    }

    // MARK: - Bearing Math

    private func bearingDegrees(
        from: CLLocationCoordinate2D,
        to:   CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude  * .pi / 180
        let lat2 = to.latitude    * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y    = sin(dLon) * cos(lat2)
        let x    = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}
