//
//  RoundPlayView.swift
//  Caddie.ai

import SwiftUI
import CoreLocation
import MapKit
import UIKit

struct RoundPlayView: View {
    let course: Course
    var launchConfig: RoundPlayLaunchConfig? = nil
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
    @StateObject private var activeRoundContext = ActiveRoundContext()
    @StateObject private var holeDetectionEngine = HoleDetectionEngine()
    @StateObject private var roundCaddieVM = CaddieShotViewModel()

    @State private var showingEditSheet = false
    @State private var showingPhotoLie = false
    @State private var showingPhotoCapture: ShotType? = nil
    @State private var showingRoundSummary = false
    @State private var showingGreenView = false

    @State private var photoCaptureWrapper: ShotTypeWrapper? = nil
    @State private var mapDebouncedUserCoordinate: CLLocationCoordinate2D?
    @State private var mapUserDebounceTask: Task<Void, Never>?

    @State private var roundContextDraft = CaddieContextDraft()
    @State private var showingRoundContextSheet = false
    @State private var showingRoundCaddieCamera = false
    @State private var roundCaddieIntent: RoundCaddieIntent = .idle
    @State private var showFullShotModePicker = false
    @State private var showPuttingModePicker = false
    @State private var showScoreInput = false

    private enum RoundCaddieIntent: Equatable {
        case idle
        case fullShot(photo: Bool)
        case putting(photo: Bool)
    }

    private var roundContextIsPuttingFlow: Bool {
        if case .putting = roundCaddieIntent { return true }
        return false
    }

    private var displayHole: Int {
        activeRoundContext.isLoaded ? activeRoundContext.currentHole : roundViewModel.currentHole
    }

    private var currentGreenCoordinate: CLLocationCoordinate2D? {
        activeRoundContext.hole(for: activeRoundContext.currentHole)?.greenCenter
    }

    /// Full hole data for the current hole — drives RoundMapView geometry and camera.
    private var currentHoleData: HoleData? {
        activeRoundContext.hole(for: activeRoundContext.currentHole)
    }

    private var resolvedHolePar: Int? {
        activeRoundContext.hole(for: activeRoundContext.currentHole)?.par
    }

    private var resolvedCourseTotalPar: Int? {
        if let p = course.par, p > 0 { return p }
        if activeRoundContext.isLoaded {
            let sum = activeRoundContext.holes.compactMap(\.par).reduce(0, +)
            if sum > 0 { return sum }
        }
        let fromDisk = scoreTrackingService.currentRound.flatMap { r -> Int? in
            let pars = r.holes.compactMap(\.par)
            guard pars.count == 18 else { return nil }
            return pars.reduce(0, +)
        }
        if let t = fromDisk, t > 0 { return t }
        return nil
    }

    private var holeHandicap: Int? {
        activeRoundContext.hole(for: activeRoundContext.currentHole)?.handicap
    }

    private var teeYardage: String {
        if let tee = activeRoundContext.selectedTee {
            let perHole = tee.totalYards / max(activeRoundContext.holes.count, 1)
            return "\(perHole)"
        }
        return "—"
    }

    private var liveDistanceYards: Int? {
        guard let snap = activeRoundContext.distances else { return nil }
        return Int(round(snap.center))
    }

    /// Auto-inferred shot type based on distance to pin.
    private var inferredShotType: ShotType {
        guard let d = liveDistanceYards else { return .approach }
        if d > 220 { return .drive }
        if d > 100 { return .approach }
        if d > 30 { return .chip }
        return .putt
    }

    private var roundProgressSummary: (strokes: Int, vsPar: Int)? {
        guard activeRoundContext.isLoaded else { return nil }
        var strokes = 0
        var parSum = 0
        for h in activeRoundContext.activeHoleRange {
            if let s = roundViewModel.scores[h], s > 0 {
                strokes += s
                if let p = activeRoundContext.hole(for: h)?.par { parSum += p }
            }
        }
        guard strokes > 0, parSum > 0 else { return nil }
        return (strokes, strokes - parSum)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if let err = activeRoundContext.loadError, !activeRoundContext.isLoaded {
                roundLoadFailedView(message: err)
            } else if !activeRoundContext.isLoaded {
                roundLoadingView
            } else {
                fullScreenRoundView
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(activeRoundContext.isLoaded)
        .sheet(isPresented: $showingEditSheet) { editRoundSheet }
        .sheet(isPresented: $showingPhotoLie) { photoLieSheet }
        .sheet(item: $photoCaptureWrapper) { wrapper in photoCaptureSheet(wrapper: wrapper) }
        .onChange(of: showingPhotoCapture) { _, newValue in
            if let shotType = newValue {
                photoCaptureWrapper = ShotTypeWrapper(shotType: shotType)
            } else {
                photoCaptureWrapper = nil
            }
        }
        .sheet(isPresented: $showingGreenView) { greenViewSheet }
        .sheet(isPresented: $showingRoundSummary) { roundSummarySheet }
        .sheet(isPresented: $showingRoundCaddieCamera) {
            CaddieCameraCaptureView(
                onCancel: {
                    showingRoundCaddieCamera = false
                    roundCaddieIntent = .idle
                },
                onCaptured: { image in
                    showingRoundCaddieCamera = false
                    roundCaddieVM.setPhoto(image)
                    let isPutt: Bool
                    if case .putting = roundCaddieIntent { isPutt = true } else { isPutt = false }
                    applyRoundCaddiePrefill(putting: isPutt)

                    if isPutt {
                        Task {
                            await roundCaddieVM.getPuttingRecommendation(
                                profile: profileViewModel.profile,
                                draft: roundContextDraft
                            )
                        }
                    } else {
                        showingRoundContextSheet = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingRoundContextSheet) {
            ContextConfirmSheet(
                draft: $roundContextDraft,
                confidence: .high,
                hasPhoto: roundCaddieVM.currentPhoto != nil,
                isSubmitting: roundCaddieVM.requestState.isSubmitting,
                onGetRecommendation: {
                    guard !roundCaddieVM.requestState.isSubmitting else { return }
                    Task {
                        switch roundCaddieIntent {
                        case .fullShot:
                            await roundCaddieVM.getShotRecommendation(
                                profile: profileViewModel.profile,
                                draft: roundContextDraft
                            )
                        case .putting:
                            await roundCaddieVM.getPuttingRecommendation(
                                profile: profileViewModel.profile,
                                draft: roundContextDraft
                            )
                        case .idle:
                            break
                        }
                        if roundCaddieVM.recommendationResult != nil {
                            showingRoundContextSheet = false
                        }
                    }
                },
                roundContextMode: true,
                photoOptional: roundContextDraft.quickModeNoPhoto,
                isPuttingFlow: roundContextIsPuttingFlow
            )
            .interactiveDismissDisabled(roundCaddieVM.requestState.isSubmitting)
        }
        .sheet(isPresented: Binding(
            get: { roundCaddieVM.recommendationResult != nil },
            set: { if !$0 { roundCaddieVM.newShot() } }
        )) {
            if let result = roundCaddieVM.recommendationResult {
                CaddieRecommendationOverlay(
                    result: result,
                    shotContext: roundCaddieVM.lastShotContext,
                    course: roundCaddieVM.currentCourse,
                    recommendationId: roundCaddieVM.lastRecommendationId,
                    recommendationType: roundCaddieVM.lastRecommendationType,
                    onSaveAndNext: { _ in roundCaddieVM.newShot() },
                    onClose: { roundCaddieVM.newShot() }
                )
                .environmentObject(feedbackService)
            }
        }
        .confirmationDialog("Caddie recommendation", isPresented: $showFullShotModePicker, titleVisibility: .visible) {
            Button("Photo mode") {
                roundCaddieIntent = .fullShot(photo: true)
                roundContextDraft.quickModeNoPhoto = false
                showingRoundCaddieCamera = true
            }
            Button("Quick mode (no photo)") {
                roundCaddieIntent = .fullShot(photo: false)
                roundCaddieVM.setPhoto(nil)
                roundContextDraft.quickModeNoPhoto = true
                applyRoundCaddiePrefill()
                showingRoundContextSheet = true
            }
            Button("Cancel", role: .cancel) { roundCaddieIntent = .idle }
        }
        .confirmationDialog("Putting read", isPresented: $showPuttingModePicker, titleVisibility: .visible) {
            Button("Photo mode") {
                roundCaddieIntent = .putting(photo: true)
                roundContextDraft.quickModeNoPhoto = false
                showingRoundCaddieCamera = true
            }
            Button("Quick mode (no photo)") {
                roundCaddieIntent = .putting(photo: false)
                roundCaddieVM.setPhoto(nil)
                roundContextDraft.quickModeNoPhoto = true
                applyRoundCaddiePrefill(putting: true)
                // Putting quick mode: skip context confirm, go straight to recommendation
                Task {
                    await roundCaddieVM.getPuttingRecommendation(
                        profile: profileViewModel.profile,
                        draft: roundContextDraft
                    )
                }
            }
            Button("Cancel", role: .cancel) { roundCaddieIntent = .idle }
        }
        .overlay {
            if roundCaddieVM.requestState.isSubmitting {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    LoadingView(message: "Analyzing your shot…")
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { roundCaddieVM.errorMessage != nil },
            set: { if !$0 { roundCaddieVM.errorMessage = nil } }
        )) {
            Button("Try Again") {
                Task {
                    await roundCaddieVM.retryLastRequest()
                    if roundCaddieVM.recommendationResult != nil {
                        showingRoundContextSheet = false
                    }
                }
            }
            Button("Dismiss", role: .cancel) { roundCaddieVM.errorMessage = nil }
        } message: {
            if let msg = roundCaddieVM.errorMessage { Text(msg) }
        }
        .onAppear {
            if course.name.isEmpty {
                scoreTrackingService.setPhase(.selectingCourse)
                dismiss()
                return
            }
            if scoreTrackingService.phase != .inProgress,
               scoreTrackingService.currentRound != nil {
                scoreTrackingService.setPhase(.inProgress)
            }
            roundViewModel.historyStore = historyStore
            roundViewModel.activeRoundContext = activeRoundContext
            roundCaddieVM.historyStore = historyStore
            let persistedRL = scoreTrackingService.currentRound?.persistedRoundLength
            handleOnAppear()
            mapDebouncedUserCoordinate = locationService.coordinate
            activeRoundContext.prepareForSession(launch: launchConfig, persistedRoundLength: persistedRL)
            holeDetectionEngine.bind(activeRoundContext)

            // Start continuous location tracking for live distance
            locationService.startContinuousUpdating()

            Task {
                let persistedTeeId = scoreTrackingService.currentRound?.selectedTeeId
                await activeRoundContext.startRound(
                    courseId: course.id,
                    courseDisplayName: course.displayName,
                    launch: launchConfig,
                    resumeHole: roundViewModel.currentHole,
                    persistedRoundLength: launchConfig == nil ? persistedRL : nil,
                    persistedTeeId: launchConfig == nil ? persistedTeeId : nil
                )
            }
        }
        .onDisappear {
            locationService.stopContinuousUpdating()
        }
        .onChange(of: roundViewModel.scores) { _, newValue in
            handleScoresChange(newValue: newValue)
        }
        .onChange(of: activeRoundContext.currentHole) { _, newHole in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                handleHoleChange(newValue: newHole)
            }
            roundViewModel.syncHoleFromContext(newHole)
            if let c = locationService.coordinate {
                activeRoundContext.updateDistances(user: c)
            }
            logRoundEngineLine()
        }
        .onChange(of: locationService.coordinateIdentifier) { _, _ in
            applyRoundEngineLocation()
            scheduleMapUserDebounce()
        }
        .onChange(of: activeRoundContext.isLoaded) { _, loaded in
            if loaded, let c = locationService.coordinate {
                activeRoundContext.updateDistances(user: c)
                logRoundEngineLine()
                persistRoundProgress(currentHole: activeRoundContext.currentHole)
            }
        }
    }

    // MARK: - Full-Screen Round View

    private var fullScreenRoundView: some View {
        ZStack {
            RoundMapView(
                holeNumber: activeRoundContext.currentHole,
                holeData: currentHoleData,
                userCoordinate: mapDebouncedUserCoordinate,
                selectedTeeSetId: activeRoundContext.selectedTee?.id
            )

            VStack(spacing: 0) {
                topHUD
                    .padding(.top, safeAreaTop + 4)

                Spacer()

                liveDistanceOverlay
                    .padding(.bottom, 8)

                HStack(alignment: .bottom, spacing: 10) {
                    bottomControlBar

                    Spacer()

                    rightCaddieStack
                }
                .padding(.horizontal, 14)
                .padding(.bottom, safeAreaBottom + 4)
            }

            VStack {
                HStack {
                    Spacer()
                    exitButton
                        .padding(.top, safeAreaTop + 8)
                        .padding(.trailing, 14)
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showScoreInput) {
            scoreInputSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
    }

    // MARK: - Safe Area Helpers

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 0
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    // MARK: - Top HUD

    private var topHUD: some View {
        HStack(spacing: 0) {
            Button {
                let range = activeRoundContext.activeHoleRange
                if displayHole > range.lowerBound {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    activeRoundContext.retreatHole()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(displayHole > activeRoundContext.activeHoleRange.lowerBound ? .white : .white.opacity(0.3))
                    .frame(width: 32, height: 44)
            }

            hudCell(top: "Hole", bottom: "\(displayHole)", accent: true)
                .frame(minWidth: 50)

            divider

            hudCell(top: activeRoundContext.selectedTee?.name ?? "Yds", bottom: teeYardage)
                .frame(minWidth: 64)

            divider

            hudCell(top: "Par", bottom: resolvedHolePar.map { "\($0)" } ?? "—")
                .frame(minWidth: 50)

            divider

            hudCell(top: "HCP", bottom: holeHandicap.map { "\($0)" } ?? "—")
                .frame(minWidth: 50)

            Button {
                let range = activeRoundContext.activeHoleRange
                if displayHole < range.upperBound {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    activeRoundContext.advanceHole()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(displayHole < activeRoundContext.activeHoleRange.upperBound ? .white : .white.opacity(0.3))
                    .frame(width: 32, height: 44)
            }
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.72))
        )
        .padding(.horizontal, 16)
    }

    private func hudCell(top: String, bottom: String, accent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(top)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
            Text(bottom)
                .font(.system(size: accent ? 22 : 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.vertical, 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 28)
    }

    // MARK: - Live Distance Overlay (glassmorphism)

    private var liveDistanceOverlay: some View {
        Group {
            if let d = liveDistanceYards {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)

                    HStack(spacing: 4) {
                        Text("\(d)")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())

                        Text("yds")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .offset(y: 2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                }
                .fixedSize()
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: liveDistanceYards)
    }

    // MARK: - Bottom Control Bar

    private var bottomControlBar: some View {
        HStack(spacing: 12) {
            scoreboardButton
            enterScoreButton
        }
    }

    private var scoreboardButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            showingEditSheet = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "list.number")
                    .font(.system(size: 18, weight: .semibold))
                Text("Scorecard")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(width: 64, height: 52)
            .background(Circle().fill(Color.black.opacity(0.55)))
        }
    }

    private var enterScoreButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            showScoreInput = true
        } label: {
            HStack(spacing: 8) {
                holeScoreIndicator
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hole \(displayHole)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Enter Score")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color(red: 0.1, green: 0.5, blue: 0.95))
            )
            .shadow(color: Color.blue.opacity(0.4), radius: 6, y: 2)
        }
    }

    @ViewBuilder
    private var holeScoreIndicator: some View {
        if let score = roundViewModel.scores[displayHole], score > 0,
           let par = resolvedHolePar {
            let diff = score - par
            let color: Color = diff < 0 ? .red : diff == 0 ? .green : .orange
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)
                Text("\(score)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        } else {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 18))
        }
    }

    // MARK: - Right Caddie Stack (Always Visible)

    private var rightCaddieStack: some View {
        VStack(spacing: 6) {
            caddieButton(icon: "camera.fill", label: "Full Shot", color: GolfTheme.grassGreen) {
                showFullShotModePicker = true
            }
            caddieButton(icon: "bolt.fill", label: "Quick", color: .orange) {
                triggerQuickShot()
            }
            caddieButton(icon: "flag.fill", label: "Putt", color: .blue) {
                showPuttingModePicker = true
            }
        }
    }

    private func caddieButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(color)
            )
            .shadow(color: color.opacity(0.4), radius: 4, y: 2)
        }
    }

    // MARK: - Exit Button

    @State private var showExitWithoutSaveConfirm = false

    private var exitButton: some View {
        Menu {
            Button {
                persistRoundProgress(currentHole: displayHole)
                locationService.stopContinuousUpdating()
                dismiss()
            } label: {
                Label("Save & Exit", systemImage: "arrow.uturn.left")
            }
            Button(role: .destructive) {
                scoreTrackingService.saveRoundFromViewModel(
                    courseName: course.displayName,
                    courseTotalPar: resolvedCourseTotalPar,
                    scores: roundViewModel.scores,
                    roundViewModel: roundViewModel,
                    holePars: holeParMapForPersistence()
                )
                scoreTrackingService.completeRound()
                locationService.stopContinuousUpdating()
                showingRoundSummary = true
            } label: {
                Label("Finish Round", systemImage: "flag.checkered")
            }
            Button(role: .destructive) {
                showExitWithoutSaveConfirm = true
            } label: {
                Label("Exit Without Saving", systemImage: "trash")
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .alert("Discard Round?", isPresented: $showExitWithoutSaveConfirm) {
            Button("Discard", role: .destructive) {
                scoreTrackingService.clearCurrentRound()
                locationService.stopContinuousUpdating()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This round will not be saved, and no scores or recommendations from this session will be included in your history or analytics.")
        }
    }

    // MARK: - Score Input Sheet

    private var scoreInputSheet: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hole \(displayHole)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    if let par = resolvedHolePar {
                        Text("Par \(par)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if let progress = roundProgressSummary {
                    let vsStr = progress.vsPar == 0 ? "E" : (progress.vsPar > 0 ? "+\(progress.vsPar)" : "\(progress.vsPar)")
                    Text("\(progress.strokes) (\(vsStr))")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(progress.vsPar <= 0 ? GolfTheme.grassGreen : .orange)
                }
            }
            .padding(.horizontal, 4)

            scoreGrid

            if displayHole >= activeRoundContext.activeHoleRange.upperBound {
                Button {
                    showScoreInput = false
                    scoreTrackingService.saveRoundFromViewModel(
                        courseName: course.displayName,
                        courseTotalPar: resolvedCourseTotalPar,
                        scores: roundViewModel.scores,
                        roundViewModel: roundViewModel,
                        holePars: holeParMapForPersistence()
                    )
                    scoreTrackingService.completeRound()
                    showingRoundSummary = true
                } label: {
                    Text("Finish Round")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(GolfTheme.grassGreen)
                        .cornerRadius(12)
                }
            } else {
                HStack(spacing: 16) {
                    Text("Hole \(displayHole)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Spacer()

                    Button {
                        showScoreInput = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            activeRoundContext.advanceHole()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Next Hole")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(GolfTheme.grassGreen)
                    }
                }
            }
        }
        .padding(20)
    }

    private var scoreGrid: some View {
        let par = resolvedHolePar ?? 4
        let scores = Array(max(par - 2, 1)...min(par + 4, 12))

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(scores, id: \.self) { score in
                let isSelected = roundViewModel.scores[displayHole] == score
                let diff = score - par
                let label: String? = diff == -2 ? "Eagle" : diff == -1 ? "Birdie" : diff == 0 ? "Par" : diff == 1 ? "Bogey" : diff == 2 ? "Dbl" : nil

                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    roundViewModel.setScore(score, forHole: displayHole)
                } label: {
                    VStack(spacing: 3) {
                        Text("\(score)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        if let label {
                            Text(label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isSelected ? scoreColor(diff: diff) : Color(.systemGray6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? scoreColor(diff: diff) : Color(.systemGray4), lineWidth: isSelected ? 0 : 1)
                    )
                    .foregroundColor(isSelected ? .white : .primary)
                }
            }
        }
    }

    private func scoreColor(diff: Int) -> Color {
        if diff <= -2 { return .red }
        if diff == -1 { return Color(red: 0.9, green: 0.2, blue: 0.2) }
        if diff == 0 { return GolfTheme.grassGreen }
        if diff == 1 { return .orange }
        return Color(red: 0.6, green: 0.4, blue: 0.2)
    }

    // MARK: - Loading / Error States

    private var roundLoadingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)
                Text("Loading course…")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Text(course.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func roundLoadFailedView(message: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Couldn't load course")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button("Close") { dismiss() }
                    .foregroundColor(GolfTheme.grassGreen)
                    .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - Sheets (Preserved)

    private var editRoundSheet: some View {
        EditRoundSheet(
            currentCourse: course,
            currentHole: Binding(
                get: { activeRoundContext.currentHole },
                set: { activeRoundContext.setCurrentHoleManual($0) }
            ),
            allowedHoleRange: activeRoundContext.activeHoleRange,
            onCourseChange: { showingEditSheet = false }
        )
        .environmentObject(courseViewModel)
        .environmentObject(locationService)
    }

    private var photoLieSheet: some View {
        PhotoLieView(
            course: course,
            holeNumber: displayHole
        )
        .environmentObject(locationService)
        .environmentObject(profileViewModel)
        .environmentObject(historyStore)
    }

    private func photoCaptureSheet(wrapper: ShotTypeWrapper) -> some View {
        PhotoCaptureView(
            course: course,
            holeNumber: displayHole,
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
            holeNumber: displayHole
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

    // MARK: - Lifecycle Handlers (Preserved)

    private func handleOnAppear() {
        if launchConfig == nil,
           scoreTrackingService.phase == .inProgress,
           let inProgressRound = scoreTrackingService.currentRound,
           roundsMatchForResume(inProgressRound) {
            let savedScores = Dictionary(uniqueKeysWithValues: inProgressRound.holes.map { ($0.holeNumber, $0.strokes) })
            let range = inProgressRound.persistedRoundLength?.holeRange ?? 1...18
            let inSubset = inProgressRound.holes.filter { range.contains($0.holeNumber) }
            let savedHole: Int
            if let ch = inProgressRound.currentHoleNumber, range.contains(ch) {
                savedHole = ch
            } else if let firstOpen = inSubset.first(where: { $0.strokes == 0 })?.holeNumber {
                savedHole = firstOpen
            } else {
                savedHole = range.lowerBound
            }
            roundViewModel.resumeRound(
                course: course,
                savedScores: savedScores,
                savedHole: savedHole,
                savedShots: [:]
            )
        } else {
            roundViewModel.startRound(course: course)
            scoreTrackingService.startNewRound(
                courseId: course.id,
                courseName: course.displayName,
                par: course.par,
                teeId: launchConfig?.selectedTeeId,
                roundLength: launchConfig?.roundLength ?? .full18,
                courseRating: activeRoundContext.courseRating,
                slopeRating: activeRoundContext.slopeRating
            )
        }
    }

    private func roundsMatchForResume(_ inProgress: Round) -> Bool {
        if let cid = inProgress.courseId, !cid.isEmpty {
            return cid == course.id
        }
        return inProgress.courseName == course.displayName
    }

    private func holeParMapForPersistence() -> [Int: Int] {
        if activeRoundContext.isLoaded {
            var m: [Int: Int] = [:]
            for h in activeRoundContext.holes { m[h.holeNumber] = h.par }
            return m
        }
        return Dictionary(uniqueKeysWithValues: (scoreTrackingService.currentRound?.holes ?? []).compactMap { h in
            guard let p = h.par else { return nil }
            return (h.holeNumber, p)
        })
    }

    private func applyRoundCaddiePrefill(putting: Bool = false) {
        let hole = displayHole
        let dist = activeRoundContext.distances?.center
        let holeData = activeRoundContext.hole(for: hole)
        let par = holeData?.par
        let cid = course.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let backendId = cid.isEmpty ? nil : cid
        let nm = activeRoundContext.courseName.isEmpty ? course.name : activeRoundContext.courseName
        roundContextDraft.course = Course(id: course.id, name: nm, par: course.par)
        roundContextDraft.courseName = nm
        roundContextDraft.holeNumber = hole
        roundContextDraft.distanceYards = dist
        roundContextDraft.holePar = par
        roundContextDraft.courseId = backendId
        roundContextDraft.teeName = activeRoundContext.selectedTee?.name
        roundContextDraft.isRoundBackedContext = backendId != nil
        roundContextDraft.city = activeRoundContext.courseCity
        roundContextDraft.state = activeRoundContext.courseState
        roundContextDraft.shotType = putting ? .putt : inferredShotType
        roundContextDraft.lie = putting ? "Green" : (roundContextDraft.lie ?? "Fairway")

        let hazards = holeData?.hazardDescriptions ?? []
        if !hazards.isEmpty {
            roundContextDraft.hazards = hazards.joined(separator: ", ")
        }
    }

    /// Quick Shot: auto-filled context → verify sheet → 1-tap confirm.
    private func triggerQuickShot() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        roundCaddieIntent = .fullShot(photo: false)
        roundCaddieVM.setPhoto(nil)
        roundContextDraft.quickModeNoPhoto = true
        applyRoundCaddiePrefill()
        showingRoundContextSheet = true
    }

    private func persistRoundProgress(currentHole hole: Int) {
        let teeId = activeRoundContext.isLoaded ? activeRoundContext.selectedTee?.id : scoreTrackingService.currentRound?.selectedTeeId
        let length = activeRoundContext.isLoaded ? activeRoundContext.roundLength : scoreTrackingService.currentRound?.persistedRoundLength
        scoreTrackingService.updateCurrentRound(
            courseId: course.id.isEmpty ? nil : course.id,
            courseName: course.displayName,
            courseTotalPar: resolvedCourseTotalPar,
            scores: roundViewModel.scores,
            currentHole: hole,
            teeId: teeId,
            roundLength: length,
            holePars: holeParMapForPersistence()
        )
    }

    private func handleScoresChange(newValue: [Int: Int]) {
        persistRoundProgress(currentHole: displayHole)
    }

    private func handleHoleChange(newValue: Int) {
        persistRoundProgress(currentHole: newValue)
    }

    private func applyRoundEngineLocation() {
        guard let c = locationService.coordinate else { return }
        activeRoundContext.updateDistances(user: c)
        holeDetectionEngine.processLocation(c) { _ in }
        logRoundEngineLine()
    }

    private func logRoundEngineLine() {
        guard activeRoundContext.isLoaded else { return }
        let y = activeRoundContext.distances.map { Int(round($0.center)) } ?? 0
        print("[ROUND] Hole: \(activeRoundContext.currentHole) | Distance: \(y) yards")
    }

    private func scheduleMapUserDebounce() {
        mapUserDebounceTask?.cancel()
        mapUserDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 550_000_000)
            await MainActor.run {
                mapDebouncedUserCoordinate = locationService.coordinate
            }
        }
    }

    private func sendFeedback(helpful: Bool, recommendation: ShotRecommendation) async {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        await roundViewModel.sendFeedback(helpful: helpful)
        await feedbackService.sendCaddieFeedback(
            courseId: course.id,
            hole: displayHole,
            clubSuggested: recommendation.club,
            userFeedback: helpful ? "helpful" : "off"
        )
        let feedback = ShotFeedback(
            courseName: course.name,
            courseId: course.id,
            holeNumber: displayHole,
            clubSuggested: recommendation.club,
            userRating: helpful
        )
        feedbackService.recordFeedback(feedback)
    }
}

struct ShotTypeWrapper: Identifiable {
    let id = UUID()
    let shotType: ShotType
}

#Preview {
    RoundPlayView(course: Course(name: "Preview Course", par: nil))
        .environmentObject(LocationService.shared)
        .environmentObject(ScoreTrackingService.shared)
        .environmentObject(FeedbackService.shared)
        .environmentObject(HistoryStore())
        .environmentObject(ProfileViewModel())
}
