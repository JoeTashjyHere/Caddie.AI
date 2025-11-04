//
//  ShotRecommendation.swift
//  Caddie.ai
//
//  Created by Joe Tashjy on 11/4/25.
//

import Foundation

struct ShotRecommendation: Codable, Identifiable {
    var id: UUID
    var club: String
    var aimOffsetYards: Double
    var shotShape: String
    var narrative: String
    var confidence: Double
    var avoidZones: [String]
    
    init(id: UUID = UUID(),
         club: String,
         aimOffsetYards: Double,
         shotShape: String,
         narrative: String,
         confidence: Double,
         avoidZones: [String] = []) {
        self.id = id
        self.club = club
        self.aimOffsetYards = aimOffsetYards
        self.shotShape = shotShape
        self.narrative = narrative
        self.confidence = confidence
        self.avoidZones = avoidZones
    }
}

