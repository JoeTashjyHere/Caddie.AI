//
//  PlayerProfile.swift
//  Caddie.ai
//

import Foundation

struct PlayerProfile: Codable {
    var name: String
    var handedness: String
    var skillLevel: String
    var missesLeftPct: Double  // Deprecated - kept for migration, use per-club preferences
    var missesRightPct: Double  // Deprecated - kept for migration, use per-club preferences
    var clubs: [ClubDistance]
    var autoAnalyzePhotos: Bool  // Deprecated - photo analysis is always automatic when a photo is provided
    var golfGoal: String?  // User's golf goal (e.g., "Break 90", "Improve short irons")
    var puttingTendencies: String  // Open-ended text about putting tendencies
    var greenRiskPreference: GreenRiskPreference  // Risk preference on greens
    
    init(name: String = "",
         handedness: String = "Right",
         skillLevel: String = "Intermediate",
         missesLeftPct: Double = 30.0, 
         missesRightPct: Double = 20.0,
         clubs: [ClubDistance]? = nil,
         autoAnalyzePhotos: Bool = true,
         golfGoal: String? = nil,
         puttingTendencies: String = "",
         greenRiskPreference: GreenRiskPreference = .hybrid) {
        self.name = name
        self.handedness = handedness
        self.skillLevel = skillLevel
        self.missesLeftPct = missesLeftPct
        self.missesRightPct = missesRightPct
        self.clubs = clubs ?? ClubDistance.defaultClubs()
        self.autoAnalyzePhotos = autoAnalyzePhotos
        self.golfGoal = golfGoal
        self.puttingTendencies = puttingTendencies
        self.greenRiskPreference = greenRiskPreference
    }
    
    static func defaultProfile() -> PlayerProfile {
        PlayerProfile()
    }
    
    // Custom decoding to handle backward compatibility
    enum CodingKeys: String, CodingKey {
        case name, handedness, skillLevel, missesLeftPct, missesRightPct, clubs, autoAnalyzePhotos, golfGoal
        case puttingTendencies, greenRiskPreference
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        name = try container.decode(String.self, forKey: .name)
        handedness = try container.decode(String.self, forKey: .handedness)
        skillLevel = try container.decode(String.self, forKey: .skillLevel)
        missesLeftPct = try container.decode(Double.self, forKey: .missesLeftPct)
        missesRightPct = try container.decode(Double.self, forKey: .missesRightPct)
        clubs = try container.decode([ClubDistance].self, forKey: .clubs)
        autoAnalyzePhotos = try container.decodeIfPresent(Bool.self, forKey: .autoAnalyzePhotos) ?? true
        golfGoal = try container.decodeIfPresent(String.self, forKey: .golfGoal)
        
        // New fields with defaults for backward compatibility
        puttingTendencies = try container.decodeIfPresent(String.self, forKey: .puttingTendencies) ?? ""
        greenRiskPreference = try container.decodeIfPresent(GreenRiskPreference.self, forKey: .greenRiskPreference) ?? .hybrid
    }
}


struct UserProfile: Codable, Equatable {
    var firstName: String
    var lastName: String?
    var email: String
    var phone: String?
    var averageScore: String?
    var yearsPlaying: Int?
    var golfGoal: String?
    var seriousness: String?
    var riskOffTee: String?
    var riskAroundHazards: String?
    var greenRiskPreference: String?
    var puttingTendencies: String?
    var clubDistances: [ClubDistance]
    var shotPreferencesByClub: [String: String]?

    var distanceUnit: String?
    var temperatureUnit: String?
    var handedness: String?
    var skillLevel: String?
    var shotShape: String?
    var strategyType: String?
    var courseType: String?
    var windSensitivity: String?

    init(
        firstName: String = "",
        lastName: String? = nil,
        email: String = "",
        phone: String? = nil,
        averageScore: String? = nil,
        yearsPlaying: Int? = nil,
        golfGoal: String? = nil,
        seriousness: String? = nil,
        riskOffTee: String? = nil,
        riskAroundHazards: String? = nil,
        greenRiskPreference: String? = nil,
        puttingTendencies: String? = nil,
        clubDistances: [ClubDistance] = [],
        shotPreferencesByClub: [String: String]? = nil,
        distanceUnit: String? = nil,
        temperatureUnit: String? = nil,
        handedness: String? = nil,
        skillLevel: String? = nil,
        shotShape: String? = nil,
        strategyType: String? = nil,
        courseType: String? = nil,
        windSensitivity: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.averageScore = averageScore
        self.yearsPlaying = yearsPlaying
        self.golfGoal = golfGoal
        self.seriousness = seriousness
        self.riskOffTee = riskOffTee
        self.riskAroundHazards = riskAroundHazards
        self.greenRiskPreference = greenRiskPreference
        self.puttingTendencies = puttingTendencies
        self.clubDistances = clubDistances
        self.shotPreferencesByClub = shotPreferencesByClub
        self.distanceUnit = distanceUnit
        self.temperatureUnit = temperatureUnit
        self.handedness = handedness
        self.skillLevel = skillLevel
        self.shotShape = shotShape
        self.strategyType = strategyType
        self.courseType = courseType
        self.windSensitivity = windSensitivity
    }
}
