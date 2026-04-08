//
//  HomeView.swift
//  Caddie.ai
//

import SwiftUI
import CoreLocation
import Charts

struct HomeView: View {
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    @EnvironmentObject var courseService: CourseService
    @EnvironmentObject var feedbackService: FeedbackService
    @EnvironmentObject var historyStore: HistoryStore
    @StateObject private var courseViewModel = CourseViewModel()
    @StateObject private var homeViewModel = HomeViewModel()
    
    @State private var showingCourseSelection = false
    @State private var showingRoundPlay = false
    @State private var showingRoundSetup = false
    @State private var pendingRoundLaunch: RoundPlayLaunchConfig?
    @State private var showingStats = false
    @State private var showingAITip = false
    @State private var showingCourseIntelligence = false
    @State private var weather: WeatherSnapshot?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Personalized Greeting with Weather
                    greetingCard
                    
                    // Resume Round Banner (if in-progress round exists)
                    if let inProgressRound = scoreTrackingService.currentRound {
                        resumeRoundBanner(round: inProgressRound)
                    }
                    
                    // Quick Actions
                    quickActionsSection
                    
                    // AI Insights Card
                    if let lastRound = scoreTrackingService.rounds.last {
                        aiInsightsCard(round: lastRound)
                    }
                    
                    // Performance Trend Graph
                    if !scoreTrackingService.rounds.isEmpty {
                        performanceTrendCard
                    }
                    
                    // Backend health check banner
                    if case .error(let message) = courseViewModel.nearbyCoursesState,
                       message.contains("Backend offline") || message.contains("Could not connect to server") {
                        backendOfflineBanner
                    }
                    
                    // Recommended Course Section
                    recommendedCourseSection
                    
                    // Location fallback banner
                    if locationService.authorizationStatus == .denied ||
                        locationService.authorizationStatus == .restricted ||
                        locationService.authorizationStatus == .notDetermined {
                        locationFallbackBanner
                    }
                }
                .padding(.vertical)
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Caddie.AI")
            .onAppear {
                // Defensive redirect: If round is in progress, redirect to RoundPlayView
                if scoreTrackingService.phase == .inProgress,
                   let currentRound = scoreTrackingService.currentRound {
                    let course = currentRound.resolvedCourse()
                    courseViewModel.selectCourse(course)
                    pendingRoundLaunch = nil
                    showingRoundPlay = true
                    return
                }
                
                // Defensive redirect: If in summary phase, prepare for summary view
                if scoreTrackingService.phase == .summary,
                   let _ = scoreTrackingService.currentRound {
                    // Summary will be handled by RoundPlayView or a separate summary flow
                    // For now, just reset phase if summary was dismissed
                    if showingRoundPlay == false {
                        // Summary was dismissed, reset phase
                        scoreTrackingService.clearCurrentRound()
                    }
                }
                
                setupHomeView()
            }
            .onChange(of: locationService.authorizationStatus) { oldValue, newValue in
                if newValue == .authorizedWhenInUse || newValue == .authorizedAlways {
                    locationService.startUpdating()
                    Task {
                        var attempts = 0
                        while locationService.coordinate == nil && attempts < 10 {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            attempts += 1
                        }
                        if let coordinate = locationService.coordinate {
                            await fetchWeatherAndCourses(coordinate: coordinate)
                        }
                    }
                }
            }
            .onChange(of: locationService.coordinate?.latitude) { oldValue, newValue in
                if let coordinate = locationService.coordinate {
                    Task {
                        await fetchWeatherAndCourses(coordinate: coordinate)
                    }
                }
            }
            .sheet(isPresented: $showingCourseSelection) {
                CourseSelectionView()
                    .environmentObject(courseViewModel)
                    .environmentObject(locationService)
            }
            .sheet(isPresented: $showingStats) {
                StatsView()
            }
            .sheet(isPresented: $showingAITip) {
                AITipSheet(tip: homeViewModel.aiTip)
            }
            .sheet(isPresented: $showingCourseIntelligence) {
                CourseIntelligenceView()
                    .environmentObject(courseService)
                    .environmentObject(profileViewModel)
                    .environmentObject(locationService)
            }
            .sheet(isPresented: $showingRoundSetup) {
                if let course = courseViewModel.currentCourse {
                    RoundPlaySetupSheet(course: course) { config in
                        pendingRoundLaunch = config
                        scoreTrackingService.setPhase(.inProgress)
                        showingRoundPlay = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showingRoundPlay) {
                if let course = courseViewModel.currentCourse ?? getCourseFromCurrentRound() {
                    RoundPlayView(
                        course: course,
                        launchConfig: pendingRoundLaunch,
                        onRoundComplete: {
                            scoreTrackingService.completeRound()
                            pendingRoundLaunch = nil
                            showingRoundPlay = false
                        }
                    )
                    .environmentObject(locationService)
                    .environmentObject(profileViewModel)
                    .environmentObject(scoreTrackingService)
                    .environmentObject(feedbackService)
                    .environmentObject(historyStore)
                } else {
                    CourseSelectionView()
                        .environmentObject(courseViewModel)
                        .environmentObject(locationService)
                        .onDisappear {
                            if scoreTrackingService.phase == .selectingCourse,
                               courseViewModel.currentCourse != nil {
                                showingRoundSetup = true
                            }
                        }
                }
            }
        }
    }
    
    // MARK: - Greeting Card
    
    private var greetingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(GolfTheme.titleFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    
                    if !profileViewModel.profile.name.isEmpty {
                        Text(profileViewModel.profile.name)
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.grassGreen)
                    }
                }
                
                Spacer()
                
                if let weather = weather {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.sun")
                                .foregroundColor(GolfTheme.accentGold)
                            Text("\(Int(weather.tempF))°F")
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "wind")
                                .foregroundColor(GolfTheme.textSecondary)
                                .font(.caption)
                            Text("\(Int(weather.windMph)) mph")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [GolfTheme.grassGreen.opacity(0.1), GolfTheme.cream],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good Morning"
        } else if hour < 17 {
            return "Good Afternoon"
        } else {
            return "Good Evening"
        }
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
            HStack(spacing: 12) {
                ActionButton(
                    icon: "flag.fill",
                    title: "Start Round",
                    color: GolfTheme.grassGreen,
                    action: {
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            
                        if courseViewModel.currentCourse != nil {
                            showingRoundSetup = true
                        } else {
                            showingCourseSelection = true
                        }
                    }
                )
                
                ActionButton(
                    icon: "chart.bar.fill",
                    title: "View Stats",
                    color: GolfTheme.accentGold,
                    action: {
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            
                        showingStats = true
                    }
                )
                }
                
                HStack(spacing: 12) {
                    ActionButton(
                        icon: "brain.head.profile",
                        title: "Course Intelligence",
                        color: Color.blue,
                        action: {
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            
                            showingCourseIntelligence = true
                        }
                    )
                
                ActionButton(
                    icon: "lightbulb.fill",
                    title: "AI Tip",
                    color: Color.blue,
                    action: {
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            
                        homeViewModel.refreshAITip()
                        showingAITip = true
                    }
                )
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - AI Insights Card
    
    private func aiInsightsCard(round: Round) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(GolfTheme.accentGold)
                    .font(.title3)
                Text("AI Insights")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            let stats = calculateRoundStats(round: round)
            
            VStack(spacing: 12) {
                StatRow(
                    icon: "arrow.up.circle.fill",
                    label: "Fairways Hit",
                    value: "\(stats.fairwaysHit)%",
                    color: GolfTheme.grassGreen
                )
                
                StatRow(
                    icon: "target",
                    label: "Putting Average",
                    value: String(format: "%.1f", stats.puttingAverage),
                    color: GolfTheme.accentGold
                )
                
                if let bestClub = stats.bestClub {
                    StatRow(
                        icon: "star.fill",
                        label: "Best Club",
                        value: bestClub,
                        color: Color.orange
                    )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    // MARK: - Performance Trend
    
    private var performanceTrendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(GolfTheme.grassGreen)
                    .font(.title3)
                Text("Performance Trend")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            let recentRounds = Array(scoreTrackingService.rounds.suffix(5))
            if !recentRounds.isEmpty {
                Chart {
                    ForEach(Array(recentRounds.enumerated()), id: \.element.id) { index, round in
                        LineMark(
                            x: .value("Round", index + 1),
                            y: .value("Score", round.totalScore)
                        )
                        .foregroundStyle(GolfTheme.grassGreen)
                        .interpolationMethod(.catmullRom)
                        
                        PointMark(
                            x: .value("Round", index + 1),
                            y: .value("Score", round.totalScore)
                        )
                        .foregroundStyle(GolfTheme.grassGreen)
                        .symbolSize(60)
                    }
                }
                .frame(height: 150)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 1)) { value in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    // MARK: - Recommended Course Section
    
    private var recommendedCourseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(GolfTheme.grassGreen)
                Text("Recommended Courses")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            .padding(.horizontal)
            
            if courseViewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(GolfTheme.grassGreen)
                    Spacer()
                }
                .padding()
            } else if !courseViewModel.nearbyCourses.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(courseViewModel.nearbyCourses.prefix(3)) { course in
                            HomeCourseCard(course: course) {
                                courseViewModel.selectCourse(course)
                                showingRoundSetup = true
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 8)
            } else if case .error(let message) = courseViewModel.nearbyCoursesState {
                // Show error state
                if message.contains("Backend offline") || message.contains("Could not connect to server") {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text(message)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else if message.contains("Waiting for GPS") {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(GolfTheme.grassGreen)
                        Text("Waiting for GPS…")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    // Other error
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text(message)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "location.slash")
                        .font(.title2)
                        .foregroundColor(GolfTheme.textSecondary)
                    
                    if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                        Text("Location disabled. Enable in Settings.")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("Enable in Settings")
                            }
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(.white)
                            .padding()
                            .background(GolfTheme.grassGreen)
                            .cornerRadius(10)
                        }
                    } else if locationService.authorizationStatus == .notDetermined {
                        Text("Enable location to find nearby courses")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {
                            locationService.requestAuthorization()
                        }) {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("Enable Location")
                            }
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(.white)
                            .padding()
                            .background(GolfTheme.grassGreen)
                            .cornerRadius(10)
                        }
                    } else {
                        Text("Waiting for GPS…")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getCourseFromCurrentRound() -> Course? {
        scoreTrackingService.currentRound.map { $0.resolvedCourse() }
    }
    
    private func setupHomeView() {
        courseViewModel.loadCurrentCourse()
        
        // Check backend health first
        Task {
            do {
                let isHealthy = try await APIService.shared.checkHealth()
                courseViewModel.backendHealthCheck = isHealthy
            } catch {
                courseViewModel.backendHealthCheck = false
                print("Backend health check failed: \(error.localizedDescription)")
            }
        }
        
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestAuthorization()
        }
        
        if locationService.authorizationStatus == .authorizedWhenInUse ||
           locationService.authorizationStatus == .authorizedAlways {
            locationService.startUpdating()
            
            Task {
                // Wait for location (up to 5 seconds)
                var attempts = 0
                while locationService.coordinate == nil && attempts < 10 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    attempts += 1
                }
                
                if let coordinate = locationService.coordinate {
                    await fetchWeatherAndCourses(coordinate: coordinate)
                } else if locationService.hasValidLocation == false {
                    // Still waiting for GPS
                    print("Still waiting for GPS location...")
                }
            }
        }
        
        homeViewModel.refreshAITip()
    }
    
    private func fetchWeatherAndCourses(coordinate: CLLocationCoordinate2D) async {
        async let weatherTask = fetchWeather(at: coordinate)
        
        weather = await weatherTask
        await courseViewModel.fetchNearbyCourses(at: coordinate)
    }
    
    private func fetchWeather(at coordinate: CLLocationCoordinate2D) async -> WeatherSnapshot {
        do {
            return try await WeatherService.shared.fetchWeather(at: coordinate)
        } catch {
            return WeatherSnapshot(windMph: 0, windDirDeg: 0, tempF: 72)
        }
    }
    
    private func calculateRoundStats(round: Round) -> RoundStats {
        let fairwayHoles = round.holes.filter { $0.fairwayHit == true }.count
        let totalFairwayHoles = round.holes.filter { $0.fairwayHit != nil }.count
        let fairwaysHit = totalFairwayHoles > 0 ? (Double(fairwayHoles) / Double(totalFairwayHoles)) * 100 : 0
        
        let totalPutts = round.holes.reduce(0) { $0 + $1.putts }
        let puttingAverage = round.holes.count > 0 ? Double(totalPutts) / Double(round.holes.count) : 0
        
        // Find best performing club (most accurate AI recommendations)
        let clubAccuracy: [String: (total: Int, accurate: Int)] = round.holes.reduce(into: [:]) { dict, hole in
            if let club = hole.recommendedClub {
                if dict[club] == nil {
                    dict[club] = (total: 0, accurate: 0)
                }
                dict[club]?.total += 1
                if hole.aiConfirmed {
                    dict[club]?.accurate += 1
                }
            }
        }
        
        let bestClub = clubAccuracy.max { club1, club2 in
            let accuracy1 = club1.value.total > 0 ? Double(club1.value.accurate) / Double(club1.value.total) : 0
            let accuracy2 = club2.value.total > 0 ? Double(club2.value.accurate) / Double(club2.value.total) : 0
            return accuracy1 < accuracy2
        }?.key
        
        return RoundStats(
            fairwaysHit: fairwaysHit,
            puttingAverage: puttingAverage,
            bestClub: bestClub
        )
    }
    
    // MARK: - Resume Round Banner
    
    private func resumeRoundBanner(round: Round) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundColor(GolfTheme.grassGreen)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Round In Progress")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    let range = round.persistedRoundLength?.holeRange ?? 1...18
                    let subsetHoles = round.holes.filter { range.contains($0.holeNumber) }
                    let currentHole = round.currentHoleNumber
                        ?? subsetHoles.first(where: { $0.strokes == 0 })?.holeNumber
                        ?? subsetHoles.map(\.holeNumber).max()
                        ?? range.lowerBound
                    Text("\(round.courseName) • Hole \(currentHole)")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    let course = round.resolvedCourse()
                    courseViewModel.selectCourse(course)
                    pendingRoundLaunch = nil
                    showingRoundPlay = true
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Resume Round")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(GolfTheme.grassGreen)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    // Finalize round (save as-is)
                    if scoreTrackingService.currentRound != nil {
                        // Use endRound to properly finalize and save
                        _ = scoreTrackingService.endRound()
                        // Round is already added to rounds array by endRound()
                        scoreTrackingService.saveRounds()
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Finalize")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.grassGreen)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(GolfTheme.grassGreen.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [GolfTheme.grassGreen.opacity(0.1), GolfTheme.cream],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
    
    // MARK: - Backend Offline Banner
    
    private var backendOfflineBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backend offline")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    Text("Start Node server at port 8080.")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Location Fallback Banner
    
    private var locationFallbackBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "location.slash.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Turn on Location")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    Text("Turn on Location to get course-aware recommendations and real-time AI guidance.")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                switch locationService.authorizationStatus {
                case .denied, .restricted:
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                default:
                    locationService.requestAuthorization()
                }
            }) {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Enable Location")
                }
                .font(GolfTheme.bodyFont)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(GolfTheme.grassGreen)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                action()
            }
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text(title)
                    .font(GolfTheme.captionFont)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color)
            .cornerRadius(12)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: color.opacity(0.3), radius: isPressed ? 4 : 8, x: 0, y: isPressed ? 2 : 4)
        }
        .buttonStyle(.plain)
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(label)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
        }
    }
}

struct HomeCourseCard: View {
    let course: Course
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                action()
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(course.displayName)
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .lineLimit(2)
                
                if let par = course.par {
                    Text("Par \(par)")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
            }
            .frame(width: 200, alignment: .leading)
            .padding()
            .background(GolfTheme.cream)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(GolfTheme.grassGreen.opacity(0.3), lineWidth: 2)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: Color.black.opacity(isPressed ? 0.05 : 0.1), radius: isPressed ? 4 : 8, x: 0, y: isPressed ? 2 : 4)
        }
        .buttonStyle(.plain)
    }
}

struct AITipSheet: View {
    let tip: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 60))
                    .foregroundColor(GolfTheme.accentGold)
                
                Text("AI Tip of the Day")
                    .font(GolfTheme.titleFont)
                    .foregroundColor(GolfTheme.textPrimary)
                
                Text(tip)
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle("AI Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(GolfTheme.grassGreen)
                }
            }
        }
    }
}

// MARK: - Supporting Models

struct RoundStats {
    let fairwaysHit: Double
    let puttingAverage: Double
    let bestClub: String?
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var aiTip: String = "Practice your putting stroke regularly to improve consistency on the greens."
    
    private let tips = [
        "Focus on your tempo - a smooth, consistent swing often beats raw power.",
        "Read the green from behind the ball, not just from the side.",
        "Keep your head still throughout the swing to maintain balance and accuracy.",
        "Practice your short game - it's where you can save the most strokes.",
        "Use the wind to your advantage - don't fight it, work with it.",
        "Visualize your shot before you hit it - see the ball's flight path.",
        "Stay relaxed and breathe - tension leads to poor shots.",
        "Practice your putting stroke regularly to improve consistency on the greens.",
        "Choose the right club for the distance - don't try to muscle it.",
        "Follow through completely - a full finish helps with accuracy."
    ]
    
    func refreshAITip() {
        aiTip = tips.randomElement() ?? tips[0]
    }
}

#Preview {
    HomeView()
        .environmentObject(LocationService.shared)
        .environmentObject(ProfileViewModel())
        .environmentObject(ScoreTrackingService.shared)
        .environmentObject(CourseService.shared)
        .environmentObject(FeedbackService.shared)
        .environmentObject(HistoryStore())
}
