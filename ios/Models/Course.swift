//
//  Course.swift
//  Caddie.ai
//

import Foundation
import CoreLocation

// MARK: - Tee info returned by /api/courses

struct TeeInfo: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let yardage: Int?
}

// MARK: - Course (one row per golf_course)

struct Course: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var clubName: String?
    var courseName: String?
    var tees: [TeeInfo]?
    var location: Coordinate?
    var par: Int?
    /// Backend-provided hole count (e.g. 9, 18). `nil` when not available.
    var numberOfHoles: Int?

    var lat: Double?
    var lon: Double?

    /// Primary display label — club name when available, falls back to `name`.
    var displayName: String {
        if let club = clubName, !club.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return club
        }
        return name
    }

    /// Course name within the club (e.g., "Championship", "Main Course").
    /// Suppresses nine-combination names like "Red + White".
    var courseLabel: String? {
        guard let cn = courseName?.trimmingCharacters(in: .whitespacesAndNewlines), !cn.isEmpty else { return nil }
        if cn == displayName { return nil }
        if GolfClub.looksLikeNineCombination(cn) { return nil }
        return cn
    }

    enum CodingKeys: String, CodingKey {
        case id, name, par, lat, lon, location, tees
        case clubName = "club_name"
        case courseName = "course_name"
        case numberOfHoles = "number_of_holes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        clubName = try container.decodeIfPresent(String.self, forKey: .clubName)
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName)
        tees = try container.decodeIfPresent([TeeInfo].self, forKey: .tees)
        par = try container.decodeIfPresent(Int.self, forKey: .par)
        numberOfHoles = try container.decodeIfPresent(Int.self, forKey: .numberOfHoles)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lon = try container.decodeIfPresent(Double.self, forKey: .lon)
        location = try container.decodeIfPresent(Coordinate.self, forKey: .location)

        if let lat = lat, let lon = lon, location == nil {
            location = Coordinate(latitude: lat, longitude: lon)
        }

        #if DEBUG
        if clubName == nil || clubName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            print("[DATA WARNING] Missing club_name for course id: \(id)")
        }
        #endif
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(clubName, forKey: .clubName)
        try container.encodeIfPresent(courseName, forKey: .courseName)
        try container.encodeIfPresent(tees, forKey: .tees)
        try container.encodeIfPresent(par, forKey: .par)
        try container.encodeIfPresent(numberOfHoles, forKey: .numberOfHoles)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lon, forKey: .lon)
    }

    struct Coordinate: Codable, Equatable {
        var latitude: Double
        var longitude: Double

        init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }

        init(from clLocation: CLLocationCoordinate2D) {
            self.latitude = clLocation.latitude
            self.longitude = clLocation.longitude
        }

        var clLocation: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    init(id: String = UUID().uuidString, name: String, clubName: String? = nil, courseName: String? = nil, tees: [TeeInfo]? = nil, location: Coordinate? = nil, par: Int? = nil, numberOfHoles: Int? = nil, lat: Double? = nil, lon: Double? = nil) {
        self.id = id
        self.name = name
        self.clubName = clubName
        self.courseName = courseName
        self.tees = tees
        self.par = par
        self.numberOfHoles = numberOfHoles
        self.lat = lat
        self.lon = lon

        if let lat = lat, let lon = lon {
            self.location = Coordinate(latitude: lat, longitude: lon)
        } else {
            self.location = location
        }
    }

    /// Resolved hole count using priority chain:
    /// 1. Backend-provided `numberOfHoles`
    /// 2. Holes array length (TODO: add `holes` array when backend provides it)
    /// 3. nil — never guessed from par
    var holeCount: Int? {
        numberOfHoles
    }

    /// Compact info string: "18 holes • 5 tee sets", "5 tee sets", etc.
    var holeAndTeeLabel: String? {
        var parts: [String] = []
        if let h = holeCount { parts.append("\(h) holes") }
        if let t = tees, !t.isEmpty { parts.append("\(t.count) tee sets") }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var hasValidBackendId: Bool {
        UUID(uuidString: id) != nil
    }

    static func isValidCourseId(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }
}

// MARK: - GolfClub (grouping container for the 3-level hierarchy)

struct GolfClub: Identifiable, Equatable {
    let name: String
    let location: Course.Coordinate?
    let courses: [Course]

    var id: String { name }

    /// Build the 3-level hierarchy from a flat [Course] array.
    /// Groups by `displayName` (club), then merges nine-combination courses
    /// (e.g. "Red + White") into a single entry with deduplicated tees.
    static func buildHierarchy(from courses: [Course]) -> [GolfClub] {
        var clubMap: [(name: String, location: Course.Coordinate?, courses: [Course])] = []
        var seen: [String: Int] = [:]
        for c in courses {
            let key = c.displayName
            if let idx = seen[key] {
                clubMap[idx].courses.append(c)
            } else {
                seen[key] = clubMap.count
                clubMap.append((name: key, location: c.location, courses: [c]))
            }
        }
        return clubMap.map { entry in
            let normalized = Self.mergeNineCombinations(entry.courses)
            return GolfClub(name: entry.name, location: entry.location, courses: normalized)
        }
    }

    // MARK: - Nine-combination normalization

    private static let nineCombinationPattern = try! NSRegularExpression(
        pattern: #"^[A-Za-z\s]{1,25}\s*\+\s*[A-Za-z\s]{1,25}$"#
    )

    static func looksLikeNineCombination(_ name: String?) -> Bool {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return false }
        let range = NSRange(name.startIndex..., in: name)
        return nineCombinationPattern.firstMatch(in: name, range: range) != nil
    }

    /// Merge courses whose `courseName` is a nine-combo into one entry.
    /// Regular courses pass through unchanged.
    private static func mergeNineCombinations(_ courses: [Course]) -> [Course] {
        var regular: [Course] = []
        var combos: [Course] = []

        for c in courses {
            if looksLikeNineCombination(c.courseName) {
                combos.append(c)
            } else {
                regular.append(c)
            }
        }

        guard !combos.isEmpty else { return courses }

        let first = combos[0]
        let mergedTees = deduplicateTees(from: combos)
        let normalizedName: String? = regular.isEmpty ? nil : "Main Course"

        var merged = Course(
            id: first.id,
            name: first.name,
            clubName: first.clubName,
            courseName: normalizedName,
            tees: mergedTees.isEmpty ? nil : mergedTees,
            par: first.par,
            lat: first.lat,
            lon: first.lon
        )
        merged.location = first.location

        return regular + [merged]
    }

    /// Collect tees from all courses, deduplicate by name keeping highest yardage.
    private static func deduplicateTees(from courses: [Course]) -> [TeeInfo] {
        var best: [String: TeeInfo] = [:]
        for c in courses {
            for t in c.tees ?? [] {
                if let existing = best[t.name] {
                    if (t.yardage ?? 0) > (existing.yardage ?? 0) {
                        best[t.name] = t
                    }
                } else {
                    best[t.name] = t
                }
            }
        }
        return best.values.sorted { ($0.yardage ?? 0) > ($1.yardage ?? 0) }
    }
}

