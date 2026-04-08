import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var viewModel: ProfileViewModel
    @EnvironmentObject var userProfileStore: UserProfileStore
    #if DEBUG
    @EnvironmentObject var recommendationDiagnosticsStore: RecommendationDiagnosticsStore
    #endif

    @State private var showingResetConfirmation = false
    @State private var showingAddClubSheet = false
    @State private var pendingDeleteIndex: Int?

    @State private var newClubType: ClubType = .driver
    @State private var newClubDistance: Int = 150
    @State private var newShotPreference: ClubShotPreference = .straight
    @State private var newConfidence: ClubConfidenceLevel = .neutral
    @State private var newClubNotes: String = ""

    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case firstName, lastName, email, phone, golfGoal, puttingTendencies, addClubNotes
    }

    private let averageScoreOptions = [
        "Under 70", "70–79", "80–89", "90–99", "100–109", "110–119", "120+"
    ]

    private let yearsPlayingOptions = [
        "< 1 year", "1–3 years", "3–5 years", "5–10 years", "10–20 years", "20+ years"
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    profileHeader
                    bagSection
                    snapshotSection
                    playerProfileSection
                    riskSection
                    puttingSection
                    preferencesSection
                    accountSection
                    developerSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(GolfTheme.screenBackground.ignoresSafeArea())
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .sheet(isPresented: $showingAddClubSheet) { addClubSheet }
            .confirmationDialog("Remove this club?", isPresented: Binding(
                get: { pendingDeleteIndex != nil },
                set: { if !$0 { pendingDeleteIndex = nil } }
            ), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let idx = pendingDeleteIndex,
                       idx < userProfileStore.profile.clubDistances.count {
                        userProfileStore.profile.clubDistances.remove(at: idx)
                    }
                    pendingDeleteIndex = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteIndex = nil }
            } message: {
                if let idx = pendingDeleteIndex,
                   idx < userProfileStore.profile.clubDistances.count {
                    Text("Remove \(userProfileStore.profile.clubDistances[idx].name) from your bag?")
                }
            }
            .confirmationDialog("Reset onboarding?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    userProfileStore.resetOnboarding()
                    viewModel.applyUserProfile(userProfileStore.profile)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears setup answers and shows onboarding again.")
            }
            .onAppear { viewModel.applyUserProfile(userProfileStore.profile) }
            .onChange(of: userProfileStore.profile) { _, _ in
                userProfileStore.save()
                viewModel.applyUserProfile(userProfileStore.profile)
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Text(String(displayFirstName.prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        LinearGradient(
                            colors: [GolfTheme.grassGreen, GolfTheme.darkGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayFirstName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    HStack(spacing: 8) {
                        CaddieWordmark()
                            .scaleEffect(0.6, anchor: .leading)
                            .frame(height: 16)
                        Text("Member")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 0) {
                statPill(value: "\(userProfileStore.profile.clubDistances.count)", label: "Clubs")
                Divider().frame(height: 28)
                statPill(value: userProfileStore.profile.averageScore ?? "—", label: "Avg Score")
                Divider().frame(height: 28)
                statPill(value: yearsSummary, label: "Experience")
            }
            .padding(.vertical, 8)
            .background(Color(.systemGray6).opacity(0.6))
            .cornerRadius(12)
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(GolfTheme.accentBlue)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var yearsSummary: String {
        guard let yp = userProfileStore.profile.yearsPlaying else { return "—" }
        if yp == 0 { return "New" }
        return "\(yp)y"
    }

    // MARK: - My Bag

    private var bagSection: some View {
        ProfileSectionCard(
            title: "My Bag",
            trailing: AnyView(
                Button {
                    newClubType = availableClubTypes.first ?? .driver
                    newClubDistance = 150
                    newShotPreference = .straight
                    newConfidence = .neutral
                    newClubNotes = ""
                    showingAddClubSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(GolfTheme.accentBlue)
                }
                .disabled(availableClubTypes.isEmpty)
            )
        ) {
            if userProfileStore.profile.clubDistances.isEmpty {
                Text("Add at least Driver and 7 Iron to get started.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }

            VStack(spacing: 10) {
                ForEach(Array(userProfileStore.profile.clubDistances.indices), id: \.self) { index in
                    EditableClubCard(
                        club: $userProfileStore.profile.clubDistances[index],
                        onDelete: { pendingDeleteIndex = index }
                    )
                }
            }
        }
    }

    // MARK: - Snapshot

    private var snapshotSection: some View {
        ProfileSectionCard(title: "Golf Snapshot") {
            SnapshotDropdownField(
                label: "Average Score",
                options: averageScoreOptions,
                selection: optionalBinding(for: \.averageScore)
            )

            SnapshotDropdownField(
                label: "Years Playing",
                options: yearsPlayingOptions,
                selection: yearsPlayingBinding
            )

            cardTextField("Golf Goal", text: optionalBinding(for: \.golfGoal), axis: .vertical)
                .lineLimit(2...4)
                .focused($focusedField, equals: .golfGoal)

            profilePickerRow("Seriousness",
                             selection: optionalBinding(for: \.seriousness),
                             options: [("Not set", ""), ("Casual", "Casual"),
                                       ("Committed", "Committed"), ("Obsessed", "Obsessed")])
        }
    }

    // MARK: - Player Profile

    private var playerProfileSection: some View {
        ProfileSectionCard(title: "Player Profile") {
            profilePickerRow("Skill Level",
                             selection: optionalBinding(for: \.skillLevel),
                             options: [("Not set", ""), ("Beginner", "Beginner"),
                                       ("Intermediate", "Intermediate"), ("Advanced", "Advanced")])
            profilePickerRow("Shot Shape",
                             selection: optionalBinding(for: \.shotShape),
                             options: [("Not set", ""), ("Straight", "Straight"),
                                       ("Draw", "Draw"), ("Fade", "Fade")])
            profilePickerRow("Strategy",
                             selection: optionalBinding(for: \.strategyType),
                             options: [("Not set", ""), ("Aggressive", "Aggressive"),
                                       ("Balanced", "Balanced"), ("Conservative", "Conservative")])
        }
    }

    // MARK: - Risk

    private var riskSection: some View {
        ProfileSectionCard(title: "Risk Profile") {
            profilePickerRow("Green Risk",
                             selection: optionalBinding(for: \.greenRiskPreference),
                             options: [("Not set", ""), ("Aggressive", "Aggressive"),
                                       ("Lag-focused", "Lag-focused"), ("Hybrid", "Hybrid")])
            profilePickerRow("Off Tee",
                             selection: optionalBinding(for: \.riskOffTee),
                             options: [("Not set", ""), ("Aggressive", "Aggressive"),
                                       ("Balanced", "Balanced"), ("Conservative", "Conservative")])
            profilePickerRow("Near Hazards",
                             selection: optionalBinding(for: \.riskAroundHazards),
                             options: [("Not set", ""), ("Take it on", "Take it on"),
                                       ("Depends", "Depends"), ("Avoid at all costs", "Avoid at all costs")])
        }
    }

    // MARK: - Putting

    private var puttingSection: some View {
        ProfileSectionCard(title: "Putting Tendencies") {
            TextField("Describe your putting tendencies…", text: optionalBinding(for: \.puttingTendencies), axis: .vertical)
                .lineLimit(3...6)
                .font(.system(size: 15))
                .padding(14)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .focused($focusedField, equals: .puttingTendencies)
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        ProfileSectionCard(title: "Preferences") {
            profilePickerRow("Distance",
                             selection: optionalBinding(for: \.distanceUnit),
                             options: [("Imperial", "Imperial"), ("Metric", "Metric")])
            profilePickerRow("Temperature",
                             selection: optionalBinding(for: \.temperatureUnit),
                             options: [("Fahrenheit", "Fahrenheit"), ("Celsius", "Celsius")])
            profilePickerRow("Handedness",
                             selection: optionalBinding(for: \.handedness),
                             options: [("Right", "Right"), ("Left", "Left")])
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        ProfileSectionCard(title: "Account") {
            cardTextField("First Name", text: $userProfileStore.profile.firstName)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .firstName)
            cardTextField("Last Name", text: optionalBinding(for: \.lastName))
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .lastName)
            cardTextField("Email", text: $userProfileStore.profile.email, keyboard: .emailAddress)
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .email)
            cardTextField("Phone", text: optionalBinding(for: \.phone), keyboard: .phonePad)
                .focused($focusedField, equals: .phone)
        }
    }

    // MARK: - Developer

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Reset Onboarding", role: .destructive) {
                showingResetConfirmation = true
            }
            .font(.system(size: 14, weight: .medium))

            #if DEBUG
            NavigationLink("Recommendation Diagnostics") {
                RecommendationDiagnosticsSummaryView()
                    .environmentObject(recommendationDiagnosticsStore)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(GolfTheme.accentBlue)
            #endif
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var displayFirstName: String {
        let trimmed = userProfileStore.profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Golfer" : trimmed
    }

    private var availableClubTypes: [ClubType] {
        let used = Set(userProfileStore.profile.clubDistances.map(\.clubTypeId))
        return ClubType.allCases.filter { !used.contains($0.rawValue) }
    }

    private var yearsPlayingBinding: Binding<String> {
        Binding(
            get: {
                if let yp = userProfileStore.profile.yearsPlaying {
                    return yearsPlayingOptions.first { opt in
                        switch opt {
                        case "< 1 year": return yp < 1
                        case "1–3 years": return (1...3).contains(yp)
                        case "3–5 years": return (4...5).contains(yp)
                        case "5–10 years": return (6...10).contains(yp)
                        case "10–20 years": return (11...20).contains(yp)
                        case "20+ years": return yp > 20
                        default: return false
                        }
                    } ?? ""
                }
                return ""
            },
            set: { val in
                switch val {
                case "< 1 year": userProfileStore.profile.yearsPlaying = 0
                case "1–3 years": userProfileStore.profile.yearsPlaying = 2
                case "3–5 years": userProfileStore.profile.yearsPlaying = 4
                case "5–10 years": userProfileStore.profile.yearsPlaying = 7
                case "10–20 years": userProfileStore.profile.yearsPlaying = 15
                case "20+ years": userProfileStore.profile.yearsPlaying = 25
                default: userProfileStore.profile.yearsPlaying = nil
                }
            }
        )
    }

    private func cardTextField(_ placeholder: String, text: Binding<String>,
                               keyboard: UIKeyboardType = .default, axis: Axis = .horizontal) -> some View {
        TextField(placeholder, text: text, axis: axis)
            .font(.system(size: 15))
            .keyboardType(keyboard)
            .padding(14)
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }

    private func profilePickerRow(_ label: String, selection: Binding<String>,
                                  options: [(String, String)]) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
            Picker(label, selection: selection) {
                ForEach(options, id: \.1) { opt in
                    Text(opt.0).tag(opt.1)
                }
            }
            .labelsHidden()
            .tint(GolfTheme.accentBlue)
        }
        .padding(.vertical, 2)
    }

    private func optionalBinding(for keyPath: WritableKeyPath<UserProfile, String?>) -> Binding<String> {
        Binding(
            get: { userProfileStore.profile[keyPath: keyPath] ?? "" },
            set: { userProfileStore.profile[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - Add Club Sheet

    @ViewBuilder
    private var addClubSheet: some View {
        NavigationStack {
            Form {
                Section("Club") {
                    Picker("Club Type", selection: $newClubType) {
                        ForEach(availableClubTypes) { clubType in
                            Text(clubType.displayName).tag(clubType)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Distance") {
                    Picker("Distance", selection: $newClubDistance) {
                        ForEach(stride(from: 0, through: 500, by: 5).map { $0 }, id: \.self) { yards in
                            Text("\(yards) yds").tag(yards)
                        }
                    }
                }
                Section("Shot Preference") {
                    Picker("Preference", selection: $newShotPreference) {
                        ForEach(ClubShotPreference.allCases) { pref in
                            Text(pref.displayName).tag(pref)
                        }
                    }
                }
                Section("Confidence") {
                    Picker("Confidence", selection: $newConfidence) {
                        ForEach(ClubConfidenceLevel.allCases) { conf in
                            Text(conf.displayName).tag(conf)
                        }
                    }
                }
                Section("Notes (Optional)") {
                    TextField("Notes", text: $newClubNotes, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .addClubNotes)
                }
            }
            .navigationTitle("Add Club")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        showingAddClubSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        userProfileStore.profile.clubDistances.append(
                            ClubDistance(
                                clubTypeId: newClubType.rawValue,
                                distanceYards: newClubDistance,
                                shotPreferenceId: newShotPreference.rawValue,
                                confidenceLevelId: newConfidence.rawValue,
                                notes: newClubNotes.isEmpty ? nil : newClubNotes
                            )
                        )
                        focusedField = nil
                        showingAddClubSheet = false
                    }
                    .disabled(!availableClubTypes.contains(newClubType))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
        .environmentObject(ProfileViewModel())
        .environmentObject(UserProfileStore())
        #if DEBUG
        .environmentObject(RecommendationDiagnosticsStore.shared)
        #endif
}

// MARK: - Diagnostics (DEBUG)

#if DEBUG
struct RecommendationDiagnosticsSummaryView: View {
    @EnvironmentObject var store: RecommendationDiagnosticsStore
    @State private var showingResetConfirmation = false

    var body: some View {
        List {
            Section("Health Metrics") {
                metricRow("Total recommendations", "\(store.snapshot.totalShotRecommendations)")
                metricRow("Normalization rate", percent(store.snapshot.normalizationRate))
                metricRow("Fallback rate", percent(store.snapshot.fallbackRate))
                metricRow("AI -> final changed", percent(store.snapshot.aiChangedRate))
                metricRow("Photo not referenced", percent(store.snapshot.photoNotReferencedRate))
                metricRow("Weather not live", percent(store.snapshot.weatherNotLiveRate))
                metricRow("Elevation not live", percent(store.snapshot.elevationNotLiveRate))
            }

            Section("Recent Diagnostics") {
                if store.snapshot.mostRecentDiagnostics.isEmpty {
                    Text("No diagnostics captured yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.snapshot.mostRecentDiagnostics, id: \.correlationId) { diag in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(diag.finalClub) @ \(diag.targetDistanceYards)y")
                                .font(.subheadline.weight(.semibold))
                            Text("Norm: \(diag.normalizationOccurred ? "yes" : "no") | Fallback: \(diag.fallbackUsed ? "yes" : "no") | PhotoRef: \(diag.photoReferencedInOutput ? "yes" : "no")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let reason = diag.normalizationReason, !reason.isEmpty {
                                Text("Normalization: \(reason)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let reason = diag.fallbackReason, !reason.isEmpty {
                                Text("Fallback: \(reason)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Actions") {
                Button("Reset Diagnostics Metrics", role: .destructive) {
                    showingResetConfirmation = true
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset diagnostics metrics?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
#endif
