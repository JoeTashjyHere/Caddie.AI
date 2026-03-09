//
//  ContextBannerView.swift
//  Caddie.ai
//
//  Banner showing auto-detected context (course/hole/distance)

import SwiftUI

struct ContextBannerView: View {
    let draft: CaddieContextDraft
    let confidence: ConfidenceLevel
    let bannerMessage: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(GolfTheme.grassGreen)
                    
                    // Show course name and location from manual entry
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.courseName ?? "Enter course context")
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        if let city = draft.city, let state = draft.state {
                            Text("\(city), \(state)")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    ConfidenceChipView(confidence: confidence)
                }
                
                if let holeNumber = draft.holeNumber {
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(GolfTheme.accentGold)
                        Text("Hole \(holeNumber)")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    }
                }
                
                if let distance = draft.distanceYards {
                    HStack {
                        Image(systemName: "ruler.fill")
                            .foregroundColor(GolfTheme.grassGreen)
                        Text("\(Int(distance)) yards")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    }
                }
                
                if let message = bannerMessage {
                    Text(message)
                        .font(GolfTheme.captionFont)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GolfTheme.cream)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Confidence Chip

struct ConfidenceChipView: View {
    let confidence: ConfidenceLevel
    
    var body: some View {
        Text(confidence.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceColor)
            .cornerRadius(8)
    }
    
    private var confidenceColor: Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .gray
        }
    }
}

#Preview {
    ContextBannerView(
        draft: CaddieContextDraft(
            course: Course(id: "1", name: "Pebble Beach"),
            holeNumber: 7,
            distanceYards: 150
        ),
        confidence: .high,
        bannerMessage: nil,
        onTap: {}
    )
    .padding()
}

