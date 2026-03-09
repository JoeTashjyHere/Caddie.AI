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
        updatePhase()
    }
    
    /// Update phase based on current round state
    private func updatePhase() {
        // Only auto-update phase if we're not in a manual phase state
        // Don't override .summary or .selectingCourse if set manually
        if phase == .summary || phase == .selectingCourse {
            return
        }
        
        if let round = currentRound {
            // Check if round is complete (all holes scored)
            let allHolesScored = round.holes.allSatisfy { $0.strokes > 0 }
            phase = allHolesScored ? .summary : .inProgress
        } else {
            // Only reset to notStarted if we're not in a manual phase
            if phase != .selectingCourse {
                phase = .notStarted
            }
        }
    }
    
    /// Set phase explicitly (used when navigating to summary or course selection)
    func setPhase(_ newPhase: RoundPhase) {
        phase = newPhase
    }
    
    func startRound(courseName: String, par: Int? = nil) {
        let roundPar = par ?? 72
        currentRound = Round(
            courseName: courseName,
            par: roundPar,
            holes: Array(1...18).map { holeNumber in
                HoleScore(holeNumber: holeNumber, par: 4)
            }
        )
        phase = .inProgress
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
    func saveRoundFromViewModel(courseName: String, par: Int, scores: [Int: Int], roundViewModel: RoundViewModel) {
        var holes: [HoleScore] = []
        
        for holeNumber in 1...18 {
            let strokes = scores[holeNumber] ?? 0
            let holePar = 4 // Default, could be improved with course data
            
            // Try to get fairway/GIR/putts from captured shots if available
            let shots = roundViewModel.getAllCapturedShots(forHole: holeNumber)
            var fairwayHit: Bool? = nil
            var gir: Bool? = nil
            var putts = 0
            
            // Infer from shot types
            for shot in shots {
                if shot.shotType == .drive {
                    // Could infer fairway hit from feedback
                    if shot.userFeedback == "helpful" {
                        fairwayHit = true
                    } else if shot.userFeedback == "off" {
                        fairwayHit = false
                    }
                } else if shot.shotType == .putt {
                    putts += 1
                } else if shot.shotType == .approach {
                    // Could infer GIR from feedback
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
        
        let round = Round(
            courseName: courseName,
            totalScore: scores.values.reduce(0, +),
            par: par,
            holes: holes
        )
        
        rounds.append(round)
        // Move to summary phase BEFORE clearing current round
        phase = .summary
        // Keep currentRound until summary is dismissed (for summary view access)
        // It will be cleared when summary is dismissed
        saveRounds()
    }
    
    /// Update current round with scores (for mid-round persistence)
    func updateCurrentRound(courseName: String, par: Int, scores: [Int: Int], currentHole: Int) {
        var holes: [HoleScore] = []
        
        for holeNumber in 1...18 {
            let strokes = scores[holeNumber] ?? 0
            let holePar = 4 // Default
            
            holes.append(HoleScore(
                holeNumber: holeNumber,
                par: holePar,
                strokes: strokes
            ))
        }
        
        currentRound = Round(
            courseName: courseName,
            totalScore: scores.values.reduce(0, +),
            par: par,
            holes: holes
        )
    }
    
    func endRound() -> Round? {
        guard var round = currentRound else { return nil }
        
        round.totalScore = round.holes.reduce(0) { $0 + $1.strokes }
        
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
        
        // Haptic feedback for ending a round
        let successGenerator = UINotificationFeedbackGenerator()
        successGenerator.notificationOccurred(.success)
        
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
    
    /// Start a new round, clearing any in-progress round
    func startNewRound(courseName: String, par: Int? = nil) {
        let roundPar = par ?? 72
        currentRound = Round(
            courseName: courseName,
            par: roundPar,
            holes: Array(1...18).map { holeNumber in
                HoleScore(holeNumber: holeNumber, par: 4)
            }
        )
        phase = .inProgress
        
        // Haptic feedback for starting a round
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    /// Resume an in-progress round
    func resumeRound() -> Round? {
        return currentRound
    }
    
    /// Clear the current round (for finalizing or canceling)
    func clearCurrentRound() {
        currentRound = nil
        phase = .notStarted
    }
    
    /// Complete the round and move to summary phase
    func completeRound() {
        phase = .summary
    }
}

