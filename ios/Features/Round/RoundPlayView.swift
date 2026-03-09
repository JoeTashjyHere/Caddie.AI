//
//  RoundPlayView.swift
//  Caddie.ai
//

import SwiftUI
import CoreLocation
import UIKit

struct RoundPlayView: View {
    let course: Course
    var onRoundComplete: (() -> Void)? = nil
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    @EnvironmentObject var feedbackService: FeedbackService
    @EnvironmentObject var historyStore: HistoryStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.selectedTab) var selectedTab
    
    @StateObject private var roundViewModel = RoundViewModel()
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @StateObject private var courseViewModel = CourseViewModel()
    
    @State private var showingEditSheet = false
    @State private var showingPhotoLie = false
    @State private var showingPhotoCapture: ShotType? = nil
    @State private var showingRoundSummary = false
    @State private var showingGreenView = false
    
    // Stub distances for now
    private var distanceFront: Int { 145 }
    private var distanceMiddle: Int { 152 }
    private var distanceBack: Int { 160 }
    private var distanceHazard: Int? { 140 }
    
    private var currentHolePar: Int { 4 } // Stub - would come from course data
    
    // Helper to unwrap course par with default value
    private var coursePar: Int {
        course.par ?? 72
    }
    
    // Computed property to simplify the Binding for photo capture sheet
    @State private var photoCaptureWrapper: ShotTypeWrapper? = nil
    
    var body: some View {
        NavigationStack {
            mainContent
                .background(GolfTheme.cream.ignoresSafeArea())
                .navigationTitle("Round")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        doneButton
                    }
                }
                .sheet(isPresented: $showingEditSheet) {
                    editRoundSheet
                }
                .sheet(isPresented: $showingPhotoLie) {
                    photoLieSheet
                }
                .sheet(item: $photoCaptureWrapper) { wrapper in
                    photoCaptureSheet(wrapper: wrapper)
                }
                .onChange(of: showingPhotoCapture) { oldValue, newValue in
                    if let shotType = newValue {
                        photoCaptureWrapper = ShotTypeWrapper(shotType: shotType)
                    } else {
                        photoCaptureWrapper = nil
                    }
                }
                .sheet(isPresented: $showingGreenView) {
                    greenViewSheet
                }
                .sheet(isPresented: $showingRoundSummary) {
                    roundSummarySheet
                }
                .onAppear {
                    // Defensive check: If no course available, dismiss and go to course selection
                    if course.id.isEmpty || course.name.isEmpty {
                        scoreTrackingService.setPhase(.selectingCourse)
                        dismiss()
                        return
                    }
                    
                    // Defensive check: If phase is not inProgress but round exists, update phase
                    if scoreTrackingService.phase != .inProgress,
                       scoreTrackingService.currentRound != nil {
                        scoreTrackingService.setPhase(.inProgress)
                    }

                    roundViewModel.historyStore = historyStore
                    
                    handleOnAppear()
                }
                .onChange(of: roundViewModel.scores) { oldValue, newValue in
                    handleScoresChange(newValue: newValue)
                }
                .onChange(of: roundViewModel.currentHole) { oldValue, newValue in
                    // Animate hole transition
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        handleHoleChange(newValue: newValue)
                    }
                }
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                distancesSection
                puttingAnalysisButton
                aiCaddieSection
                shotTrackingSection
                scoringSection
                navigationButtons
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Toolbar
    
    private var doneButton: some View {
        Button("Done") {
            scoreTrackingService.updateCurrentRound(
                courseName: course.name,
                par: coursePar,
                scores: roundViewModel.scores,
                currentHole: roundViewModel.currentHole
            )
            dismiss()
        }
        .foregroundColor(GolfTheme.grassGreen)
    }
    
    // MARK: - Sheets
    
    private var editRoundSheet: some View {
        EditRoundSheet(
            currentCourse: course,
            currentHole: $roundViewModel.currentHole,
            onCourseChange: {
                showingEditSheet = false
            }
        )
        .environmentObject(courseViewModel)
        .environmentObject(locationService)
    }
    
    private var photoLieSheet: some View {
        PhotoLieView(
            course: course,
            holeNumber: roundViewModel.currentHole
        )
        .environmentObject(locationService)
        .environmentObject(profileViewModel)
        .environmentObject(historyStore)
    }
    
    private func photoCaptureSheet(wrapper: ShotTypeWrapper) -> some View {
        PhotoCaptureView(
            course: course,
            holeNumber: roundViewModel.currentHole,
            shotType: wrapper.shotType,
            onCapture: { capturedShot in
                roundViewModel.addCapturedShot(capturedShot)
            }
        )
        .environmentObject(locationService)
        .environmentObject(profileViewModel)
    }
    
    private var greenViewSheet: some View {
        GreenView(
            course: course,
            holeNumber: roundViewModel.currentHole
        )
        .environmentObject(locationService)
        .environmentObject(historyStore)
    }
    
    private var roundSummarySheet: some View {
        RoundSummaryView(
            course: course,
            roundViewModel: roundViewModel,
            onDismiss: {
                showingRoundSummary = false
                onRoundComplete?()
                selectedTab.wrappedValue = 0
            }
        )
        .environmentObject(scoreTrackingService)
    }
    
    // MARK: - Lifecycle Handlers
    
    private func handleOnAppear() {
        // Check if there's an in-progress round for this course
        if let inProgressRound = scoreTrackingService.currentRound,
           inProgressRound.courseName == course.name {
            // Resume in-progress round
            let savedScores = Dictionary(uniqueKeysWithValues: inProgressRound.holes.map { ($0.holeNumber, $0.strokes) })
            // Find first unscored hole, or use last hole if all are scored
            let firstUnscoredHole = inProgressRound.holes.first(where: { $0.strokes == 0 })?.holeNumber
            let maxHoleNumber = inProgressRound.holes.map { $0.holeNumber }.max()
            let savedHole = firstUnscoredHole ?? maxHoleNumber ?? 1
            roundViewModel.resumeRound(
                course: course,
                savedScores: savedScores,
                savedHole: savedHole,
                savedShots: [:] // Could be enhanced to persist shots
            )
        } else {
            // Start new round
            roundViewModel.startRound(course: course)
            // Initialize ScoreTrackingService currentRound
            scoreTrackingService.startNewRound(courseName: course.name, par: course.par)
        }
    }
    
    private func handleScoresChange(newValue: [Int: Int]) {
        // Persist round state as user scores holes
        scoreTrackingService.updateCurrentRound(
            courseName: course.name,
            par: coursePar,
            scores: newValue,
            currentHole: roundViewModel.currentHole
        )
    }
    
    private func handleHoleChange(newValue: Int) {
        // Update current round when hole changes
        scoreTrackingService.updateCurrentRound(
            courseName: course.name,
            par: coursePar,
            scores: roundViewModel.scores,
            currentHole: newValue
        )
    }
    
    // MARK: - View Sections
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name)
                        .font(GolfTheme.titleFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    
                    Text("Hole \(roundViewModel.currentHole) of 18")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                        .id("hole-\(roundViewModel.currentHole)")
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Par")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                    Text("\(currentHolePar)")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                        .id("par-\(roundViewModel.currentHole)")
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                
                Button(action: {
                    showingEditSheet = true
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundColor(GolfTheme.grassGreen)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(GolfTheme.grassGreen.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var distancesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distances")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            HStack(spacing: 16) {
                DistanceBadge(label: "Front", value: "\(distanceFront) yds")
                DistanceBadge(label: "Middle", value: "\(distanceMiddle) yds", isPrimary: true)
                DistanceBadge(label: "Back", value: "\(distanceBack) yds")
                
                if let hazardDist = distanceHazard {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("\(hazardDist) yds")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
    }
    
    private var puttingAnalysisButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            showingGreenView = true
        }) {
            HStack {
                Image(systemName: "target")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Putting Analysis")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(.white)
                    Text("Capture green photo for putting read")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
            }
            .foregroundColor(.white)
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue,
                        Color.blue.opacity(0.8)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal)
    }
    
    private var aiCaddieSection: some View {
        VStack(spacing: 16) {
            photoLieButton
            
            // Show ShotFlowState-based UI
            switch roundViewModel.shotFlowState {
            case .idle:
                askCaddieButton
                
            case .waitingForPhoto:
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Waiting for photo...")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(GolfTheme.cream)
                .cornerRadius(12)
                .padding(.horizontal)
                
            case .sendingToAI:
                LoadingView(message: "📸 Sending photo to AI vision...")
                    .padding(.horizontal)
                
            case .waitingForRecommendation:
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("🤖 Getting AI recommendation...")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                    Text("Trying fallback methods if needed")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(GolfTheme.cream)
                .cornerRadius(12)
                .padding(.horizontal)
                
            case .showingRecommendation:
                if let recommendation = roundViewModel.aiRecommendation {
                    VStack(spacing: 16) {
                        RecommendationCardView(
                            recommendation: recommendation,
                            onThumbsUp: {
                                Task {
                                    await sendFeedback(helpful: true, recommendation: recommendation)
                                }
                            },
                            onThumbsDown: {
                                Task {
                                    await sendFeedback(helpful: false, recommendation: recommendation)
                                }
                            },
                            distance: nil,
                            lie: nil,
                            shotType: nil
                        )
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        
                        // Explicit "Use This Recommendation" button
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            roundViewModel.acceptRecommendation()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Use This Recommendation")
                            }
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(GolfTheme.grassGreen)
                            .cornerRadius(12)
                        }
                        
                        // Show warning if fallback was used
                        if recommendation.narrative.contains("⚠️") || recommendation.narrative.contains("Fallback") {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Using fallback recommendation")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: roundViewModel.shotFlowState)
                } else {
                    askCaddieButton
                }
                
            case .recommendationAccepted:
                if let recommendation = roundViewModel.aiRecommendation {
                    VStack(spacing: 12) {
                        RecommendationCardView(
                            recommendation: recommendation,
                            onThumbsUp: {
                                Task {
                                    await sendFeedback(helpful: true, recommendation: recommendation)
                                }
                            },
                            onThumbsDown: {
                                Task {
                                    await sendFeedback(helpful: false, recommendation: recommendation)
                                }
                            },
                            distance: nil,
                            lie: nil,
                            shotType: nil
                        )
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(GolfTheme.grassGreen)
                            Text("Recommendation accepted - You can now score this hole")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.horizontal)
                }
                
            case .error(let message):
                ErrorView(message: message) {
                    Task {
                        await roundViewModel.askCaddie(
                            profile: profileViewModel.profile,
                            location: locationService.coordinate
                        )
                    }
                }
            }
        }
    }
    
    private var photoLieButton: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            showingPhotoLie = true
        }) {
            HStack {
                Image(systemName: "camera.fill")
                Text("Analyze Photo Lie")
            }
            .font(GolfTheme.bodyFont)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
        }
        .padding(.horizontal)
    }
    
    private var askCaddieButton: some View {
        VStack(spacing: 12) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                Task {
                    await roundViewModel.askCaddie(
                        profile: profileViewModel.profile,
                        location: locationService.coordinate
                    )
                }
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Ask Caddie")
                }
                .font(GolfTheme.bodyFont)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(GolfTheme.grassGreen)
                .cornerRadius(12)
            }
            .disabled(roundViewModel.shotFlowState.isActive)
            .opacity(roundViewModel.shotFlowState.isActive ? 0.7 : 1.0)
            .padding(.horizontal)
            
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                photoCaptureWrapper = ShotTypeWrapper(shotType: .approach)
                showingPhotoCapture = .approach
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                    .font(.caption)
                    Text("Photo")
                    .font(GolfTheme.captionFont)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal)
        }
    }
    
    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Score this hole")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            HStack(spacing: 12) {
                ScoreButton(
                    label: "\(currentHolePar - 1)",
                    subtitle: "Par-1",
                    color: GolfTheme.grassGreen,
                    action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        roundViewModel.setScore(currentHolePar - 1, forHole: roundViewModel.currentHole)
                    },
                    cameraAction: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        photoCaptureWrapper = ShotTypeWrapper(shotType: .approach)
                    showingPhotoCapture = .approach
                    }
                )
                
                ScoreButton(
                    label: "\(currentHolePar)",
                    subtitle: "Par",
                    color: GolfTheme.accentGold,
                    action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        roundViewModel.setScore(currentHolePar, forHole: roundViewModel.currentHole)
                    },
                    cameraAction: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        photoCaptureWrapper = ShotTypeWrapper(shotType: .approach)
                    showingPhotoCapture = .approach
                    }
                )
                
                ScoreButton(
                    label: "\(currentHolePar + 1)",
                    subtitle: "Par+1",
                    color: Color.orange,
                    action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        roundViewModel.setScore(currentHolePar + 1, forHole: roundViewModel.currentHole)
                    },
                    cameraAction: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        photoCaptureWrapper = ShotTypeWrapper(shotType: .approach)
                    showingPhotoCapture = .approach
                    }
                )
                
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    roundViewModel.setScore(currentHolePar + 2, forHole: roundViewModel.currentHole)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(GolfTheme.textPrimary)
                        Text("Custom")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(GolfTheme.cream)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(GolfTheme.textSecondary.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            
            if roundViewModel.showSavedConfirmation {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(GolfTheme.grassGreen)
                    Text("Saved ✅")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.grassGreen)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(GolfTheme.grassGreen.opacity(0.1))
                .cornerRadius(8)
                .transition(.opacity)
            }
            
            if let strokes = roundViewModel.scores[roundViewModel.currentHole] {
                HStack {
                    Text("Current score: \(strokes)")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    Spacer()
                    Button("Change") {
                        roundViewModel.setScore(currentHolePar, forHole: roundViewModel.currentHole)
                    }
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.grassGreen)
                }
                .padding()
                .background(GolfTheme.cream.opacity(0.5))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
    }
    
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if roundViewModel.currentHole > 1 {
                Button(action: {
                    roundViewModel.previousHole()
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Previous")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(GolfTheme.textSecondary)
                    .cornerRadius(10)
                }
            }
            
            if roundViewModel.currentHole < 18 {
                Button(action: {
                    roundViewModel.nextHole()
                }) {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(GolfTheme.grassGreen)
                    .cornerRadius(10)
                }
            } else {
                Button(action: {
                    // Save round and move to summary phase
                    scoreTrackingService.saveRoundFromViewModel(
                        courseName: course.name,
                        par: coursePar,
                        scores: roundViewModel.scores,
                        roundViewModel: roundViewModel
                    )
                    scoreTrackingService.completeRound()
                    showingRoundSummary = true
                }) {
                    Text("Finish Round")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(GolfTheme.grassGreen)
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Shot Tracking Section
    
    private var shotTrackingSection: some View {
        VStack(spacing: 20) {
            Text("Shot Tracking")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Shot type sections
            shotTypeSection(shotType: .drive, title: "Drive", icon: "arrow.up.circle.fill", color: GolfTheme.grassGreen)
            shotTypeSection(shotType: .approach, title: "Approach", icon: "target", color: GolfTheme.accentGold)
            shotTypeSection(shotType: .chip, title: "Chip", icon: "arrow.down.circle.fill", color: Color.orange)
            shotTypeSection(shotType: .putt, title: "Putt", icon: "circle.fill", color: Color.blue)
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
    }
    
    // MARK: - Shot Type Section
    
    private func shotTypeSection(shotType: ShotType, title: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Text(title)
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
                Spacer()
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    photoCaptureWrapper = ShotTypeWrapper(shotType: shotType)
                    showingPhotoCapture = shotType
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                        Text("Add Photo")
                    }
                    .font(GolfTheme.captionFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(color)
                    .cornerRadius(8)
                }
            }
            
            // Quick photo capture button (smaller, inline)
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                photoCaptureWrapper = ShotTypeWrapper(shotType: shotType)
                showingPhotoCapture = shotType
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                    Text("Photo")
                        .font(GolfTheme.captionFont)
                }
                .foregroundColor(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color.opacity(0.1))
                .cornerRadius(6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Display captured shots for this type
            shotListContent(shotType: shotType, color: color)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Shot List Content
    
    @ViewBuilder
    private func shotListContent(shotType: ShotType, color: Color) -> some View {
        let shots = roundViewModel.getCapturedShots(forHole: roundViewModel.currentHole, shotType: shotType)
        
        if shots.isEmpty {
            Text("No shots captured")
                .font(GolfTheme.captionFont)
                .foregroundColor(GolfTheme.textSecondary)
                .padding(.vertical, 8)
        } else {
            ForEach(shots) { shot in
                capturedShotRow(shot: shot, color: color)
            }
        }
        
        // Success state for recently analyzed photos
        if let recentShot = shots.first,
           recentShot.recommendation != nil,
           recentShot.timestamp.timeIntervalSinceNow > -10 { // Within last 10 seconds
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(GolfTheme.grassGreen)
                    .font(.caption)
                Text("AI analyzed photo ✅")
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.grassGreen)
                
                if let image = recentShot.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .cornerRadius(4)
                        .clipped()
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(GolfTheme.grassGreen.opacity(0.1))
            .cornerRadius(6)
        }
    }
    
    // MARK: - Captured Shot Row
    
    private func capturedShotRow(shot: CapturedShot, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                if let image = shot.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                        .clipped()
                } else if let imageURL = shot.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                                .foregroundColor(GolfTheme.textSecondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 80, height: 80)
                    .background(GolfTheme.cream)
                    .cornerRadius(8)
                    .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(GolfTheme.cream)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(GolfTheme.textSecondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let club = shot.club {
                            Text(club)
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(color)
                                .fontWeight(.semibold)
                        }
                        if let distance = shot.distance {
                            Text("\(distance) yds")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }
                    }
                    
                    Text(shot.timestamp, style: .time)
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                    
                    // Recommendation summary
                    if let recommendation = shot.recommendation {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .foregroundColor(GolfTheme.accentGold)
                                .font(.caption)
                            Text("\(recommendation.club) • \(recommendation.aim)")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textPrimary)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Full recommendation details (if available)
            if let recommendation = shot.recommendation {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    HStack {
                        Text("Club:")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        Text(recommendation.club)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(color)
                            .fontWeight(.semibold)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aim:")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        Text(recommendation.aim)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avoid:")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        Text(recommendation.avoid)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(Color.orange)
                    }
                    
                    HStack {
                        Text("Confidence:")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        ProgressView(value: recommendation.confidence, total: 1.0)
                            .tint(color)
                            .frame(width: 100)
                        Text("\(Int(recommendation.confidence * 100))%")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
                .padding(.top, 4)
            }
            
            if let feedback = shot.userFeedback {
                HStack(spacing: 8) {
                    Image(systemName: feedback == "helpful" ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundColor(feedback == "helpful" ? GolfTheme.grassGreen : .red)
                    Text(feedback == "helpful" ? "Marked helpful" : "Marked off target")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
            }
            
            if shot.backendId != nil {
                HStack(spacing: 12) {
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        if let backendId = shot.backendId {
                            Task {
                                await roundViewModel.sendFeedback(
                                    helpful: true,
                                    shotId: backendId,
                                    suggestedClub: shot.recommendation?.club ?? shot.club ?? "unknown"
                                )
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.thumbsup.fill")
                            Text("Helpful")
                        }
                        .font(GolfTheme.captionFont)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(GolfTheme.grassGreen)
                        .cornerRadius(8)
                    }
                    
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        if let backendId = shot.backendId {
                            Task {
                                await roundViewModel.sendFeedback(
                                    helpful: false,
                                    shotId: backendId,
                                    suggestedClub: shot.recommendation?.club ?? shot.club ?? "unknown"
                                )
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.thumbsdown.fill")
                            Text("Off")
                        }
                        .font(GolfTheme.captionFont)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.red)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(8)
    }
    
    // MARK: - Feedback Helper
    
    private func sendFeedback(helpful: Bool, recommendation: ShotRecommendation) async {
        // Haptic feedback for thumbs up/down (additional to RoundViewModel's haptic)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Send via RoundViewModel
        await roundViewModel.sendFeedback(helpful: helpful)
        
        // Also send via FeedbackService
        await feedbackService.sendCaddieFeedback(
            courseId: course.id,
            hole: roundViewModel.currentHole,
            clubSuggested: recommendation.club,
            userFeedback: helpful ? "helpful" : "off"
        )
        
        // Record in FeedbackService
        let feedback = ShotFeedback(
            courseName: course.name,
            courseId: course.id,
            holeNumber: roundViewModel.currentHole,
            clubSuggested: recommendation.club,
            userRating: helpful
        )
        feedbackService.recordFeedback(feedback)
    }
}

// Helper wrapper to make ShotType Identifiable for sheet
struct ShotTypeWrapper: Identifiable {
    let id = UUID()
    let shotType: ShotType
}

struct DistanceBadge: View {
    let label: String
    let value: String
    var isPrimary: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(GolfTheme.captionFont)
                .foregroundColor(GolfTheme.textSecondary)
            Text(value)
                .font(isPrimary ? GolfTheme.headlineFont : GolfTheme.bodyFont)
                .foregroundColor(isPrimary ? GolfTheme.grassGreen : GolfTheme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isPrimary ? GolfTheme.grassGreen.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
}

struct ScoreButton: View {
    let label: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    var cameraAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 8) {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(GolfTheme.captionFont)
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color)
            .cornerRadius(10)
            }
            
            // Camera icon button
            if let cameraAction = cameraAction {
                Button(action: cameraAction) {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundColor(color)
                        .padding(6)
                        .background(color.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
    }
}

#Preview {
    RoundPlayView(course: Course(name: "Pebble Beach Golf Links", par: 72))
        .environmentObject(LocationService.shared)
}
