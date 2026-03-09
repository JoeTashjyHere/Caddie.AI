//
//  RoundSummaryView.swift
//  Caddie.ai
//
//  Post-round AI summary view
//

import SwiftUI
import UIKit

struct RoundSummaryView: View {
    let course: Course
    @ObservedObject var roundViewModel: RoundViewModel
    var onDismiss: (() -> Void)? = nil
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var summaryViewModel = RoundSummaryViewModel()
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Round Complete!")
                            .font(GolfTheme.titleFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        Text(course.name)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .padding(.top)
                    
                    if isLoading {
                        ProgressView()
                            .tint(GolfTheme.grassGreen)
                            .scaleEffect(1.5)
                            .padding(40)
                    } else if let summary = summaryViewModel.summary {
                        summaryContent(summary: summary)
                    } else if let error = summaryViewModel.errorMessage {
                        errorView(error: error)
                    }
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Round Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Clear round and reset phase when summary is dismissed
                        scoreTrackingService.clearCurrentRound()
                        dismiss()
                        // Call onDismiss callback if provided
                        onDismiss?()
                    }
                    .foregroundColor(GolfTheme.grassGreen)
                }
            }
            .onAppear {
                // Defensive check: If phase is not summary, redirect
                if scoreTrackingService.phase != .summary {
                    // If round is in progress, go back to round play
                    if scoreTrackingService.phase == .inProgress {
                        dismiss()
                        return
                    }
                    // Otherwise, clear round and go to home
                    scoreTrackingService.clearCurrentRound()
                    dismiss()
                    return
                }
                
                // Defensive check: Ensure course and round data exist
                if course.id.isEmpty || course.name.isEmpty {
                    scoreTrackingService.clearCurrentRound()
                    dismiss()
                    return
                }
                
                Task {
                    await summaryViewModel.fetchSummary(
                        courseId: course.id,
                        roundViewModel: roundViewModel
                    )
                    isLoading = false
                }
            }
        }
    }
    
    // MARK: - Summary Content
    
    private func summaryContent(summary: RoundSummary) -> some View {
        VStack(spacing: 24) {
            // Best Holes
            if let bestHoles = summary.bestHoles, !bestHoles.isEmpty {
                prominentInsightCard(
                    icon: "star.fill",
                    title: "Best Holes",
                    color: GolfTheme.accentGold,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You played these holes exceptionally well:")
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(bestHoles, id: \.hole) { bestHole in
                                    HStack {
                                        Text("Hole \(bestHole.hole)")
                                            .font(GolfTheme.headlineFont)
                                            .foregroundColor(GolfTheme.accentGold)
                                        
                                        Spacer()
                                        
                                        if bestHole.scoreVsPar < 0 {
                                            Text("\(bestHole.scoreVsPar)")
                                                .font(GolfTheme.headlineFont)
                                                .foregroundColor(GolfTheme.grassGreen)
                                        } else if bestHole.scoreVsPar == 0 {
                                            Text("Par")
                                                .font(GolfTheme.bodyFont)
                                                .foregroundColor(GolfTheme.textSecondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                )
            }
            
            // Most Costly Miss Pattern
            if let missPattern = summary.mostCostlyMissPattern {
                prominentInsightCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "Most Costly Miss Pattern",
                    color: Color.orange,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(missPattern.pattern)
                                .font(GolfTheme.headlineFont)
                                .foregroundColor(Color.orange)
                            
                            Text(missPattern.description)
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if let impact = missPattern.impact {
                                HStack {
                                    Text("Impact:")
                                        .font(GolfTheme.captionFont)
                                        .foregroundColor(GolfTheme.textSecondary)
                                    Text(impact)
                                        .font(GolfTheme.bodyFont)
                                        .foregroundColor(GolfTheme.textPrimary)
                                }
                            }
                        }
                    }
                )
            }
            
            // Recommended Practice Focus
            if let practiceFocus = summary.recommendedPracticeFocus {
                prominentInsightCard(
                    icon: "sparkles",
                    title: "Recommended Practice Focus",
                    color: GolfTheme.grassGreen,
                    content: {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(practiceFocus.focus)
                                .font(GolfTheme.headlineFont)
                                .foregroundColor(GolfTheme.grassGreen)
                            
                            Text(practiceFocus.reason)
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if let drills = practiceFocus.drills, !drills.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Suggested Drills:")
                                        .font(GolfTheme.captionFont)
                                        .foregroundColor(GolfTheme.textSecondary)
                                    
                                    ForEach(drills, id: \.self) { drill in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(GolfTheme.grassGreen)
                                                .font(.caption)
                                            Text(drill)
                                                .font(GolfTheme.captionFont)
                                                .foregroundColor(GolfTheme.textPrimary)
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Prominent Insight Card
    
    private func prominentInsightCard<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(color)
                    .clipShape(Circle())
                
                Text(title)
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            Divider()
                .background(color.opacity(0.3))
            
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.white, color.opacity(0.05)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(color.opacity(0.3), lineWidth: 2)
        )
        .shadow(color: color.opacity(0.2), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Error View
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title)
            Text(error)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Round Summary Models

struct RoundSummary: Codable {
    let courseId: String
    let mostAccurateClub: ClubAccuracy?
    let shotStruggledWith: ShotStruggle?
    let nextRoundSuggestion: String?
    let bestHoles: [BestHole]?
    let mostCostlyMissPattern: MissPattern?
    let recommendedPracticeFocus: PracticeFocus?
}

struct ClubAccuracy: Codable {
    let club: String
    let note: String
    let accuracy: Double?
}

struct ShotStruggle: Codable {
    let shotType: String
    let note: String
    let holes: [Int]?
}

struct BestHole: Codable, Identifiable {
    var id: UUID
    let hole: Int
    let scoreVsPar: Int
    let strokes: Int
    let par: Int
    
    init(id: UUID = UUID(), hole: Int, scoreVsPar: Int, strokes: Int, par: Int) {
        self.id = id
        self.hole = hole
        self.scoreVsPar = scoreVsPar
        self.strokes = strokes
        self.par = par
    }
}

struct MissPattern: Codable {
    let pattern: String
    let description: String
    let impact: String?
}

struct PracticeFocus: Codable {
    let focus: String
    let reason: String
    let drills: [String]?
}

// MARK: - Round Summary ViewModel

@MainActor
class RoundSummaryViewModel: ObservableObject {
    @Published var summary: RoundSummary?
    @Published var errorMessage: String?
    
    func fetchSummary(courseId: String, roundViewModel: RoundViewModel) async {
        // Calculate summary from round data
        var mostAccurateClub: ClubAccuracy? = nil
        var shotStruggledWith: ShotStruggle? = nil
        var nextRoundSuggestion: String? = nil
        var bestHoles: [BestHole] = []
        var mostCostlyMissPattern: MissPattern? = nil
        var recommendedPracticeFocus: PracticeFocus? = nil
        
        // Get scores from RoundViewModel
        let scores = roundViewModel.scores
        
        // Analyze captured shots
        var clubAccuracy: [String: (count: Int, helpful: Int)] = [:]
        var shotTypeFeedback: [String: (off: Int, helpful: Int)] = [:]
        var strugglingHoles: [Int] = []
        var holeScores: [(hole: Int, strokes: Int, par: Int)] = []
        
        // Collect hole scores (assuming par 4 for all holes as default)
        for hole in 1...18 {
            if let strokes = scores[hole] {
                let par = 4 // Default par, could be improved with course data
                holeScores.append((hole: hole, strokes: strokes, par: par))
            }
        }
        
        // Find best holes (under par or par)
        let sortedHoles = holeScores.sorted { hole1, hole2 in
            let score1 = hole1.strokes - hole1.par
            let score2 = hole2.strokes - hole2.par
            if score1 != score2 {
                return score1 < score2 // Lower is better
            }
            return hole1.strokes < hole2.strokes
        }
        
        // Get top 3 best holes
        bestHoles = Array(sortedHoles.prefix(3)).map { holeData in
            BestHole(
                hole: holeData.hole,
                scoreVsPar: holeData.strokes - holeData.par,
                strokes: holeData.strokes,
                par: holeData.par
            )
        }
        
        // Collect data from all holes for AI insights
        for hole in 1...18 {
            let shots = roundViewModel.getAllCapturedShots(forHole: hole)
            for shot in shots {
                // Track club accuracy
                if let club = shot.recommendation?.club {
                    if clubAccuracy[club] == nil {
                        clubAccuracy[club] = (0, 0)
                    }
                    clubAccuracy[club]?.count += 1
                    if shot.userFeedback == "helpful" {
                        clubAccuracy[club]?.helpful += 1
                    }
                }
                
                // Track shot type feedback
                let type = shot.shotType.rawValue
                if shotTypeFeedback[type] == nil {
                    shotTypeFeedback[type] = (0, 0)
                }
                if shot.userFeedback == "off" {
                    shotTypeFeedback[type]?.off += 1
                } else if shot.userFeedback == "helpful" {
                    shotTypeFeedback[type]?.helpful += 1
                }
                
                // Track struggling holes
                if shot.userFeedback == "off" {
                    if !strugglingHoles.contains(hole) {
                        strugglingHoles.append(hole)
                    }
                }
            }
        }
        
        // Find most accurate club
        if !clubAccuracy.isEmpty {
            let sorted = clubAccuracy.sorted { (a, b) in
                let accuracyA = Double(a.value.helpful) / Double(a.value.count)
                let accuracyB = Double(b.value.helpful) / Double(b.value.count)
                return accuracyA > accuracyB
            }
            
            if let best = sorted.first {
                let accuracy = Double(best.value.helpful) / Double(best.value.count)
                mostAccurateClub = ClubAccuracy(
                    club: best.key,
                    note: "Used \(best.value.count) times with \(best.value.helpful) successful recommendations",
                    accuracy: accuracy
                )
            }
        }
        
        // Find shot type struggled with
        if !shotTypeFeedback.isEmpty {
            let sorted = shotTypeFeedback.sorted { (a, b) in
                let ratioA = Double(a.value.off) / Double(a.value.off + a.value.helpful + 1)
                let ratioB = Double(b.value.off) / Double(b.value.off + b.value.helpful + 1)
                return ratioA > ratioB
            }
            
            if let worst = sorted.first, worst.value.off > worst.value.helpful {
                shotStruggledWith = ShotStruggle(
                    shotType: worst.key,
                    note: "Had difficulty with \(worst.key) shots (\(worst.value.off) off target)",
                    holes: strugglingHoles.isEmpty ? nil : Array(strugglingHoles.prefix(5))
                )
            }
        }
        
        // Analyze most costly miss pattern
        var missPatterns: [String: (count: Int, totalStrokes: Int)] = [:]
        
        for hole in 1...18 {
            if let strokes = scores[hole] {
                let par = 4 // Default par
                let overPar = strokes - par
                
                if overPar > 0 {
                    // Analyze what went wrong
                    let shots = roundViewModel.getAllCapturedShots(forHole: hole)
                    var pattern = "General difficulty"
                    
                    // Check for specific patterns
                    let offTargetShots = shots.filter { $0.userFeedback == "off" }
                    if !offTargetShots.isEmpty {
                        if let worstShot = offTargetShots.first {
                            pattern = "\(worstShot.shotType.rawValue.capitalized) accuracy"
                        }
                    } else if strokes > par + 1 {
                        pattern = "Multiple mistakes"
                    }
                    
                    if missPatterns[pattern] == nil {
                        missPatterns[pattern] = (0, 0)
                    }
                    missPatterns[pattern]?.count += 1
                    missPatterns[pattern]?.totalStrokes += overPar
                }
            }
        }
        
        // Find most costly pattern
        if !missPatterns.isEmpty {
            let sorted = missPatterns.sorted { (a, b) in
                let avgA = Double(a.value.totalStrokes) / Double(a.value.count)
                let avgB = Double(b.value.totalStrokes) / Double(b.value.count)
                return avgA > avgB
            }
            
            if let worst = sorted.first {
                let avgStrokes = Double(worst.value.totalStrokes) / Double(worst.value.count)
                mostCostlyMissPattern = MissPattern(
                    pattern: worst.key,
                    description: "This pattern cost you an average of \(String(format: "%.1f", avgStrokes)) strokes over par on \(worst.value.count) hole\(worst.value.count == 1 ? "" : "s").",
                    impact: "Total impact: +\(worst.value.totalStrokes) strokes"
                )
            }
        }
        
        // Generate recommended practice focus
        var focusAreas: [String] = []
        var reasons: [String] = []
        var drills: [String] = []
        
        if let missPattern = mostCostlyMissPattern {
            focusAreas.append(missPattern.pattern)
            reasons.append("This was your most costly miss pattern this round.")
            
            if missPattern.pattern.contains("accuracy") {
                drills.append("Practice target accuracy with alignment drills")
                drills.append("Focus on consistent swing tempo")
            } else if missPattern.pattern.contains("Multiple") {
                drills.append("Work on course management")
                drills.append("Practice recovery shots")
            }
        }
        
        if let struggle = shotStruggledWith {
            if !focusAreas.contains(struggle.shotType) {
                focusAreas.append(struggle.shotType)
            }
            reasons.append("You struggled with \(struggle.shotType) shots.")
            
            if struggle.shotType == "drive" {
                drills.append("Practice driving range accuracy")
                drills.append("Work on tee shot consistency")
            } else if struggle.shotType == "approach" {
                drills.append("Practice approach shot distance control")
                drills.append("Work on green targeting")
            } else if struggle.shotType == "putt" {
                drills.append("Practice putting distance control")
                drills.append("Work on reading greens")
            }
        }
        
        if focusAreas.isEmpty {
            focusAreas.append("Overall consistency")
            reasons.append("Great round! Focus on maintaining consistency.")
            drills.append("Continue using AI caddie recommendations")
            drills.append("Practice course management")
        }
        
        recommendedPracticeFocus = PracticeFocus(
            focus: focusAreas.joined(separator: " & "),
            reason: reasons.joined(separator: " "),
            drills: drills.isEmpty ? nil : drills
        )
        
        // Generate AI suggestion
        if let club = mostAccurateClub {
            nextRoundSuggestion = "Focus on using your \(club.club) for approach shots. It had \(Int((club.accuracy ?? 0) * 100))% accuracy this round."
        } else if let struggle = shotStruggledWith {
            nextRoundSuggestion = "Practice your \(struggle.shotType) shots. Consider adjusting your club selection or shot shape for these shots."
        } else {
            nextRoundSuggestion = "Great round! Keep using the AI caddie for consistent improvements."
        }
        
        summary = RoundSummary(
            courseId: courseId,
            mostAccurateClub: mostAccurateClub,
            shotStruggledWith: shotStruggledWith,
            nextRoundSuggestion: nextRoundSuggestion,
            bestHoles: bestHoles.isEmpty ? nil : bestHoles,
            mostCostlyMissPattern: mostCostlyMissPattern,
            recommendedPracticeFocus: recommendedPracticeFocus
        )
    }
}

