//
//  RoundMapView.swift
//  Caddie.ai
//
//  Full-screen satellite hole map.
//
//  ARCHITECTURE INVARIANTS (must not be violated):
//    • Tee  — always comes from HoleGeometry POI data (never user location)
//    • Green — always comes from HoleGeometry (greenCenter)
//    • Bearing — locked to tee → green vector, computed once per hole
//    • Camera — never reacts to user location; user location is display-only
//    • Distance — computed elsewhere (user → green), shown via parent view

import SwiftUI
import MapKit

// MARK: - Per-hole locked camera state

private struct HoleCameraState: Equatable {
    let holeNumber: Int
    let bearing: CLLocationDirection
    let tee: CLLocationCoordinate2D
    let greenCenter: CLLocationCoordinate2D
    let par: Int

    /// Only equality-compare by hole identity — geometry is stable per hole.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.holeNumber == rhs.holeNumber
    }
}

// MARK: - View

struct RoundMapView: View {

    // MARK: Inputs

    var holeNumber: Int
    /// Full hole data (geometry, par). Drives ALL camera and orientation logic.
    var holeData: HoleData?
    /// User coordinate — shown as a blue dot ONLY. Never used for camera.
    var userCoordinate: CLLocationCoordinate2D?

    // MARK: State

    @State private var position: MapCameraPosition = .automatic
    @State private var lockedState: HoleCameraState?

    // MARK: Body

    var body: some View {
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

            // ── Hole corridor line: tee → green ────────────────────────────
            if let s = lockedState {
                MapPolyline(coordinates: [s.tee, s.greenCenter])
                    .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .ignoresSafeArea()
        .onAppear { lockCamera(animated: false) }
        .onChange(of: holeNumber) { _, _ in lockCamera(animated: true) }
        .onChange(of: geometryStabilityKey) { _, _ in lockCamera(animated: false) }
        // User location changes never trigger camera — this is intentional.
    }

    // MARK: - Geometry Key

    /// Changes only when the hole's spatial geometry changes (not user position).
    /// Triggers camera re-lock only when backend delivers new hole data.
    private var geometryStabilityKey: String {
        let g = resolvedGreenCenter.map { "\($0.latitude),\($0.longitude)" } ?? "nil"
        return "\(holeNumber)|\(g)"
    }

    // MARK: - Tee/Green Resolution

    private var resolvedGreenCenter: CLLocationCoordinate2D? {
        holeData?.geometry?.greenCenter ?? holeData?.greenCenter
    }

    private func resolvedTee(greenCenter: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        // Priority: geometry POI → synthetic offset
        if let geom = holeData?.geometry { return geom.selectedTee }
        return syntheticTee(from: greenCenter)
    }

    /// Fallback tee when no POI data exists: ~320 yards (293 m) north of green.
    private func syntheticTee(from green: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude:  green.latitude  + (293.0 / 111_320.0),
            longitude: green.longitude
        )
    }

    // MARK: - Camera Lock

    private func lockCamera(animated: Bool) {
        guard let state = buildCameraState() else {
            // Edge case: no green data — stay wherever we are
            return
        }
        lockedState = state
        let cam = computeCamera(from: state)
        if animated {
            withAnimation(.easeInOut(duration: 0.8)) { position = cam }
        } else {
            position = cam
        }
    }

    private func buildCameraState() -> HoleCameraState? {
        guard let greenCenter = resolvedGreenCenter else { return nil }
        let tee     = resolvedTee(greenCenter: greenCenter)
        let bearing = bearingDegrees(from: tee, to: greenCenter)
        let par     = holeData?.par ?? 4

        return HoleCameraState(
            holeNumber:  holeNumber,
            bearing:     bearing,
            tee:         tee,
            greenCenter: greenCenter,
            par:         par
        )
    }

    // MARK: - Camera Computation

    private func computeCamera(from state: HoleCameraState) -> MapCameraPosition {
        let tee   = state.tee
        let green = state.greenCenter

        // Hole distance drives zoom
        let holeDistance = CLLocation(latitude: tee.latitude, longitude: tee.longitude)
            .distance(from: CLLocation(latitude: green.latitude, longitude: green.longitude))

        // Par-based zoom multiplier — par 3 = tight, par 5 = wide
        let multiplier: Double
        switch state.par {
        case 3:  multiplier = 2.0
        case 5:  multiplier = 3.2
        default: multiplier = 2.6   // par 4 and unknown
        }

        let cameraDistance = max(holeDistance * multiplier, 350)

        // Midpoint shifted 7% toward tee — compensates for bottom control bar
        // occupying more vertical screen real-estate than the top HUD.
        let rawMidLat = (tee.latitude  + green.latitude)  / 2
        let rawMidLon = (tee.longitude + green.longitude) / 2
        let adjustedCenter = CLLocationCoordinate2D(
            latitude:  rawMidLat - 0.07 * (green.latitude  - tee.latitude),
            longitude: rawMidLon - 0.07 * (green.longitude - tee.longitude)
        )

        return .camera(MapCamera(
            centerCoordinate: adjustedCenter,
            distance:         cameraDistance,
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
