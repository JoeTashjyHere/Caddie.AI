//
//  AILogger.swift
//  Caddie.ai
//
//  Centralized logging utility for AI-related operations
//

import Foundation

@MainActor
class AILogger {
    static let shared = AILogger()
    
    private init() {}
    
    /// Logs an AI request with truncated response for debugging
    func logRequest(endpoint: String, payload: [String: Any], response: String?, error: Error? = nil) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🤖 AI Request [\(timestamp)]")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Endpoint: \(endpoint)")
        
        // Log payload (truncated if too long)
        if let payloadJSON = try? JSONSerialization.data(withJSONObject: payload),
           let payloadString = String(data: payloadJSON, encoding: .utf8) {
            let truncatedPayload = truncateString(payloadString, maxLength: 500)
            print("📤 Payload: \(truncatedPayload)")
        }
        
        if let error = error {
            print("❌ Error: \(error.localizedDescription)")
            if let apiError = error as? APIError {
                print("   Type: \(apiError)")
            }
        } else if let response = response {
            let truncatedResponse = truncateString(response, maxLength: 500)
            print("📥 Response: \(truncatedResponse)")
        } else {
            print("⚠️  No response or error")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Logs a photo upload request
    func logPhotoUpload(courseId: String, holeNumber: Int, shotType: String, success: Bool, error: Error? = nil) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📸 Photo Upload [\(timestamp)]")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Course: \(courseId)")
        print("📍 Hole: \(holeNumber)")
        print("📍 Shot Type: \(shotType)")
        print(success ? "✅ Success" : "❌ Failed")
        
        if let error = error {
            print("   Error: \(error.localizedDescription)")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Logs a parsing error with context
    func logParsingError(endpoint: String, rawResponse: String, error: Error) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⚠️  Parsing Error [\(timestamp)]")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Endpoint: \(endpoint)")
        print("❌ Error: \(error.localizedDescription)")
        let truncatedResponse = truncateString(rawResponse, maxLength: 300)
        print("📥 Raw Response: \(truncatedResponse)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Helper to truncate long strings
    private func truncateString(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        let truncated = String(string.prefix(maxLength))
        return "\(truncated)... [truncated \(string.count - maxLength) chars]"
    }
}

struct AnalyticsEvent: Codable {
    let id: String
    let eventType: String
    let timestamp: String
    let userId: String
    let sessionId: String
    let recommendationType: String?
    let correlationId: String?
    let courseName: String?
    let city: String?
    let state: String?
    let holeNumber: Int?
    let distanceToTarget: Double?
    let lie: String?
    let shotType: String?
    let hazards: String?
    let recommendationText: String?
    let success: Bool?
    let durationMs: Int?
    let errorMessage: String?
    let feedbackRating: String?
    let feedbackComments: String?
}

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let endpoint = "/api/analytics/events"
    private let userDefaults = UserDefaults.standard
    private let userKey = "caddie_user_id"
    private let sessionKey = "caddie_session_id"

    private init() {
        if userDefaults.string(forKey: userKey) == nil {
            userDefaults.set(UUID().uuidString, forKey: userKey)
        }
        if userDefaults.string(forKey: sessionKey) == nil {
            userDefaults.set(UUID().uuidString, forKey: sessionKey)
        }
    }

    var userId: String {
        if let existing = userDefaults.string(forKey: userKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        userDefaults.set(created, forKey: userKey)
        return created
    }

    var sessionId: String {
        if let existing = userDefaults.string(forKey: sessionKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        userDefaults.set(created, forKey: sessionKey)
        return created
    }

    func refreshSession() {
        userDefaults.set(UUID().uuidString, forKey: sessionKey)
    }

    func track(_ event: AnalyticsEvent) {
        Task.detached(priority: .utility) {
            guard let url = URL(string: APIService.baseURLString + self.endpoint) else {
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            guard let body = try? JSONEncoder().encode(event) else {
                return
            }
            request.httpBody = body

            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                #if DEBUG
                print("⚠️ Analytics track failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
