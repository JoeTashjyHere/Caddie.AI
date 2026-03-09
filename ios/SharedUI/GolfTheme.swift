//
//  GolfTheme.swift
//  Caddie.ai
//

import SwiftUI

struct GolfTheme {
    // Colors
    static let grassGreen = Color(red: 0.2, green: 0.6, blue: 0.3)
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.94)
    static let accentGold = Color(red: 0.85, green: 0.7, blue: 0.2)
    static let textPrimary = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.5)
    
    // Fonts
    static let titleFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 16, weight: .regular, design: .rounded)
    static let captionFont = Font.system(size: 12, weight: .regular, design: .rounded)
}

// Golf card modifier
extension View {
    func golfCard() -> some View {
        self
            .padding()
            .background(GolfTheme.cream)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
}

// Golf button style
struct GolfButtonStyle: ButtonStyle {
    var isPrimary: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GolfTheme.bodyFont)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(isPrimary ? GolfTheme.grassGreen : GolfTheme.textSecondary)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

