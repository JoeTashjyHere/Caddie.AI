//
//  PlayView.swift
//  Caddie.ai
//

import SwiftUI
import CoreLocation

struct PlayView: View {
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    @EnvironmentObject var feedbackService: FeedbackService
    @StateObject private var courseViewModel = CourseViewModel()
    
    @State private var showingRoundPlay = false
    @State private var isRefreshing = false
    @State private var showSuccessMessage = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Selected Course Card with Start Round Button
                    if let selectedCourse = courseViewModel.currentCourse {
                        selectedCourseCard(course: selectedCourse)
                    }
                    
                    // Location fallback banner
                    if locationService.authorizationStatus == .denied || 
                       locationService.authorizationStatus == .restricted ||
                       locationService.authorizationStatus == .notDetermined {
                        locationFallbackBanner
                    }
                    
                    // Course List Section
                    if courseViewModel.nearbyCoursesState == .loading && courseViewModel.nearbyCourses.isEmpty && !isRefreshing {
                        loadingState
                    } else if shouldShowNearbyCourses {
                        nearbyCoursesSection
                    } else if shouldShowRecentCourses {
                        recentCoursesSection
                    } else {
                        emptyState
                    }
                }
                .padding(.vertical)
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Play")
            .refreshable {
                await refreshCourses()
            }
            .onAppear {
                // Defensive redirect: If round is in progress, redirect to RoundPlayView
                if scoreTrackingService.phase == .inProgress,
                   let currentRound = scoreTrackingService.currentRound {
                    let course = Course(name: currentRound.courseName, par: currentRound.par)
                    courseViewModel.selectCourse(course)
                    showingRoundPlay = true
                    return
                }
                
                // Defensive redirect: If course not selected and phase is selecting
                if scoreTrackingService.phase == .selectingCourse || courseViewModel.currentCourse == nil {
                    // This will be handled by the "Start Round" button flow
                }
                
                setupPlayView()
            }
            .onChange(of: locationService.coordinate?.latitude) { oldValue, newValue in
                if let coordinate = locationService.coordinate, shouldShowNearbyCourses {
                    Task {
                        await courseViewModel.fetchNearbyCourses(at: coordinate)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingRoundPlay) {
                // Defensive check: Ensure course exists
                if let course = courseViewModel.currentCourse ?? getCourseFromCurrentRound() {
                    RoundPlayView(
                        course: course,
                        onRoundComplete: {
                            // Round completed, move to summary phase
                            scoreTrackingService.completeRound()
                            showingRoundPlay = false
                        }
                    )
                    .environmentObject(locationService)
                    .environmentObject(profileViewModel)
                    .environmentObject(scoreTrackingService)
                    .environmentObject(feedbackService)
                } else {
                    // No course available, show course selection
                    CourseSelectionView()
                        .environmentObject(courseViewModel)
                        .environmentObject(locationService)
                        .onDisappear {
                            // After course selection, start round if course selected
                            if let course = courseViewModel.currentCourse {
                                scoreTrackingService.setPhase(.selectingCourse)
                                showingRoundPlay = true
                            }
                        }
                }
            }
                        }
                    }
                
    // MARK: - Computed Properties
    
    private var shouldShowNearbyCourses: Bool {
        locationService.authorizationStatus == .authorizedWhenInUse ||
        locationService.authorizationStatus == .authorizedAlways
    }
    
    private var shouldShowRecentCourses: Bool {
        !scoreTrackingService.rounds.isEmpty && !shouldShowNearbyCourses
    }
    
    private var recentCourses: [Course] {
        let uniqueCourseNames = Set(scoreTrackingService.rounds.map { $0.courseName })
        return uniqueCourseNames.compactMap { courseName in
            // Try to find in nearby courses first
            if let course = courseViewModel.nearbyCourses.first(where: { $0.name == courseName }) {
                return course
            }
            // Otherwise create a basic course from round data
            if let round = scoreTrackingService.rounds.first(where: { $0.courseName == courseName }) {
                return Course(name: courseName, par: round.par)
            }
            return nil
        }
    }
    
    // MARK: - Selected Course Card
    
    private func selectedCourseCard(course: Course) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Course")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                    
                    Text(course.name)
                        .font(GolfTheme.titleFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    
                    if let par = course.par {
                        Text("Par \(par)")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    courseViewModel.currentCourse = nil
                    UserDefaults.standard.removeObject(forKey: "CurrentCourse")
                    withAnimation(.spring(response: 0.3)) {
                        showSuccessMessage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            showSuccessMessage = false
                        }
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(GolfTheme.textSecondary)
                }
            }
            
            if showSuccessMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(GolfTheme.grassGreen)
                    Text("Course deselected")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.grassGreen)
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .scale))
            }
            
            PrimaryButton(
                title: "Start Round",
                action: {
                    withAnimation(.spring(response: 0.3)) {
                        showingRoundPlay = true
                    }
                                }
                            )
        }
                            .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [GolfTheme.grassGreen.opacity(0.1), GolfTheme.cream],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
                            }
                            
    // MARK: - Nearby Courses Section
    
    private var nearbyCoursesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(GolfTheme.grassGreen)
                
                Text("Nearby Courses")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
                
                Spacer()
                
                if courseViewModel.nearbyCoursesState == .loading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(GolfTheme.grassGreen)
                }
            }
            .padding(.horizontal)
            
            if courseViewModel.nearbyCourses.isEmpty && courseViewModel.nearbyCoursesState != .loading {
                VStack(spacing: 12) {
                    Image(systemName: "location.slash")
                        .font(.title2)
                        .foregroundColor(GolfTheme.textSecondary)
                    Text("No courses found nearby")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                                }
                .frame(maxWidth: .infinity)
                            .padding()
            } else {
                ForEach(courseViewModel.nearbyCourses) { course in
                    CourseCard(
                        course: course,
                        distance: calculateDistance(to: course),
                        isSelected: courseViewModel.currentCourse?.id == course.id,
                        action: {
                            selectCourse(course)
                    }
                    )
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // MARK: - Recent Courses Section
    
    private var recentCoursesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(GolfTheme.accentGold)
                
                Text("Recently Played")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await requestLocationAndFetch()
                }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                        Text("Enable Location")
                    }
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.grassGreen)
                }
            }
            .padding(.horizontal)
            
            ForEach(recentCourses) { course in
                CourseCard(
                    course: course,
                    distance: nil, // No distance for recent courses
                    isSelected: courseViewModel.currentCourse?.id == course.id,
                    action: {
                        selectCourse(course)
                    }
                )
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(GolfTheme.grassGreen)
            Text("Finding nearby courses...")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 48))
                .foregroundColor(GolfTheme.textSecondary)
            
            Text("No Courses Available")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Text("Enable location services to find nearby courses, or play a round to see recent courses here.")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                Task {
                    await requestLocationAndFetch()
                }
            }) {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Enable Location Services")
                }
                .font(GolfTheme.bodyFont)
                .foregroundColor(.white)
                .padding()
                .background(GolfTheme.grassGreen)
                .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Helper Functions
    
    private func getCourseFromCurrentRound() -> Course? {
        if let currentRound = scoreTrackingService.currentRound {
            return Course(name: currentRound.courseName, par: currentRound.par)
        }
        return nil
    }
    
    private func setupPlayView() {
        courseViewModel.loadCurrentCourse()
        
        // Request location if needed
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestAuthorization()
        }
        
        // Start location updates and fetch courses
        if shouldShowNearbyCourses {
                locationService.startUpdating()
            
            Task {
                var attempts = 0
                while locationService.coordinate == nil && attempts < 10 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    attempts += 1
                }
                
                if let coordinate = locationService.coordinate {
                    await courseViewModel.fetchNearbyCourses(at: coordinate)
                }
            }
        }
    }
    
    private func refreshCourses() async {
        isRefreshing = true
        
        defer {
            isRefreshing = false
        }
        
        if shouldShowNearbyCourses, let coordinate = locationService.coordinate {
            await courseViewModel.fetchNearbyCourses(at: coordinate)
        }
        
        // Small delay to show refresh animation
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    
    private func requestLocationAndFetch() async {
        locationService.requestAuthorization()
        
        // Wait for authorization
        var attempts = 0
        while locationService.authorizationStatus == .notDetermined && attempts < 20 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            attempts += 1
        }
        
        if shouldShowNearbyCourses {
            locationService.startUpdating()
            
            // Wait for location
            attempts = 0
            while locationService.coordinate == nil && attempts < 10 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                attempts += 1
            }
            
            if let coordinate = locationService.coordinate {
                await courseViewModel.fetchNearbyCourses(at: coordinate)
            }
        }
    }
    
    private func selectCourse(_ course: Course) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            courseViewModel.selectCourse(course)
            showSuccessMessage = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showSuccessMessage = false
            }
        }
    }
    
    private func calculateDistance(to course: Course) -> Double? {
        guard let userLocation = locationService.coordinate,
              let courseLocation = course.location?.clLocation else {
            return nil
        }
        
        let userCLLocation = CLLocation(
            latitude: userLocation.latitude,
            longitude: userLocation.longitude
        )
        let courseCLLocation = CLLocation(
            latitude: courseLocation.latitude,
            longitude: courseLocation.longitude
        )
        
        // Distance in meters, convert to miles
        let distanceMeters = userCLLocation.distance(from: courseCLLocation)
        let distanceMiles = distanceMeters / 1609.34
        
        return distanceMiles
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
                    Text("Turn on Location to get hole-by-hole AI guidance for the course you're actually on.")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                    // Open iOS Settings
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                } else {
                    // Request authorization
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
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Course Card Component

struct CourseCard: View {
    let course: Course
    let distance: Double?
    let isSelected: Bool
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
            HStack(spacing: 16) {
                // Course Icon
                ZStack {
                    Circle()
                        .fill(
                            isSelected ?
                            GolfTheme.grassGreen.opacity(0.2) :
                            GolfTheme.grassGreen.opacity(0.1)
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "flag.fill")
                        .foregroundColor(isSelected ? GolfTheme.grassGreen : GolfTheme.textSecondary)
                        .font(.title3)
                }
                
                // Course Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(course.name)
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 12) {
                        if let par = course.par {
                            Label("Par \(par)", systemImage: "target")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                }
                        
                        if let distance = distance {
                            Label(String(format: "%.1f mi", distance), systemImage: "location.fill")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
            }
        }
                }
                
                Spacer()
                
                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(GolfTheme.grassGreen)
                        .font(.title3)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(GolfTheme.textSecondary)
                        .font(.caption)
                }
            }
            .padding()
            .background(
                isSelected ?
                GolfTheme.grassGreen.opacity(0.1) :
                GolfTheme.cream
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ?
                        GolfTheme.grassGreen.opacity(0.5) :
                        Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .shadow(
                color: Color.black.opacity(isPressed ? 0.05 : 0.08),
                radius: isPressed ? 4 : 8,
                x: 0,
                y: isPressed ? 2 : 4
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlayView()
        .environmentObject(LocationService.shared)
        .environmentObject(ProfileViewModel())
        .environmentObject(ScoreTrackingService.shared)
}

