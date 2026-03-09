//
//  HistoryView.swift
//  Caddie.ai
//
//  View displaying past recommendations and insights
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var historyStore: HistoryStore
    
    @State private var selectedItem: HistoryItem?
    
    var body: some View {
        NavigationStack {
            if historyStore.items.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .navigationTitle("History")
        .sheet(item: $selectedItem) { item in
            HistoryDetailView(item: item)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(GolfTheme.grassGreen.opacity(0.5))
            
            Text("No recommendations yet")
                .font(GolfTheme.titleFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Text("Take a photo to get started.")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var historyList: some View {
        List {
            ForEach(historyStore.items) { item in
                HistoryItemRow(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - History Item Row

struct HistoryItemRow: View {
    let item: HistoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                // Type icon
                Image(systemName: item.type == .shot ? "figure.golf" : "flag.fill")
                    .foregroundColor(item.type == .shot ? GolfTheme.grassGreen : GolfTheme.accentGold)
                    .font(.title3)

                // Type label + pill
                HStack(spacing: 6) {
                    Text(item.type.displayName)
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)

                    Text(item.type == .shot ? "SHOT" : "PUTT")
                        .font(GolfTheme.captionFont)
                        .fontWeight(.semibold)
                        .foregroundColor(item.type == .shot ? .white : .black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((item.type == .shot ? GolfTheme.grassGreen : GolfTheme.accentGold).opacity(0.9))
                        .cornerRadius(6)
                }

                Spacer()

                // Time ago
                Text(relativeTimeString(from: item.createdAt))
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
            }
            
            // Course name
            if let courseName = item.courseName ?? item.shotMetadata?.courseName ?? item.puttMetadata?.courseName {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(GolfTheme.textSecondary)
                    Text(courseName)
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
            } else {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(GolfTheme.textSecondary.opacity(0.5))
                    Text("Unknown course")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary.opacity(0.7))
                }
            }
            
            // Key details based on type
            if item.type == .shot {
                shotDetails
            } else {
                puttDetails
            }
            
            // Preview of recommendation text (first 1-2 lines)
            let previewLines = item.recommendationText.components(separatedBy: .newlines).prefix(2).joined(separator: " ")
            if !previewLines.isEmpty {
                Text(previewLines)
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var shotDetails: some View {
        HStack(spacing: 16) {
            if let distance = item.shotMetadata?.distanceYards ?? item.distanceYards {
                detailChip(icon: "ruler.fill", text: "\(distance) yds", color: GolfTheme.grassGreen)
            }
            
            if let lie = item.shotMetadata?.lie ?? item.lie {
                detailChip(icon: "circle.grid.2x2.fill", text: lie.capitalized, color: Color.blue)
            }
            
            if let shotType = item.shotMetadata?.shotType ?? item.shotType {
                detailChip(icon: "target", text: shotType.capitalized, color: Color.purple)
            }
        }
    }
    
    private var puttDetails: some View {
        HStack(spacing: 16) {
            if let distance = item.puttMetadata?.puttDistanceFeet {
                detailChip(icon: "ruler.fill", text: "\(distance) ft", color: GolfTheme.accentGold)
            }
            
            if let breakDir = item.puttMetadata?.breakDirection, !breakDir.isEmpty {
                detailChip(icon: "arrow.left.and.right", text: breakDir, color: GolfTheme.accentGold)
            }
            
            if let speed = item.puttMetadata?.speedRecommendation, !speed.isEmpty {
                detailChip(icon: "speedometer", text: speed.capitalized, color: GolfTheme.accentGold)
            }
        }
    }
    
    private func detailChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(GolfTheme.captionFont)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hr ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) day\(days > 1 ? "s" : "") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(ScoreTrackingService.shared)
        .environmentObject(ProfileViewModel())
        .environmentObject(HistoryStore())
}
