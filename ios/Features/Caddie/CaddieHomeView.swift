//
//  CaddieHomeView.swift
//  Caddie.ai
//
//  Single-screen Caddie experience with explicit Shot and Putt entry points.

import SwiftUI
import UIKit

struct CaddieHomeView: View {
    private enum CaddieCaptureFlow {
        case shot
        case putt
    }

    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var userProfileStore: UserProfileStore
    @EnvironmentObject var feedbackService: FeedbackService
    @EnvironmentObject var historyStore: HistoryStore
    
    @StateObject private var vm = CaddieShotViewModel()
    @StateObject private var coursePickerVM = CourseViewModel()
    
    @State private var showingCamera = false
    @State private var showingCoursePicker = false
    @State private var showingContextSheet = false
    @State private var contextSheetIsPutting = false
    @State private var showingOnboarding = false
    @State private var showingOnboardingMessage = false
    @State private var contextDraft = CaddieContextDraft()
    @State private var captureFlow: CaddieCaptureFlow?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Main interaction area
                    cameraCard
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Caddie")
            .navigationBarTitleDisplayMode(.large)
            .overlay {
                if vm.requestState.isSubmitting {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        LoadingView(message: "Thinking…")
                            .padding(32)
                            .background(GolfTheme.grassGreen.opacity(0.95))
                            .cornerRadius(16)
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CaddieCameraCaptureView(
                    onCancel: { showingCamera = false },
                    onCaptured: { image in
                        showingCamera = false
                        vm.setPhoto(image)
                        handleCapturedImage()
                    }
                )
            }
            .sheet(isPresented: $showingCoursePicker) {
                CourseSelectionView()
                    .environmentObject(coursePickerVM)
                    .environmentObject(locationService)
            }
            .sheet(isPresented: $showingContextSheet) {
                ContextConfirmSheet(
                    draft: $contextDraft,
                    confidence: .high,
                    hasPhoto: vm.currentPhoto != nil,
                    isSubmitting: vm.requestState.isSubmitting,
                    onGetRecommendation: {
                        guard !vm.requestState.isSubmitting else { return }
                        Task {
                            await vm.getShotRecommendation(profile: profileViewModel.profile, draft: contextDraft)
                            if vm.recommendationResult != nil {
                                showingContextSheet = false
                            }
                        }
                    },
                    roundContextMode: contextDraft.courseId != nil,
                    photoOptional: contextDraft.quickModeNoPhoto,
                    isPuttingFlow: false
                )
                .interactiveDismissDisabled(vm.requestState.isSubmitting)
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingCoordinatorView(initialMessage: "Quick setup needed so your caddie recommendations are accurate.")
                    .environmentObject(userProfileStore)
            }
            .sheet(isPresented: Binding(
                get: { vm.recommendationResult != nil },
                set: { if !$0 { vm.newShot() } }
            )) {
                if let result = vm.recommendationResult {
                    CaddieRecommendationOverlay(
                        result: result,
                        shotContext: vm.lastShotContext,
                        course: vm.currentCourse,
                        recommendationId: vm.lastRecommendationId,
                        recommendationType: vm.lastRecommendationType,
                        onSaveAndNext: { _ in
                            vm.newShot()
                        },
                        onClose: {
                            vm.newShot()
                        }
                    )
                    .environmentObject(feedbackService)
                }
            }
            .onAppear {
                vm.historyStore = historyStore
                coursePickerVM.loadCurrentCourse()
                if let c = coursePickerVM.currentCourse {
                    vm.selectCourse(c)
                }
            }
            .onChange(of: coursePickerVM.currentCourse) { _, newValue in
                if let c = newValue {
                    vm.selectCourse(c)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("Try Again") {
                    Task {
                        await vm.retryLastRequest()
                        if vm.recommendationResult != nil {
                            showingContextSheet = false
                        }
                    }
                }
                Button("Edit Context") {
                    vm.errorMessage = nil
                    showingContextSheet = true
                }
                Button("Retake Photo", role: .destructive) {
                    vm.errorMessage = nil
                    showingCamera = true
                }
                Button("Dismiss", role: .cancel) { vm.errorMessage = nil }
            } message: {
                if let msg = vm.errorMessage {
                    let debugSuffix = vm.requestState.debugId.map { "\nReference: \($0.prefix(8))" } ?? ""
                    Text("\(msg)\(debugSuffix)")
                }
            }
            .alert("Setup Required", isPresented: $showingOnboardingMessage) {
                Button("Start Setup") {
                    showingOnboarding = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Quick setup needed so your caddie recommendations are accurate.")
            }
        }
    }
    
    // MARK: - Camera Card
    
    private var cameraCard: some View {
        VStack(spacing: 16) {
            Button {
                showingCoursePicker = true
            } label: {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                    Text(coursePickerVM.currentCourse?.name ?? "Select course")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textPrimary)
                .padding()
                .background(GolfTheme.cream)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            PrimaryCaddieCTAButton(
                title: "Full Shot",
                subtitle: "Photo + verify context",
                systemImage: "camera.fill",
                color: GolfTheme.grassGreen
            ) {
                guard !vm.requestState.isSubmitting else { return }
                guard userProfileStore.isOnboardingComplete else {
                    showingOnboardingMessage = true
                    return
                }
                captureFlow = .shot
                showingCamera = true
            }

            PrimaryCaddieCTAButton(
                title: "Quick Shot",
                subtitle: "No photo — verify & get recommendation",
                systemImage: "bolt.fill",
                color: .orange
            ) {
                guard !vm.requestState.isSubmitting else { return }
                guard userProfileStore.isOnboardingComplete else {
                    showingOnboardingMessage = true
                    return
                }
                contextSheetIsPutting = false
                vm.setPhoto(nil)
                prefillShotDraft()
                contextDraft.quickModeNoPhoto = true
                showingContextSheet = true
            }

            PrimaryCaddieCTAButton(
                title: "Green Reader",
                subtitle: "Photo → putting read",
                systemImage: "flag.2.crossed",
                color: GolfTheme.accentGold
            ) {
                guard !vm.requestState.isSubmitting else { return }
                guard userProfileStore.isOnboardingComplete else {
                    showingOnboardingMessage = true
                    return
                }
                captureFlow = .putt
                showingCamera = true
            }

            if let image = vm.currentPhoto {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .clipped()
                    .cornerRadius(12)

                Button("Retake Photo") {
                    guard !vm.requestState.isSubmitting else { return }
                    showingCamera = true
                }
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.grassGreen)
            }
        }
    }

    private func handleCapturedImage() {
        guard let flow = captureFlow else { return }

        switch flow {
        case .shot:
            contextSheetIsPutting = false
            prefillShotDraft()
            showingContextSheet = true
        case .putt:
            prefillShotDraft()
            Task {
                await vm.getPuttingRecommendation(
                    profile: profileViewModel.profile,
                    draft: contextDraft
                )
            }
        }
        captureFlow = nil
    }

    private func prefillShotDraft() {
        contextDraft = CaddieContextDraft()
        let c = coursePickerVM.currentCourse ?? vm.currentCourse
        contextDraft.course = c
        contextDraft.courseName = c?.name
        let cid = c?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cid.isEmpty {
            contextDraft.courseId = cid
            contextDraft.isRoundBackedContext = true
        } else {
            contextDraft.courseId = nil
            contextDraft.isRoundBackedContext = false
        }
        contextDraft.holeNumber = vm.currentHoleNumber
        contextDraft.lie = contextDraft.lie ?? "Fairway"
    }
}

// MARK: - Course Selection Sheet

struct CaddieCourseSheet: View {
    let currentCourse: Course?
    let currentHole: Int?
    let nearbyCourses: [Course]
    let onSelectCourse: (Course) -> Void
    let onSelectHole: (Int) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Nearby courses
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nearby Courses")
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        
                        if nearbyCourses.isEmpty {
                            Text("No courses found. Enable location to detect nearby courses.")
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textSecondary)
                                .padding()
                        } else {
                            ForEach(nearbyCourses) { course in
                                Button {
                                    onSelectCourse(course)
                                } label: {
                                    HStack {
                                        Text(course.displayName)
                                            .font(GolfTheme.bodyFont)
                                            .foregroundColor(GolfTheme.textPrimary)
                                        Spacer()
                                        if currentCourse?.id == course.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(GolfTheme.grassGreen)
                                        }
                                    }
                                    .padding()
                                    .background(currentCourse?.id == course.id ? GolfTheme.grassGreen.opacity(0.15) : GolfTheme.cream)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Hole selector (when course is set)
                    if currentCourse != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Select Hole")
                                .font(GolfTheme.headlineFont)
                                .foregroundColor(GolfTheme.textPrimary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                                ForEach(1...18, id: \.self) { hole in
                                    Button {
                                        onSelectHole(hole)
                                    } label: {
                                        Text("\(hole)")
                                            .font(GolfTheme.headlineFont)
                                            .foregroundColor(currentHole == hole ? .white : GolfTheme.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(currentHole == hole ? GolfTheme.grassGreen : GolfTheme.cream)
                                            .cornerRadius(12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Select Course & Hole")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(GolfTheme.grassGreen)
                }
            }
        }
    }
}

#Preview {
    CaddieHomeView()
        .environmentObject(LocationService.shared)
        .environmentObject(ProfileViewModel())
        .environmentObject(FeedbackService.shared)
        .environmentObject(HistoryStore())
}
