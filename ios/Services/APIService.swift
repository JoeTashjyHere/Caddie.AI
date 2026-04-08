//
//  APIService.swift
//  Caddie.ai
//
//  Service for calling the Node.js backend
//

import Foundation
import CoreLocation

/// Nonisolated base URL for use from any context (e.g. Task.detached)
enum APIConfig {
    static let baseURLString = "https://caddie-ai-backend.onrender.com"
}

@MainActor
class APIService: ObservableObject {
    static let shared = APIService()
    
    // Production backend base URL - single source of truth (use APIConfig.baseURLString from non-MainActor)
    static let baseURLString = APIConfig.baseURLString
    private static let baseURL = URL(string: APIConfig.baseURLString)!
    private let requestTimeout: TimeInterval = 20
    private let maxRetryCount = 2
    
    private init() {}
    
    // MARK: - URL Construction Helpers
    
    /// Constructs a URL for an API endpoint, ensuring no double slashes.
    /// Splits path segments to avoid encoding slashes in path components.
    private func url(for endpoint: String) -> URL {
        let cleanEndpoint = endpoint.hasPrefix("/") ? String(endpoint.dropFirst()) : endpoint
        let segments = cleanEndpoint.split(separator: "/").map(String.init)
        var result = Self.baseURL
        for segment in segments {
            result = result.appendingPathComponent(segment)
        }
        return result
    }
    
    /// Exposes the base URL for use by other services
    static func getBaseURL() -> URL {
        return baseURL
    }
    
    // MARK: - Health Check
    
    func checkHealth() async throws -> Bool {
        let url = self.url(for: "health")
        
        DebugLogging.logAPI(endpoint: "health", url: url, method: "GET")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogging.logAPI(endpoint: "health", url: url, method: "GET", responseData: data, error: APIError.invalidResponse)
            return false
        }
        
        let healthResponse = try? JSONDecoder().decode(HealthResponse.self, from: data)
        
        DebugLogging.logAPI(
            endpoint: "health",
            url: url,
            method: "GET",
            responseStatus: httpResponse.statusCode,
            responseData: data,
            parsedModel: healthResponse
        )
        
        return healthResponse?.ok ?? false
    }
    
    // MARK: - Courses
    
    func fetchNearbyCourses(lat: Double, lon: Double) async throws -> [Course] {
        var components = URLComponents(url: url(for: "api/courses"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon))
        ]
        
        guard let url = components.url else {
            let payload = ["lat": lat, "lon": lon]
            DebugLogging.logAPI(endpoint: "courses (nearby)", url: nil as URL?, method: "GET", payload: payload, error: APIError.invalidURL)
            throw APIError.invalidURL
        }
        
        let payload = ["lat": lat, "lon": lon]
        DebugLogging.logAPI(endpoint: "courses (nearby)", url: url, method: "GET", payload: payload)
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogging.logAPI(endpoint: "courses (nearby)", url: url, method: "GET", payload: payload, responseData: data, error: APIError.invalidResponse)
            throw APIError.invalidResponse
        }
        
        #if DEBUG
        print("[COURSE] fetchNearbyCourses status: \(httpResponse.statusCode)")
        #endif
        
        guard (200...299).contains(httpResponse.statusCode) else {
            DebugLogging.logAPI(endpoint: "courses (nearby)", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: APIError.invalidResponse)
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[COURSE] fetchNearbyCourses error response: \(raw.prefix(500))")
            }
            #endif
            throw APIError.invalidResponse
        }
        
        do {
            let coursesResponse = try JSONDecoder().decode(CoursesResponse.self, from: data)
            DebugLogging.logAPI(endpoint: "courses (nearby)", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, parsedModel: coursesResponse)
            #if DEBUG
            print("[COURSE] Loaded \(coursesResponse.courses.count) live courses from GET /api/courses")
            for c in coursesResponse.courses.prefix(5) {
                print("[COURSE]   \(c.displayName) (\(c.courseLabel ?? "-")) | courseId: \(c.id)")
            }
            #endif
            return coursesResponse.courses
        } catch {
            DebugLogging.logAPI(endpoint: "courses (nearby)", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
            #if DEBUG
            print("[COURSE] fetchNearbyCourses decode failed: \(error)")
            if let raw = String(data: data, encoding: .utf8) {
                print("[COURSE] raw response: \(raw.prefix(1000))")
            }
            #endif
            throw APIError.decodingError
        }
    }
    
    // MARK: - Round engine course context

    /// Generic lat/lon coordinate DTO — reused for all POI types (green center, tee front/back, etc.)
    struct CourseContextCoordDTO: Decodable {
        let lat: Double
        let lon: Double

        var clCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    /// Legacy alias kept so existing callsites compile unchanged.
    typealias CourseContextGreenCenterDTO = CourseContextCoordDTO

    struct CourseContextHoleDTO: Decodable {
        let holeNumber: Int
        let par: Int
        let handicap: Int?
        // Green POIs
        let greenCenter: CourseContextCoordDTO?
        let greenFront: CourseContextCoordDTO?
        let greenBack: CourseContextCoordDTO?
        // Tee POIs — populated from coordinates.csv entries "Tee Front" / "Tee Back"
        let teeFront: CourseContextCoordDTO?
        let teeBack: CourseContextCoordDTO?
        let hazards: [String]?

        enum CodingKeys: String, CodingKey {
            case holeNumber = "hole_number"
            case par
            case handicap
            case greenCenter = "green_center"
            case greenFront  = "green_front"
            case greenBack   = "green_back"
            case teeFront    = "tee_front"
            case teeBack     = "tee_back"
            case hazards
        }
    }
    
    struct CourseContextTeeDTO: Decodable {
        let id: String
        let name: String
        let totalYards: Int
        
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case totalYards = "total_yards"
        }
    }
    
    struct CourseContextCourseDTO: Decodable {
        let id: String
        let name: String
        let lat: Double?
        let lon: Double?
        let city: String?
        let state: String?
        let clubName: String?
        // TODO: Backend should supply courseRating (e.g. 72.1) and slopeRating (e.g. 131)
        // for USGA-style handicap calculation. Until then these will decode as nil.
        let courseRating: Double?
        let slopeRating: Double?

        var displayName: String {
            clubName ?? name
        }
    }
    
    struct CourseContextResponse: Decodable {
        let course: CourseContextCourseDTO
        let holes: [CourseContextHoleDTO]
        let tees: [CourseContextTeeDTO]
    }
    
    func fetchCourseContext(courseId: String) async throws -> CourseContextResponse {
        let encoded = courseId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? courseId
        let url = url(for: "api/course-context/\(encoded)")
        DebugLogging.logAPI(endpoint: "course-context", url: url, method: "GET", payload: ["courseId": courseId])
        
        #if DEBUG
        print("[API] course-context requesting courseId: \(courseId)")
        #endif
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogging.logAPI(endpoint: "course-context", url: url, method: "GET", responseData: data, error: APIError.invalidResponse)
            throw APIError.invalidResponse
        }
        
        #if DEBUG
        print("[API] course-context status: \(httpResponse.statusCode)")
        #endif
        
        guard (200...299).contains(httpResponse.statusCode) else {
            DebugLogging.logAPI(endpoint: "course-context", url: url, method: "GET", responseStatus: httpResponse.statusCode, responseData: data, error: APIError.invalidResponse)
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[API] course-context error response: \(raw.prefix(500))")
            }
            #endif
            throw APIError.invalidResponse
        }
        
        do {
            let decoded = try JSONDecoder().decode(CourseContextResponse.self, from: data)
            DebugLogging.logAPI(endpoint: "course-context", url: url, method: "GET", responseStatus: httpResponse.statusCode, parsedModel: decoded)
            #if DEBUG
            print("[API] course-context decoded OK — course: \(decoded.course.displayName) holes: \(decoded.holes.count) tees: \(decoded.tees.count)")
            #endif
            return decoded
        } catch {
            DebugLogging.logAPI(endpoint: "course-context", url: url, method: "GET", responseStatus: httpResponse.statusCode, responseData: data, error: error)
            #if DEBUG
            print("[API] course-context decode failed: \(error)")
            if let raw = String(data: data, encoding: .utf8) {
                print("[API] raw response: \(raw.prefix(1000))")
            }
            #endif
            throw APIError.decodingError
        }
    }
    
    func searchCourses(query: String, lat: Double? = nil, lon: Double? = nil) async throws -> [Course] {
        var components = URLComponents(url: url(for: "api/courses"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "query", value: query)]
        if let lat = lat, let lon = lon {
            queryItems.append(URLQueryItem(name: "lat", value: String(lat)))
            queryItems.append(URLQueryItem(name: "lon", value: String(lon)))
        }
        components.queryItems = queryItems
        
        guard let url = components.url else {
            var payload: [String: Any] = ["query": query]
            if let lat = lat, let lon = lon {
                payload["lat"] = lat
                payload["lon"] = lon
            }
            DebugLogging.logAPI(endpoint: "courses (search)", url: nil as URL?, method: "GET", payload: payload, error: APIError.invalidURL)
            throw APIError.invalidURL
        }
        
        var payload: [String: Any] = ["query": query]
        if let lat = lat, let lon = lon {
            payload["lat"] = lat
            payload["lon"] = lon
        }
        DebugLogging.logAPI(endpoint: "courses (search)", url: url, method: "GET", payload: payload)
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogging.logAPI(endpoint: "courses (search)", url: url, method: "GET", payload: payload, responseData: data, error: APIError.invalidResponse)
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            DebugLogging.logAPI(endpoint: "courses (search)", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: APIError.invalidResponse)
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[COURSE] searchCourses error response: \(raw.prefix(500))")
            }
            #endif
            throw APIError.invalidResponse
        }
        
        do {
            let coursesResponse = try JSONDecoder().decode(CoursesResponse.self, from: data)
            DebugLogging.logAPI(endpoint: "courses (search)", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, parsedModel: coursesResponse)
            #if DEBUG
            print("[COURSE] Loaded \(coursesResponse.courses.count) live courses from search query=\(query)")
            for c in coursesResponse.courses.prefix(5) {
                print("[COURSE]   \(c.displayName) (\(c.courseLabel ?? "-")) | courseId: \(c.id)")
            }
            #endif
            return coursesResponse.courses
        } catch {
            DebugLogging.logAPI(endpoint: "courses (search)", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
            #if DEBUG
            print("[COURSE] searchCourses decode failed: \(error)")
            if let raw = String(data: data, encoding: .utf8) {
                print("[COURSE] raw response: \(raw.prefix(1000))")
            }
            #endif
            throw APIError.decodingError
        }
    }
    
    func fetchCourseInsights(courseId: String, userId: String? = nil) async throws -> CourseInsights {
        var components = URLComponents(url: url(for: "api/insights/course"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "courseId", value: courseId)]
        if let userId {
            items.append(URLQueryItem(name: "userId", value: userId))
        }
        components.queryItems = items
        
        guard let url = components.url else {
            var payload: [String: Any] = ["courseId": courseId]
            if let userId = userId {
                payload["userId"] = userId
            }
            DebugLogging.logAPI(endpoint: "insights/course", url: nil as URL?, method: "GET", payload: payload, error: APIError.invalidURL)
            throw APIError.invalidURL
        }
        
        var payload: [String: Any] = ["courseId": courseId]
        if let userId = userId {
            payload["userId"] = userId
        }
        DebugLogging.logAPI(endpoint: "insights/course", url: url, method: "GET", payload: payload)
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogging.logAPI(endpoint: "insights/course", url: url, method: "GET", payload: payload, responseData: data, error: APIError.invalidResponse)
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            DebugLogging.logAPI(endpoint: "insights/course", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: APIError.invalidResponse)
            throw APIError.invalidResponse
        }
        
        do {
            let insights = try JSONDecoder().decode(CourseInsights.self, from: data)
            DebugLogging.logAPI(endpoint: "insights/course", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, parsedModel: insights)
            return insights
        } catch {
            DebugLogging.logAPI(endpoint: "insights/course", url: url, method: "GET", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
            throw APIError.decodingError
        }
    }
    
    // MARK: - AI Caddie
    
    func askCaddie(
        payload: [String: String],
        fallbackProfile: PlayerProfile? = nil,
        metadata: [String: Any]? = nil,
        correlationId: String? = nil
    ) async throws -> ShotRecommendation {
        let url = self.url(for: "api/openai/complete")
        let resolvedCorrelationId = correlationId ?? UUID().uuidString
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(resolvedCorrelationId, forHTTPHeaderField: "X-Correlation-ID")
        
        var wirePayload: [String: Any] = payload
        let resolvedMetadata = buildRequestMetadata(recommendationType: "shot", overrides: metadata)
        for (key, value) in resolvedMetadata {
            wirePayload[key] = value
        }
        wirePayload["correlationId"] = resolvedCorrelationId
        request.httpBody = try JSONSerialization.data(withJSONObject: wirePayload)

        DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId])
        
        let fallbackDistanceYards = inferredDistanceYards(from: payload, metadata: metadata)

        do {
            let (data, httpResponse) = try await performRequest(
                request: request,
                endpoint: "openai/complete",
                correlationId: resolvedCorrelationId,
                safeToRetry: true
            )
            
            // Handle error responses
            if !(200...299).contains(httpResponse.statusCode) {
                // Try to decode error message
                if let errorResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
                   let errorMessage = errorResponse.error {
                    // Check if it's an API key missing error
                    let error: APIError
                    if errorMessage.contains("OPENAI_API_KEY missing") {
                        error = .serverError("Caddie AI isn't configured yet. Try again later.")
                    } else {
                        error = .serverError(errorMessage)
                    }
                    DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, responseData: data, error: error)
                    throw error
                }
                
                let error = APIError.invalidResponse
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, responseData: data, error: error)
                throw error
            }
            
            // Use OpenAIResponse from OpenAIClient.swift
            let openAIResponse: OpenAIResponse
            do {
                openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            } catch {
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, responseData: data, error: error)
                
                // Try fallback if we have profile
                if let profile = fallbackProfile {
                    let fallback = createFallbackRecommendation(
                        profile: profile,
                        message: "Server response was malformed. Using fallback recommendation.",
                        targetDistanceYards: fallbackDistanceYards
                    )
                    DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, parsedModel: fallback)
                    return fallback
                }
                throw APIError.decodingError
            }
            
            if let error = openAIResponse.error {
                // Check if it's an API key missing error
                let apiError: APIError
                if error.contains("OPENAI_API_KEY missing") {
                    apiError = .serverError("Caddie AI isn't configured yet. Try again later.")
                } else {
                    apiError = .serverError(error)
                }
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, responseData: data, error: apiError)
                throw apiError
            }
            
            guard let resultJSON = openAIResponse.resultJSON else {
                let error = APIError.missingResult
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, responseData: data, error: error)
                
                // Try fallback if we have profile
                if let profile = fallbackProfile {
                    let fallback = createFallbackRecommendation(
                        profile: profile,
                        message: "Server response was incomplete. Using fallback recommendation.",
                        targetDistanceYards: fallbackDistanceYards
                    )
                    DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, parsedModel: fallback)
                    return fallback
                }
                throw error
            }
            
            // Parse the JSON response defensively
            let cleanedJSON = stripMarkdownCodeFences(resultJSON)
            guard let jsonData = cleanedJSON.data(using: .utf8) else {
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, responseData: cleanedJSON.data(using: .utf8), error: NSError(domain: "APIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON string"]))
                
                // Try fallback if we have profile
                if let profile = fallbackProfile {
                    let fallback = createFallbackRecommendation(
                        profile: profile,
                        message: "Could not parse server response. Using fallback recommendation.",
                        targetDistanceYards: fallbackDistanceYards
                    )
                    DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, parsedModel: fallback)
                    return fallback
                }
                throw APIError.decodingError
            }
            
            // Try to decode, with fallback on failure
            do {
                let recommendation = try JSONDecoder().decode(ShotRecommendation.self, from: jsonData)
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, parsedModel: recommendation)
                return recommendation
            } catch {
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, responseData: jsonData, error: error)
                
                // Try fallback if we have profile
                if let profile = fallbackProfile {
                    let fallback = createFallbackRecommendation(
                        profile: profile,
                        message: "Could not parse recommendation. Using fallback recommendation.",
                        targetDistanceYards: fallbackDistanceYards
                    )
                    DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], responseStatus: httpResponse.statusCode, parsedModel: fallback)
                    return fallback
                }
                throw APIError.decodingError
            }
            
        } catch let error as APIError {
            throw error
        } catch {
            let apiError = APIError.serverError(error.localizedDescription)
            DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: ["correlationId": resolvedCorrelationId], error: apiError)
            throw apiError
        }
    }
    
    // MARK: - Fallback Recommendation
    
    private func createFallbackRecommendation(
        profile: PlayerProfile,
        message: String,
        targetDistanceYards: Int?
    ) -> ShotRecommendation {
        let defaultClub: ClubDistance
        if let targetDistanceYards {
            defaultClub = profile.clubs.min {
                abs($0.carryYards - targetDistanceYards) < abs($1.carryYards - targetDistanceYards)
            } ?? profile.clubs.first ?? ClubDistance(name: "7i", carryYards: 150)
        } else {
            defaultClub = profile.clubs.first ?? ClubDistance(name: "7i", carryYards: 150)
        }
        let distanceText = targetDistanceYards.map { "\($0) yards" } ?? "approximately \(defaultClub.carryYards) yards"
        DebugLogging.log(
            "Fallback recommendation used. reason=\(message) inferredDistance=\(targetDistanceYards?.description ?? "nil") selectedClub=\(defaultClub.name)",
            category: "Diagnostics"
        )
        
        return ShotRecommendation(
            club: defaultClub.name,
            aimOffsetYards: 0.0,
            shotShape: "Straight",
            narrative: "\(message) Recommended club: \(defaultClub.name) for \(distanceText). Aim for center of green.",
            confidence: 0.5,
            avoidZones: []
        )
    }

    private func inferredDistanceYards(from payload: [String: String], metadata: [String: Any]?) -> Int? {
        if let distance = metadata?["distanceYards"] as? Int {
            return distance
        }
        if let distance = metadata?["distanceYards"] as? Double {
            return Int(distance.rounded())
        }
        guard let userString = payload["user"],
              let userData = userString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: userData) as? [String: Any] else {
            return nil
        }
        return findDistanceRecursively(in: json)
    }

    private func findDistanceRecursively(in object: Any) -> Int? {
        if let number = object as? NSNumber {
            return Int(number.doubleValue.rounded())
        }
        if let dict = object as? [String: Any] {
            let distanceKeys = ["distanceYards", "distanceToTargetYards", "distance", "distanceToCenter"]
            for key in distanceKeys {
                if let value = dict[key] {
                    if let distance = findDistanceRecursively(in: value), distance > 0 {
                        return distance
                    }
                }
            }
            for value in dict.values {
                if let distance = findDistanceRecursively(in: value), distance > 0 {
                    return distance
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let distance = findDistanceRecursively(in: value), distance > 0 {
                    return distance
                }
            }
        }
        return nil
    }
    
    // MARK: - Feedback
    
    func sendFeedback(courseId: String, hole: Int, suggestedClub: String, feedback: String, shotId: String? = nil) async throws {
        let url = self.url(for: "api/feedback/caddie")
        
        var payload: [String: Any] = [
            "courseId": courseId,
            "hole": hole,
            "suggestedClub": suggestedClub,
            "feedback": feedback
        ]
        if let shotId {
            payload["shotId"] = shotId
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        DebugLogging.logAPI(endpoint: "feedback/caddie", url: url, method: "POST", payload: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogging.logAPI(endpoint: "feedback/caddie", url: url, method: "POST", payload: payload, responseData: data, error: APIError.invalidResponse)
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            DebugLogging.logAPI(endpoint: "feedback/caddie", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: APIError.invalidResponse)
            throw APIError.invalidResponse
        }
        
        do {
            // Backend returns { ok: true }
            let feedbackResponse = try JSONDecoder().decode(FeedbackResponse.self, from: data)
            DebugLogging.logAPI(endpoint: "feedback/caddie", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, parsedModel: feedbackResponse)
        } catch {
            DebugLogging.logAPI(endpoint: "feedback/caddie", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
            throw APIError.decodingError
        }
    }

    // MARK: - Recommendation Analytics

    func sendRecommendationEvent(_ event: RecommendationEventPayload) async {
        let url = self.url(for: "api/analytics/recommendation")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(event)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }
            if !(200...299).contains(httpResponse.statusCode) {
                DebugLogging.log("Recommendation event rejected with status \(httpResponse.statusCode)", category: "Analytics")
            }
        } catch {
            DebugLogging.log("Recommendation event send failed: \(error.localizedDescription)", category: "Analytics")
        }
    }

    func sendRecommendationFeedback(_ payload: RecommendationFeedbackPayload) async {
        let url = self.url(for: "api/analytics/feedback")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }
            if !(200...299).contains(httpResponse.statusCode) {
                DebugLogging.log("Recommendation feedback rejected with status \(httpResponse.statusCode)", category: "Analytics")
            }
        } catch {
            DebugLogging.log("Recommendation feedback send failed: \(error.localizedDescription)", category: "Analytics")
        }
    }

    func makeProfileSnapshot(playerProfile: PlayerProfile) -> RecommendationEventProfileSnapshot {
        let defaults = UserDefaults.standard
        var seriousness: String?
        var riskOffTee: String?
        var riskAroundHazards: String?
        var greenRiskPreference: String?
        if let profileData = defaults.data(forKey: "caddie_user_profile"),
           let storedProfile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            seriousness = storedProfile.seriousness
            riskOffTee = storedProfile.riskOffTee
            riskAroundHazards = storedProfile.riskAroundHazards
            greenRiskPreference = storedProfile.greenRiskPreference
        }

        let clubProfiles = playerProfile.clubs.map {
            RecommendationEventClubProfile(
                clubName: $0.name,
                carryYards: $0.carryYards,
                shotPreference: $0.shotPreference.displayName,
                confidenceLevel: $0.confidenceLevel.displayName,
                notes: $0.notes
            )
        }

        return RecommendationEventProfileSnapshot(
            golfGoal: playerProfile.golfGoal,
            seriousness: seriousness,
            riskOffTee: riskOffTee,
            riskAroundHazards: riskAroundHazards,
            greenRiskPreference: greenRiskPreference,
            clubs: clubProfiles
        )
    }

    func sendRecommendationEventNonBlocking(_ event: RecommendationEventPayload) {
        Task {
            await sendRecommendationEvent(event)
        }
    }

    func sendRecommendationFeedbackNonBlocking(_ payload: RecommendationFeedbackPayload) {
        Task {
            await sendRecommendationFeedback(payload)
        }
    }
    
    func analyzePutting(
        imageData: Data,
        courseId: String,
        holeNumber: Int,
        lat: Double? = nil,
        lon: Double? = nil,
        context: [String: String?] = [:],
        correlationId: String? = nil
    ) async throws -> Data {
        let url = self.url(for: "api/putting/analyze")
        let resolvedCorrelationId = correlationId ?? UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue(resolvedCorrelationId, forHTTPHeaderField: "X-Correlation-ID")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        appendMultipartField(&body, boundary: boundary, name: "photo", filename: "putting.jpg", mimeType: "image/jpeg", data: imageData)
        appendMultipartField(&body, boundary: boundary, name: "courseId", value: courseId)
        appendMultipartField(&body, boundary: boundary, name: "holeNumber", value: String(holeNumber))

        if let lat {
            appendMultipartField(&body, boundary: boundary, name: "lat", value: String(lat))
        }
        if let lon {
            appendMultipartField(&body, boundary: boundary, name: "lon", value: String(lon))
        }

        for (key, value) in context {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendMultipartField(&body, boundary: boundary, name: key, value: value)
            }
        }

        let metadata = buildRequestMetadata(recommendationType: "putt", overrides: nil)
        for (key, value) in metadata {
            appendMultipartField(&body, boundary: boundary, name: key, value: String(describing: value))
        }
        appendMultipartField(&body, boundary: boundary, name: "correlationId", value: resolvedCorrelationId)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        DebugLogging.logAPI(
            endpoint: "putting/analyze",
            url: url,
            method: "POST",
            payload: [
                "correlationId": resolvedCorrelationId,
                "recommendationType": "putt",
                "courseId": courseId,
                "holeNumber": holeNumber
            ]
        )

        let (data, httpResponse) = try await performRequest(
            request: request,
            endpoint: "putting/analyze",
            correlationId: resolvedCorrelationId,
            safeToRetry: true
        )

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data),
               let message = errorResponse.error {
                throw APIError.serverError(message)
            }
            throw APIError.serverError("Putting analysis failed (Status: \(httpResponse.statusCode)).")
        }

        return data
    }

    /// Text-only putting analysis — sends structured JSON (no image).
    func analyzePuttingText(context: PuttingContext, correlationId: String = UUID().uuidString) async throws -> PuttingRead {
        let url = self.url(for: "api/openai/complete")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(correlationId, forHTTPHeaderField: "X-Correlation-ID")

        var userPayload: [String: Any] = [
            "courseId": context.courseId,
            "courseName": context.courseName,
            "distanceFeet": context.distanceFeet,
            "shotType": "putt"
        ]
        if let h = context.holeNumber { userPayload["holeNumber"] = h }
        if let s = context.slope { userPayload["slope"] = s }
        if let g = context.greenSpeed { userPayload["greenSpeed"] = g }
        if let p = context.holePar { userPayload["par"] = p }

        let systemPrompt = """
        You are an expert golf caddie specializing in putting. Analyze the green conditions and provide a putting recommendation.
        Return ONLY valid JSON matching: {"breakDirection":"string","breakAmount":0.0,"speed":"string","narrative":"string","theLine":"string","theSpeed":"string","finalPicture":"string","commitmentCue":"string"}
        """

        let userJSON = (try? JSONSerialization.data(withJSONObject: userPayload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let body: [String: Any] = ["system": systemPrompt, "user": userJSON, "correlationId": correlationId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("[API] analyzePuttingText courseId=\(context.courseId) distanceFeet=\(context.distanceFeet)")
        #endif

        let (data, httpResponse) = try await performRequest(
            request: request,
            endpoint: "openai/complete (putting-text)",
            correlationId: correlationId,
            safeToRetry: true
        )

        guard (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("[API] analyzePuttingText status=\(httpResponse.statusCode)")
            if let raw = String(data: data, encoding: .utf8) { print("[API] raw response: \(raw)") }
            #endif
            throw APIError.serverError("Putting analysis failed (Status: \(httpResponse.statusCode)).")
        }

        let openAIResp = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let resultJSON = openAIResp.resultJSON, !resultJSON.isEmpty else {
            throw APIError.missingResult
        }

        var cleaned = resultJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let newline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: newline)...])
            }
        }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw APIError.decodingError
        }

        if let structured = try? JSONDecoder().decode(StructuredPuttingRead.self, from: jsonData) {
            return PuttingRead(from: structured)
        }
        return try JSONDecoder().decode(PuttingRead.self, from: jsonData)
    }

    private func buildRequestMetadata(recommendationType: String, overrides: [String: Any]?) -> [String: Any] {
        var metadata: [String: Any] = [:]
        metadata["recommendationType"] = recommendationType

        let defaults = UserDefaults.standard
        if let userId = defaults.string(forKey: "caddie_user_id"), !userId.isEmpty {
            metadata["userId"] = userId
        }

        if let profileData = defaults.data(forKey: "caddie_user_profile"),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            if !profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata["firstName"] = profile.firstName
            }
            if !profile.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadata["email"] = profile.email
            }
            if let golfGoal = profile.golfGoal, !golfGoal.isEmpty {
                metadata["golfGoal"] = golfGoal
            }
            if let greenRisk = profile.greenRiskPreference, !greenRisk.isEmpty {
                metadata["greenRiskPreference"] = greenRisk
            }
            if let puttingTendencies = profile.puttingTendencies, !puttingTendencies.isEmpty {
                metadata["puttingTendencies"] = puttingTendencies
            }
            if let riskOffTee = profile.riskOffTee, !riskOffTee.isEmpty {
                metadata["riskOffTee"] = riskOffTee
            }
            if let riskAroundHazards = profile.riskAroundHazards, !riskAroundHazards.isEmpty {
                metadata["riskAroundHazards"] = riskAroundHazards
            }

            let summarizedClubs = profile.clubDistances.map { [
                "clubName": $0.name,
                "carryYards": $0.carryYards,
                "shotPreference": $0.shotPreference.displayName,
                "confidenceLevel": $0.confidenceLevel.displayName
            ] }
            if !summarizedClubs.isEmpty {
                metadata["clubDistances"] = summarizedClubs
            }
        }

        if let overrides {
            for (key, value) in overrides {
                metadata[key] = value
            }
        }

        return metadata
    }

    private func appendMultipartField(_ body: inout Data, boundary: String, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append(value.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
    }

    private func appendMultipartField(_ body: inout Data, boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    private func performRequest(
        request: URLRequest,
        endpoint: String,
        correlationId: String,
        safeToRetry: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0

        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }

                if safeToRetry && shouldRetry(statusCode: httpResponse.statusCode) && attempt < maxRetryCount {
                    attempt += 1
                    let delayNs = UInt64(pow(2.0, Double(attempt - 1)) * 300_000_000)
                    DebugLogging.log("Retrying \(endpoint) correlationId=\(correlationId) attempt=\(attempt)", category: "API")
                    try await Task.sleep(nanoseconds: delayNs)
                    continue
                }

                return (data, httpResponse)
            } catch {
                if safeToRetry && shouldRetry(error: error) && attempt < maxRetryCount {
                    attempt += 1
                    let delayNs = UInt64(pow(2.0, Double(attempt - 1)) * 300_000_000)
                    DebugLogging.log("Retrying \(endpoint) correlationId=\(correlationId) attempt=\(attempt) due to \(error.localizedDescription)", category: "API")
                    try await Task.sleep(nanoseconds: delayNs)
                    continue
                }

                if let urlError = error as? URLError, urlError.code == .timedOut {
                    throw APIError.timeout
                }
                throw error
            }
        }
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        [502, 503, 504].contains(statusCode)
    }

    private func shouldRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            URLError.timedOut,
            URLError.networkConnectionLost,
            URLError.notConnectedToInternet,
            URLError.cannotFindHost,
            URLError.cannotConnectToHost
        ].contains(urlError.code)
    }

    // MARK: - Helpers
    
    private func stripMarkdownCodeFences(_ jsonString: String) -> String {
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleaned.hasPrefix("```") {
            if let jsonIndex = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: jsonIndex)...])
            } else {
                cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
                cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            }
        }
        
        if cleaned.hasSuffix("```") {
            if let lastNewlineIndex = cleaned.lastIndex(of: "\n") {
                cleaned = String(cleaned[..<lastNewlineIndex])
            } else {
                cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Response Models

// Note: OpenAIResponse is defined in OpenAIClient.swift

struct RecommendationEventContextSnapshot: Codable {
    let courseName: String?
    let city: String?
    let state: String?
    let holeNumber: Int?
    let distanceToTarget: Double?
    let lie: String?
    let shotType: String?
    let hazards: [String]
}

struct RecommendationEventClubProfile: Codable {
    let clubName: String
    let carryYards: Int
    let shotPreference: String
    let confidenceLevel: String
    let notes: String?
}

struct RecommendationEventProfileSnapshot: Codable {
    let golfGoal: String?
    let seriousness: String?
    let riskOffTee: String?
    let riskAroundHazards: String?
    let greenRiskPreference: String?
    let clubs: [RecommendationEventClubProfile]
}

struct RecommendationEventOutputSnapshot: Codable {
    let aiSelectedClub: String?
    let finalRecommendedClub: String?
    let recommendationText: String
    let normalizationOccurred: Bool
    let normalizationReason: String?
    let fallbackOccurred: Bool
    let fallbackReason: String?
    let topCandidateClubs: [String]
}

struct RecommendationEventDiagnosticsSnapshot: Codable {
    let targetDistanceYards: Int?
    let playsLikeDistanceYards: Int?
    let weatherSourceQuality: String?
    let elevationSourceQuality: String?
    let photoIncluded: Bool
    let photoReferenced: Bool
    let requestDurationMs: Int?
}

struct RecommendationEventPayload: Codable {
    let recommendationId: String
    let userId: String
    let sessionId: String
    let recommendationType: RecommendationType
    let createdAt: String
    let context: RecommendationEventContextSnapshot
    let profile: RecommendationEventProfileSnapshot?
    let output: RecommendationEventOutputSnapshot
    let diagnostics: RecommendationEventDiagnosticsSnapshot
}

struct RecommendationFeedbackPayload: Codable {
    let feedbackId: String
    let recommendationId: String
    let userId: String
    let sessionId: String
    let recommendationType: RecommendationType
    let helpful: Bool
    let feedbackReason: RecommendationFeedbackReason?
    let freeTextNote: String?
    let rating: Int?
    let submittedAt: String
}

struct FeedbackResponse: Codable {
    let ok: Bool?
}

struct HealthResponse: Codable {
    let ok: Bool
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case timeout
    case serverError(String)
    case missingResult
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .timeout:
            return "Request timed out. Please try again."
        case .serverError(let message):
            return "Server error: \(message)"
        case .missingResult:
            return "Missing result from server"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}
