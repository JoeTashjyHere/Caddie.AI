//
//  CourseService.swift
//  Caddie.ai
//

import Foundation
import CoreLocation

// Note: CourseMapperService must be included in the same Xcode target
// If you see "Cannot find 'CourseMapperService' in scope", ensure CourseMapperService.swift
// is added to your target in Xcode: Select the file → File Inspector → Target Membership

// Response model for backend courses endpoint
struct CoursesResponse: Codable {
    let source: String?
    let courses: [Course]
}

struct HoleContext {
    var holeNumber: Int
    var centerOfGreen: CLLocationCoordinate2D
    var hazards: [String]
}

enum CourseError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Failed to decode course data"
        }
    }
}

@MainActor
class CourseService: ObservableObject {
    static let shared = CourseService()
    
    @Published private(set) var currentCourse: Course?
    @Published private(set) var suggestedCourse: Course?
    
    var localCourses: [Course] {
        []
    }
    
    private let currentCourseKey = "CurrentCourse"
    private let suggestedCourseKey = "SuggestedCourse"
    private let baseURL: URL
    
    private init() {
        // Use APIService as single source of truth for base URL
        self.baseURL = APIService.getBaseURL().appendingPathComponent("api")
        loadCurrentCourse()
    }
    
    func getNearbyCourses(at coordinate: CLLocationCoordinate2D) async throws -> [Course] {
        // Try Node backend first
        do {
            let url = baseURL.appendingPathComponent("courses")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "lat", value: String(coordinate.latitude)),
                URLQueryItem(name: "lon", value: String(coordinate.longitude))
            ]
            guard let finalURL = components?.url else { throw CourseError.invalidURL }
            
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: finalURL))
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                print("Node backend returned status \((response as? HTTPURLResponse)?.statusCode ?? -1), trying course-mapper...")
                return try await getNearbyCoursesFromCourseMapper(at: coordinate)
            }
            let coursesResponse = try JSONDecoder().decode(CoursesResponse.self, from: data)
            return coursesResponse.courses
        } catch {
            print("Error fetching nearby courses from Node backend: \(error). Trying course-mapper...")
            return try await getNearbyCoursesFromCourseMapper(at: coordinate)
        }
    }
    
    private func getNearbyCoursesFromCourseMapper(at coordinate: CLLocationCoordinate2D) async throws -> [Course] {
        do {
            let mapperCourses = try await CourseMapperService.shared.fetchNearbyCourses(
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                radiusKm: 10.0
            )
            
            // Convert CourseMapperCourse to Course
            return mapperCourses.map { mapperCourse in
                // Get location from course mapper or use provided coordinate
                mapperCourse.toCourse(location: coordinate)
            }
        } catch {
            print("Error fetching courses from course-mapper: \(error). Returning empty results.")
            return []
        }
    }
    
    func searchCourses(query: String, lat: Double? = nil, lon: Double? = nil) async throws -> [Course] {
        do {
            let url = baseURL.appendingPathComponent("courses")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = [URLQueryItem(name: "query", value: query)]
            if let lat = lat, let lon = lon {
                queryItems.append(URLQueryItem(name: "lat", value: String(lat)))
                queryItems.append(URLQueryItem(name: "lon", value: String(lon)))
            }
            components?.queryItems = queryItems
            guard let finalURL = components?.url else { throw CourseError.invalidURL }
            
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: finalURL))
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                print("Backend returned status \((response as? HTTPURLResponse)?.statusCode ?? -1), returning empty results")
                return []
            }
            let coursesResponse = try JSONDecoder().decode(CoursesResponse.self, from: data)
            return coursesResponse.courses
        } catch {
            print("Error searching courses from backend: \(error). Returning empty results.")
            return []
        }
    }
    
    func suggestCourse(at coordinate: CLLocationCoordinate2D) async {
        do {
            let courses = try await getNearbyCourses(at: coordinate)
            if let nearestCourse = courses.first {
                suggestedCourse = nearestCourse
                saveSuggestedCourse()
            }
        } catch {
            print("Error suggesting course: \(error)")
        }
    }
    
    func clearSuggestedCourse() {
        suggestedCourse = nil
        UserDefaults.standard.removeObject(forKey: suggestedCourseKey)
    }
    
    func setCurrentCourse(_ course: Course) {
        currentCourse = course
        saveCurrentCourse()
    }
    
    func getCurrentCourse() -> Course? {
        return currentCourse
    }
    
    func resolveCourseAndHole(at coordinate: CLLocationCoordinate2D) async throws -> HoleContext {
        try await Task.sleep(nanoseconds: 400_000_000)
        
        return HoleContext(
            holeNumber: 7,
            centerOfGreen: coordinate,
            hazards: ["Water left", "Bunker right"]
        )
    }
    
    private func saveCurrentCourse() {
        if let course = currentCourse,
           let encoded = try? JSONEncoder().encode(course) {
            UserDefaults.standard.set(encoded, forKey: currentCourseKey)
        }
    }
    
    private func loadCurrentCourse() {
        if let data = UserDefaults.standard.data(forKey: currentCourseKey),
           let course = try? JSONDecoder().decode(Course.self, from: data) {
            currentCourse = course
        }
        
        if let data = UserDefaults.standard.data(forKey: suggestedCourseKey),
           let course = try? JSONDecoder().decode(Course.self, from: data) {
            suggestedCourse = course
        }
    }
    
    private func saveSuggestedCourse() {
        if let course = suggestedCourse,
           let encoded = try? JSONEncoder().encode(course) {
            UserDefaults.standard.set(encoded, forKey: suggestedCourseKey)
        }
    }
}
