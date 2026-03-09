//
//  PuttingReadCardView.swift
//  Caddie.ai
//
//  Card displaying putting read results

import SwiftUI

struct PuttingReadCardView: View {
    let puttingRead: PuttingRead
    let course: Course?
    let holeNumber: Int?
    let onNewShot: () -> Void
    let onOpenGreenView: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "flag.2.crossed.fill")
                    .foregroundColor(GolfTheme.accentGold)
                Text("Putting Read")
                    .font(GolfTheme.headlineFont)
                Spacer()
            }
            
            // Break Direction & Amount
            VStack(alignment: .leading, spacing: 8) {
                Text("Break: \(puttingRead.breakDirection)")
                    .font(GolfTheme.bodyFont)
                Text("Amount: \(String(format: "%.1f", puttingRead.breakAmount)) feet")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
            }
            
            // Speed
            Text("Speed: \(puttingRead.speed)")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
            
            // Structured content: headline, bullets, commitCue (when present)
            if puttingRead.headline != nil || !(puttingRead.bullets ?? []).isEmpty || puttingRead.commitmentCue != nil {
                VStack(alignment: .leading, spacing: 12) {
                    if let headline = puttingRead.headline, !headline.isEmpty {
                        Text(headline)
                            .font(GolfTheme.headlineFont)
                            .fontWeight(.bold)
                            .foregroundColor(GolfTheme.textPrimary)
                    }
                    if let bullets = puttingRead.bullets, !bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(bullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(GolfTheme.accentGold)
                                        .padding(.top, 6)
                                    Text(bullet)
                                        .font(GolfTheme.bodyFont)
                                        .foregroundColor(GolfTheme.textPrimary)
                                }
                            }
                        }
                    }
                    if let cue = puttingRead.commitmentCue, !cue.isEmpty {
                        Text(cue)
                            .font(GolfTheme.bodyFont)
                            .italic()
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
            }
            // Fallback: Narrative
            else if !puttingRead.narrative.isEmpty {
                Text(puttingRead.narrative)
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            // Actions
            HStack(spacing: 12) {
                if course != nil && holeNumber != nil {
                    Button {
                        onOpenGreenView()
                    } label: {
                        Text("Open Green View")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(GolfTheme.accentGold)
                            .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                Button {
                    onNewShot()
                } label: {
                    Text("New Shot")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.grassGreen)
                }
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    PuttingReadCardView(
        puttingRead: PuttingRead(
            breakDirection: "Right to Left",
            breakAmount: 3.5,
            speed: "Medium",
            narrative: "The putt will break significantly from right to left. Aim about 3.5 feet to the right of the hole."
        ),
        course: Course(id: "1", name: "Pebble Beach"),
        holeNumber: 7,
        onNewShot: {},
        onOpenGreenView: {}
    )
    .padding()
}


