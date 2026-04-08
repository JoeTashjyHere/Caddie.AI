//
//  OnboardingView.swift
//  Caddie.ai
//

import SwiftUI
import UIKit

// MARK: - Bag Entry

struct BagClubEntry: Identifiable {
    let id = UUID()
    var clubType: ClubType
    var distanceYards: Int
    var isEnabled: Bool = true

    static func generateBag(driverYards: Int, sevenIronYards: Int) -> [BagClubEntry] {
        let longGap = Double(driverYards - sevenIronYards) / 6.0
        let shortGap = max(longGap * 0.7, 8.0)
        func r5(_ v: Double) -> Int { max(Int((v / 5.0).rounded()) * 5, 20) }

        return [
            BagClubEntry(clubType: .driver, distanceYards: driverYards),
            BagClubEntry(clubType: .wood3, distanceYards: r5(Double(driverYards) - longGap)),
            BagClubEntry(clubType: .wood5, distanceYards: r5(Double(driverYards) - longGap * 2)),
            BagClubEntry(clubType: .hybrid4, distanceYards: r5(Double(driverYards) - longGap * 3)),
            BagClubEntry(clubType: .iron5, distanceYards: r5(Double(driverYards) - longGap * 4)),
            BagClubEntry(clubType: .iron6, distanceYards: r5(Double(driverYards) - longGap * 5)),
            BagClubEntry(clubType: .iron7, distanceYards: sevenIronYards),
            BagClubEntry(clubType: .iron8, distanceYards: r5(Double(sevenIronYards) - shortGap)),
            BagClubEntry(clubType: .iron9, distanceYards: r5(Double(sevenIronYards) - shortGap * 2)),
            BagClubEntry(clubType: .pitchingWedge, distanceYards: r5(Double(sevenIronYards) - shortGap * 3)),
            BagClubEntry(clubType: .gapWedge, distanceYards: r5(Double(sevenIronYards) - shortGap * 4)),
            BagClubEntry(clubType: .sandWedge, distanceYards: r5(Double(sevenIronYards) - shortGap * 5)),
            BagClubEntry(clubType: .lobWedge, distanceYards: r5(Double(sevenIronYards) - shortGap * 6)),
        ]
    }
}

// MARK: - Coordinator

struct OnboardingCoordinatorView: View {
    enum Step: Int, CaseIterable {
        case carousel, signUp, preferences, driverDistance, ironDistance, bagReady, bagReview
    }

    @EnvironmentObject var userProfileStore: UserProfileStore
    let initialMessage: String?

    @State private var step: Step = .carousel
    @State private var navigatingForward = true

    @State private var firstName = ""
    @State private var distanceUnit = "Imperial"
    @State private var temperatureUnit = "Fahrenheit"
    @State private var handedness = "Right"
    @State private var driverYards = 250
    @State private var sevenIronYards = 150
    @State private var bagEntries: [BagClubEntry] = []

    init(initialMessage: String? = nil) {
        self.initialMessage = initialMessage
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            Group {
                switch step {
                case .carousel:
                    carouselStep
                case .signUp:
                    signUpStep
                case .preferences:
                    preferencesStep
                case .driverDistance:
                    driverStep
                case .ironDistance:
                    ironStep
                case .bagReady:
                    bagReadyStep
                case .bagReview:
                    bagReviewStep
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: navigatingForward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: navigatingForward ? .leading : .trailing).combined(with: .opacity)
            ))
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .interactiveDismissDisabled(!userProfileStore.isOnboardingComplete)
    }

    // MARK: Steps

    private var carouselStep: some View {
        OnboardingCarouselScreen(onGetStarted: advance, onLogIn: advance)
    }

    private var signUpStep: some View {
        OnboardingSignUpScreen(firstName: $firstName, onContinue: advance, onBack: goBack)
    }

    private var preferencesStep: some View {
        OnboardingPreferencesScreen(
            distanceUnit: $distanceUnit,
            temperatureUnit: $temperatureUnit,
            handedness: $handedness,
            onContinue: advance,
            onBack: goBack
        )
    }

    private var driverStep: some View {
        ClubDistanceEntryScreen(
            clubName: "Driver",
            subtitle: "How far do you hit your driver?",
            defaultYards: 250,
            range: 150...400,
            yards: $driverYards,
            onContinue: advance,
            onBack: goBack,
            onSkip: { driverYards = 250; advance() }
        )
    }

    private var ironStep: some View {
        ClubDistanceEntryScreen(
            clubName: "7 Iron",
            subtitle: "How far do you hit your 7 iron?",
            defaultYards: 150,
            range: 80...250,
            yards: $sevenIronYards,
            onContinue: {
                bagEntries = BagClubEntry.generateBag(driverYards: driverYards, sevenIronYards: sevenIronYards)
                advance()
            },
            onBack: goBack,
            onSkip: {
                sevenIronYards = 150
                bagEntries = BagClubEntry.generateBag(driverYards: driverYards, sevenIronYards: 150)
                advance()
            }
        )
    }

    private var bagReadyStep: some View {
        BagReadyScreen(onReviewBag: advance)
    }

    private var bagReviewStep: some View {
        OnboardingBagReviewScreen(
            entries: $bagEntries,
            onComplete: completeOnboarding,
            onSaveMinimal: completeWithMinimal
        )
    }

    // MARK: Navigation

    private func advance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        navigatingForward = true
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    private func goBack() {
        navigatingForward = false
        if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
    }

    // MARK: Completion

    private func completeOnboarding() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        applyProfile(clubs: bagEntries.filter(\.isEnabled).map {
            ClubDistance(clubTypeId: $0.clubType.rawValue, distanceYards: $0.distanceYards)
        })
    }

    private func completeWithMinimal() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        applyProfile(clubs: [
            ClubDistance(clubTypeId: ClubType.driver.rawValue, distanceYards: driverYards),
            ClubDistance(clubTypeId: ClubType.iron7.rawValue, distanceYards: sevenIronYards),
        ])
    }

    private func applyProfile(clubs: [ClubDistance]) {
        userProfileStore.profile.firstName = firstName
        userProfileStore.profile.distanceUnit = distanceUnit
        userProfileStore.profile.temperatureUnit = temperatureUnit
        userProfileStore.profile.handedness = handedness
        userProfileStore.profile.clubDistances = clubs
        userProfileStore.save()
    }
}

// MARK: - 1. Carousel

private struct OnboardingCarouselScreen: View {
    var onGetStarted: () -> Void
    var onLogIn: () -> Void
    @State private var page = 0

    private let pages: [(icon: String, colors: [Color], title: String, subtitle: String)] = [
        ("location.viewfinder",
         [Color(red: 0.12, green: 0.52, blue: 0.32), Color(red: 0.06, green: 0.32, blue: 0.18)],
         "Know Every Distance",
         "GPS distances to the hole and every hazard on any course worldwide."),
        ("sparkles",
         [Color(red: 0.10, green: 0.46, blue: 0.44), Color(red: 0.05, green: 0.28, blue: 0.24)],
         "Your AI Caddie",
         "Personalized club and shot recommendations powered by AI."),
        ("chart.line.uptrend.xyaxis",
         [Color(red: 0.15, green: 0.40, blue: 0.55), Color(red: 0.08, green: 0.22, blue: 0.34)],
         "Track Your Progress",
         "Keep score, track stats, and watch your handicap improve over time."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    OnboardingHeroCard(
                        icon: item.icon,
                        gradient: item.colors,
                        title: item.title,
                        subtitle: item.subtitle
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: 14) {
                BrandedPrimaryButton(title: "Get Started", action: onGetStarted)
                BrandedSecondaryButton(title: "Log In", action: onLogIn)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - 2. Sign Up

private struct OnboardingSignUpScreen: View {
    @Binding var firstName: String
    var onContinue: () -> Void
    var onBack: () -> Void
    @State private var showNameInput = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    CaddieLogoView(height: 90)
                        .padding(.top, 16)

                    VStack(spacing: 8) {
                        Text("Sign Up")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Join golfers improving their game\nevery round.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }

                    if showNameInput {
                        nameEntry
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        authSection
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showNameInput)
    }

    private var authSection: some View {
        VStack(spacing: 14) {
            BrandedAuthButton(type: .apple) { withAnimation { showNameInput = true } }
            BrandedAuthButton(type: .google) { withAnimation { showNameInput = true } }

            LabeledDivider(label: "Or You Can")
                .padding(.vertical, 4)

            BrandedAuthButton(type: .email) { withAnimation { showNameInput = true } }

            (Text("By signing up, you agree to our ") +
             Text("Terms of Service").foregroundColor(GolfTheme.accentBlue) +
             Text(" and ") +
             Text("Privacy Policy").foregroundColor(GolfTheme.accentBlue) +
             Text("."))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .padding(.top, 16)
    }

    private var nameEntry: some View {
        VStack(spacing: 20) {
            Text("What should we call you?")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            TextField("First name", text: $firstName)
                .font(.system(size: 17))
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(14)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            BrandedPrimaryButton(title: "Continue", action: onContinue)
                .opacity(firstName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.top, 12)
    }
}

// MARK: - 3. Preferences

private struct OnboardingPreferencesScreen: View {
    @Binding var distanceUnit: String
    @Binding var temperatureUnit: String
    @Binding var handedness: String
    var onContinue: () -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(title: "Preferences", onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    PreferenceRadioGroup(
                        title: "Distance",
                        options: [("Imperial (Feet, Yards, Miles)", "Imperial"),
                                  ("Metric (Meters, Kilometers)", "Metric")],
                        selection: $distanceUnit
                    )
                    PreferenceRadioGroup(
                        title: "Temperature",
                        options: [("Fahrenheit", "Fahrenheit"),
                                  ("Celsius", "Celsius")],
                        selection: $temperatureUnit
                    )
                    PreferenceRadioGroup(
                        title: "Club Direction / Dominant Hand",
                        options: [("Right Handed", "Right"),
                                  ("Left Handed", "Left")],
                        selection: $handedness
                    )
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }

            BrandedPrimaryButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
        }
    }
}

// MARK: - 4 & 5. Club Distance Entry

private struct ClubDistanceEntryScreen: View {
    let clubName: String
    let subtitle: String
    let defaultYards: Int
    let range: ClosedRange<Int>
    @Binding var yards: Int
    var onContinue: () -> Void
    var onBack: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(showSkip: true, onBack: onBack, onSkip: onSkip)

            Spacer()

            VStack(spacing: 6) {
                Text(clubName)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            ZStack {
                Circle()
                    .fill(GolfTheme.grassGreen.opacity(0.08))
                    .frame(width: 140, height: 140)
                Image(systemName: clubName == "Driver" ? "figure.golf" : "sportscourt.fill")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(GolfTheme.grassGreen.opacity(0.6))
            }
            .padding(.vertical, 16)

            VStack(spacing: 0) {
                Text("\(yards)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                Text("Yds")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 24) {
                stepButton(delta: -10, label: "-10")
                stepButton(delta: -5, label: "-5")
                stepButton(delta: 5, label: "+5")
                stepButton(delta: 10, label: "+10")
            }
            .padding(.top, 16)

            Spacer()

            BrandedPrimaryButton(title: "Add Distance", action: onContinue)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
        }
    }

    private func stepButton(delta: Int, label: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let newVal = yards + delta
            if range.contains(newVal) { yards = newVal }
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(GolfTheme.accentBlue)
                .frame(width: 52, height: 40)
                .background(GolfTheme.lightBlue)
                .cornerRadius(10)
        }
    }
}

// MARK: - 6. Bag Ready

private struct BagReadyScreen: View {
    var onReviewBag: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [GolfTheme.grassGreen.opacity(0.12), GolfTheme.grassGreen.opacity(0.02)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: 180, height: 180)

                    Image(systemName: "bag.fill")
                        .font(.system(size: 72, weight: .thin))
                        .foregroundStyle(GolfTheme.grassGreen)
                }

                VStack(spacing: 12) {
                    Text("Your Golf Bag is Ready")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("We estimated your club distances\nbased on your Driver and 7 Iron.")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }

            Spacer()

            BrandedPrimaryButton(title: "Review My Bag", action: onReviewBag)
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
        }
    }
}

// MARK: - 7. Bag Review

private struct OnboardingBagReviewScreen: View {
    @Binding var entries: [BagClubEntry]
    var onComplete: () -> Void
    var onSaveMinimal: () -> Void
    @State private var editingId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Review your bag")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Add, remove, or adjust distances to\npersonalize your bag.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach($entries) { $entry in
                        BagReviewRow(
                            entry: $entry,
                            isEditing: editingId == entry.id,
                            onEdit: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    editingId = editingId == entry.id ? nil : entry.id
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            VStack(spacing: 14) {
                BrandedPrimaryButton(title: "Continue", action: onComplete)
                BrandedSecondaryButton(title: "Save Driver & 7 Iron Only", action: onSaveMinimal)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingCoordinatorView()
        .environmentObject(UserProfileStore())
}
