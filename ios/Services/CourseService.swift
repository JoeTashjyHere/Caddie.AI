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
    
    private let currentCourseKey = "CurrentCourse"
    private let suggestedCourseKey = "SuggestedCourse"
    
    private init() {
        loadCurrentCourse()
    }
    
    func getNearbyCourses(at coordinate: CLLocationCoordinate2D) async throws -> [Course] {
        let courses = try await APIService.shared.fetchNearbyCourses(
            lat: coordinate.latitude,
            lon: coordinate.longitude
        )
        #if DEBUG
        print("[COURSE] CourseService.getNearbyCourses returned \(courses.count) live courses")
        #endif
        return courses
    }
    
    func searchCourses(query: String, lat: Double? = nil, lon: Double? = nil) async throws -> [Course] {
        let courses = try await APIService.shared.searchCourses(query: query, lat: lat, lon: lon)
        #if DEBUG
        print("[COURSE] CourseService.searchCourses query=\(query) returned \(courses.count) live courses")
        #endif
        return courses
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
        #if DEBUG
        print("[COURSE] CourseService.setCurrentCourse: \(course.displayName) | courseId: \(course.id)")
        #endif
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
            if course.hasValidBackendId {
                currentCourse = course
            } else {
                #if DEBUG
                print("[COURSE] Invalid cached courseId detected, clearing: \(course.id)")
                #endif
                UserDefaults.standard.removeObject(forKey: currentCourseKey)
            }
        }

        if let data = UserDefaults.standard.data(forKey: suggestedCourseKey),
           let course = try? JSONDecoder().decode(Course.self, from: data) {
            if course.hasValidBackendId {
                suggestedCourse = course
            } else {
                #if DEBUG
                print("[COURSE] Invalid cached suggestedCourseId detected, clearing: \(course.id)")
                #endif
                UserDefaults.standard.removeObject(forKey: suggestedCourseKey)
            }
        }
    }
    
    private func saveSuggestedCourse() {
        if let course = suggestedCourse,
           let encoded = try? JSONEncoder().encode(course) {
            UserDefaults.standard.set(encoded, forKey: suggestedCourseKey)
        }
    }
}
