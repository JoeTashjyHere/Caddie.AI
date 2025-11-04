//
//  ClubDistance.swift
//  Caddie.ai
//
//  Created by Joe Tashjy on 11/4/25.
//

import Foundation

struct ClubDistance: Codable, Identifiable {
    var id: UUID
    var name: String
    var carryYards: Int
    var dispersionLeftRight: Int
    
    init(id: UUID = UUID(), name: String, carryYards: Int, dispersionLeftRight: Int = 10) {
        self.id = id
        self.name = name
        self.carryYards = carryYards
        self.dispersionLeftRight = dispersionLeftRight
    }
    
    static func defaultClubs() -> [ClubDistance] {
        [
            ClubDistance(name: "Driver", carryYards: 250, dispersionLeftRight: 20),
            ClubDistance(name: "3 Wood", carryYards: 230, dispersionLeftRight: 18),
            ClubDistance(name: "5 Wood", carryYards: 210, dispersionLeftRight: 16),
            ClubDistance(name: "3i", carryYards: 200, dispersionLeftRight: 15),
            ClubDistance(name: "4i", carryYards: 185, dispersionLeftRight: 15),
            ClubDistance(name: "5i", carryYards: 170, dispersionLeftRight: 12),
            ClubDistance(name: "6i", carryYards: 155, dispersionLeftRight: 12),
            ClubDistance(name: "7i", carryYards: 140, dispersionLeftRight: 10),
            ClubDistance(name: "8i", carryYards: 125, dispersionLeftRight: 10),
            ClubDistance(name: "9i", carryYards: 110, dispersionLeftRight: 8),
            ClubDistance(name: "PW", carryYards: 100, dispersionLeftRight: 8),
            ClubDistance(name: "SW", carryYards: 80, dispersionLeftRight: 6),
            ClubDistance(name: "LW", carryYards: 60, dispersionLeftRight: 6)
        ]
    }
}

