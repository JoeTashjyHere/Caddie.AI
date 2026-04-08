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
    @EnvironmentObject var historyStore: HistoryStore
    @StateObject private var courseViewModel = CourseViewModel()

    @State private var showingRoundPlay = false
    @State private var showingRoundSetup = false
    @State private var pendingRoundLaunch: RoundPlayLaunchConfig?
    @State private var isRefreshing = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let selectedCourse = courseViewModel.currentCourse {
                        selectedCourseCard(course: selectedCourse)
                    }

                    if locationService.authorizationStatus == .denied ||
                       locationService.authorizationStatus == .restricted ||
                       locationService.authorizationStatus == .notDetermined {
                        locationFallbackBanner
                    }

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
                if scoreTrackingService.phase == .inProgress,
                   let currentRound = scoreTrackingService.currentRound {
                    let course = currentRound.resolvedCourse()
                    courseViewModel.selectCourse(course)
                    pendingRoundLaunch = nil
                    showingRoundPlay = true
                    return
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
                            if courseViewModel.currentCourse != nil {
                                scoreTrackingService.setPhase(.selectingCourse)
                                showingRoundSetup = true
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
            if let course = courseViewModel.nearbyCourses.first(where: { $0.name == courseName }) {
                return course
            }
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

                    Text(course.displayName)
                        .font(GolfTheme.titleFont)
                        .foregroundColor(GolfTheme.textPrimary)

                    if let label = course.courseLabel {
                        Text(label)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }

                    if let par = course.par {
                        Text("Par \(par)")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }

                Spacer()

                Button(action: {
                    courseViewModel.currentCourse = nil
                    UserDefaults.standard.removeObject(forKey: "CurrentCourse")
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(GolfTheme.textSecondary)
                }
            }

            PrimaryButton(
                title: "Start Round",
                action: {
                    withAnimation(.spring(response: 0.3)) {
                        showingRoundSetup = true
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

    // MARK: - Nearby Courses (Club → Course hierarchy)

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
                ForEach(courseViewModel.clubs) { club in
                    PlayClubRow(
                        club: club,
                        distance: courseViewModel.distanceString(for: club.courses[0]),
                        selectedCourseId: courseViewModel.selectedCourseId,
                        onSelectCourse: { course in
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
                    Task { await requestLocationAndFetch() }
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
                PlayCourseCard(
                    course: course,
                    distance: nil,
                    isSelected: courseViewModel.currentCourse?.id == course.id,
                    action: { selectCourse(course) }
                )
                .padding(.horizontal)
            }
        }
    }

    // MARK: - States

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
                Task { await requestLocationAndFetch() }
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

    // MARK: - Helpers

    private func getCourseFromCurrentRound() -> Course? {
        scoreTrackingService.currentRound.map { $0.resolvedCourse() }
    }

    private func setupPlayView() {
        courseViewModel.loadCurrentCourse()
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestAuthorization()
        }
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
        defer { isRefreshing = false }
        if shouldShowNearbyCourses, let coordinate = locationService.coordinate {
            await courseViewModel.fetchNearbyCourses(at: coordinate)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    private func requestLocationAndFetch() async {
        locationService.requestAuthorization()
        var attempts = 0
        while locationService.authorizationStatus == .notDetermined && attempts < 20 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            attempts += 1
        }
        if shouldShowNearbyCourses {
            locationService.startUpdating()
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
        }
    }

    private func calculateDistance(to course: Course) -> Double? {
        guard let userLocation = locationService.coordinate,
              let courseLocation = course.location?.clLocation else { return nil }
        let userCL = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let courseCL = CLLocation(latitude: courseLocation.latitude, longitude: courseLocation.longitude)
        return userCL.distance(from: courseCL) / 1609.34
    }

    // MARK: - Location Fallback

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
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } else {
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Play Club Row (Club → Course hierarchy for Play tab)

struct PlayClubRow: View {
    let club: GolfClub
    let distance: String?
    let selectedCourseId: String?
    let onSelectCourse: (Course) -> Void

    @State private var isExpanded = false

    private var hasSingleCourse: Bool { club.courses.count == 1 }
    private var isSelected: Bool {
        guard let id = selectedCourseId else { return false }
        return club.courses.contains { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if hasSingleCourse {
                    onSelectCourse(club.courses[0])
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(GolfTheme.grassGreen.opacity(isSelected ? 0.2 : 0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "flag.fill")
                            .foregroundColor(isSelected ? GolfTheme.grassGreen : GolfTheme.textSecondary)
                            .font(.system(size: 18))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(club.name)
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 10) {
                            if !hasSingleCourse {
                                Text("\(club.courses.count) courses")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(GolfTheme.textSecondary)
                            } else if let par = club.courses[0].par {
                                Label("Par \(par)", systemImage: "target")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(GolfTheme.textSecondary)
                            }

                            if let distance {
                                HStack(spacing: 4) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 10))
                                    Text(distance)
                                        .font(GolfTheme.captionFont)
                                }
                                .foregroundColor(GolfTheme.grassGreen)
                            }
                        }
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(GolfTheme.grassGreen)
                            .font(.title3)
                    } else if !hasSingleCourse {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(GolfTheme.textSecondary)
                            .font(.caption)
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundColor(GolfTheme.textSecondary)
                            .font(.caption)
                    }
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded && !hasSingleCourse {
                VStack(spacing: 0) {
                    ForEach(club.courses) { course in
                        let courseSelected = selectedCourseId == course.id
                        Button {
                            onSelectCourse(course)
                        } label: {
                            HStack(spacing: 12) {
                                Text(course.courseLabel ?? course.courseName ?? "Main")
                                    .font(GolfTheme.bodyFont.weight(.medium))
                                    .foregroundColor(courseSelected ? GolfTheme.grassGreen : GolfTheme.textPrimary)

                                if let par = course.par {
                                    Text("Par \(par)")
                                        .font(GolfTheme.captionFont)
                                        .foregroundColor(GolfTheme.textSecondary)
                                }

                                if let info = course.holeAndTeeLabel {
                                    Text(info)
                                        .font(GolfTheme.captionFont)
                                        .foregroundColor(GolfTheme.textSecondary)
                                }

                                Spacer()

                                if courseSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(GolfTheme.grassGreen)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if course.id != club.courses.last?.id {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .background(GolfTheme.grassGreen.opacity(0.03))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isSelected ? GolfTheme.grassGreen.opacity(0.08) : GolfTheme.cream)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? GolfTheme.grassGreen.opacity(0.4) : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}

// MARK: - Simple Play Course Card (for recent courses)

struct PlayCourseCard: View {
    let course: Course
    let distance: Double?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(GolfTheme.grassGreen.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "flag.fill")
                        .foregroundColor(isSelected ? GolfTheme.grassGreen : GolfTheme.textSecondary)
                        .font(.system(size: 18))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.displayName)
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                        .lineLimit(2)
                    if let par = course.par {
                        Label("Par \(par)", systemImage: "target")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundColor(isSelected ? GolfTheme.grassGreen : GolfTheme.textSecondary)
                    .font(isSelected ? .title3 : .caption)
            }
            .padding()
            .background(isSelected ? GolfTheme.grassGreen.opacity(0.08) : GolfTheme.cream)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? GolfTheme.grassGreen.opacity(0.4) : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PlayView()
        .environmentObject(LocationService.shared)
        .environmentObject(ProfileViewModel())
        .environmentObject(ScoreTrackingService.shared)
        .environmentObject(FeedbackService.shared)
        .environmentObject(HistoryStore())
}
