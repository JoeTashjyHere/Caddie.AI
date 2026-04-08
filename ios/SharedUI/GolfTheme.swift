//
//  GolfTheme.swift
//  Caddie.ai
//

import SwiftUI

struct GolfTheme {
    // Brand
    static let grassGreen = Color(red: 0.2, green: 0.6, blue: 0.3)
    static let darkGreen = Color(red: 0.1, green: 0.4, blue: 0.18)
    static let cream = Color(red: 0.98, green: 0.96, blue: 0.94)
    static let accentGold = Color(red: 0.85, green: 0.7, blue: 0.2)
    static let textPrimary = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.5)

    // Modern palette
    static let accentBlue = Color(red: 0.13, green: 0.47, blue: 0.95)
    static let lightBlue = Color(red: 0.91, green: 0.95, blue: 1.0)
    static let cardBackground = Color.white
    static let screenBackground = Color(uiColor: .systemGroupedBackground)

    // Fonts
    static let largeTitleFont = Font.system(size: 34, weight: .bold, design: .rounded)
    static let titleFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headlineFont = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 16, weight: .regular, design: .rounded)
    static let captionFont = Font.system(size: 12, weight: .regular, design: .rounded)
}

extension View {
    func golfCard() -> some View {
        self
            .padding()
            .background(GolfTheme.cream)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    func modernCard() -> some View {
        self
            .padding(20)
            .background(GolfTheme.cardBackground)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

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

// Branded button styles are in BrandedComponents.swift
