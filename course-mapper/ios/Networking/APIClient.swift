//
//  APIClient.swift
//  Caddie.AI iOS Client
//
//  Networking client for course-mapper API
//

import Foundation
import CoreLocation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError(Error)
    case serverError(Int, String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()
    
    private let baseURL: String
    private let session: URLSession
    
    private init() {
        self.baseURL = Config.baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Config.networkTimeout
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Nearby Courses
    
    func fetchNearbyCourses(lat: Double, lon: Double, radiusKm: Double = 10.0) async throws -> [Course] {
        if Config.useMockData {
            return MockData.nearbyCourses
        }
        
        var components = URLComponents(string: "\(baseURL)/courses/nearby")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "radius_km", value: String(radiusKm))
        ]
        
        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, message)
        }
        
        do {
            let courses = try JSONDecoder().decode([Course].self, from: data)
            return courses
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    // MARK: - Course Features
    
    func fetchCourseFeatures(courseId: Int) async throws -> [CourseFeature] {
        if Config.useMockData {
            return MockData.courseFeatures
        }
        
        guard let url = URL(string: "\(baseURL)/courses/\(courseId)/features") else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, message)
        }
        
        do {
            let featureCollection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
            return featureCollection.toCourseFeatures(courseId: courseId)
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    // MARK: - Green Reading
    
    func getGreenRead(greenId: Int, request: GreenReadRequest) async throws -> GreenReadResponse {
        if Config.useMockData {
            return MockData.greenReadResponse
        }
        
        guard let url = URL(string: "\(baseURL)/greens/\(greenId)/read") else {
            throw APIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(httpResponse.statusCode, message)
        }
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(GreenReadResponse.self, from: data)
            return response
        } catch {
            print("Decoding error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Response JSON: \(jsonString)")
            }
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Helper Extensions

struct GeoJSONFeatureCollection: Codable {
    let type: String
    let features: [GeoJSONFeature]
    
    func toCourseFeatures(courseId: Int) -> [CourseFeature] {
        features.enumerated().compactMap { index, feature in
            guard let featureTypeString = feature.properties?["feature_type"],
                  let featureType = CourseFeature.FeatureType(rawValue: featureTypeString),
                  let holeNumberString = feature.properties?["hole_number"],
                  let holeNumber = Int(holeNumberString) else {
                return nil
            }
            
            return CourseFeature(
                id: index + 1,
                courseId: courseId,
                featureType: featureType,
                holeNumber: holeNumber,
                geometry: feature
            )
        }
    }
}



