//
//  ActiveRoundContext.swift
//  Caddie.ai
//
//  Single source of truth for round play: cached course context, holes, tees, distances.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Hole Geometry (POI-based, from coordinates.csv)

/// Full spatial geometry for a hole: structured tee and green POIs.
/// Separation of responsibilities — geometry defines the hole corridor;
/// user location is never used here.
struct HoleGeometry: Equatable {
    let teeFront: CLLocationCoordinate2D?
    let teeBack: CLLocationCoordinate2D?
    let greenFront: CLLocationCoordinate2D?
    let greenCenter: CLLocationCoordinate2D   // always present when geometry exists
    let greenBack: CLLocationCoordinate2D?

    /// Priority: Tee Front → Tee Back → synthetic offset from green.
    var selectedTee: CLLocationCoordinate2D {
        if let t = teeFront { return t }
        if let t = teeBack  { return t }
        return syntheticTee()
    }

    /// Fallback tee: project ~320 yards (293 m) due north of greenCenter.
    /// Only used when no real tee data exists.
    private func syntheticTee() -> CLLocationCoordinate2D {
        let offsetMeters = 293.0
        return CLLocationCoordinate2D(
            latitude:  greenCenter.latitude  + (offsetMeters / 111_320.0),
            longitude: greenCenter.longitude
        )
    }

    static func == (lhs: HoleGeometry, rhs: HoleGeometry) -> Bool {
        lhs.greenCenter.latitude  == rhs.greenCenter.latitude  &&
        lhs.greenCenter.longitude == rhs.greenCenter.longitude &&
        lhs.teeFront?.latitude    == rhs.teeFront?.latitude    &&
        lhs.teeFront?.longitude   == rhs.teeFront?.longitude   &&
        lhs.teeBack?.latitude     == rhs.teeBack?.latitude     &&
        lhs.teeBack?.longitude    == rhs.teeBack?.longitude
    }
}

// MARK: - HoleData

struct HoleData: Equatable {
    let holeNumber: Int
    let par: Int
    let handicap: Int?
    /// Legacy green center coordinate (kept for distance engine / detection backward compat).
    let greenCenter: CLLocationCoordinate2D?
    /// Full POI geometry when available from backend. Drives all camera and orientation logic.
    let geometry: HoleGeometry?
    let hazards: [String]

    /// Human-readable hazard descriptions for the caddie prompt.
    var hazardDescriptions: [String] { hazards }

    static func == (lhs: HoleData, rhs: HoleData) -> Bool {
        guard lhs.holeNumber == rhs.holeNumber,
              lhs.par        == rhs.par,
              lhs.handicap   == rhs.handicap,
              lhs.hazards    == rhs.hazards,
              lhs.geometry   == rhs.geometry else { return false }
        switch (lhs.greenCenter, rhs.greenCenter) {
        case (nil, nil): return true
        case let (l?, r?): return l.latitude == r.latitude && l.longitude == r.longitude
        default: return false
        }
    }
}

struct TeeData: Equatable, Identifiable {
    let id: String
    let name: String
    let totalYards: Int
}

struct DistanceSnapshot: Equatable {
    var front: Double?
    var center: Double
    var back: Double?
}

enum RoundLength: String, CaseIterable {
    case front9
    case back9
    case full18
}

/// Passed from Play → setup sheet → `RoundPlayView` to initialize the active round.
struct RoundPlayLaunchConfig: Equatable {
    var roundLength: RoundLength
    var selectedTeeId: String?
}

extension RoundLength {
    var holeRange: ClosedRange<Int> {
        switch self {
        case .full18: return 1...18
        case .front9: return 1...9
        case .back9: return 10...18
        }
    }

    var displayTitle: String {
        switch self {
        case .full18: return "18 holes"
        case .front9: return "Front 9"
        case .back9: return "Back 9"
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

@MainActor
final class ActiveRoundContext: ObservableObject {
    @Published private(set) var courseId: String = ""
    @Published private(set) var courseName: String = ""
    @Published private(set) var courseCity: String?
    @Published private(set) var courseState: String?
    @Published private(set) var holes: [HoleData] = []
    @Published private(set) var tees: [TeeData] = []
    @Published var selectedTee: TeeData?
    @Published private(set) var currentHole: Int = 1
    @Published private(set) var roundLength: RoundLength = .full18
    @Published private(set) var distances: DistanceSnapshot?
    @Published private(set) var startedAt: Date = Date()
    @Published private(set) var loadError: String?
    @Published private(set) var isLoaded: Bool = false
    // TODO: Backend should supply courseRating and slopeRating via CourseContextCourseDTO
    // for accurate USGA-style handicap differential calculation.
    @Published private(set) var courseRating: Double?
    @Published private(set) var slopeRating: Double?

    var activeHoleRange: ClosedRange<Int> { roundLength.holeRange }

    /// Holes considered for POI-based auto detection (subset only).
    var activeHolesForDetection: [HoleData] {
        holes.filter { activeHoleRange.contains($0.holeNumber) }
    }

    func hole(for number: Int) -> HoleData? {
        holes.first { $0.holeNumber == number }
    }

    /// Sets `roundLength` before async load so navigation / labels match chosen round type immediately.
    func prepareForSession(launch: RoundPlayLaunchConfig?, persistedRoundLength: RoundLength?) {
        if let launch {
            roundLength = launch.roundLength
        } else if let persistedRoundLength {
            roundLength = persistedRoundLength
        } else {
            roundLength = .full18
        }
    }

    /// Load and configure round. Fresh start from setup uses `launch`; resume uses persisted length/tee and `resumeHole` (clamped). When both `launch` and persistence are nil, defaults to full 18.
    func startRound(
        courseId: String,
        courseDisplayName: String,
        launch: RoundPlayLaunchConfig?,
        resumeHole: Int?,
        persistedRoundLength: RoundLength?,
        persistedTeeId: String?
    ) async {
        self.courseId = courseId
        self.courseName = courseDisplayName
        self.startedAt = Date()
        self.loadError = nil
        self.isLoaded = false

        if let launch {
            roundLength = launch.roundLength
        } else if let persistedRoundLength {
            roundLength = persistedRoundLength
        } else {
            roundLength = .full18
        }

        #if DEBUG
        print("[ROUND] startRound — courseId: \(courseId) displayName: \(courseDisplayName)")
        #endif
        do {
            let dto = try await APIService.shared.fetchCourseContext(courseId: courseId)
            if courseName.isEmpty { courseName = dto.course.name }
            courseCity = dto.course.city
            courseState = dto.course.state
            courseRating = dto.course.courseRating
            slopeRating = dto.course.slopeRating

            holes = dto.holes.map { h in
                let gc: CLLocationCoordinate2D?
                if let lat = h.greenCenter?.lat, let lon = h.greenCenter?.lon {
                    gc = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                } else {
                    gc = nil
                }

                // Build full POI geometry when we have at least a green center.
                let geometry: HoleGeometry? = gc.map { center in
                    HoleGeometry(
                        teeFront:    h.teeFront.map    { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                        teeBack:     h.teeBack.map     { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                        greenFront:  h.greenFront.map  { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                        greenCenter: center,
                        greenBack:   h.greenBack.map   { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                    )
                }

                return HoleData(
                    holeNumber: h.holeNumber,
                    par:        h.par,
                    handicap:   h.handicap,
                    greenCenter: gc,
                    geometry:   geometry,
                    hazards:    h.hazards ?? []
                )
            }

            tees = dto.tees.map { TeeData(id: $0.id, name: $0.name, totalYards: $0.totalYards) }

            if let tid = launch?.selectedTeeId, let match = tees.first(where: { $0.id == tid }) {
                selectedTee = match
            } else if selectedTee == nil || tees.first(where: { $0.id == selectedTee?.id }) == nil {
                selectedTee = tees.first
            }

            let range = activeHoleRange
            let startHole: Int
            if launch != nil {
                startHole = range.lowerBound
            } else if let r = resumeHole {
                startHole = r.clamped(to: range)
            } else {
                startHole = range.lowerBound
            }
            applyHoleChange(startHole, logAsRoundChange: true)

            isLoaded = true
            let teeLabel = selectedTee.map { "\($0.name)" } ?? "none"
            print("[CTX] Round context initialized — \(courseName) holes:\(holes.count) tee:\(teeLabel) round:\(roundLength.displayTitle)")
        } catch {
            loadError = error.localizedDescription
            print("[CTX] Failed to load course context: \(error.localizedDescription)")
        }
    }

    /// Legacy entry: full-round resume-style load.
    func fetchCourseContext(courseId: String, courseDisplayName: String, initialHole: Int) async {
        await startRound(
            courseId: courseId,
            courseDisplayName: courseDisplayName,
            launch: nil,
            resumeHole: initialHole,
            persistedRoundLength: nil,
            persistedTeeId: nil
        )
    }

    func setCurrentHoleManual(_ hole: Int) {
        let clamped = hole.clamped(to: activeHoleRange)
        applyHoleChange(clamped, logAsRoundChange: true)
    }

    func advanceHole() {
        guard currentHole < activeHoleRange.upperBound else { return }
        applyHoleChange(currentHole + 1, logAsRoundChange: true)
    }

    func retreatHole() {
        guard currentHole > activeHoleRange.lowerBound else { return }
        applyHoleChange(currentHole - 1, logAsRoundChange: true)
    }

    /// Auto hole switch: only if detected hole is in the active subset.
    @discardableResult
    func applyDetectedHole(_ hole: Int) -> Bool {
        guard activeHoleRange.contains(hole), hole != currentHole else { return false }
        applyHoleChange(hole, logAsRoundChange: true)
        return true
    }

    private func applyHoleChange(_ hole: Int, logAsRoundChange: Bool) {
        guard hole != currentHole else { return }
        currentHole = hole
        if logAsRoundChange {
            print("[ROUND] Current hole changed — now \(hole)")
        }
    }

    /// Update yardages from user location to current hole's green (live).
    func updateDistances(user: CLLocationCoordinate2D) {
        guard let hole = hole(for: currentHole) else { return }
        guard let snap = DistanceEngine.distanceSnapshotToGreenCenter(user: user, greenCenter: hole.greenCenter) else { return }
        distances = snap
        print("[DIST] Updated — \(Int(round(snap.center))) yds")
    }
}
