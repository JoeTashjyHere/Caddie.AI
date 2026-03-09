//
//  PlayerProfile.swift
//  Caddie.ai
//
//  Created by Joe Tashjy on 11/4/25.
//

import Foundation

struct PlayerProfile: Codable {
    var preferredShotShape: String
    var missesLeftPct: Double
    var missesRightPct: Double
    var clubs: [ClubDistance]
    
    init(preferredShotShape: String = "Straight", 
         missesLeftPct: Double = 30.0, 
         missesRightPct: Double = 20.0,
         clubs: [ClubDistance] = ClubDistance.defaultClubs()) {
        self.preferredShotShape = preferredShotShape
        self.missesLeftPct = missesLeftPct
        self.missesRightPct = missesRightPct
        self.clubs = clubs
    }
}

