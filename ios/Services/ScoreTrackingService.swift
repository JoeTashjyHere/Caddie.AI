//
//  ScoreTrackingService.swift
//  Caddie.ai
//

import Foundation
import UIKit

/// Single source of truth for round state
enum RoundPhase: Equatable {
    case notStarted
    case selectingCourse
    case inProgress
    case summary
}

@MainActor
class ScoreTrackingService: ObservableObject {
    static let shared = ScoreTrackingService()

    @Published var currentRound: Round? {
        didSet {
            saveCurrentRound()
            updatePhase()
        }
    }
    @Published var rounds: [Round] = []
    @Published var phase: RoundPhase = .notStarted

    private let roundsKey = "SavedRounds"
    private let currentRoundKey = "CurrentRoundInProgress"

    private init() {
        loadRounds()
        loadCurrentRound()
        purgeLegacyCurrentRoundIfNeeded()
        updatePhase()
    }

    /// Drops in-progress rounds saved before full engine metadata was required.
    private func purgeLegacyCurrentRoundIfNeeded() {
        guard let round = currentRound else { return }
        let hasCourseId = round.courseId.map { !$0.isEmpty } ?? false
        let hasLength = round.roundLengthRaw.map { !$0.isEmpty } ?? false
        if !hasCourseId || !hasLength {
            print("[ROUND] Discarding in-progress round (missing courseId or roundLengthRaw)")
            UserDefaults.standard.removeObject(forKey: currentRoundKey)
            currentRound = nil
            if phase == .inProgress {
                phase = .notStarted
            }
        }
    }

    /// Update phase based on current round state
    private func updatePhase() {
        if phase == .summary || phase == .selectingCourse {
            return
        }

        if let round = currentRound {
            let allHolesScored = round.holes.allSatisfy { $0.strokes > 0 }
            phase = allHolesScored ? .summary : .inProgress
        } else {
            if phase != .selectingCourse {
                phase = .notStarted
            }
        }
    }

    func setPhase(_ newPhase: RoundPhase) {
        phase = newPhase
    }

    func startRound(courseName: String, par: Int? = nil) {
        startNewRound(courseName: courseName, par: par)
    }

    /// Empty score rows for the chosen round length; per-hole par is filled from `ActiveRoundContext` via `updateCurrentRound`.
    private static func initialHolesWithoutPar(for range: ClosedRange<Int>) -> [HoleScore] {
        range.map { HoleScore(holeNumber: $0, par: nil, strokes: 0) }
    }

    func logHole(number: Int, strokes: Int, fairwayHit: Bool? = nil, gir: Bool? = nil, putts: Int = 0) {
        guard var round = currentRound else { return }
        if let index = round.holes.firstIndex(where: { $0.holeNumber == number }) {
            round.holes[index].strokes = strokes
            round.holes[index].fairwayHit = fairwayHit
            round.holes[index].greenInRegulation = gir
            round.holes[index].putts = putts
            currentRound = round
        }
    }

    /// Save a round from RoundViewModel scores and finalize it
    func saveRoundFromViewModel(
        courseName: String,
        courseTotalPar: Int?,
        scores: [Int: Int],
        roundViewModel: RoundViewModel,
        holePars: [Int: Int]
    ) {
        let roundHoleRange = currentRound?.persistedRoundLength?.holeRange ?? 1...18
        var holes: [HoleScore] = []

        for holeNumber in roundHoleRange {
            let strokes = scores[holeNumber] ?? 0
            guard strokes > 0 else { continue }

            let holePar = holePars[holeNumber]
            if holePar == nil {
                print("[PAR] Missing par for hole \(holeNumber) — omitting from saved hole metadata")
            }

            let shots = roundViewModel.getAllCapturedShots(forHole: holeNumber)
            var fairwayHit: Bool? = nil
            var gir: Bool? = nil
            var putts = 0

            for shot in shots {
                if shot.shotType == .drive {
                    if shot.userFeedback == "helpful" {
                        fairwayHit = true
                    } else if shot.userFeedback == "off" {
                        fairwayHit = false
                    }
                } else if shot.shotType == .putt {
                    putts += 1
                } else if shot.shotType == .approach {
                    if shot.userFeedback == "helpful" {
                        gir = true
                    } else if shot.userFeedback == "off" {
                        gir = false
                    }
                }
            }

            holes.append(HoleScore(
                holeNumber: holeNumber,
                par: holePar,
                strokes: strokes,
                fairwayHit: fairwayHit,
                greenInRegulation: gir,
                putts: putts
            ))
        }

        let meta = currentRound
        let totalScore = holes.reduce(0) { $0 + $1.strokes }
        let parPlayed = holes.compactMap(\.par).reduce(0, +)

        let round = Round(
            courseName: courseName,
            totalScore: totalScore,
            par: parPlayed,
            holes: holes,
            courseId: meta?.courseId,
            selectedTeeId: meta?.selectedTeeId,
            roundLengthRaw: meta?.roundLengthRaw,
            currentHoleNumber: meta?.currentHoleNumber,
            courseRating: meta?.courseRating,
            slopeRating: meta?.slopeRating
        )

        rounds.append(round)
        currentRound = round
        phase = .summary
        saveRounds()

        AnalyticsService.shared.track(
            event: .roundCompleted(courseId: meta?.courseId ?? "", totalScore: round.totalScore, vsPar: round.scoreVsParPlayed)
        )
    }

    /// Update current round with scores. `holePars` must reflect `ActiveRoundContext` (per-hole par).
    func updateCurrentRound(
        courseId: String?,
        courseName: String,
        courseTotalPar: Int?,
        scores: [Int: Int],
        currentHole: Int,
        teeId: String?,
        roundLength: RoundLength?,
        holePars: [Int: Int]
    ) {
        let existing = currentRound
        let roundId = existing?.id ?? UUID()
        let roundDate = existing?.date ?? Date()

        let holeRange: ClosedRange<Int> = {
            if let rl = roundLength { return rl.holeRange }
            if let e = existing?.persistedRoundLength { return e.holeRange }
            return 1...18
        }()

        var holes: [HoleScore] = []
        for holeNumber in holeRange {
            let strokes = scores[holeNumber] ?? 0
            let holePar = holePars[holeNumber]
            if holePar == nil {
                print("[PAR] Missing par for hole \(holeNumber) while persisting round")
            }
            let prev = existing?.holes.first(where: { $0.holeNumber == holeNumber })
            holes.append(HoleScore(
                id: prev?.id ?? UUID(),
                holeNumber: holeNumber,
                par: holePar ?? prev?.par,
                strokes: strokes,
                fairwayHit: prev?.fairwayHit,
                greenInRegulation: prev?.greenInRegulation,
                putts: prev?.putts ?? 0,
                recommendedClub: prev?.recommendedClub,
                actualClub: prev?.actualClub,
                aiConfirmed: prev?.aiConfirmed ?? false
            ))
        }

        let mergedCourseId: String? = {
            let c = courseId ?? existing?.courseId
            if let c, !c.isEmpty { return c }
            return nil
        }()
        let mergedTee = teeId ?? existing?.selectedTeeId
        let mergedLengthRaw = roundLength?.rawValue ?? existing?.roundLengthRaw

        let mergedTotalPar: Int = {
            if let p = courseTotalPar, p > 0 { return p }
            let rangePar = holeRange.compactMap { holePars[$0] }.reduce(0, +)
            if rangePar > 0 { return rangePar }
            let sum = holePars.values.reduce(0, +)
            if sum > 0 { return sum }
            if let e = existing?.par, e > 0 { return e }
            print("[PAR] Missing course total par on update")
            return existing?.par ?? 0
        }()

        let totalInRange = holeRange.reduce(0) { $0 + (scores[$1] ?? 0) }

        currentRound = Round(
            id: roundId,
            date: roundDate,
            courseName: courseName,
            totalScore: totalInRange,
            par: mergedTotalPar,
            holes: holes,
            aiAccuracy: existing?.aiAccuracy,
            courseId: mergedCourseId,
            selectedTeeId: mergedTee,
            roundLengthRaw: mergedLengthRaw,
            currentHoleNumber: currentHole,
            courseRating: existing?.courseRating,
            slopeRating: existing?.slopeRating
        )
    }

    func endRound() -> Round? {
        guard var round = currentRound else { return nil }

        round.totalScore = round.totalStrokesPlayed()

        let positiveFeedback = round.holes.filter { $0.aiConfirmed }.count
        let totalFeedback = round.holes.filter { $0.recommendedClub != nil }.count
        if totalFeedback > 0 {
            round.aiAccuracy = Double(positiveFeedback) / Double(totalFeedback)
        }

        rounds.append(round)
        let finishedRound = round
        currentRound = nil
        phase = .summary
        saveRounds()

        let successGenerator = UINotificationFeedbackGenerator()
        successGenerator.notificationOccurred(.success)

        AnalyticsService.shared.track(
            event: .roundCompleted(courseId: finishedRound.courseId ?? "", totalScore: finishedRound.totalStrokesPlayed(), vsPar: finishedRound.scoreVsParPlayed)
        )

        return finishedRound
    }

    func recordShot(holeNumber: Int, recommendedClub: String, actualClub: String, aiConfirmed: Bool) {
        guard var round = currentRound else { return }
        if let index = round.holes.firstIndex(where: { $0.holeNumber == holeNumber }) {
            round.holes[index].recommendedClub = recommendedClub
            round.holes[index].actualClub = actualClub
            round.holes[index].aiConfirmed = aiConfirmed
            currentRound = round
        }
    }

    func saveRounds() {
        if let encoded = try? JSONEncoder().encode(rounds) {
            UserDefaults.standard.set(encoded, forKey: roundsKey)
        }
    }

    private func loadRounds() {
        if let data = UserDefaults.standard.data(forKey: roundsKey),
           let decoded = try? JSONDecoder().decode([Round].self, from: data) {
            rounds = decoded
        }
    }

    private func saveCurrentRound() {
        if let round = currentRound,
           let encoded = try? JSONEncoder().encode(round) {
            UserDefaults.standard.set(encoded, forKey: currentRoundKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentRoundKey)
        }
    }

    private func loadCurrentRound() {
        if let data = UserDefaults.standard.data(forKey: currentRoundKey),
           let decoded = try? JSONDecoder().decode(Round.self, from: data) {
            currentRound = decoded
        }
    }

    func startNewRound(courseName: String, par: Int? = nil) {
        startNewRound(courseId: "", courseName: courseName, par: par, teeId: nil, roundLength: nil)
    }

    func startNewRound(
        courseId: String,
        courseName: String,
        par: Int?,
        teeId: String?,
        roundLength: RoundLength?,
        courseRating: Double? = nil,
        slopeRating: Double? = nil
    ) {
        let roundPar = par.flatMap { $0 > 0 ? $0 : nil } ?? 0
        if roundPar == 0 {
            print("[PAR] Missing course total par at round start (will fill from hole pars when context loads)")
        }
        let rl = roundLength ?? .full18
        let storedId: String? = courseId.isEmpty ? nil : courseId
        let startHole = rl.holeRange.lowerBound
        currentRound = Round(
            courseName: courseName,
            par: roundPar,
            holes: Self.initialHolesWithoutPar(for: rl.holeRange),
            courseId: storedId,
            selectedTeeId: teeId,
            roundLengthRaw: rl.rawValue,
            currentHoleNumber: startHole,
            // TODO: Backend must supply courseRating/slopeRating for USGA handicap.
            // Until then, these remain nil and handicap uses estimate fallback.
            courseRating: courseRating,
            slopeRating: slopeRating
        )
        phase = .inProgress

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        AnalyticsService.shared.track(
            event: .roundStarted(courseId: storedId ?? "", roundLength: rl.rawValue, isRoundBacked: true)
        )
    }

    func resumeRound() -> Round? {
        return currentRound
    }

    func clearCurrentRound() {
        currentRound = nil
        phase = .notStarted
    }

    func completeRound() {
        phase = .summary
    }

    // MARK: - Delete Round

    func deleteRound(_ round: Round) {
        rounds.removeAll { $0.id == round.id }
        saveRounds()
    }

    func deleteRoundById(_ id: UUID) {
        rounds.removeAll { $0.id == id }
        saveRounds()
    }

    // MARK: - Handicap Calculation (USGA-style)

    /// Qualifying rounds for handicap, newest first.
    private var handicapQualifyingRounds: [Round] {
        rounds
            .filter { $0.totalStrokesPlayed() > 0 && $0.totalParPlayed() > 0 }
            .sorted { $0.date > $1.date }
    }

    /// Whether at least one qualifying round has official course/slope rating data.
    var hasOfficialRatingData: Bool {
        handicapQualifyingRounds.contains { $0.hasOfficialRatingData }
    }

    /// True when all rounds used in the handicap have official rating data.
    var handicapIsOfficial: Bool {
        let pool = Array(handicapQualifyingRounds.prefix(20))
        guard pool.count >= 5 else { return false }
        let bestCount = pool.count >= 20 ? 8 : (pool.count >= 10 ? 5 : pool.count / 2)
        let sorted = pool.sorted { $0.handicapDifferential < $1.handicapDifferential }
        return Array(sorted.prefix(bestCount)).allSatisfy { $0.hasOfficialRatingData }
    }

    /// Handicap index using USGA-style formula:
    ///   Differential = (Score - Course Rating) × 113 / Slope Rating
    ///   Take best N of last M differentials, average, × 0.96, round to 1 decimal.
    ///   Falls back to raw stroke differential when course/slope ratings are unavailable.
    var handicapEstimate: Double? {
        let qualifying = handicapQualifyingRounds
        let pool = Array(qualifying.prefix(20))
        guard pool.count >= 5 else { return nil }

        let bestCount: Int
        if pool.count >= 20 {
            bestCount = 8
        } else if pool.count >= 10 {
            bestCount = 5
        } else {
            bestCount = max(1, pool.count / 2)
        }

        let differentials = pool.map { $0.handicapDifferential }
        let best = differentials.sorted().prefix(bestCount)
        let avg = best.reduce(0, +) / Double(best.count)
        let index = (avg * 0.96 * 10).rounded() / 10
        return index
    }

    /// Number of qualifying rounds toward handicap (max 20)
    var handicapQualifyingRoundCount: Int {
        min(20, handicapQualifyingRounds.count)
    }

    // MARK: - Performance Analytics

    /// Average score across all completed rounds
    var averageScore: Double? {
        let qualifying = rounds.filter { $0.totalStrokesPlayed() > 0 }
        guard !qualifying.isEmpty else { return nil }
        return Double(qualifying.map { $0.totalStrokesPlayed() }.reduce(0, +)) / Double(qualifying.count)
    }

    /// Average score relative to par
    var averageVsPar: Double? {
        let qualifying = rounds.filter { $0.totalStrokesPlayed() > 0 && $0.totalParPlayed() > 0 }
        guard !qualifying.isEmpty else { return nil }
        return Double(qualifying.map { $0.scoreVsParPlayed }.reduce(0, +)) / Double(qualifying.count)
    }

    /// Best round (lowest vs par)
    var bestRound: Round? {
        rounds
            .filter { $0.totalStrokesPlayed() > 0 && $0.totalParPlayed() > 0 }
            .min { $0.scoreVsParPlayed < $1.scoreVsParPlayed }
    }

    /// Completed rounds sorted newest first
    var completedRounds: [Round] {
        rounds
            .filter { $0.totalStrokesPlayed() > 0 }
            .sorted { $0.date > $1.date }
    }

    /// Hole-level statistics across all rounds
    func holePerformance() -> [(holeNumber: Int, avgVsPar: Double, count: Int)] {
        var stats: [Int: (totalVsPar: Int, count: Int)] = [:]
        for round in rounds {
            for hole in round.playedHoles() {
                guard let par = hole.par, par > 0 else { continue }
                let diff = hole.strokes - par
                if stats[hole.holeNumber] != nil {
                    stats[hole.holeNumber]!.totalVsPar += diff
                    stats[hole.holeNumber]!.count += 1
                } else {
                    stats[hole.holeNumber] = (diff, 1)
                }
            }
        }
        return stats.map { (holeNumber: $0.key, avgVsPar: Double($0.value.totalVsPar) / Double($0.value.count), count: $0.value.count) }
            .sorted { $0.holeNumber < $1.holeNumber }
    }

    /// Scoring distribution: birdies, pars, bogeys, doubles+
    func scoringDistribution() -> (birdiesOrBetter: Int, pars: Int, bogeys: Int, doublePlus: Int) {
        var b = 0, p = 0, bo = 0, d = 0
        for round in rounds {
            for hole in round.playedHoles() {
                guard let par = hole.par, par > 0 else { continue }
                let diff = hole.strokes - par
                if diff <= -1 { b += 1 }
                else if diff == 0 { p += 1 }
                else if diff == 1 { bo += 1 }
                else { d += 1 }
            }
        }
        return (b, p, bo, d)
    }

    /// Par-type averages (par 3, par 4, par 5)
    func parTypeAverages() -> [(parType: Int, avgScore: Double, count: Int)] {
        var stats: [Int: (total: Int, count: Int)] = [:]
        for round in rounds {
            for hole in round.playedHoles() {
                guard let par = hole.par, par >= 3, par <= 5 else { continue }
                if stats[par] != nil {
                    stats[par]!.total += hole.strokes
                    stats[par]!.count += 1
                } else {
                    stats[par] = (hole.strokes, 1)
                }
            }
        }
        return stats.map { (parType: $0.key, avgScore: Double($0.value.total) / Double($0.value.count), count: $0.value.count) }
            .sorted { $0.parType < $1.parType }
    }
}
