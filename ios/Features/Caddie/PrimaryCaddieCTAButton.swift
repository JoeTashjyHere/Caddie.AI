//
//  PrimaryCaddieCTAButton.swift
//  Caddie.ai
//
//  Large primary CTA button for camera-first action

import SwiftUI

struct PrimaryCaddieCTAButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var color: Color = GolfTheme.grassGreen
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundColor(.white)
                
                Text(title)
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(GolfTheme.captionFont)
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(20)
            .shadow(color: color.opacity(0.3), radius: 16, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PrimaryCaddieCTAButton(
        title: "Take Photo for Recommendation",
        subtitle: "Fast, like camera intelligence",
        systemImage: "camera.fill",
        onTap: {}
    )
    .padding()
}

