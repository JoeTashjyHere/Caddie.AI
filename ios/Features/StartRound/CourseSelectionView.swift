//
//  CourseSelectionView.swift
//  Caddie.ai
//

import SwiftUI
import CoreLocation
import MapKit

// Helper struct to make CLLocationCoordinate2D observable in onChange
private struct CoordinateKey: Equatable {
    let latitude: Double
    let longitude: Double
    
    init?(_ coordinate: CLLocationCoordinate2D?) {
        guard let coordinate = coordinate else { return nil }
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct CourseSelectionView: View {
    @EnvironmentObject var courseViewModel: CourseViewModel
    @EnvironmentObject var locationService: LocationService
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var showingMap = true
    @State private var scrollToCourseId: String?
    
    // Computed property to make coordinate observable in onChange
    private var coordinateKey: CoordinateKey? {
        CoordinateKey(locationService.coordinate)
    }
    
    private var filteredClubs: [GolfClub] {
        let allClubs = courseViewModel.clubs
        guard !searchText.isEmpty else { return allClubs }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return allClubs }
        return allClubs.filter { club in
            courseViewModel.fuzzyMatch(query: query, in: club.name)
            || club.courses.contains { c in
                courseViewModel.fuzzyMatch(query: query, in: c.courseLabel ?? "")
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Map preview section
                if showingMap {
                    mapSection
                        .frame(height: 250)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Search and controls section
                searchAndControlsSection
                
                // Courses list
                coursesListSection
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Select Course")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingMap.toggle()
                        }
                    }) {
                        Image(systemName: showingMap ? "map" : "map.fill")
                            .foregroundColor(GolfTheme.grassGreen)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(GolfTheme.grassGreen)
                }
            }
            .onAppear {
                setupInitialState()
            }
            .onChange(of: coordinateKey) { oldValue, newValue in
                // Auto-fetch courses when location becomes available
                if let coordinate = locationService.coordinate, courseViewModel.nearbyCourses.isEmpty {
                    Task {
                        await courseViewModel.fetchNearbyCourses(at: coordinate)
                    }
                }
            }
            .onChange(of: locationService.authorizationStatus) { oldValue, newValue in
                // When authorization is granted, start updating location
                if newValue == .authorizedWhenInUse || newValue == .authorizedAlways {
                    locationService.startUpdating()
                    // Wait for location and fetch courses
                    Task {
                        var attempts = 0
                        while locationService.coordinate == nil && attempts < 6 {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            attempts += 1
                        }
                        if let coordinate = locationService.coordinate {
                            await courseViewModel.fetchNearbyCourses(at: coordinate)
                        }
                    }
                }
            }
            .onChange(of: scrollToCourseId) { oldValue, newValue in
                if newValue != nil {
                    // Scroll will be handled in ScrollViewReader
                }
            }
        }
    }
    
    // MARK: - Map Section
    
    private var mapSection: some View {
        ZStack(alignment: .bottomTrailing) {
            CourseMapView(
                courses: courseViewModel.uniqueClubCourses,
                userLocation: locationService.coordinate,
                selectedCourseId: courseViewModel.selectedCourseId,
                onCourseSelected: { course in
                    handleCourseSelectionFromMap(course)
                }
            )
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Toggle map button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showingMap.toggle()
                }
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(.trailing, 24)
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Search and Controls Section
    
    private var searchAndControlsSection: some View {
        VStack(spacing: 12) {
            // Search bar with fuzzy search
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(GolfTheme.textSecondary)
                
                TextField("Search clubs or courses...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(GolfTheme.bodyFont)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchText) { oldValue, newValue in
                        // Real-time fuzzy search - no need to call API for local filtering
                        // Only call API if user presses search or submits
                    }
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            searchText = ""
                            courseViewModel.clearSearch()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .padding(.horizontal)
            
            // Backend offline warning
            if case .error(let message) = courseViewModel.nearbyCoursesState,
               message.contains("Backend offline") || message.contains("Could not connect to server") {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // Sort options and location button
            HStack(spacing: 12) {
                // Sort toggle
                Picker("Sort", selection: $courseViewModel.sortOption) {
                    ForEach(CourseSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: courseViewModel.sortOption) { oldValue, newValue in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        // Sort will be handled by displayedCourses computed property
                    }
                }
                
                // Use My Location button (if location denied)
                if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                    Button(action: {
                        openLocationSettings()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                            Text("Use My Location")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(GolfTheme.grassGreen)
                        .cornerRadius(8)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(GolfTheme.cream)
    }
    
    // MARK: - Courses List Section

    private var coursesListSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if courseViewModel.searchState == .loading || courseViewModel.nearbyCoursesState == .loading {
                        ForEach(0..<3, id: \.self) { _ in
                            CourseCardShimmer()
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                        }
                    } else {
                        let clubs = filteredClubs
                        if clubs.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(clubs) { club in
                                ClubSection(
                                    club: club,
                                    distance: courseViewModel.distanceString(for: club.courses[0]),
                                    selectedCourseId: courseViewModel.selectedCourseId,
                                    onSelect: { course in
                                        selectCourse(course)
                                    }
                                )
                                .id(club.id)
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .refreshable {
                if let coordinate = locationService.coordinate {
                    await courseViewModel.fetchNearbyCourses(at: coordinate)
                } else if locationService.authorizationStatus == .authorizedWhenInUse ||
                          locationService.authorizationStatus == .authorizedAlways {
                    locationService.startUpdating()
                    var attempts = 0
                    while locationService.coordinate == nil && attempts < 6 {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        attempts += 1
                    }
                    if let coordinate = locationService.coordinate {
                        await courseViewModel.fetchNearbyCourses(at: coordinate)
                    }
                }
            }
            .onChange(of: scrollToCourseId) { oldValue, newValue in
                if let courseId = newValue {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(courseId, anchor: .center)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        scrollToCourseId = nil
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        Group {
            if !searchText.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No courses found matching '\(searchText)'"
                )
                .padding(.vertical, 40)
            } else if locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted {
                VStack(spacing: 16) {
                    EmptyStateView(
                        icon: "location.slash",
                        title: "Location Access Needed",
                        message: "Enable location access to find courses near you"
                    )
                    
                    Button(action: {
                        openLocationSettings()
                    }) {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("Enable Location")
                        }
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(GolfTheme.grassGreen)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 40)
            } else if locationService.authorizationStatus == .notDetermined {
                VStack(spacing: 16) {
                    EmptyStateView(
                        icon: "location.magnifyingglass",
                        title: "Enable Location",
                        message: "Allow location access to find nearby courses"
                    )
                    
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
                        .frame(maxWidth: .infinity)
                        .background(GolfTheme.grassGreen)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 40)
            } else if case .error(let message) = courseViewModel.nearbyCoursesState, message == "Waiting for GPS…" {
                EmptyStateView(
                    icon: "location.magnifyingglass",
                    title: "Waiting for GPS…",
                    message: "Please wait while we find your location"
                )
                .padding(.vertical, 40)
            } else {
                EmptyStateView(
                    icon: "location.magnifyingglass",
                    title: "Find Courses",
                    message: "Search for a course or wait for nearby courses to load"
                )
                .padding(.vertical, 40)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupInitialState() {
        // Request location permission if not determined
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestAuthorization()
        }
        
        // Start location updates
        if locationService.authorizationStatus == .authorizedWhenInUse || 
           locationService.authorizationStatus == .authorizedAlways {
            locationService.startUpdating()
        }
        
        // Wait for location and then fetch courses
        Task {
            // Wait up to 3 seconds for location
            var attempts = 0
            while locationService.coordinate == nil && attempts < 6 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                attempts += 1
            }
            
            if let coordinate = locationService.coordinate {
                await courseViewModel.fetchNearbyCourses(at: coordinate)
            } else if locationService.authorizationStatus != .denied && 
                      locationService.authorizationStatus != .restricted {
                // Still waiting for GPS...
                courseViewModel.nearbyCoursesState = .error("Waiting for GPS…")
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        Task {
            let lat = locationService.coordinate?.latitude
            let lon = locationService.coordinate?.longitude
            await courseViewModel.searchCourses(query: searchText, lat: lat, lon: lon)
        }
    }
    
    private func selectCourse(_ course: Course) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        courseViewModel.selectCourse(course)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dismiss()
        }
    }
    
    private func handleCourseSelectionFromMap(_ course: Course) {
        courseViewModel.selectCourse(course)
        scrollToCourseId = course.id
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func openLocationSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Club Section (3-level hierarchy: Club → Course → Tee)

struct ClubSection: View {
    let club: GolfClub
    let distance: String?
    let selectedCourseId: String?
    let onSelect: (Course) -> Void

    @State private var isExpanded = false

    private var hasSingleCourse: Bool { club.courses.count == 1 }
    private var singleCourseHasNoTees: Bool {
        hasSingleCourse && (club.courses[0].tees ?? []).isEmpty
    }
    private var singleCourseNoLabel: Bool {
        hasSingleCourse && club.courses[0].courseLabel == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Club header
            Button {
                if singleCourseHasNoTees {
                    onSelect(club.courses[0])
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(GolfTheme.grassGreen.opacity(hasSelection ? 0.2 : 0.1))
                            .frame(width: 44, height: 44)
                        Image(systemName: hasSelection ? "checkmark.circle.fill" : "flag.fill")
                            .foregroundColor(hasSelection ? GolfTheme.grassGreen : GolfTheme.textSecondary)
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
                            }

                            if let distance = distance {
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

                    if singleCourseHasNoTees {
                        Image(systemName: "chevron.right")
                            .foregroundColor(GolfTheme.textSecondary)
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(GolfTheme.textSecondary)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding()
            }
            .buttonStyle(.plain)

            // MARK: Expanded course + tee list
            if isExpanded {
                VStack(spacing: 0) {
                    if singleCourseNoLabel {
                        teesOnlyRow(club.courses[0])
                    } else {
                        ForEach(club.courses) { course in
                            courseRow(course)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(hasSelection ? GolfTheme.grassGreen.opacity(0.06) : Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hasSelection ? GolfTheme.grassGreen : Color.clear, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(hasSelection ? 0.1 : 0.05), radius: hasSelection ? 6 : 4, x: 0, y: 2)
        .onAppear {
            if hasSelection { isExpanded = true }
        }
    }

    // MARK: - Tees-only row (single merged course, no distinct course name)
    @ViewBuilder
    private func teesOnlyRow(_ course: Course) -> some View {
        let isSelected = course.id == selectedCourseId
        let courseTees = course.tees ?? []

        Button {
            onSelect(course)
        } label: {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(GolfTheme.grassGreen.opacity(0.3))
                    .frame(width: 2)
                    .padding(.leading, 20)

                VStack(alignment: .leading, spacing: 4) {
                    if let par = course.par {
                        Text("Par \(par)")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    ForEach(courseTees) { tee in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(GolfTheme.grassGreen.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(tee.name)
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textPrimary)
                            if let yds = tee.yardage, yds > 0 {
                                Text("\(yds) yds")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(GolfTheme.textSecondary)
                            }
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(GolfTheme.grassGreen)
                        .font(.system(size: 18))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(isSelected ? GolfTheme.grassGreen.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Course row (level 2)
    @ViewBuilder
    private func courseRow(_ course: Course) -> some View {
        let isSelected = course.id == selectedCourseId
        let courseTees = course.tees ?? []

        Button {
            onSelect(course)
        } label: {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(GolfTheme.grassGreen.opacity(0.3))
                    .frame(width: 2)
                    .padding(.leading, 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(course.courseLabel ?? course.displayName)
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)

                    HStack(spacing: 10) {
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
                    }

                    // Level 3: Tees inline
                    if !courseTees.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(courseTees) { tee in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(GolfTheme.grassGreen.opacity(0.4))
                                        .frame(width: 6, height: 6)
                                    Text(tee.name)
                                        .font(GolfTheme.captionFont)
                                        .foregroundColor(GolfTheme.textPrimary)
                                    if let yds = tee.yardage, yds > 0 {
                                        Text("\(yds) yds")
                                            .font(GolfTheme.captionFont)
                                            .foregroundColor(GolfTheme.textSecondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(GolfTheme.grassGreen)
                        .font(.system(size: 18))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal)
            .background(isSelected ? GolfTheme.grassGreen.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var hasSelection: Bool {
        guard let sel = selectedCourseId else { return false }
        return club.courses.contains { $0.id == sel }
    }
}

// MARK: - Course Row with Highlighting

struct CourseRow: View {
    let course: Course
    let searchQuery: String?
    let distance: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let searchQuery = searchQuery, !searchQuery.isEmpty {
                        Text(highlightedText(course.displayName, query: searchQuery))
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    } else {
                        Text(course.displayName)
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    }

                    if let label = course.courseLabel {
                        Text(label)
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }

                    HStack(spacing: 12) {
                        if let par = course.par {
                            Text("Par \(par)")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }

                        if let distance = distance {
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

                Image(systemName: "chevron.right")
                    .foregroundColor(GolfTheme.textSecondary)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding()
            .background(isSelected ? GolfTheme.grassGreen.opacity(0.1) : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? GolfTheme.grassGreen : Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.1 : 0.05), radius: isSelected ? 6 : 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .opacity(isSelected ? 1.0 : 0.95)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
    
    private func highlightedText(_ text: String, query: String) -> AttributedString {
        var attributedString = AttributedString(text)
        let queryLower = query.lowercased()
        let textLower = text.lowercased()
        
        var searchRange = textLower.startIndex..<textLower.endIndex
        
        // Find and highlight matches
        while let range = textLower.range(of: queryLower, range: searchRange) {
            if let attributedRange = Range(range, in: attributedString) {
                attributedString[attributedRange].foregroundColor = GolfTheme.grassGreen
                attributedString[attributedRange].font = .headline
            }
            searchRange = range.upperBound..<textLower.endIndex
        }
        
        return attributedString
    }
}

#Preview {
    CourseSelectionView()
        .environmentObject(CourseViewModel())
        .environmentObject(LocationService.shared)
}

