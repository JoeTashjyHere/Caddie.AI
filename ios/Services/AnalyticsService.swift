//
//  AnalyticsService.swift
//  Caddie.ai
//
//  Product analytics (console) + legacy API payload forwarding.
//

import Foundation

// MARK: - Product events (console)

enum AnalyticsEvent {
    // Onboarding
    case onboardingStarted
    case onboardingCompleted(provider: String)

    // Auth
    case authCompleted(provider: String)
    case authFailed(provider: String, error: String)

    // App lifecycle
    case appOpened
    case sessionStarted(sessionId: String)

    // Rounds
    case roundStarted(courseId: String, roundLength: String, isRoundBacked: Bool)
    case roundCompleted(courseId: String, totalScore: Int, vsPar: Int)

    // Recommendations
    case recommendationRequested(courseId: String, holeNumber: Int?, shotType: String, hasPhoto: Bool, isRoundBacked: Bool)
    case recommendationCompleted(courseId: String, holeNumber: Int?, shotType: String, hasPhoto: Bool, isRoundBacked: Bool, responseTimeMs: Int, confidence: String?)
    case recommendationError(courseId: String?, holeNumber: Int?, shotType: String, hasPhoto: Bool, isRoundBacked: Bool, errorMessage: String)

    // Putting
    case puttingRequested(courseId: String, holeNumber: Int?, hasPhoto: Bool, isRoundBacked: Bool)
    case puttingCompleted(courseId: String, holeNumber: Int?, hasPhoto: Bool, isRoundBacked: Bool, responseTimeMs: Int)

    // Profile
    case profileEdited(field: String)
    case clubEdited(clubType: String, action: String)

    var eventName: String {
        switch self {
        case .onboardingStarted: return "onboarding_started"
        case .onboardingCompleted: return "onboarding_completed"
        case .authCompleted: return "auth_completed"
        case .authFailed: return "auth_failed"
        case .appOpened: return "app_opened"
        case .sessionStarted: return "session_started"
        case .roundStarted: return "roundStarted"
        case .roundCompleted: return "roundCompleted"
        case .recommendationRequested: return "recommendationRequested"
        case .recommendationCompleted: return "recommendationCompleted"
        case .recommendationError: return "recommendationError"
        case .puttingRequested: return "puttingRequested"
        case .puttingCompleted: return "puttingCompleted"
        case .profileEdited: return "profile_edited"
        case .clubEdited: return "club_edited"
        }
    }

    var properties: [String: Any] {
        switch self {
        case .onboardingStarted:
            return [:]
        case .onboardingCompleted(let provider):
            return ["provider": provider]
        case .authCompleted(let provider):
            return ["provider": provider]
        case .authFailed(let provider, let error):
            return ["provider": provider, "error": error]
        case .appOpened:
            return [:]
        case .sessionStarted(let sessionId):
            return ["sessionId": sessionId]
        case .profileEdited(let field):
            return ["field": field]
        case .clubEdited(let clubType, let action):
            return ["clubType": clubType, "action": action]
        case .roundStarted(let courseId, let roundLength, let isRoundBacked):
            return ["courseId": courseId, "roundLength": roundLength, "isRoundBacked": isRoundBacked]
        case .roundCompleted(let courseId, let totalScore, let vsPar):
            return ["courseId": courseId, "totalScore": totalScore, "vsPar": vsPar]
        case .recommendationRequested(let courseId, let holeNumber, let shotType, let hasPhoto, let isRoundBacked):
            var d: [String: Any] = ["courseId": courseId, "shotType": shotType, "hasPhoto": hasPhoto, "isRoundBacked": isRoundBacked]
            if let h = holeNumber { d["holeNumber"] = h }
            return d
        case .recommendationCompleted(let courseId, let holeNumber, let shotType, let hasPhoto, let isRoundBacked, let responseTimeMs, let confidence):
            var d: [String: Any] = ["courseId": courseId, "shotType": shotType, "hasPhoto": hasPhoto, "isRoundBacked": isRoundBacked, "responseTimeMs": responseTimeMs, "success": true]
            if let h = holeNumber { d["holeNumber"] = h }
            if let c = confidence { d["confidence"] = c }
            return d
        case .recommendationError(let courseId, let holeNumber, let shotType, let hasPhoto, let isRoundBacked, let errorMessage):
            var d: [String: Any] = ["shotType": shotType, "hasPhoto": hasPhoto, "isRoundBacked": isRoundBacked, "success": false, "errorMessage": errorMessage]
            if let cid = courseId { d["courseId"] = cid }
            if let h = holeNumber { d["holeNumber"] = h }
            return d
        case .puttingRequested(let courseId, let holeNumber, let hasPhoto, let isRoundBacked):
            var d: [String: Any] = ["courseId": courseId, "shotType": "putt", "hasPhoto": hasPhoto, "isRoundBacked": isRoundBacked]
            if let h = holeNumber { d["holeNumber"] = h }
            return d
        case .puttingCompleted(let courseId, let holeNumber, let hasPhoto, let isRoundBacked, let responseTimeMs):
            var d: [String: Any] = ["courseId": courseId, "shotType": "putt", "hasPhoto": hasPhoto, "isRoundBacked": isRoundBacked, "responseTimeMs": responseTimeMs, "success": true]
            if let h = holeNumber { d["holeNumber"] = h }
            return d
        }
    }
}

/// Codable payload for `/api/analytics/events` (legacy pipeline).
struct AnalyticsPayload: Codable {
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

    /// Product analytics: structured console log (future: Segment, Firebase, etc.).
    func track(event: AnalyticsEvent) {
        validateAndTrack(event.eventName, properties: event.properties)
    }

    /// Freeform event with key-value properties.
    func track(_ name: String, properties: [String: Any]) {
        validateAndTrack(name, properties: properties)
    }

    private func validateAndTrack(_ name: String, properties: [String: Any]) {
        #if DEBUG
        print("[ANALYTICS] Event: \(name)")
        print("[ANALYTICS] Properties: \(Self.formatPayload(properties))")
        #endif
    }

    private static func formatPayload(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return payload.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        }
        return s
    }

    /// Legacy server-side analytics.
    func track(_ payload: AnalyticsPayload) {
        Task.detached(priority: .utility) {
            guard let url = URL(string: APIConfig.baseURLString + self.endpoint) else {
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            guard let body = try? JSONEncoder().encode(payload) else {
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
