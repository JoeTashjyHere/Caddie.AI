//
//  CourseViewModel.swift
//  Caddie.ai
//

import Foundation
import CoreLocation

enum CourseSortOption: String, CaseIterable {
    case closestFirst = "Closest First"
    case highestRated = "Highest Rated"
    
    var displayName: String {
        rawValue
    }
}

@MainActor
class CourseViewModel: ObservableObject {
    @Published var currentCourse: Course?
    @Published var nearbyCourses: [Course] = []
    @Published var searchResults: [Course] = []
    @Published var nearbyCoursesState: ViewState = .idle
    @Published var searchState: ViewState = .idle
    @Published var sortOption: CourseSortOption = .closestFirst
    @Published var selectedCourseId: String?
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var backendHealthCheck: Bool = true
    
    private let apiService = APIService.shared
    var searchText: String = ""

    /// 3-level hierarchy: Club → Course → Tee, built from the flat courses list.
    var clubs: [GolfClub] {
        let courses = !searchText.isEmpty ? searchResults : nearbyCourses
        let sorted = sortByDistance(courses: courses)
        return GolfClub.buildHierarchy(from: sorted)
    }

    /// One representative course per club for map annotations.
    var uniqueClubCourses: [Course] {
        var seen = Set<String>()
        var result: [Course] = []
        let courses = !searchText.isEmpty ? searchResults : nearbyCourses
        for c in sortByDistance(courses: courses) {
            let key = c.displayName
            if seen.insert(key).inserted { result.append(c) }
        }
        return result
    }

    func displayedCourses(searchText: String = "") -> [Course] {
        let courses: [Course]

        if !searchText.isEmpty {
            courses = searchResults
        } else {
            courses = nearbyCourses
        }

        switch sortOption {
        case .closestFirst:
            return sortByDistance(courses: courses)
        case .highestRated:
            return courses
        }
    }
    
    // Legacy computed properties for backward compatibility
    var isLoading: Bool {
        nearbyCoursesState == .loading || searchState == .loading
    }
    
    var errorMessage: String? {
        nearbyCoursesState.errorMessage ?? searchState.errorMessage
    }
    
    func fetchNearbyCourses(at coordinate: CLLocationCoordinate2D) async {
        userLocation = coordinate
        nearbyCoursesState = .loading
        
        // First check backend health
        do {
            let isHealthy = try await apiService.checkHealth()
            if !isHealthy {
                nearbyCoursesState = .error("Backend offline — Start Node server at port 8080.")
                return
            }
        } catch {
            // Health check failed, but try to fetch courses anyway
            // Will show better error message if fetch also fails
            print("Health check failed: \(error.localizedDescription)")
        }
        
        do {
            let courses = try await apiService.fetchNearbyCourses(
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
            nearbyCourses = courses
            nearbyCoursesState = courses.isEmpty ? .empty : .loaded
        } catch let error as APIError {
            let errorMessage: String
            switch error {
            case .invalidURL:
                errorMessage = "Invalid server configuration."
            case .invalidResponse:
                errorMessage = "Could not connect to server."
            case .serverError(let message):
                errorMessage = message
            case .decodingError:
                errorMessage = "Could not understand server response."
            case .missingResult:
                errorMessage = "Server response was incomplete."
            case .timeout:
                errorMessage = "Request timed out. Please try again."
            }
            nearbyCoursesState = .error(errorMessage)
            print("Error fetching nearby courses: \(errorMessage)")
        } catch {
            nearbyCoursesState = .error("Could not connect to server. Make sure the backend is running.")
            print("Error fetching nearby courses: \(error)")
        }
    }
    
    func searchCourses(query: String, lat: Double? = nil, lon: Double? = nil) async {
        searchState = .loading
        searchText = query
        
        do {
            let courses = try await apiService.searchCourses(query: query, lat: lat, lon: lon)
            searchResults = courses
            searchState = courses.isEmpty ? .empty : .loaded
        } catch {
            searchState = .error(error.localizedDescription)
            print("Error searching courses: \(error)")
        }
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
        searchState = .idle
    }
    
    func selectCourse(_ course: Course) {
        currentCourse = course
        selectedCourseId = course.id
        #if DEBUG
        print("[COURSE] Selected course: \(course.displayName) (\(course.courseLabel ?? "-")) | courseId: \(course.id)")
        #endif
        if let encoded = try? JSONEncoder().encode(course) {
            UserDefaults.standard.set(encoded, forKey: "CurrentCourse")
        }
    }
    
    func loadCurrentCourse() {
        if let data = UserDefaults.standard.data(forKey: "CurrentCourse"),
           let course = try? JSONDecoder().decode(Course.self, from: data) {
            if course.hasValidBackendId {
                currentCourse = course
                selectedCourseId = course.id
            } else {
                #if DEBUG
                print("[COURSE] Invalid cached courseId detected, clearing: \(course.id)")
                #endif
                UserDefaults.standard.removeObject(forKey: "CurrentCourse")
            }
        }
    }
    
    // MARK: - Sorting and Distance Calculation
    
    func setSortOption(_ option: CourseSortOption) {
        sortOption = option
    }
    
    func sortByDistance(courses: [Course]) -> [Course] {
        guard let userLocation = userLocation else {
            return courses
        }
        
        return courses.sorted { course1, course2 in
            let distance1 = distanceToCourse(course1, from: userLocation)
            let distance2 = distanceToCourse(course2, from: userLocation)
            return distance1 < distance2
        }
    }
    
    func distanceToCourse(_ course: Course, from location: CLLocationCoordinate2D) -> Double {
        guard let courseLocation = course.location else {
            return Double.greatestFiniteMagnitude
        }
        
        let location1 = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let location2 = CLLocation(
            latitude: courseLocation.latitude,
            longitude: courseLocation.longitude
        )
        
        return location1.distance(from: location2)
    }
    
    func distanceString(for course: Course) -> String? {
        guard let userLocation = userLocation,
              course.location != nil else {
            return nil
        }
        
        let distance = distanceToCourse(course, from: userLocation)
        let miles = distance * 0.000621371 // Convert meters to miles
        
        if miles < 0.1 {
            let feet = miles * 5280
            return String(format: "%.0f ft", feet)
        } else if miles < 1 {
            return String(format: "%.2f mi", miles)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }
    
    // MARK: - Fuzzy Search
    
    func fuzzyMatch(query: String, in text: String) -> Bool {
        let query = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.lowercased()
        
        if query.isEmpty { return true }
        if text.contains(query) { return true }
        
        // Fuzzy matching: check if all characters in query appear in order in text
        var queryIndex = query.startIndex
        for char in text {
            if queryIndex < query.endIndex && char == query[queryIndex] {
                queryIndex = query.index(after: queryIndex)
            }
        }
        
        return queryIndex == query.endIndex
    }
    
    func highlightMatches(query: String, in text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        let query = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if query.isEmpty {
            return attributedString
        }
        
        let textLower = text.lowercased()
        
        // Find all ranges where query appears
        var searchRange = textLower.startIndex..<textLower.endIndex
        while let range = textLower.range(of: query, range: searchRange) {
            let nsRange = NSRange(range, in: text)
            if let attributedRange = Range(nsRange, in: attributedString) {
                attributedString[attributedRange].foregroundColor = GolfTheme.grassGreen
                attributedString[attributedRange].font = .headline
            }
            
            // Continue searching after this match
            searchRange = range.upperBound..<textLower.endIndex
        }
        
        return attributedString
    }
}
