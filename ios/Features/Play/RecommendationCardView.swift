//
//  RecommendationCardView.swift
//  Caddie.ai
//
//  Enhanced recommendation card with animations, gradients, and feedback
//

import SwiftUI
import UIKit

struct RecommendationCardView: View {
    let recommendation: ShotRecommendation
    let onThumbsUp: () -> Void
    let onThumbsDown: () -> Void
    
    // Optional context data
    let distance: Int?
    let lie: String?
    let shotType: String?
    
    @State private var showFeedbackConfirmation = false
    @State private var feedbackMessage = ""
    @State private var isAnimating = false
    
    init(
        recommendation: ShotRecommendation,
        onThumbsUp: @escaping () -> Void,
        onThumbsDown: @escaping () -> Void,
        distance: Int? = nil,
        lie: String? = nil,
        shotType: String? = nil
    ) {
        self.recommendation = recommendation
        self.onThumbsUp = onThumbsUp
        self.onThumbsDown = onThumbsDown
        self.distance = distance
        self.lie = lie
        self.shotType = shotType
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with AI badge
            headerSection
            
            // Main content
            contentSection
            
            // Feedback buttons
            feedbackSection
        }
        .background(cardBackground)
        .cornerRadius(20)
        .shadow(color: GolfTheme.grassGreen.opacity(0.3), radius: 16, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .scaleEffect(isAnimating ? 1.0 : 0.95)
        .opacity(isAnimating ? 1.0 : 0.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isAnimating)
        .overlay(
            // Feedback confirmation toast
            Group {
                if showFeedbackConfirmation {
                    feedbackToast
                }
            }
        )
        .onAppear {
            // Entry animation
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            // Animated AI Badge
            animatedAIBadge
            
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Recommendation")
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
                
                Text("Shot Analysis")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            Spacer()
            
            // Confidence badge
            confidenceBadge
        }
        .padding(20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    GolfTheme.grassGreen.opacity(0.1),
                    GolfTheme.grassGreen.opacity(0.05)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var animatedAIBadge: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            GolfTheme.grassGreen,
                            GolfTheme.grassGreen.opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .shadow(color: GolfTheme.grassGreen.opacity(0.4), radius: 8, x: 0, y: 4)
            
            Text("AI")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
        )
    }
    
    private var confidenceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(confidenceColor)
            
            Text("\(Int(recommendation.confidence * 100))%")
                .font(GolfTheme.captionFont)
                .fontWeight(.semibold)
                .foregroundColor(confidenceColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(confidenceColor.opacity(0.15))
        .cornerRadius(12)
    }
    
    private var confidenceColor: Color {
        if recommendation.confidence >= 0.8 {
            return GolfTheme.grassGreen
        } else if recommendation.confidence >= 0.6 {
            return GolfTheme.accentGold
        } else {
            return Color.orange
        }
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Club - Most prominent
            clubSection
            
            Divider()
                .background(GolfTheme.textSecondary.opacity(0.2))
            
            // Key details in grid
            detailsGrid
            
            // Structured content: headline, bullets, commitCue (when present)
            if recommendation.headline != nil || !recommendation.bullets.isEmpty || recommendation.commitCue != nil {
                structuredContentSection
            }
            // Fallback: Narrative when structured fields are missing
            else if !recommendation.narrative.isEmpty {
                narrativeSection
            }
            
            // Hazards to avoid
            if !recommendation.avoidZones.isEmpty {
                hazardsSection
            }
        }
        .padding(20)
    }
    
    private var structuredContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Headline as bold primary text
            if let headline = recommendation.headline, !headline.isEmpty {
                Text(headline)
                    .font(GolfTheme.headlineFont)
                    .fontWeight(.bold)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            // Bullets (2–4 rows)
            if !recommendation.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recommendation.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(GolfTheme.grassGreen)
                                .padding(.top, 6)
                            Text(bullet)
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                        }
                    }
                }
            }
            
            // Commit cue as subtle italic below bullets
            if let commitCue = recommendation.commitCue, !commitCue.isEmpty {
                Text(commitCue)
                    .font(GolfTheme.bodyFont)
                    .italic()
                    .foregroundColor(GolfTheme.textSecondary)
            }
        }
        .padding(16)
        .background(GolfTheme.cream)
        .cornerRadius(12)
    }
    
    private var clubSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended Club")
                .font(GolfTheme.captionFont)
                .foregroundColor(GolfTheme.textSecondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(recommendation.club)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(GolfTheme.grassGreen)
                
                if let distance = distance {
                    Text("\(distance) yds")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
            }
        }
    }
    
    private var detailsGrid: some View {
        VStack(spacing: 16) {
            // Aim direction
            if recommendation.aimOffsetYards != 0 {
                detailRow(
                    icon: "arrow.right.circle.fill",
                    label: "Aim Direction",
                    value: aimDirectionText,
                    color: GolfTheme.accentGold
                )
            }
            
            // Shot shape
            if !recommendation.shotShape.isEmpty && recommendation.shotShape.lowercased() != "straight" {
                detailRow(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Shot Shape",
                    value: recommendation.shotShape,
                    color: GolfTheme.grassGreen
                )
            }
            
            // Lie
            if let lie = lie {
                detailRow(
                    icon: "circle.grid.2x2.fill",
                    label: "Lie",
                    value: lie.capitalized,
                    color: Color.blue
                )
            }
            
            // Shot type
            if let shotType = shotType {
                detailRow(
                    icon: "target",
                    label: "Shot Type",
                    value: shotType.capitalized,
                    color: Color.purple
                )
            }
        }
    }
    
    private func detailRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
                Text(value)
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
    }
    
    private var aimDirectionText: String {
        let offset = abs(recommendation.aimOffsetYards)
        let direction = recommendation.aimOffsetYards > 0 ? "right" : "left"
        return "\(String(format: "%.0f", offset)) yds \(direction)"
    }
    
    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendation")
                .font(GolfTheme.captionFont)
                .foregroundColor(GolfTheme.textSecondary)
            
            Text(recommendation.narrative)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(GolfTheme.cream)
        .cornerRadius(12)
    }
    
    private var hazardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color.orange)
                    .font(.title3)
                Text("Hazards to Avoid")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(recommendation.avoidZones, id: \.self) { zone in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(Color.orange)
                            .padding(.top, 6)
                        Text(zone)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Feedback Section
    
    private var feedbackSection: some View {
        VStack(spacing: 12) {
            Divider()
                .background(GolfTheme.textSecondary.opacity(0.2))
            
            HStack(spacing: 12) {
                feedbackButton(
                    icon: "hand.thumbsup.fill",
                    label: "Helpful",
                    color: GolfTheme.grassGreen,
                    action: {
                        handleFeedback(helpful: true)
                    }
                )
                
                feedbackButton(
                    icon: "hand.thumbsdown.fill",
                    label: "Off",
                    color: Color.red,
                    action: {
                        handleFeedback(helpful: false)
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    private func feedbackButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(GolfTheme.bodyFont)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        color,
                        color.opacity(0.8)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func handleFeedback(helpful: Bool) {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Show confirmation
        feedbackMessage = "Got it – we'll learn from this"
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showFeedbackConfirmation = true
        }
        
        // Call the callback
        if helpful {
            onThumbsUp()
        } else {
            onThumbsDown()
        }
        
        // Hide confirmation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showFeedbackConfirmation = false
            }
        }
    }
    
    private var feedbackToast: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(GolfTheme.grassGreen)
                    .font(.title3)
                
                Text(feedbackMessage)
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Color.white
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
            )
            .cornerRadius(16)
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Background
    
    private var cardBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.white,
                GolfTheme.cream.opacity(0.3)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            GolfTheme.grassGreen.opacity(0.3),
                            GolfTheme.grassGreen.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

#Preview {
    RecommendationCardView(
        recommendation: ShotRecommendation(
            club: "7i",
            aimOffsetYards: 5.0,
            shotShape: "Draw",
            narrative: "Hit a 7 iron with a slight draw. Aim 5 yards right of center to account for wind. Focus on smooth tempo and let the club do the work.",
            confidence: 0.85,
            avoidZones: ["Water left", "Bunker right"]
        ),
        onThumbsUp: {},
        onThumbsDown: {},
        distance: 150,
        lie: "Fairway",
        shotType: "Approach"
    )
    .padding()
}
