//
//  BrandedComponents.swift
//  Caddie.ai
//
//  Reusable branded UI components for onboarding, profile, and app-wide usage.
//

import SwiftUI
import UIKit

// MARK: - Logo

struct CaddieLogoView: View {
    enum Variant { case full, wordmark }
    var height: CGFloat = 80

    var body: some View {
        Image("CaddieLogo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
    }
}

struct CaddieWordmark: View {
    var body: some View {
        HStack(spacing: 1) {
            Text("Caddie")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("+")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(GolfTheme.grassGreen)
        }
    }
}

// MARK: - Buttons

struct BrandedPrimaryButton: View {
    let title: String
    var color: Color = GolfTheme.accentBlue
    var action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(color)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

struct BrandedSecondaryButton: View {
    let title: String
    var color: Color = GolfTheme.accentBlue
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(color)
        }
    }
}

struct BrandedAuthButton: View {
    enum AuthType { case apple, google, email }
    let type: AuthType
    var action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                authIcon
                Text(authLabel)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundColor)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    private var authIcon: some View {
        Group {
            switch type {
            case .apple:
                Image(systemName: "apple.logo")
                    .font(.system(size: 19))
            case .google:
                Text("G")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
            case .email:
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16))
            }
        }
    }

    private var authLabel: String {
        switch type {
        case .apple: return "Continue with Apple"
        case .google: return "Continue with Google"
        case .email: return "Continue with Phone or Email"
        }
    }

    private var foregroundColor: Color {
        switch type {
        case .apple: return .white
        case .google, .email: return GolfTheme.accentBlue
        }
    }

    private var backgroundColor: Color {
        switch type {
        case .apple: return .black
        case .google, .email: return GolfTheme.lightBlue
        }
    }
}

// MARK: - Cards

struct ProfileSectionCard<Content: View>: View {
    let title: String
    var trailing: AnyView? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                trailing
            }
            content()
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

struct OnboardingHeroCard: View {
    let icon: String
    let gradient: [Color]
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 340)
                    .padding(.horizontal, 24)
                    .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 24, x: 0, y: 12)

                Image(systemName: icon)
                    .font(.system(size: 80, weight: .thin))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.top, 24)
    }
}

// MARK: - Input Controls

struct PreferenceRadioGroup: View {
    let title: String
    let options: [(label: String, value: String)]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.bottom, 14)

            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selection = option.value
                    } label: {
                        HStack {
                            Text(option.label)
                                .font(.system(size: 17))
                                .foregroundColor(.primary)
                            Spacer()
                            ZStack {
                                Circle()
                                    .strokeBorder(
                                        selection == option.value ? GolfTheme.accentBlue : Color.gray.opacity(0.3),
                                        lineWidth: 2
                                    )
                                    .frame(width: 24, height: 24)
                                if selection == option.value {
                                    Circle()
                                        .fill(GolfTheme.accentBlue)
                                        .frame(width: 14, height: 14)
                                }
                            }
                            .animation(.easeInOut(duration: 0.15), value: selection)
                        }
                        .padding(.vertical, 15)
                    }
                    if index < options.count - 1 {
                        Divider().padding(.leading, 4)
                    }
                }
            }
        }
    }
}

struct SnapshotDropdownField: View {
    let label: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        HStack {
                            Text(option)
                            if selection == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.isEmpty ? "Select" : selection)
                        .font(.system(size: 15))
                        .foregroundColor(selection.isEmpty ? .secondary : GolfTheme.accentBlue)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EditableClubCard: View {
    @Binding var club: ClubDistance
    var onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(club.clubType.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(
                            colors: [GolfTheme.grassGreen, GolfTheme.darkGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(club.clubType.displayName)
                        .font(.system(size: 16, weight: .semibold))
                    Text(club.shotPreference.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(club.distanceYards) yds")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(GolfTheme.accentBlue)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isExpanded ? GolfTheme.accentBlue : .gray.opacity(0.35))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if isExpanded {
                Divider().padding(.horizontal, 16)
                expandedContent
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemGray6).opacity(0.6))
        .cornerRadius(14)
    }

    private var expandedContent: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Club Type")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Type", selection: Binding(
                    get: { club.clubType },
                    set: {
                        club.clubType = $0
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )) {
                    ForEach(ClubType.allCases) { ct in
                        Text(ct.displayName).tag(ct)
                    }
                }
                .pickerStyle(.menu)
                .tint(GolfTheme.accentBlue)
            }

            HStack {
                Text("Distance")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Stepper("\(club.distanceYards) yds", value: $club.distanceYards, in: 20...500, step: 5)
                    .font(.system(size: 14, weight: .medium))
                    .labelsHidden()
                Text("\(club.distanceYards) yds")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 60, alignment: .trailing)
            }

            HStack {
                Text("Shot Shape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Shot", selection: Binding(
                    get: { club.shotPreference },
                    set: { club.shotPreference = $0 }
                )) {
                    ForEach(ClubShotPreference.allCases) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.menu)
                .tint(GolfTheme.accentBlue)
            }

            HStack {
                Text("Confidence")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Confidence", selection: Binding(
                    get: { club.confidenceLevel },
                    set: { club.confidenceLevel = $0 }
                )) {
                    ForEach(ClubConfidenceLevel.allCases) { conf in
                        Text(conf.displayName).tag(conf)
                    }
                }
                .pickerStyle(.menu)
                .tint(GolfTheme.accentBlue)
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                    Text("Remove from bag")
                        .font(.system(size: 14, weight: .medium))
                }
            }
        }
    }
}

// MARK: - Onboarding Nav

struct OnboardingNavBar: View {
    var title: String? = nil
    var showSkip: Bool = false
    var onBack: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                }
            } else {
                Color.clear.frame(width: 36, height: 36)
            }

            Spacer()

            if let title {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }

            Spacer()

            if showSkip, let onSkip {
                Button("Skip", action: onSkip)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Bag Review Row (Onboarding)

struct BagReviewRow: View {
    @Binding var entry: BagClubEntry
    let isEditing: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    entry.isEnabled.toggle()
                } label: {
                    Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(entry.isEnabled ? GolfTheme.accentBlue : .gray.opacity(0.3))
                }

                Text(entry.clubType.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        LinearGradient(
                            colors: entry.isEnabled
                                ? [GolfTheme.grassGreen, GolfTheme.darkGreen]
                                : [.gray.opacity(0.4), .gray.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(entry.clubType.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(entry.isEnabled ? .primary : .secondary)

                Spacer()

                Text("\(entry.distanceYards) Yds")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(entry.isEnabled ? GolfTheme.accentBlue : .secondary)

                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isEditing ? GolfTheme.accentBlue : .gray.opacity(0.3))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)

            if isEditing {
                Divider().padding(.horizontal, 16)
                HStack {
                    Text("Distance")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Stepper("\(entry.distanceYards)", value: $entry.distanceYards, in: 20...400, step: 5)
                        .labelsHidden()
                    Text("\(entry.distanceYards) yds")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 55, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemGray6).opacity(0.7))
        .cornerRadius(14)
        .opacity(entry.isEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: entry.isEnabled)
    }
}

// MARK: - Divider with text

struct LabeledDivider: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize()
            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
        }
    }
}
