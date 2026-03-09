//
//  RecommendationCardView.swift
//  Caddie.ai
//
//  Card view displaying shot recommendation
//

import SwiftUI

struct RecommendationCardView: View {
    let recommendation: ShotRecommendation
    let onThumbsUp: () -> Void
    let onThumbsDown: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Club name
            Text(recommendation.club)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.primary)
            
            // Narrative
            Text(recommendation.narrative)
                .font(.body)
                .foregroundColor(.secondary)
            
            // Aim offset
            if recommendation.aimOffsetYards != 0 {
                HStack {
                    Image(systemName: recommendation.aimOffsetYards > 0 ? "arrow.right" : "arrow.left")
                    Text("Aim \(abs(recommendation.aimOffsetYards), specifier: "%.1f") yards \(recommendation.aimOffsetYards > 0 ? "right" : "left")")
                        .font(.subheadline)
                }
                .foregroundColor(.secondary)
            }
            
            // Avoid zones
            if !recommendation.avoidZones.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avoid:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(recommendation.avoidZones, id: \.self) { zone in
                        Text("• \(zone)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Confidence
            HStack {
                Text("Confidence:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(Int(recommendation.confidence * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            
            Divider()
            
            // Feedback buttons
            HStack(spacing: 20) {
                Button(action: onThumbsUp) {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                }
                
                Button(action: onThumbsDown) {
                    Image(systemName: "hand.thumbsdown.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    RecommendationCardView(
        recommendation: ShotRecommendation(
            club: "7i",
            aimOffsetYards: 5.0,
            shotShape: "Draw",
            narrative: "Hit a 7 iron with a slight draw. Aim 5 yards right of center to account for wind.",
            confidence: 0.85,
            avoidZones: ["Water left", "Bunker right"]
        ),
        onThumbsUp: {},
        onThumbsDown: {}
    )
    .padding()
}

