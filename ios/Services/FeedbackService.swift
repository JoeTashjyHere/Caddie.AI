//
//  FeedbackService.swift
//  Caddie.ai
//

import Foundation

struct ShotFeedback: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let courseName: String
    let courseId: String?
    let holeNumber: Int
    let clubSuggested: String
    let userRating: Bool
    
    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         courseName: String,
         courseId: String? = nil,
         holeNumber: Int,
         clubSuggested: String,
         userRating: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.courseName = courseName
        self.courseId = courseId
        self.holeNumber = holeNumber
        self.clubSuggested = clubSuggested
        self.userRating = userRating
    }
}

@MainActor
class FeedbackService: ObservableObject {
    static let shared = FeedbackService()
    
    @Published private(set) var feedbackHistory: [ShotFeedback] = []
    
    private let userDefaultsKey = "shotFeedbackHistory"
    
    private init() {
        loadFeedback()
    }
    
    func recordFeedback(_ feedback: ShotFeedback) {
        feedbackHistory.append(feedback)
        saveFeedback()
    }
    
    func getAccuracy(forCourseId courseId: String? = nil) -> Double? {
        let relevantFeedback = feedbackHistory.filter { feedback in
            courseId == nil || feedback.courseId == courseId
        }
        guard !relevantFeedback.isEmpty else { return nil }
        
        let positiveFeedbackCount = relevantFeedback.filter { $0.userRating }.count
        return Double(positiveFeedbackCount) / Double(relevantFeedback.count)
    }
    
    /// Submit open-ended feedback for a shot or putt. Persists locally and sends to backend (non-blocking).
    func submitCaddieFeedback(
        context: ShotContext,
        courseId: String?,
        courseName: String?,
        shotRecommendation: ShotRecommendation?,
        puttingRead: PuttingRead?,
        feedbackText: String
    ) {
        let cid = courseId ?? "unknown"
        let hole = context.hole
        let clubSuggested = shotRecommendation?.club ?? puttingRead.map { "Putt: \($0.speed)" } ?? "N/A"
        
        // Persist for future ML training (extend storage as needed)
        let feedback = ShotFeedback(
            courseName: courseName ?? "Course",
            courseId: cid,
            holeNumber: hole,
            clubSuggested: clubSuggested,
            userRating: !feedbackText.isEmpty
        )
        recordFeedback(feedback)
        
        // Non-blocking backend call
        guard !feedbackText.isEmpty else { return }
        Task {
            await self.sendCaddieFeedback(
                courseId: cid,
                hole: hole,
                clubSuggested: clubSuggested,
                userFeedback: feedbackText
            )
        }
    }
    
    func sendCaddieFeedback(courseId: String, hole: Int, clubSuggested: String, userFeedback: String) async {
        let feedbackPayload: [String: Any] = [
            "courseId": courseId,
            "hole": hole,
            "clubSuggested": clubSuggested,
            "userFeedback": userFeedback,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Use APIService as single source of truth for base URL
        let url = APIService.getBaseURL().appendingPathComponent("api/feedback/caddie")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: feedbackPayload)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Error: Invalid response from feedback endpoint")
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                print("✅ Caddie feedback sent successfully")
            } else {
                print("⚠️ Feedback endpoint returned status: \(httpResponse.statusCode)")
            }
        } catch {
            print("Error sending caddie feedback: \(error)")
        }
    }

    func submitRecommendationFeedback(
        recommendationId: String,
        recommendationType: RecommendationType,
        helpful: Bool,
        feedbackReason: RecommendationFeedbackReason?,
        freeTextNote: String?,
        rating: Int?,
        historyStore: HistoryStore? = nil
    ) {
        let trimmedRecommendationId = recommendationId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRecommendationId.isEmpty else { return }

        let record = RecommendationFeedbackRecord(
            helpful: helpful,
            feedbackReason: feedbackReason,
            freeTextNote: freeTextNote?.trimmingCharacters(in: .whitespacesAndNewlines),
            rating: rating,
            submittedAt: Date()
        )
        historyStore?.upsertFeedback(for: trimmedRecommendationId, feedback: record)

        let payload = RecommendationFeedbackPayload(
            feedbackId: UUID().uuidString,
            recommendationId: trimmedRecommendationId,
            userId: AnalyticsService.shared.userId,
            sessionId: AnalyticsService.shared.sessionId,
            recommendationType: recommendationType,
            helpful: helpful,
            feedbackReason: feedbackReason,
            freeTextNote: record.freeTextNote,
            rating: rating,
            submittedAt: ISO8601DateFormatter().string(from: record.submittedAt)
        )

        APIService.shared.sendRecommendationFeedbackNonBlocking(payload)
    }
    
    private func saveFeedback() {
        if let encoded = try? JSONEncoder().encode(feedbackHistory) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadFeedback() {
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decodedFeedback = try? JSONDecoder().decode([ShotFeedback].self, from: savedData) {
            feedbackHistory = decodedFeedback
        }
    }
}
