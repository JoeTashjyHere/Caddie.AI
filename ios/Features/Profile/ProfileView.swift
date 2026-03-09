import SwiftUI

// QA checklist:
// 1) Add club, set distance/shape/confidence, save.
// 2) Edit club row pickers and notes, then tap Done.
// 3) Swipe left on a club row, tap Delete, confirm.
// 4) Verify profile persists after app relaunch.
// 5) Verify recommendations still work with per-club confidence and preference.
struct ProfileView: View {
    @EnvironmentObject var viewModel: ProfileViewModel
    @EnvironmentObject var userProfileStore: UserProfileStore
    #if DEBUG
    @EnvironmentObject var recommendationDiagnosticsStore: RecommendationDiagnosticsStore
    #endif

    @State private var showingResetConfirmation = false
    @State private var showingAddClubSheet = false
    @State private var pendingDeleteClub: ClubDistance?

    @State private var newClubType: ClubType = .driver
    @State private var newClubDistance: Int = 150
    @State private var newShotPreference: ClubShotPreference = .straight
    @State private var newConfidence: ClubConfidenceLevel = .neutral
    @State private var newClubNotes: String = ""

    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case firstName
        case lastName
        case email
        case phone
        case averageScore
        case yearsPlaying
        case golfGoal
        case puttingTendencies
        case clubNotes(UUID)
        case addClubNotes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Hey, \(displayFirstName)")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(userProfileStore.isOnboardingComplete ? "Your caddie profile is ready." : "Finish setup to improve recommendation accuracy.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                basicInfoSection
                golfSnapshotSection
                myBagSection
                riskProfileSection
                puttingSection
                resetSection
            }
            .navigationTitle("Profile")
            .scrollContentBackground(.automatic)
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .sheet(isPresented: $showingAddClubSheet) {
                addClubSheet
            }
            .confirmationDialog(
                "Delete club?",
                isPresented: Binding(
                    get: { pendingDeleteClub != nil },
                    set: { if !$0 { pendingDeleteClub = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let club = pendingDeleteClub {
                        deleteClub(club)
                    }
                    pendingDeleteClub = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteClub = nil
                }
            } message: {
                if let club = pendingDeleteClub {
                    Text("Remove \(club.name) from your bag?")
                }
            }
            .confirmationDialog(
                "Reset onboarding?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    userProfileStore.resetOnboarding()
                    syncLegacyProfile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears setup answers and shows onboarding again.")
            }
            .onAppear {
                syncLegacyProfile()
            }
            .onChange(of: userProfileStore.profile) { _, _ in
                userProfileStore.save()
                syncLegacyProfile()
            }
        }
    }

    private var displayFirstName: String {
        let trimmed = userProfileStore.profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Golfer" : trimmed
    }

    private var basicInfoSection: some View {
        Section("Basic Info") {
            TextField("First Name *", text: $userProfileStore.profile.firstName)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .firstName)
            TextField("Last Name", text: binding(for: \.lastName))
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .lastName)
            TextField("Email *", text: $userProfileStore.profile.email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .focused($focusedField, equals: .email)
            TextField("Phone", text: binding(for: \.phone))
                .keyboardType(.phonePad)
                .focused($focusedField, equals: .phone)
        }
    }

    private var golfSnapshotSection: some View {
        Section("Golf Snapshot") {
            TextField("Average Score", text: binding(for: \.averageScore))
                .keyboardType(.numbersAndPunctuation)
                .focused($focusedField, equals: .averageScore)
            TextField("Years Playing", value: $userProfileStore.profile.yearsPlaying, format: .number)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .yearsPlaying)
            TextField("Golf Goal", text: binding(for: \.golfGoal), axis: .vertical)
                .lineLimit(2...4)
                .focused($focusedField, equals: .golfGoal)
            Picker("Seriousness", selection: binding(for: \.seriousness)) {
                Text("Not set").tag("")
                Text("Casual").tag("Casual")
                Text("Committed").tag("Committed")
                Text("Obsessed").tag("Obsessed")
            }
        }
    }

    private var myBagSection: some View {
        Section("My Bag") {
            if userProfileStore.profile.clubDistances.isEmpty {
                Text("Add at least Driver, 7i, and PW.")
                    .foregroundColor(.secondary)
            }

            ForEach(Array(userProfileStore.profile.clubDistances.indices), id: \.self) { index in
                clubRow(index: index)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteClub = userProfileStore.profile.clubDistances[index]
                        } label: {
                            Label("Delete club", systemImage: "trash")
                        }
                        .accessibilityLabel("Delete club \(userProfileStore.profile.clubDistances[index].name)")
                    }
            }

            Button {
                newClubType = availableClubTypes.first ?? .driver
                newClubDistance = 150
                newShotPreference = .straight
                newConfidence = .neutral
                newClubNotes = ""
                showingAddClubSheet = true
            } label: {
                Label("Add Club", systemImage: "plus")
            }
            .disabled(availableClubTypes.isEmpty)

            if availableClubTypes.isEmpty {
                Text("All preset clubs already added.")
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func clubRow(index: Int) -> some View {
        let clubBinding = $userProfileStore.profile.clubDistances[index]
        let rowClub = userProfileStore.profile.clubDistances[index]
        let clubTypeBinding = Binding<ClubType>(
            get: { clubBinding.wrappedValue.clubType },
            set: { clubBinding.wrappedValue.clubType = $0 }
        )
        let shotPreferenceBinding = Binding<ClubShotPreference>(
            get: { clubBinding.wrappedValue.shotPreference },
            set: { clubBinding.wrappedValue.shotPreference = $0 }
        )
        let confidenceBinding = Binding<ClubConfidenceLevel>(
            get: { clubBinding.wrappedValue.confidenceLevel },
            set: { clubBinding.wrappedValue.confidenceLevel = $0 }
        )

        VStack(alignment: .leading, spacing: 10) {
            Picker("Club Type", selection: clubTypeBinding) {
                ForEach(clubTypeOptions(for: rowClub)) { clubType in
                    Text(clubType.displayName).tag(clubType)
                }
            }
            .frame(minHeight: 44)

            HStack(spacing: 12) {
                Picker("Distance", selection: clubBinding.distanceYards) {
                    ForEach(distanceOptions(including: rowClub.distanceYards), id: \.self) { yards in
                        Text("\(yards) yds").tag(yards)
                    }
                }
                .frame(minHeight: 44)

                Picker("Shot Preference", selection: shotPreferenceBinding) {
                    ForEach(ClubShotPreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .frame(minHeight: 44)
            }

            Picker("Confidence", selection: confidenceBinding) {
                ForEach(ClubConfidenceLevel.allCases) { confidence in
                    Text(confidence.displayName).tag(confidence)
                }
            }
            .frame(minHeight: 44)

            TextField("Notes (optional)", text: Binding(
                get: { clubBinding.wrappedValue.notes ?? "" },
                set: { clubBinding.wrappedValue.notes = $0.isEmpty ? nil : $0 }
            ))
            .focused($focusedField, equals: .clubNotes(clubBinding.wrappedValue.id))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var riskProfileSection: some View {
        Section("Risk Profile") {
            Picker("Green Risk Preference *", selection: binding(for: \.greenRiskPreference)) {
                Text("Aggressive").tag("Aggressive")
                Text("Lag-focused").tag("Lag-focused")
                Text("Hybrid").tag("Hybrid")
            }

            Picker("Risk Off Tee", selection: binding(for: \.riskOffTee)) {
                Text("Not set").tag("")
                Text("Aggressive").tag("Aggressive")
                Text("Balanced").tag("Balanced")
                Text("Conservative").tag("Conservative")
            }

            Picker("Risk Around Hazards", selection: binding(for: \.riskAroundHazards)) {
                Text("Not set").tag("")
                Text("Take it on").tag("Take it on")
                Text("Depends").tag("Depends")
                Text("Avoid at all costs").tag("Avoid at all costs")
            }
        }
    }

    private var puttingSection: some View {
        Section("Putting Tendencies") {
            TextField("Open notes", text: binding(for: \.puttingTendencies), axis: .vertical)
                .lineLimit(3...6)
                .focused($focusedField, equals: .puttingTendencies)
        }
    }

    private var resetSection: some View {
        Section("Developer") {
            Button("Reset Onboarding", role: .destructive) {
                showingResetConfirmation = true
            }
            #if DEBUG
            NavigationLink("Recommendation Diagnostics") {
                RecommendationDiagnosticsSummaryView()
                    .environmentObject(recommendationDiagnosticsStore)
            }
            #endif
        }
    }

    private var availableClubTypes: [ClubType] {
        let used = Set(userProfileStore.profile.clubDistances.map(\.clubTypeId))
        return ClubType.allCases.filter { !used.contains($0.rawValue) }
    }

    private func clubTypeOptions(for club: ClubDistance) -> [ClubType] {
        let used = Set(userProfileStore.profile.clubDistances.map(\.clubTypeId))
        return ClubType.allCases.filter { $0.rawValue == club.clubTypeId || !used.contains($0.rawValue) }
    }

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
                        ForEach(ClubShotPreference.allCases) { preference in
                            Text(preference.displayName).tag(preference)
                        }
                    }
                }

                Section("Confidence") {
                    Picker("Confidence", selection: $newConfidence) {
                        ForEach(ClubConfidenceLevel.allCases) { confidence in
                            Text(confidence.displayName).tag(confidence)
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
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
    }

    private func distanceOptions(including value: Int) -> [Int] {
        var options = Set(stride(from: 0, through: 500, by: 5).map { $0 })
        options.insert(min(max(value, 0), 500))
        return options.sorted()
    }

    private func binding(for keyPath: WritableKeyPath<UserProfile, String?>) -> Binding<String> {
        Binding(
            get: { userProfileStore.profile[keyPath: keyPath] ?? "" },
            set: { userProfileStore.profile[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func syncLegacyProfile() {
        viewModel.applyUserProfile(userProfileStore.profile)
    }

    private func deleteClub(_ club: ClubDistance) {
        userProfileStore.profile.clubDistances.removeAll { $0.id == club.id }
    }
}

#Preview {
    ProfileView()
        .environmentObject(ProfileViewModel())
        .environmentObject(UserProfileStore())
        #if DEBUG
        .environmentObject(RecommendationDiagnosticsStore.shared)
        #endif
}

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
        .confirmationDialog(
            "Reset diagnostics metrics?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                store.reset()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
#endif
