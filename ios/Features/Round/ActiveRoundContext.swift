//
//  ActiveRoundContext.swift
//  Caddie.ai
//
//  Single source of truth for round play: cached course context, holes, tees, distances.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Per-Tee Coordinate (from golf_hole_tees)

/// GPS coordinate for a specific tee set on a specific hole.
struct HoleTeeCoordinate: Equatable {
    let teeSetId: String
    let teeName: String
    let coordinate: CLLocationCoordinate2D
    let yardage: Int
    let isSynthesized: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.teeSetId == rhs.teeSetId &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

// MARK: - Hole Geometry

/// Full spatial geometry for a hole, including per-tee positions.
/// Separation of responsibilities — geometry defines the hole corridor;
/// user location is never used here.
struct HoleGeometry: Equatable {
    // Legacy generic tee POIs (backward compat)
    let teeFront: CLLocationCoordinate2D?
    let teeBack: CLLocationCoordinate2D?
    let greenFront: CLLocationCoordinate2D?
    let greenCenter: CLLocationCoordinate2D
    let greenBack: CLLocationCoordinate2D?
    /// Per-tee-set coordinates (from golf_hole_tees)
    let holeTees: [HoleTeeCoordinate]

    /// Returns the coordinate for a specific tee set, or the best available fallback.
    func teeCoordinate(forTeeSetId teeSetId: String?) -> CLLocationCoordinate2D {
        if let id = teeSetId,
           let match = holeTees.first(where: { $0.teeSetId == id }) {
            return match.coordinate
        }
        if let first = holeTees.first {
            return first.coordinate
        }
        if let t = teeFront { return t }
        if let t = teeBack  { return t }
        return syntheticTee()
    }

    /// Source label for debugging.
    func teeSource(forTeeSetId teeSetId: String?) -> String {
        if let id = teeSetId,
           let match = holeTees.first(where: { $0.teeSetId == id }) {
            return match.isSynthesized ? "holeTee(\(match.teeName),synth)" : "holeTee(\(match.teeName),real)"
        }
        if let first = holeTees.first {
            return first.isSynthesized ? "holeTee(\(first.teeName),synth)" : "holeTee(\(first.teeName),real)"
        }
        if teeFront != nil { return "legacyTeeFront" }
        if teeBack  != nil { return "legacyTeeBack" }
        return "synthetic"
    }

    /// Legacy accessor — prefer teeCoordinate(forTeeSetId:) for tee-specific resolution.
    var selectedTee: CLLocationCoordinate2D {
        teeCoordinate(forTeeSetId: nil)
    }

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
        lhs.holeTees == rhs.holeTees &&
        lhs.teeFront?.latitude    == rhs.teeFront?.latitude    &&
        lhs.teeFront?.longitude   == rhs.teeFront?.longitude
    }
}

// MARK: - Raw Hazard POI (for tee-relative computation)

struct HazardPoi: Equatable {
    let type: String
    let locationLabel: String?
    let fairwaySide: String?
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.type == rhs.type &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
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
    /// Text hazard descriptions (for display / caddie prompt).
    let hazards: [String]
    /// Raw hazard POIs with coordinates (for tee-relative computation).
    let hazardPois: [HazardPoi]

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
    let slope: Int?
    let courseRating: Double?
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
                // Green center: prefer nested green object, then flat field
                let resolvedGC = h.resolvedGreenCenter
                let gc: CLLocationCoordinate2D?
                if let coord = resolvedGC {
                    gc = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon)
                } else {
                    gc = nil
                }

                let teeFrontCoord   = h.teeFront.map  { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let teeBackCoord    = h.teeBack.map   { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let greenFrontCoord = h.resolvedGreenFront.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                let greenBackCoord  = h.resolvedGreenBack.map  { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }

                // Per-tee coordinates from golf_hole_tees
                let holeTees: [HoleTeeCoordinate] = (h.tees ?? []).map { t in
                    HoleTeeCoordinate(
                        teeSetId: t.teeSetId,
                        teeName: t.teeName,
                        coordinate: CLLocationCoordinate2D(latitude: t.coordinate.lat, longitude: t.coordinate.lon),
                        yardage: t.yardage,
                        isSynthesized: t.isSynthesized ?? true
                    )
                }

                let geometry: HoleGeometry? = gc.map { center in
                    HoleGeometry(
                        teeFront:    teeFrontCoord,
                        teeBack:     teeBackCoord,
                        greenFront:  greenFrontCoord,
                        greenCenter: center,
                        greenBack:   greenBackCoord,
                        holeTees:    holeTees
                    )
                }

                // Raw hazard POIs
                let hazardPoiModels: [HazardPoi] = (h.hazardPois ?? []).map { hp in
                    HazardPoi(
                        type: hp.type,
                        locationLabel: hp.locationLabel,
                        fairwaySide: hp.fairwaySide,
                        coordinate: CLLocationCoordinate2D(latitude: hp.lat, longitude: hp.lon)
                    )
                }

                #if DEBUG
                let teeSource: String
                if !holeTees.isEmpty {
                    let synth = holeTees.allSatisfy { $0.isSynthesized }
                    teeSource = "✅ \(holeTees.count) tees\(synth ? " (synth)" : " (real)")"
                } else if teeFrontCoord != nil || teeBackCoord != nil {
                    teeSource = "⚠️ LEGACY POI"
                } else {
                    teeSource = "❌ SYNTHETIC"
                }
                print("[HOLE GEOMETRY] Hole \(h.holeNumber): green=\(gc != nil ? "✅" : "❌") tee=\(teeSource)")
                if holeTees.isEmpty && teeFrontCoord == nil && teeBackCoord == nil {
                    print("[ALIGNMENT HEALTH] ⚠️ Hole \(h.holeNumber): NO TEE DATA — map will use due-north fallback bearing")
                }
                #endif

                return HoleData(
                    holeNumber:  h.holeNumber,
                    par:         h.par,
                    handicap:    h.handicap,
                    greenCenter: gc,
                    geometry:    geometry,
                    hazards:     h.hazards ?? [],
                    hazardPois:  hazardPoiModels
                )
            }

            tees = dto.tees.map { TeeData(id: $0.id, name: $0.name, totalYards: $0.totalYards, slope: $0.slope, courseRating: $0.courseRating) }

            if let tid = launch?.selectedTeeId, let match = tees.first(where: { $0.id == tid }) {
                selectedTee = match
            } else if selectedTee == nil || tees.first(where: { $0.id == selectedTee?.id }) == nil {
                selectedTee = tees.first
            }

            #if DEBUG
            print("[TEE SELECTION] Selected tee: \(selectedTee?.name ?? "nil") id: \(selectedTee?.id ?? "nil")")
            print("[TEE SELECTION] Available tees: \(tees.map { "\($0.name)(\($0.id.prefix(8)))" }.joined(separator: ", "))")
            for h in holes {
                guard let geom = h.geometry else { continue }
                let matchCount = geom.holeTees.filter { $0.teeSetId == selectedTee?.id }.count
                if matchCount == 0 && !geom.holeTees.isEmpty {
                    print("[TEE SELECTION] ⚠️ Hole \(h.holeNumber): selectedTee id NOT in holeTees — will fallback")
                }
            }
            #endif

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
        // Prefer full geometry snapshot (includes front/back) when available
        if let snap = DistanceEngine.distanceSnapshot(user: user, geometry: hole.geometry) {
            distances = snap
            print("[DIST] Updated — \(Int(round(snap.center))) yds (front: \(snap.front.map { "\(Int(round($0)))" } ?? "-") back: \(snap.back.map { "\(Int(round($0)))" } ?? "-"))")
            return
        }
        guard let snap = DistanceEngine.distanceSnapshotToGreenCenter(user: user, greenCenter: hole.greenCenter) else { return }
        distances = snap
        print("[DIST] Updated — \(Int(round(snap.center))) yds (center only)")
    }
}
