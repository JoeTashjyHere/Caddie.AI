//
//  CourseMapperService.swift
//  Caddie.ai
//
//  Service for calling the course-mapper FastAPI backend

import Foundation
import CoreLocation
import SwiftUI

@MainActor
class CourseMapperService: ObservableObject {
    static let shared = CourseMapperService()
    
    // Base URL for course-mapper API (runs on port 8081)
    private var baseURL: String {
        #if targetEnvironment(simulator)
            return "http://localhost:8081"
        #else
            // Replace with your Mac's local IP when testing on physical device
            return "http://192.168.1.151:8081"
        #endif
    }
    
    private init() {}
    
    // MARK: - Nearby Courses
    
    func fetchNearbyCourses(
        lat: Double,
        lon: Double,
        radiusKm: Double = 10.0
    ) async throws -> [CourseMapperCourse] {
        let urlString = "\(baseURL)/courses/nearby?lat=\(lat)&lon=\(lon)&radius_km=\(radiusKm)"
        
        guard let url = URL(string: urlString) else {
            throw CourseMapperError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CourseMapperError.invalidResponse
        }
        
        do {
            let courses = try JSONDecoder().decode([CourseMapperCourse].self, from: data)
            return courses
        } catch {
            print("CourseMapper: Error decoding courses: \(error)")
            throw CourseMapperError.decodingError
        }
    }
    
    // MARK: - Course Holes
    
    func fetchCourseHoles(courseId: String) async throws -> [CourseMapperHole] {
        let urlString = "\(baseURL)/courses/\(courseId)/holes"
        
        guard let url = URL(string: urlString) else {
            throw CourseMapperError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CourseMapperError.invalidResponse
        }
        
        do {
            let holes = try JSONDecoder().decode([CourseMapperHole].self, from: data)
            return holes
        } catch {
            print("CourseMapper: Error decoding holes: \(error)")
            throw CourseMapperError.decodingError
        }
    }
    
    // MARK: - Hole Layout
    
    func fetchHoleLayout(courseId: String, holeNumber: Int) async throws -> HoleLayoutResponse {
        let urlString = "\(baseURL)/courses/\(courseId)/holes/\(holeNumber)/layout"
        
        guard let url = URL(string: urlString) else {
            throw CourseMapperError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CourseMapperError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw CourseMapperError.holeNotFound
            }
            throw CourseMapperError.invalidResponse
        }
        
        do {
            let layout = try JSONDecoder().decode(HoleLayoutResponse.self, from: data)
            return layout
        } catch {
            print("CourseMapper: Error decoding hole layout: \(error)")
            throw CourseMapperError.decodingError
        }
    }
    
    // MARK: - Green Contours
    
    func fetchGreenContours(courseId: String, holeNumber: Int) async throws -> GreenContourResponse? {
        let urlString = "\(baseURL)/courses/\(courseId)/holes/\(holeNumber)/green-contours"
        
        guard let url = URL(string: urlString) else {
            throw CourseMapperError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CourseMapperError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                return nil  // No contours available
            }
            throw CourseMapperError.invalidResponse
        }
        
        do {
            let contours = try JSONDecoder().decode(GreenContourResponse.self, from: data)
            return contours
        } catch {
            print("CourseMapper: Error decoding green contours: \(error)")
            return nil  // Fail gracefully
        }
    }
}

// MARK: - Models

struct CourseMapperCourse: Codable {
    let id: String
    let name: String
    let distanceKm: Double
    let city: String?
    let country: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case distanceKm = "distance_km"
        case city, country
    }
    
    func toCourse(location: CLLocationCoordinate2D? = nil) -> Course {
        // Create a Course from CourseMapperCourse
        // Note: Course mapper doesn't provide lat/lon directly, so we use the search location
        // In production, we'd fetch full course details with actual coordinates
        return Course(
            id: id,
            name: name,
            location: location.map { Course.Coordinate(from: $0) },
            par: nil,
            lat: location?.latitude,
            lon: location?.longitude
        )
    }
    
    func toCourseWithLocation() -> Course {
        // Attempt to create course with location from distance calculation
        // This is a placeholder - in production, fetch actual course coordinates from DB
        return Course(
            id: id,
            name: name,
            location: nil,
            par: nil,
            lat: nil,
            lon: nil
        )
    }
}

struct CourseMapperHole: Codable {
    let number: Int
    let par: Int?
    let handicap: Int?
    let teeYardages: [String: Int]?
    
    enum CodingKeys: String, CodingKey {
        case number, par, handicap
        case teeYardages = "tee_yardages"
    }
}

struct GreenContourResponse: Codable {
    let contourRasterUrl: String?
    let metadata: [String: Double]?
    
    enum CodingKeys: String, CodingKey {
        case contourRasterUrl = "contour_raster_url"
        case metadata
    }
}

// MARK: - Errors

enum CourseMapperError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    case holeNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for course mapper"
        case .invalidResponse:
            return "Invalid response from course mapper"
        case .decodingError:
            return "Failed to decode course mapper data"
        case .holeNotFound:
            return "Hole not found in course mapper"
        }
    }
}

