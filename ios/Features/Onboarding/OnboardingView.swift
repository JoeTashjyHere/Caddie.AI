//
//  OnboardingView.swift
//  Caddie.ai
//

import SwiftUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var courseService: CourseService
    @StateObject private var courseViewModel = CourseViewModel()
    
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var currentStep = 1
    @State private var showingCourseSelection = false
    
    var body: some View {
        ZStack {
            GolfTheme.cream.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress Indicator
                progressIndicator
                
                // Content
                TabView(selection: $currentStep) {
                    WelcomeStep()
                        .tag(1)
                    
                    PlayerBasicsStep(profileViewModel: profileViewModel)
                        .tag(2)
                    
                    PermissionsStep(
                        locationService: locationService,
                        courseViewModel: courseViewModel,
                        showingCourseSelection: $showingCourseSelection
                    )
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Note: Removed .disabled(true) - it was blocking all interactions inside TabView
                // To prevent swiping, we rely on programmatic step changes only
                
                // Navigation Buttons
                navigationButtons
            }
        }
        .sheet(isPresented: $showingCourseSelection) {
            CourseSelectionView()
                .environmentObject(courseViewModel)
                .environmentObject(locationService)
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(1...3, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? GolfTheme.grassGreen : GolfTheme.textSecondary.opacity(0.3))
                        .frame(width: 10, height: 10)
                    
                    if step < 3 {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Text("Step \(currentStep) of 3")
                .font(GolfTheme.captionFont)
                .foregroundColor(GolfTheme.textSecondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        VStack(spacing: 16) {
            if currentStep == 1 {
                PrimaryButton(
                    title: "Get Started",
                    action: {
                        withAnimation(.spring(response: 0.3)) {
                            currentStep = 2
                        }
                    }
                )
            } else if currentStep == 2 {
                PrimaryButton(
                    title: "Continue",
                    action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        withAnimation(.spring(response: 0.3)) {
                            currentStep = 3
                        }
                    },
                    isEnabled: isStep2Valid
                )
            } else {
                PrimaryButton(
                    title: "Finish",
                    action: {
                        completeOnboarding()
                    }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 50)
    }
    
    private var isStep2Valid: Bool {
        let trimmedName = profileViewModel.profile.name.trimmingCharacters(in: .whitespaces)
        return !trimmedName.isEmpty &&
               !profileViewModel.profile.handedness.isEmpty &&
               !profileViewModel.profile.skillLevel.isEmpty
    }
    
    private func completeOnboarding() {
        // Save profile
        profileViewModel.saveProfile()
        
        // Complete onboarding
        withAnimation(.spring(response: 0.3)) {
            hasOnboarded = true
        }
    }
}

// MARK: - Step 1: Welcome

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "figure.golf")
                .font(.system(size: 80))
                .foregroundColor(GolfTheme.grassGreen)
            
            VStack(spacing: 16) {
                Text("Your AI caddie is ready")
                    .font(GolfTheme.titleFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(
                        icon: "target",
                        title: "Club Recommendations",
                        description: "Get personalized club suggestions based on your game"
                    )
                    
                    FeatureRow(
                        icon: "flag.fill",
                        title: "Hole Strategy",
                        description: "AI-powered strategy for each hole"
                    )
                    
                    FeatureRow(
                        icon: "location.fill",
                        title: "Putting Help",
                        description: "Improve your putting with AI insights"
                    )
                }
                .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(GolfTheme.grassGreen)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
                
                Text(description)
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Step 2: Player Basics

struct PlayerBasicsStep: View {
    @ObservedObject var profileViewModel: ProfileViewModel
    @State private var playerName = ""
    @State private var selectedHandedness = "Right"
    @State private var selectedSkillLevel = "Intermediate"
    
    let handednessOptions = ["Left", "Right"]
    let skillLevelOptions = ["Beginner", "Intermediate", "Advanced"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Text("Tell us about yourself")
                        .font(GolfTheme.titleFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    
                    Text("This helps your AI caddie provide better recommendations")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.horizontal)
                
                VStack(spacing: 24) {
                    // Player Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Name")
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        
                        TextField("Enter your name", text: $playerName)
                            .textFieldStyle(.roundedBorder)
                            .font(GolfTheme.bodyFont)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .onChange(of: playerName) { oldValue, newValue in
                                profileViewModel.profile.name = newValue
                            }
                    }
                    .padding()
                    .background(GolfTheme.cream)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    
                    // Handedness
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Handedness")
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        
                        Picker("Handedness", selection: $selectedHandedness) {
                            ForEach(handednessOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedHandedness) { oldValue, newValue in
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            profileViewModel.profile.handedness = newValue
                        }
                    }
                    .padding()
                    .background(GolfTheme.cream)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    
                    // Skill Level
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Skill Level")
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        
                        Picker("Skill Level", selection: $selectedSkillLevel) {
                            ForEach(skillLevelOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedSkillLevel) { oldValue, newValue in
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            profileViewModel.profile.skillLevel = newValue
                        }
                    }
                    .padding()
                    .background(GolfTheme.cream)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 100) // Space for button
        }
        .onAppear {
            // Initialize from existing profile if available
            playerName = profileViewModel.profile.name
            selectedHandedness = profileViewModel.profile.handedness.isEmpty ? "Right" : profileViewModel.profile.handedness
            selectedSkillLevel = profileViewModel.profile.skillLevel.isEmpty ? "Intermediate" : profileViewModel.profile.skillLevel
            
            // Sync initial values to profile
            if profileViewModel.profile.name != playerName {
                profileViewModel.profile.name = playerName
            }
            if profileViewModel.profile.handedness != selectedHandedness {
                profileViewModel.profile.handedness = selectedHandedness
            }
            if profileViewModel.profile.skillLevel != selectedSkillLevel {
                profileViewModel.profile.skillLevel = selectedSkillLevel
            }
        }
    }
}

// MARK: - Step 3: Permissions

struct PermissionsStep: View {
    @ObservedObject var locationService: LocationService
    @ObservedObject var courseViewModel: CourseViewModel
    @Binding var showingCourseSelection: Bool
    
    @State private var locationEnabled = false
    @State private var homeCourse: Course?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Text("Almost there!")
                        .font(GolfTheme.titleFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    
                    Text("Enable location to auto-load nearby courses")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                .padding(.horizontal)
                
                VStack(spacing: 24) {
                    // Location Permission Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "location.fill")
                                .font(.title2)
                                .foregroundColor(GolfTheme.grassGreen)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Location")
                                    .font(GolfTheme.headlineFont)
                                    .foregroundColor(GolfTheme.textPrimary)
                                
                                Text("Auto-load nearby courses when you open the app")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(GolfTheme.textSecondary)
                            }
                            
                            Spacer()
                            
                            if locationService.authorizationStatus == .authorizedWhenInUse ||
                               locationService.authorizationStatus == .authorizedAlways {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(GolfTheme.grassGreen)
                                    .font(.title3)
                            }
                        }
                        
                        if locationService.authorizationStatus != .authorizedWhenInUse &&
                           locationService.authorizationStatus != .authorizedAlways {
                            Button(action: {
                                locationService.requestAuthorization()
                            }) {
                                Text("Enable Location")
                                    .font(GolfTheme.bodyFont)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(GolfTheme.grassGreen)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    .background(GolfTheme.cream)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    
                    // Home Course Selection (Optional)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "flag.fill")
                                .font(.title2)
                                .foregroundColor(GolfTheme.accentGold)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Home Course (Optional)")
                                    .font(GolfTheme.headlineFont)
                                    .foregroundColor(GolfTheme.textPrimary)
                                
                                Text("Quickly access your favorite course")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(GolfTheme.textSecondary)
                            }
                            
                            Spacer()
                        }
                        
                        if let course = homeCourse ?? courseViewModel.currentCourse {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(course.name)
                                        .font(GolfTheme.bodyFont)
                                        .foregroundColor(GolfTheme.textPrimary)
                                    
                                    if let par = course.par {
                                        Text("Par \(par)")
                                            .font(GolfTheme.captionFont)
                                            .foregroundColor(GolfTheme.textSecondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    homeCourse = nil
                                    courseViewModel.currentCourse = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(GolfTheme.textSecondary)
                                }
                            }
                            .padding()
                            .background(GolfTheme.grassGreen.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            Button(action: {
                                showingCourseSelection = true
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Select Home Course")
                                }
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.grassGreen)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(GolfTheme.grassGreen.opacity(0.1))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    .background(GolfTheme.cream)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 100) // Space for button
        }
        .onAppear {
            // Load current course if available
            courseViewModel.loadCurrentCourse()
            homeCourse = courseViewModel.currentCourse
        }
        .onChange(of: courseViewModel.currentCourse) { oldValue, newValue in
            homeCourse = newValue
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(ProfileViewModel())
        .environmentObject(LocationService.shared)
}


//
//  OnboardingCoordinatorView.swift
//  Caddie.ai
//

import SwiftUI


struct OnboardingCoordinatorView: View {
    enum Step: Int, CaseIterable {
        case welcome = 1
        case basicInfo
        case golfSnapshot
        case clubDistances
        case riskProfile
        case puttingTendencies
        case finish

        var title: String {
            "Step \(rawValue) of \(Self.allCases.count)"
        }
    }

    @EnvironmentObject var userProfileStore: UserProfileStore
    let initialMessage: String?

    @State private var step: Step = .welcome

    init(initialMessage: String? = nil) {
        self.initialMessage = initialMessage
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count))
                        .tint(GolfTheme.grassGreen)
                    HStack {
                        Text(step.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding()

                Group {
                    switch step {
                    case .welcome:
                        WelcomeScreen(initialMessage: initialMessage)
                    case .basicInfo:
                        BasicInfoScreen(profile: $userProfileStore.profile)
                    case .golfSnapshot:
                        GolfSnapshotScreen(profile: $userProfileStore.profile)
                    case .clubDistances:
                        ClubDistancesScreen(profile: $userProfileStore.profile)
                    case .riskProfile:
                        RiskProfileScreen(profile: $userProfileStore.profile)
                    case .puttingTendencies:
                        PuttingTendenciesScreen(profile: $userProfileStore.profile)
                    case .finish:
                        FinishScreen(profile: userProfileStore.profile)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 12) {
                    if step != .welcome {
                        Button("Back") {
                            if let previous = Step(rawValue: step.rawValue - 1) {
                                step = previous
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(step == .finish ? "Start your first round" : "Next") {
                        if step == .clubDistances {
                            userProfileStore.ensureRequiredClubRows()
                        }
                        if step == .finish {
                            userProfileStore.save()
                        } else if let next = Step(rawValue: step.rawValue + 1) {
                            step = next
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GolfTheme.grassGreen)
                    .disabled(!canAdvanceFromCurrentStep)
                }
                .padding()
            }
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .interactiveDismissDisabled(!userProfileStore.isOnboardingComplete)
    }

    private var canAdvanceFromCurrentStep: Bool {
        switch step {
        case .welcome:
            return true
        case .basicInfo:
            let first = userProfileStore.profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = userProfileStore.profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
            return !first.isEmpty && !email.isEmpty && email.contains("@")
        case .clubDistances:
            return hasRequiredClubs
        case .riskProfile:
            return !(userProfileStore.profile.greenRiskPreference?.isEmpty ?? true)
        default:
            return true
        }
    }

    private var hasRequiredClubs: Bool {
        let selected = Set(userProfileStore.profile.clubDistances.map { $0.clubTypeId })
        return selected.contains(ClubType.driver.rawValue)
            && selected.contains(ClubType.iron7.rawValue)
            && selected.contains(ClubType.pitchingWedge.rawValue)
    }
}

private struct WelcomeScreen: View {
    let initialMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "figure.golf")
                .font(.system(size: 64))
                .foregroundColor(GolfTheme.grassGreen)
            Text("Set up your AI caddie")
                .font(.title2.weight(.semibold))
            Text("2–3 minutes now for better shot and putt recommendations all round.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let initialMessage {
                Text(initialMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
    }
}

private struct BasicInfoScreen: View {
    @Binding var profile: UserProfile
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case firstName
        case lastName
        case email
        case phone
    }

    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("First name *", text: $profile.firstName)
                    .focused($focusedField, equals: .firstName)
                TextField("Last name", text: Binding($profile.lastName, replacingNilWith: ""))
                    .focused($focusedField, equals: .lastName)
                TextField("Email *", text: $profile.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .focused($focusedField, equals: .email)
                TextField("Phone", text: Binding($profile.phone, replacingNilWith: ""))
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .phone)
            }
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }
}

private struct GolfSnapshotScreen: View {
    @Binding var profile: UserProfile
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case averageScore
        case yearsPlaying
        case golfGoal
    }

    var body: some View {
        Form {
            Section("Golf Snapshot") {
                TextField("Average score", text: Binding($profile.averageScore, replacingNilWith: ""))
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedField, equals: .averageScore)
                TextField("Years playing", value: $profile.yearsPlaying, format: .number)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .yearsPlaying)
                TextField("Golf goal", text: Binding($profile.golfGoal, replacingNilWith: ""), axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .golfGoal)
                Picker("Seriousness", selection: Binding($profile.seriousness, replacingNilWith: "")) {
                    Text("Not set").tag("")
                    Text("Casual").tag("Casual")
                    Text("Committed").tag("Committed")
                    Text("Obsessed").tag("Obsessed")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }
}

private struct ClubDistancesScreen: View {
    @Binding var profile: UserProfile
    @State private var showingAddClubSheet = false
    @State private var pendingDeleteClub: ClubDistance?
    @State private var newClubType: ClubType = .driver
    @State private var newDistance: Int = 150
    @State private var newShotPreference: ClubShotPreference = .straight
    @State private var newConfidence: ClubConfidenceLevel = .neutral
    @State private var newNotes: String = ""
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        Form {
            Section("Required: Driver, 7 Iron, Pitching Wedge") {
                ForEach(Array(profile.clubDistances.indices), id: \.self) { index in
                    clubRow(index: index)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeleteClub = profile.clubDistances[index]
                            } label: {
                                Label("Delete club", systemImage: "trash")
                            }
                            .accessibilityLabel("Delete club \(profile.clubDistances[index].name)")
                        }
                }

                Button {
                    newClubType = availableClubTypes.first ?? .driver
                    newDistance = 150
                    newShotPreference = .straight
                    newConfidence = .neutral
                    newNotes = ""
                    showingAddClubSheet = true
                } label: {
                    Label("Add another club", systemImage: "plus")
                }
                .disabled(availableClubTypes.isEmpty)

                if availableClubTypes.isEmpty {
                    Text("All preset clubs already added.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            if profile.clubDistances.isEmpty {
                profile.clubDistances = [
                    ClubDistance(clubTypeId: ClubType.driver.rawValue, distanceYards: 0),
                    ClubDistance(clubTypeId: ClubType.iron7.rawValue, distanceYards: 0),
                    ClubDistance(clubTypeId: ClubType.pitchingWedge.rawValue, distanceYards: 0)
                ]
            }
        }
        .confirmationDialog(
            "Delete club?",
            isPresented: Binding(
                get: { pendingDeleteClub != nil },
                set: { if !$0 { pendingDeleteClub = nil } }
            )
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
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showingAddClubSheet) {
            NavigationStack {
                Form {
                    Section("Club") {
                        Picker("Club Type", selection: $newClubType) {
                            ForEach(availableClubTypes) { clubType in
                                Text(clubType.displayName).tag(clubType)
                            }
                        }
                    }

                    Section("Distance") {
                        Picker("Distance", selection: $newDistance) {
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

                    Section("Notes") {
                        TextField("Optional notes", text: $newNotes, axis: .vertical)
                            .lineLimit(2...4)
                            .focused($isNotesFocused)
                    }
                }
                .navigationTitle("Add Club")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isNotesFocused = false
                            showingAddClubSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            profile.clubDistances.append(
                                ClubDistance(
                                    clubTypeId: newClubType.rawValue,
                                    distanceYards: newDistance,
                                    shotPreferenceId: newShotPreference.rawValue,
                                    confidenceLevelId: newConfidence.rawValue,
                                    notes: newNotes.isEmpty ? nil : newNotes
                                )
                            )
                            isNotesFocused = false
                            showingAddClubSheet = false
                        }
                        .disabled(!availableClubTypes.contains(newClubType))
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isNotesFocused = false }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isNotesFocused = false }
            }
        }
    }

    private var availableClubTypes: [ClubType] {
        let selected = Set(profile.clubDistances.map(\.clubTypeId))
        return ClubType.allCases.filter { !selected.contains($0.rawValue) }
    }

    @ViewBuilder
    private func clubRow(index: Int) -> some View {
        let clubBinding = $profile.clubDistances[index]
        let rowClub = profile.clubDistances[index]
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

            TextField("Notes", text: Binding(clubBinding.notes, replacingNilWith: ""))
                .focused($isNotesFocused)
        }
        .contentShape(Rectangle())
    }

    private func clubTypeOptions(for club: ClubDistance) -> [ClubType] {
        let used = Set(profile.clubDistances.map(\.clubTypeId))
        return ClubType.allCases.filter { $0.rawValue == club.clubTypeId || !used.contains($0.rawValue) }
    }

    private func distanceOptions(including value: Int) -> [Int] {
        var options = Set(stride(from: 0, through: 500, by: 5).map { $0 })
        options.insert(min(max(value, 0), 500))
        return options.sorted()
    }

    private func deleteClub(_ club: ClubDistance) {
        profile.clubDistances.removeAll { $0.id == club.id }
    }
}

private struct RiskProfileScreen: View {
    @Binding var profile: UserProfile

    var body: some View {
        Form {
            Section("Green Risk Preference *") {
                Picker("Preference", selection: Binding($profile.greenRiskPreference, replacingNilWith: "")) {
                    Text("Aggressive").tag("Aggressive")
                    Text("Lag-focused").tag("Lag-focused")
                    Text("Hybrid").tag("Hybrid")
                }
                .pickerStyle(.segmented)
            }

            Section("Optional Risk Settings") {
                Picker("Off tee", selection: Binding($profile.riskOffTee, replacingNilWith: "")) {
                    Text("Not set").tag("")
                    Text("Aggressive").tag("Aggressive")
                    Text("Balanced").tag("Balanced")
                    Text("Conservative").tag("Conservative")
                }
                Picker("Around hazards", selection: Binding($profile.riskAroundHazards, replacingNilWith: "")) {
                    Text("Not set").tag("")
                    Text("Take it on").tag("Take it on")
                    Text("Depends").tag("Depends")
                    Text("Avoid at all costs").tag("Avoid at all costs")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct PuttingTendenciesScreen: View {
    @Binding var profile: UserProfile
    @FocusState private var isFocused: Bool

    var body: some View {
        Form {
            Section("Putting Tendencies") {
                TextField("Open notes", text: Binding($profile.puttingTendencies, replacingNilWith: ""), axis: .vertical)
                    .lineLimit(3...6)
                    .focused($isFocused)
            }
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFocused = false }
            }
        }
    }
}

private struct FinishScreen: View {
    let profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review")
                    .font(.title3.weight(.semibold))
                Text("Name: \(profile.firstName) \(profile.lastName ?? "")")
                Text("Email: \(profile.email)")
                Text("Green Risk: \(profile.greenRiskPreference ?? "Not set")")
                Text("Clubs captured: \(profile.clubDistances.count)")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

private extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init(
            get: { source.wrappedValue ?? fallback },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
