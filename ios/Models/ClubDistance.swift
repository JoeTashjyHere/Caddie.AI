//
//  ClubDistance.swift
//  Caddie.ai
//

import Foundation

enum ShotShape: String, Codable, CaseIterable {
    case straight
    case draw
    case fade
}

enum ClubType: String, Codable, CaseIterable, Identifiable {
    case driver
    case wood3
    case wood5
    case wood7
    case hybrid2
    case hybrid3
    case hybrid4
    case hybrid5
    case iron2
    case iron3
    case iron4
    case iron5
    case iron6
    case iron7
    case iron8
    case iron9
    case pitchingWedge
    case gapWedge
    case sandWedge
    case lobWedge
    case putter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .wood3: return "3W"
        case .wood5: return "5W"
        case .wood7: return "7W"
        case .hybrid2: return "2H"
        case .hybrid3: return "3H"
        case .hybrid4: return "4H"
        case .hybrid5: return "5H"
        case .iron2: return "2i"
        case .iron3: return "3i"
        case .iron4: return "4i"
        case .iron5: return "5i"
        case .iron6: return "6i"
        case .iron7: return "7i"
        case .iron8: return "8i"
        case .iron9: return "9i"
        case .pitchingWedge: return "PW"
        case .gapWedge: return "GW"
        case .sandWedge: return "SW"
        case .lobWedge: return "LW"
        case .putter: return "Putter"
        }
    }

    static func fromLegacy(_ rawName: String) -> ClubType {
        let normalized = rawName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")

        switch normalized {
        case "driver": return .driver
        case "3wood", "3w": return .wood3
        case "5wood", "5w": return .wood5
        case "7wood", "7w": return .wood7
        case "2hybrid", "2h": return .hybrid2
        case "3hybrid", "3h": return .hybrid3
        case "4hybrid", "4h": return .hybrid4
        case "5hybrid", "5h": return .hybrid5
        case "2iron", "2i": return .iron2
        case "3iron", "3i": return .iron3
        case "4iron", "4i": return .iron4
        case "5iron", "5i": return .iron5
        case "6iron", "6i": return .iron6
        case "7iron", "7i": return .iron7
        case "8iron", "8i": return .iron8
        case "9iron", "9i": return .iron9
        case "pitchingwedge", "pw": return .pitchingWedge
        case "gapwedge", "approachwedge", "gw", "aw": return .gapWedge
        case "sandwedge", "sw": return .sandWedge
        case "lobwedge", "lw": return .lobWedge
        case "putter": return .putter
        default:
            if normalized.contains("wedge") { return .gapWedge }
            if normalized.contains("putt") { return .putter }
            if normalized.contains("iron") || normalized.hasSuffix("i") { return .iron7 }
            if normalized.contains("hybrid") || normalized.hasSuffix("h") { return .hybrid4 }
            if normalized.contains("wood") || normalized.hasSuffix("w") { return .wood5 }
            return .iron7
        }
    }
}

enum ClubShotPreference: String, Codable, CaseIterable, Identifiable {
    case straight
    case fade
    case draw
    case cut
    case hookMiss
    case sliceMiss
    case high
    case low
    case varies

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .straight: return "Straight"
        case .fade: return "Fade"
        case .draw: return "Draw"
        case .cut: return "Cut"
        case .hookMiss: return "Hook (miss)"
        case .sliceMiss: return "Slice (miss)"
        case .high: return "High"
        case .low: return "Low"
        case .varies: return "Varies"
        }
    }

    var legacyShotShape: ShotShape {
        switch self {
        case .fade, .cut, .sliceMiss:
            return .fade
        case .draw, .hookMiss:
            return .draw
        case .straight, .high, .low, .varies:
            return .straight
        }
    }

    static func fromLegacyShape(_ shape: ShotShape) -> ClubShotPreference {
        switch shape {
        case .straight: return .straight
        case .draw: return .draw
        case .fade: return .fade
        }
    }
}

enum ClubConfidenceLevel: String, Codable, CaseIterable, Identifiable {
    case veryConfident
    case confident
    case neutral
    case notConfident
    case avoidAtAllCosts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .veryConfident: return "Very confident"
        case .confident: return "Confident"
        case .neutral: return "Neutral"
        case .notConfident: return "Not confident"
        case .avoidAtAllCosts: return "Avoid at all costs"
        }
    }
}

struct ClubDistance: Codable, Identifiable, Equatable {
    var id: UUID
    var clubTypeId: String
    var distanceYards: Int
    var shotPreferenceId: String
    var confidenceLevelId: String
    var notes: String?
    var dispersionLeftRight: Int
    var missLeftPct: Double
    var missRightPct: Double

    var clubType: ClubType {
        get { ClubType(rawValue: clubTypeId) ?? .iron7 }
        set { clubTypeId = newValue.rawValue }
    }

    var shotPreference: ClubShotPreference {
        get { ClubShotPreference(rawValue: shotPreferenceId) ?? .straight }
        set { shotPreferenceId = newValue.rawValue }
    }

    var confidenceLevel: ClubConfidenceLevel {
        get { ClubConfidenceLevel(rawValue: confidenceLevelId) ?? .neutral }
        set { confidenceLevelId = newValue.rawValue }
    }

    var preferredShotShape: ShotShape {
        get { shotPreference.legacyShotShape }
        set { shotPreference = ClubShotPreference.fromLegacyShape(newValue) }
    }

    var name: String {
        get { clubType.displayName }
        set { clubType = ClubType.fromLegacy(newValue) }
    }

    var clubName: String {
        get { name }
        set { name = newValue }
    }

    var carryYards: Int {
        get { distanceYards }
        set { distanceYards = min(max(newValue, 0), 500) }
    }

    init(
        id: UUID = UUID(),
        clubTypeId: String,
        distanceYards: Int,
        shotPreferenceId: String = ClubShotPreference.straight.rawValue,
        confidenceLevelId: String = ClubConfidenceLevel.neutral.rawValue,
        notes: String? = nil,
        dispersionLeftRight: Int = 10,
        preferredShotShape: ShotShape = .straight,
        missLeftPct: Double = 30.0,
        missRightPct: Double = 20.0
    ) {
        self.id = id
        self.clubTypeId = clubTypeId
        self.distanceYards = min(max(distanceYards, 0), 500)
        self.shotPreferenceId = shotPreferenceId
        self.confidenceLevelId = confidenceLevelId
        self.notes = notes
        self.dispersionLeftRight = dispersionLeftRight
        self.missLeftPct = missLeftPct
        self.missRightPct = missRightPct

        // Preserve compatibility if caller still passes preferredShotShape but not shotPreference.
        if shotPreferenceId == ClubShotPreference.straight.rawValue {
            self.shotPreference = ClubShotPreference.fromLegacyShape(preferredShotShape)
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        carryYards: Int,
        notes: String? = nil,
        dispersionLeftRight: Int = 10,
        preferredShotShape: ShotShape = .straight,
        missLeftPct: Double = 30.0,
        missRightPct: Double = 20.0
    ) {
        self.init(
            id: id,
            clubTypeId: ClubType.fromLegacy(name).rawValue,
            distanceYards: carryYards,
            shotPreferenceId: ClubShotPreference.fromLegacyShape(preferredShotShape).rawValue,
            confidenceLevelId: ClubConfidenceLevel.neutral.rawValue,
            notes: notes,
            dispersionLeftRight: dispersionLeftRight,
            preferredShotShape: preferredShotShape,
            missLeftPct: missLeftPct,
            missRightPct: missRightPct
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case clubTypeId
        case distanceYards
        case shotPreferenceId
        case confidenceLevelId
        case notes
        case dispersionLeftRight
        case preferredShotShape
        case missLeftPct
        case missRightPct
        case name
        case carryYards
        case clubName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        if let storedClubType = try container.decodeIfPresent(String.self, forKey: .clubTypeId),
           ClubType(rawValue: storedClubType) != nil {
            clubTypeId = storedClubType
        } else {
            let legacyPrimaryName = try container.decodeIfPresent(String.self, forKey: .name)
            let legacySecondaryName = try container.decodeIfPresent(String.self, forKey: .clubName)
            let legacyName = legacyPrimaryName ?? legacySecondaryName ?? "7i"
            clubTypeId = ClubType.fromLegacy(legacyName).rawValue
        }

        let legacyCarry = try container.decodeIfPresent(Int.self, forKey: .carryYards)
        let newDistance = try container.decodeIfPresent(Int.self, forKey: .distanceYards)
        distanceYards = min(max(newDistance ?? legacyCarry ?? 0, 0), 500)

        if let storedPreference = try container.decodeIfPresent(String.self, forKey: .shotPreferenceId),
           ClubShotPreference(rawValue: storedPreference) != nil {
            shotPreferenceId = storedPreference
        } else if let legacyShape = try container.decodeIfPresent(ShotShape.self, forKey: .preferredShotShape) {
            shotPreferenceId = ClubShotPreference.fromLegacyShape(legacyShape).rawValue
        } else {
            shotPreferenceId = ClubShotPreference.straight.rawValue
        }

        if let storedConfidence = try container.decodeIfPresent(String.self, forKey: .confidenceLevelId),
           ClubConfidenceLevel(rawValue: storedConfidence) != nil {
            confidenceLevelId = storedConfidence
        } else {
            confidenceLevelId = ClubConfidenceLevel.neutral.rawValue
        }

        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        dispersionLeftRight = try container.decodeIfPresent(Int.self, forKey: .dispersionLeftRight) ?? 10
        missLeftPct = try container.decodeIfPresent(Double.self, forKey: .missLeftPct) ?? 30.0
        missRightPct = try container.decodeIfPresent(Double.self, forKey: .missRightPct) ?? 20.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(clubTypeId, forKey: .clubTypeId)
        try container.encode(distanceYards, forKey: .distanceYards)
        try container.encode(shotPreferenceId, forKey: .shotPreferenceId)
        try container.encode(confidenceLevelId, forKey: .confidenceLevelId)
        try container.encode(notes, forKey: .notes)
        try container.encode(dispersionLeftRight, forKey: .dispersionLeftRight)
        try container.encode(preferredShotShape, forKey: .preferredShotShape)
        try container.encode(missLeftPct, forKey: .missLeftPct)
        try container.encode(missRightPct, forKey: .missRightPct)
    }

    static func defaultClubs() -> [ClubDistance] {
        [
            ClubDistance(clubTypeId: ClubType.driver.rawValue, distanceYards: 250, confidenceLevelId: ClubConfidenceLevel.confident.rawValue),
            ClubDistance(clubTypeId: ClubType.wood3.rawValue, distanceYards: 230),
            ClubDistance(clubTypeId: ClubType.wood5.rawValue, distanceYards: 210),
            ClubDistance(clubTypeId: ClubType.iron3.rawValue, distanceYards: 200),
            ClubDistance(clubTypeId: ClubType.iron4.rawValue, distanceYards: 185),
            ClubDistance(clubTypeId: ClubType.iron5.rawValue, distanceYards: 170),
            ClubDistance(clubTypeId: ClubType.iron6.rawValue, distanceYards: 155),
            ClubDistance(clubTypeId: ClubType.iron7.rawValue, distanceYards: 140),
            ClubDistance(clubTypeId: ClubType.iron8.rawValue, distanceYards: 125),
            ClubDistance(clubTypeId: ClubType.iron9.rawValue, distanceYards: 110),
            ClubDistance(clubTypeId: ClubType.pitchingWedge.rawValue, distanceYards: 100),
            ClubDistance(clubTypeId: ClubType.sandWedge.rawValue, distanceYards: 80),
            ClubDistance(clubTypeId: ClubType.lobWedge.rawValue, distanceYards: 60)
        ]
    }
}

typealias ClubProfile = ClubDistance
