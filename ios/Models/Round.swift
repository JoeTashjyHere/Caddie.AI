//
//  Round.swift
//  Caddie.ai
//

import Foundation

struct Round: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var courseName: String
    var totalScore: Int
    var par: Int
    var holes: [HoleScore]
    var aiAccuracy: Double?
    /// Backend course id for `/api/course-context` (never a random client UUID for new rounds).
    var courseId: String?
    var selectedTeeId: String?
    /// `RoundLength.rawValue` for resume (front9 / back9 / full18).
    var roundLengthRaw: String?
    /// Last active hole when the app persisted mid-round.
    var currentHoleNumber: Int?
    /// Course rating for handicap calculation (e.g. 72.1). `nil` when not available.
    var courseRating: Double?
    /// Slope rating for handicap calculation (e.g. 131). `nil` when not available.
    var slopeRating: Double?

    init(id: UUID = UUID(),
         date: Date = Date(),
         courseName: String,
         totalScore: Int = 0,
         par: Int = 0,
         holes: [HoleScore] = [],
         aiAccuracy: Double? = nil,
         courseId: String? = nil,
         selectedTeeId: String? = nil,
         roundLengthRaw: String? = nil,
         currentHoleNumber: Int? = nil,
         courseRating: Double? = nil,
         slopeRating: Double? = nil) {
        self.id = id
        self.date = date
        self.courseName = courseName
        self.totalScore = totalScore
        self.par = par
        self.holes = holes
        self.aiAccuracy = aiAccuracy
        self.courseId = courseId
        self.selectedTeeId = selectedTeeId
        self.roundLengthRaw = roundLengthRaw
        self.currentHoleNumber = currentHoleNumber
        self.courseRating = courseRating
        self.slopeRating = slopeRating
    }

    /// Build a `Course` for navigation / API using persisted backend id when available.
    func resolvedCourse() -> Course {
        if let cid = courseId, !cid.isEmpty {
            return Course(id: cid, name: courseName, par: par)
        }
        return Course(name: courseName, par: par)
    }

    var persistedRoundLength: RoundLength? {
        guard let raw = roundLengthRaw else { return nil }
        return RoundLength(rawValue: raw)
    }

    /// Holes the player recorded a score for (strokes greater than zero).
    func playedHoles() -> [HoleScore] {
        holes.filter { $0.strokes > 0 }
    }

    /// Sum of strokes on played holes only.
    func totalStrokesPlayed() -> Int {
        playedHoles().reduce(0) { $0 + $1.strokes }
    }

    /// Sum of par on played holes where par is known.
    func totalParPlayed() -> Int {
        playedHoles().compactMap(\.par).reduce(0, +)
    }

    /// Vs par using only played holes (9-hole, partial, or 18).
    var scoreVsParPlayed: Int {
        totalStrokesPlayed() - totalParPlayed()
    }

    // MARK: - Handicap Differential

    /// Whether this round has official course/slope data for true USGA differential.
    var hasOfficialRatingData: Bool {
        courseRating != nil && slopeRating != nil
    }

    /// USGA-style differential: (Score - Course Rating) × 113 / Slope Rating.
    /// Falls back to raw stroke differential when rating data is unavailable.
    var handicapDifferential: Double {
        let score = Double(totalStrokesPlayed())
        guard score > 0 else { return 0 }
        if let cr = courseRating, let sr = slopeRating, sr > 0 {
            return (score - cr) * 113.0 / sr
        }
        let parPlayed = Double(totalParPlayed())
        guard parPlayed > 0 else { return 0 }
        return score - parPlayed
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
            guard let p = hole.par else { return false }
            return (p == 4 || p == 5) && (hole.fairwayHit ?? false)
        }.count
    }

    /// Number of par 4 and 5 holes (for fairway percentage calculation)
    var par4And5Holes: Int {
        holes.filter { $0.par == 4 || $0.par == 5 }.count
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

struct HoleScore: Codable, Identifiable, Equatable {
    var id: UUID
    var holeNumber: Int
    /// Per-hole par from course context; `nil` only if never synced from engine.
    var par: Int?
    var strokes: Int
    var fairwayHit: Bool?
    var greenInRegulation: Bool?
    var putts: Int
    var recommendedClub: String?
    var actualClub: String?
    var aiConfirmed: Bool
    
    init(id: UUID = UUID(),
         holeNumber: Int,
         par: Int? = nil,
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

