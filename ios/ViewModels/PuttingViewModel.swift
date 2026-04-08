//
//  PuttingViewModel.swift
//  Caddie.ai
//

import Foundation
import SwiftUI
import UIKit

@MainActor
class PuttingViewModel: ObservableObject {
    @Published var puttingRead: PuttingRead?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var requestState: RequestState = .idle

    private let apiService = APIService.shared
    var historyStore: HistoryStore?
    private var inFlightTask: Task<Void, Never>?
    private var lastRequest: (imageData: Data, courseId: String, holeNumber: Int, lat: Double?, lon: Double?, context: [String: String?], correlationId: String)?

    func analyzePutting(
        imageData: Data,
        courseId: String,
        holeNumber: Int,
        lat: Double? = nil,
        lon: Double? = nil,
        context: [String: String?] = [:],
        correlationId: String = UUID().uuidString
    ) async {
        guard !requestState.isSubmitting else { return }
        inFlightTask?.cancel()
        lastRequest = (imageData, courseId, holeNumber, lat, lon, context, correlationId)

        isLoading = true
        errorMessage = nil
        puttingRead = nil
        requestState = .submitting
        let startedAt = Date()
        AnalyticsService.shared.track(event: .puttingRequested(courseId: courseId, holeNumber: holeNumber, hasPhoto: true, isRoundBacked: true))

        inFlightTask = Task { [weak self] in
            guard let self else { return }

            do {
                var mergedContext = context
                if mergedContext["holeNumber"] == nil {
                    mergedContext["holeNumber"] = String(holeNumber)
                }
                let responseData = try await apiService.analyzePutting(
                    imageData: imageData,
                    courseId: courseId,
                    holeNumber: holeNumber,
                    lat: lat,
                    lon: lon,
                    context: mergedContext,
                    correlationId: correlationId
                )

                let parsedRead = try JSONDecoder().decode(PuttingRead.self, from: responseData)
                if Task.isCancelled { return }

                puttingRead = parsedRead
                isLoading = false
                requestState = .success
                let recommendationId = UUID().uuidString

                if let historyStore = historyStore {
                    let item = HistoryItem(
                        type: .putt,
                        courseName: nil,
                        recommendationText: parsedRead.narrative,
                        rawAIResponse: nil,
                        thumbnailData: nil,
                        recommendationId: recommendationId,
                        shotMetadata: nil,
                        puttMetadata: PuttHistoryMetadata(
                            puttDistanceFeet: nil,
                            breakDirection: parsedRead.breakDirection,
                            speedRecommendation: parsedRead.speed,
                            greenSlopeInference: nil,
                            courseName: nil,
                            holeNumber: nil,
                            timestamp: Date()
                        )
                    )
                    historyStore.add(item)
                }

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                AnalyticsService.shared.track(event: .puttingCompleted(courseId: courseId, holeNumber: holeNumber, hasPhoto: true, isRoundBacked: true, responseTimeMs: durationMs))
                AnalyticsService.shared.track(
                    AnalyticsPayload(
                        id: UUID().uuidString,
                        eventType: "recommendation_completed",
                        timestamp: ISO8601DateFormatter().string(from: Date()),
                        userId: AnalyticsService.shared.userId,
                        sessionId: AnalyticsService.shared.sessionId,
                        recommendationType: "putt",
                        correlationId: correlationId,
                        courseName: nil,
                        city: nil,
                        state: nil,
                        holeNumber: holeNumber,
                        distanceToTarget: nil,
                        lie: nil,
                        shotType: nil,
                        hazards: nil,
                        recommendationText: parsedRead.narrative,
                        success: true,
                        durationMs: durationMs,
                        errorMessage: nil,
                        feedbackRating: nil,
                        feedbackComments: nil
                    )
                )
                APIService.shared.sendRecommendationEventNonBlocking(
                    RecommendationEventPayload(
                        recommendationId: recommendationId,
                        userId: AnalyticsService.shared.userId,
                        sessionId: AnalyticsService.shared.sessionId,
                        recommendationType: .putt,
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        context: RecommendationEventContextSnapshot(
                            courseName: nil,
                            city: nil,
                            state: nil,
                            holeNumber: holeNumber,
                            distanceToTarget: nil,
                            lie: "green",
                            shotType: "putt",
                            hazards: []
                        ),
                        profile: nil,
                        output: RecommendationEventOutputSnapshot(
                            aiSelectedClub: nil,
                            finalRecommendedClub: nil,
                            recommendationText: parsedRead.narrative,
                            normalizationOccurred: false,
                            normalizationReason: nil,
                            fallbackOccurred: false,
                            fallbackReason: nil,
                            topCandidateClubs: []
                        ),
                        diagnostics: RecommendationEventDiagnosticsSnapshot(
                            targetDistanceYards: nil,
                            playsLikeDistanceYards: nil,
                            weatherSourceQuality: nil,
                            elevationSourceQuality: nil,
                            photoIncluded: true,
                            photoReferenced: false,
                            requestDurationMs: durationMs
                        )
                    )
                )

                AILogger.shared.logPhotoUpload(courseId: courseId, holeNumber: holeNumber, shotType: "putt", success: true, error: nil as Error?)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                if Task.isCancelled { return }
                let message: String
                if let apiError = error as? APIError {
                    message = apiError.errorDescription ?? "Putting analysis failed. Please try again."
                } else {
                    message = "Putting analysis failed: \(error.localizedDescription). Please try again."
                }
                errorMessage = message
                isLoading = false
                requestState = .failure(errorMessage: message, debugId: correlationId)

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                AnalyticsService.shared.track(event: .recommendationError(courseId: courseId, holeNumber: holeNumber, shotType: "putt", hasPhoto: true, isRoundBacked: true, errorMessage: message))
                AnalyticsService.shared.track(
                    AnalyticsPayload(
                        id: UUID().uuidString,
                        eventType: "recommendation_failed",
                        timestamp: ISO8601DateFormatter().string(from: Date()),
                        userId: AnalyticsService.shared.userId,
                        sessionId: AnalyticsService.shared.sessionId,
                        recommendationType: "putt",
                        correlationId: correlationId,
                        courseName: nil,
                        city: nil,
                        state: nil,
                        holeNumber: holeNumber,
                        distanceToTarget: nil,
                        lie: nil,
                        shotType: nil,
                        hazards: nil,
                        recommendationText: nil,
                        success: false,
                        durationMs: durationMs,
                        errorMessage: message,
                        feedbackRating: nil,
                        feedbackComments: nil
                    )
                )

                AILogger.shared.logPhotoUpload(courseId: courseId, holeNumber: holeNumber, shotType: "putt", success: false, error: error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }

        await inFlightTask?.value
    }

    func retryLastRequest() async {
        guard let lastRequest else { return }
        await analyzePutting(
            imageData: lastRequest.imageData,
            courseId: lastRequest.courseId,
            holeNumber: lastRequest.holeNumber,
            lat: lastRequest.lat,
            lon: lastRequest.lon,
            context: lastRequest.context,
            correlationId: UUID().uuidString
        )
    }
}
