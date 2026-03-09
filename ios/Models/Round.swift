//
//  Round.swift
//  Caddie.ai
//

import Foundation

struct Round: Codable, Identifiable {
    var id: UUID
    var date: Date
    var courseName: String
    var totalScore: Int
    var par: Int
    var holes: [HoleScore]
    var aiAccuracy: Double?
    
    init(id: UUID = UUID(),
         date: Date = Date(),
         courseName: String,
         totalScore: Int = 0,
         par: Int = 72,
         holes: [HoleScore] = [],
         aiAccuracy: Double? = nil) {
        self.id = id
        self.date = date
        self.courseName = courseName
        self.totalScore = totalScore
        self.par = par
        self.holes = holes
        self.aiAccuracy = aiAccuracy
    }
    
    // MARK: - Statistics Helpers
    
    /// Score relative to par
    var scoreVsPar: Int {
        totalScore - par
    }
    
    /// Total putts for the round
    var totalPutts: Int {
        holes.reduce(0) { $0 + $1.putts }
    }
    
    /// Number of fairways hit (only counts par 4 and 5 holes)
    var fairwaysHit: Int {
        holes.filter { hole in
            hole.par >= 4 && (hole.fairwayHit ?? false)
        }.count
    }
    
    /// Number of par 4 and 5 holes (for fairway percentage calculation)
    var par4And5Holes: Int {
        holes.filter { $0.par >= 4 }.count
    }
    
    /// Fairway hit percentage
    var fairwayHitPercent: Double {
        guard par4And5Holes > 0 else { return 0.0 }
        return (Double(fairwaysHit) / Double(par4And5Holes)) * 100.0
    }
    
    /// Number of greens in regulation
    var greensInRegulation: Int {
        holes.filter { $0.greenInRegulation ?? false }.count
    }
    
    /// GIR percentage
    var girPercent: Double {
        guard !holes.isEmpty else { return 0.0 }
        return (Double(greensInRegulation) / Double(holes.count)) * 100.0
    }
    
    /// Average putts per round
    var averagePutts: Double {
        guard !holes.isEmpty else { return 0.0 }
        return Double(totalPutts) / Double(holes.count)
    }
}

struct HoleScore: Codable, Identifiable {
    var id: UUID
    var holeNumber: Int
    var par: Int
    var strokes: Int
    var fairwayHit: Bool?
    var greenInRegulation: Bool?
    var putts: Int
    var recommendedClub: String?
    var actualClub: String?
    var aiConfirmed: Bool
    
    init(id: UUID = UUID(),
         holeNumber: Int,
         par: Int = 4,
         strokes: Int = 0,
         fairwayHit: Bool? = nil,
         greenInRegulation: Bool? = nil,
         putts: Int = 0,
         recommendedClub: String? = nil,
         actualClub: String? = nil,
         aiConfirmed: Bool = false) {
        self.id = id
        self.holeNumber = holeNumber
        self.par = par
        self.strokes = strokes
        self.fairwayHit = fairwayHit
        self.greenInRegulation = greenInRegulation
        self.putts = putts
        self.recommendedClub = recommendedClub
        self.actualClub = actualClub
        self.aiConfirmed = aiConfirmed
    }
}

