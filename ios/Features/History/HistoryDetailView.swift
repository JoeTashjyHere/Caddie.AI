//
//  HistoryDetailView.swift
//  Caddie.ai
//
//  Detail view for a single history item
//

import SwiftUI

struct HistoryDetailView: View {
    let item: HistoryItem
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var feedbackService: FeedbackService
    @EnvironmentObject var historyStore: HistoryStore
    @State private var helpful: Bool = true
    @State private var reason: RecommendationFeedbackReason = .wrongClub
    @State private var note: String = ""
    @State private var feedbackSubmitted = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with type and date
                    headerSection
                    
                    // Key metadata
                    metadataSection
                    
                    Divider()
                    
                    // Recommendation text
                    recommendationTextSection

                    feedbackSection

                    // Raw AI Response (debugging)
                    if let rawResponse = item.rawAIResponse {
                        rawJSONSection(json: rawResponse)
                    }
                }
                .padding()
            }
            .navigationTitle(item.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let recommendationId = item.recommendationId {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recommendation Feedback")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)

                Picker("Helpful", selection: $helpful) {
                    Text("Helpful").tag(true)
                    Text("Not Helpful").tag(false)
                }
                .pickerStyle(.segmented)

                if !helpful {
                    Picker("Reason", selection: $reason) {
                        ForEach(RecommendationFeedbackReason.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                TextEditor(text: $note)
                    .font(GolfTheme.bodyFont)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(8)

                Button("Submit Feedback") {
                    feedbackService.submitRecommendationFeedback(
                        recommendationId: recommendationId,
                        recommendationType: item.type,
                        helpful: helpful,
                        feedbackReason: helpful ? nil : reason,
                        freeTextNote: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
                        rating: helpful ? 1 : -1,
                        historyStore: historyStore
                    )
                    feedbackSubmitted = true
                }
                .buttonStyle(.borderedProminent)

                if feedbackSubmitted {
                    Text("Saved")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.type == .shot ? "figure.golf" : "flag.fill")
                    .foregroundColor(item.type == .shot ? GolfTheme.grassGreen : GolfTheme.accentGold)
                    .font(.title2)
                
                Text(item.type.displayName)
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
                
                Spacer()
            }
            
            Text(formatDate(item.createdAt))
                .font(GolfTheme.captionFont)
                .foregroundColor(GolfTheme.textSecondary)
        }
    }
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let courseName = item.courseName ?? item.shotMetadata?.courseName ?? item.puttMetadata?.courseName {
                metadataRow(label: "Course", value: courseName)
            }
        
            if item.type == .shot {
                if let distance = item.shotMetadata?.distanceYards ?? item.distanceYards {
                    metadataRow(label: "Distance", value: "\(distance) yards")
                }
                
                if let shotType = item.shotMetadata?.shotType ?? item.shotType {
                    metadataRow(label: "Shot Type", value: shotType.capitalized)
                }
                
                if let lie = item.shotMetadata?.lie ?? item.lie {
                    metadataRow(label: "Lie", value: lie.capitalized)
                }
                
                if let club = item.shotMetadata?.clubRecommended {
                    metadataRow(label: "Club", value: club)
                }
                
                if let holeNumber = item.shotMetadata?.holeNumber {
                    metadataRow(label: "Hole", value: "\(holeNumber)")
                }
                
                if let hazards = item.shotMetadata?.hazards ?? item.hazards {
                    metadataRow(label: "Hazards", value: hazards)
                }
            } else {
                if let distance = item.puttMetadata?.puttDistanceFeet {
                    metadataRow(label: "Putt Length", value: "\(distance) feet")
                }
                
                if let breakDir = item.puttMetadata?.breakDirection {
                    metadataRow(label: "Break", value: breakDir)
                }
                
                if let speed = item.puttMetadata?.speedRecommendation {
                    metadataRow(label: "Speed", value: speed.capitalized)
                }
                
                if let slope = item.puttMetadata?.greenSlopeInference {
                    metadataRow(label: "Slope", value: slope)
                }
                
                if let holeNumber = item.puttMetadata?.holeNumber {
                    metadataRow(label: "Hole", value: "\(holeNumber)")
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
            Spacer()
            Text(value)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textPrimary)
                .fontWeight(.medium)
        }
    }
    
    private var recommendationTextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendation")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Text(item.recommendationText)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    @ViewBuilder
    private func rawJSONSection(json: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Raw AI Response (Debug)")
                .font(GolfTheme.captionFont)
                .foregroundColor(GolfTheme.textSecondary)
            
            ScrollView(.horizontal, showsIndicators: true) {
                Text(json)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(GolfTheme.textSecondary)
                    .padding()
            }
            .frame(maxHeight: 200)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    HistoryDetailView(
        item: HistoryItem(
            type: .shot,
            courseName: "Pebble Beach",
            distanceYards: 150,
            shotType: "Approach",
            lie: "Fairway",
            recommendationText: "Recommended Club: 7 Iron\nDistance: 150 yards\nLie: Fairway\n\nUse a smooth 7 iron swing..."
        )
    )
}
