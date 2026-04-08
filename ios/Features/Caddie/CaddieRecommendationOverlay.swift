//
//  CaddieRecommendationOverlay.swift
//  Caddie.ai
//
//  Unified overlay for full-shot and putting recommendations with open-ended feedback.

import SwiftUI
import CoreLocation

struct CaddieRecommendationOverlay: View {
    let result: CaddieRecommendationResult
    let shotContext: ShotContext?
    let course: Course?
    let recommendationId: String?
    let recommendationType: RecommendationType?
    let onSaveAndNext: (String) -> Void
    let onClose: () -> Void
    
    @State private var feedbackText: String = ""
    @State private var helpfulSelection: Bool?
    @State private var selectedReason: RecommendationFeedbackReason?
    @State private var showFeedbackSaved = false
    @EnvironmentObject var feedbackService: FeedbackService
    @EnvironmentObject var historyStore: HistoryStore
    #if DEBUG
    @State private var showDiagnostics: Bool = false
    @State private var diagnostics: ShotRecommendationDiagnostics?
    #endif
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Recommendation content
                recommendationContent
                #if DEBUG
                diagnosticsPanel
                #endif
                
                // Feedback section
                feedbackSection
                
                // Buttons
                HStack(spacing: 16) {
                    Button {
                        submitStructuredFeedback()
                        onSaveAndNext(feedbackText)
                    } label: {
                        Text("Save & Next")
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(GolfTheme.grassGreen)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        onClose()
                    } label: {
                        Text("Close")
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(GolfTheme.cream)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(GolfTheme.textSecondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(24)
        }
        .background(GolfTheme.cream.ignoresSafeArea())
        #if DEBUG
        .onAppear {
            refreshDiagnostics()
        }
        #endif
    }

    private func labeledCaddieRow(title: String, value: String, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(GolfTheme.textSecondary)
            Text(value)
                .font(emphasis ? .system(size: 28, weight: .bold, design: .rounded) : GolfTheme.bodyFont)
                .foregroundColor(emphasis ? GolfTheme.grassGreen : GolfTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var shotRec: ShotRecommendation? {
        if case .fullShot(let rec) = result { return rec }
        return nil
    }
    
    private var puttRec: PuttingRead? {
        if case .putt(let read) = result { return read }
        return nil
    }
    
    private var defaultContext: ShotContext {
        ShotContext(
            hole: 1,
            playerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            targetCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            distanceToCenter: 0,
            elevationDelta: 0,
            windSpeedMph: 0,
            windDirectionDeg: 0,
            temperatureF: 70,
            lieType: "Fairway"
        )
    }
    
    @ViewBuilder
    private var recommendationContent: some View {
        switch result {
        case .fullShot(let rec):
            fullShotContent(rec)
        case .putt(let read):
            puttContent(read)
        }
    }
    
    private func fullShotContent(_ rec: ShotRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.golf")
                    .foregroundColor(GolfTheme.grassGreen)
                Text("AI Recommendation")
                    .font(GolfTheme.headlineFont)
                Spacer()
            }
            
            if let c = rec.caddieStructured {
                VStack(alignment: .leading, spacing: 10) {
                    labeledCaddieRow(title: "CLUB", value: c.club, emphasis: true)
                    labeledCaddieRow(title: "SHOT", value: c.shotType, emphasis: false)
                    labeledCaddieRow(title: "AIM", value: c.aim, emphasis: false)
                    labeledCaddieRow(title: "STRATEGY", value: c.strategy, emphasis: false)
                    labeledCaddieRow(title: "CONFIDENCE", value: c.confidence, emphasis: false)
                }
            } else {
                Text(rec.club)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(GolfTheme.grassGreen)
            }
            
            if let ctx = shotContext {
                Text("\(Int(ctx.distanceToCenter)) yards")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
            }
            
            if rec.caddieStructured == nil {
                if rec.aimOffsetYards != 0 {
                    let dir = rec.aimOffsetYards > 0 ? "right" : "left"
                    Text("Aim \(String(format: "%.0f", abs(rec.aimOffsetYards))) yards \(dir)")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)
                }

                if !rec.shotShape.isEmpty && rec.shotShape.lowercased() != "straight" {
                    Text("Shot: \(rec.shotShape)")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)
                }
            }
            
            Text(rec.narrative)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
            
            if !rec.avoidZones.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Avoid:")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(.orange)
                    ForEach(rec.avoidZones, id: \.self) { z in
                        Text("• \(z)")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    }
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        #if DEBUG
        .onLongPressGesture(minimumDuration: 0.8) {
            showDiagnostics.toggle()
        }
        #endif
    }
    
    private func puttContent(_ read: PuttingRead) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flag.2.crossed.fill")
                    .foregroundColor(GolfTheme.accentGold)
                Text("Putting Read")
                    .font(GolfTheme.headlineFont)
                Spacer()
            }
            
            Text("Break: \(read.breakDirection)")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Text("Amount: \(String(format: "%.1f", read.breakAmount)) feet")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
            
            Text("Speed: \(read.speed)")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
            
            if let line = read.theLine ?? read.puttingLine {
                Text("Line: \(line)")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            Text(read.narrative)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional: Recommendation Feedback")
                .font(GolfTheme.captionFont)
                .foregroundColor(GolfTheme.textSecondary)

            Picker("Helpful", selection: Binding(
                get: { helpfulSelection ?? true },
                set: { helpfulSelection = $0 }
            )) {
                Text("Helpful").tag(true)
                Text("Not Helpful").tag(false)
            }
            .pickerStyle(.segmented)

            if helpfulSelection == false {
                Picker("Reason", selection: Binding(
                    get: { selectedReason ?? .wrongClub },
                    set: { selectedReason = $0 }
                )) {
                    ForEach(RecommendationFeedbackReason.allCases) { reason in
                        Text(reason.displayName).tag(reason)
                    }
                }
                .pickerStyle(.menu)
            }
            
            TextEditor(text: $feedbackText)
                .font(GolfTheme.bodyFont)
                .frame(minHeight: 80)
                .padding(12)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GolfTheme.textSecondary.opacity(0.2), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if feedbackText.isEmpty {
                        Text("Optional note")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary.opacity(0.6))
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }

            if showFeedbackSaved {
                Text("Feedback saved")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private func submitStructuredFeedback() {
        guard let recommendationId = recommendationId else { return }
        let normalizedNote = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        if helpfulSelection == nil && normalizedNote.isEmpty { return }
        let helpful = helpfulSelection ?? true
        let type = recommendationType ?? (shotRec != nil ? .shot : .putt)
        let reason = helpful ? nil : selectedReason
        feedbackService.submitRecommendationFeedback(
            recommendationId: recommendationId,
            recommendationType: type,
            helpful: helpful,
            feedbackReason: reason,
            freeTextNote: normalizedNote.isEmpty ? nil : normalizedNote,
            rating: helpful ? 1 : -1,
            historyStore: historyStore
        )
        showFeedbackSaved = true
    }

    #if DEBUG
    @ViewBuilder
    private var diagnosticsPanel: some View {
        if case .fullShot = result {
            VStack(alignment: .leading, spacing: 12) {
                Button(showDiagnostics ? "Hide Diagnostics" : "Show Diagnostics") {
                    refreshDiagnostics()
                    showDiagnostics.toggle()
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.blue)

                if showDiagnostics {
                    if let diagnostics = diagnostics {
                        DisclosureGroup("A) Recommendation Basics", isExpanded: .constant(true)) {
                            debugRow("Target", "\(diagnostics.targetDistanceYards) yd")
                            debugRow("Plays-like", "\(diagnostics.playsLikeDistanceYards) yd")
                            debugRow("Course/Hole", "\(diagnostics.courseName) / \(diagnostics.holeNumber)")
                            debugRow("Lie", diagnostics.lie)
                            debugRow("Shot Type", diagnostics.shotType)
                            if let duration = diagnostics.requestDurationMs {
                                debugRow("Duration", "\(duration) ms")
                            }
                        }

                        DisclosureGroup("B) Club Selection", isExpanded: .constant(true)) {
                            debugRow("AI Club", diagnostics.aiChosenClub ?? "N/A")
                            debugRow("Final Club", diagnostics.finalClub)
                            debugRow("Normalized", diagnostics.normalizationOccurred ? "Yes" : "No")
                            debugRow("Normalization Reason", diagnostics.normalizationReason ?? "None")
                            ForEach(Array(diagnostics.candidates.enumerated()), id: \.offset) { index, candidate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("#\(index + 1) \(candidate.club) • score \(String(format: "%.1f", candidate.score)) • gap \(candidate.distanceGapYards)y")
                                        .font(.caption.monospaced())
                                    Text(candidate.rationale.joined(separator: " | "))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        DisclosureGroup("C) Reliability / Fallback", isExpanded: .constant(true)) {
                            debugRow("Fallback Used", diagnostics.fallbackUsed ? "Yes" : "No")
                            debugRow("Fallback Reason", diagnostics.fallbackReason ?? "None")
                        }

                        DisclosureGroup("D) Environment Data Quality", isExpanded: .constant(true)) {
                            debugRow("Weather", diagnostics.weatherSource)
                            debugRow("Elevation", diagnostics.elevationSource)
                        }

                        DisclosureGroup("E) Photo Influence", isExpanded: .constant(true)) {
                            debugRow("Photo Included", diagnostics.hasPhoto ? "Yes" : "No")
                            debugRow("Photo Referenced", diagnostics.photoReferencedInOutput ? "Yes" : "No")
                        }

                        DisclosureGroup("F) Confidence / Personalization", isExpanded: .constant(true)) {
                            ForEach(Array(diagnostics.candidates.enumerated()), id: \.offset) { index, candidate in
                                VStack(alignment: .leading, spacing: 2) {
                                    debugRow("#\(index + 1) \(candidate.club) confidence", candidate.confidenceLevel)
                                    if let notes = candidate.notes, !notes.isEmpty {
                                        debugRow("\(candidate.club) notes", notes)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("No diagnostics captured for this recommendation yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private func refreshDiagnostics() {
        diagnostics = RecommenderService.shared.lastDiagnostics
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
        }
    }
    #endif
}

#Preview {
    CaddieRecommendationOverlay(
        result: .fullShot(ShotRecommendation(
            club: "7i",
            aimOffsetYards: 5,
            shotShape: "Draw",
            narrative: "Hit a 7 iron with a slight draw. Aim 5 yards right.",
            confidence: 0.85,
            avoidZones: ["Water left"]
        )),
        shotContext: nil,
        course: nil,
        recommendationId: UUID().uuidString,
        recommendationType: .shot,
        onSaveAndNext: { _ in },
        onClose: {}
    )
    .environmentObject(FeedbackService.shared)
    .environmentObject(HistoryStore())
}
