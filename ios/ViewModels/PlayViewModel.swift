//
//  PlayViewModel.swift
//  Caddie.ai
//

import Foundation
import CoreLocation
import UIKit

@MainActor
class PlayViewModel: ObservableObject {
    @Published var recommendation: ShotRecommendation?
    @Published var state: ViewState = .idle
    @Published var shotFlowState: ShotFlowState = .idle
    @Published var recommendationAccepted: Bool = false
    @Published var currentDistance: Double?
    @Published var currentHole: Int = 1
    @Published var lastRecommendationId: String?
    
    // Legacy computed properties for backward compatibility
    var isLoading: Bool {
        state == .loading
    }
    
    var errorMessage: String? {
        state.errorMessage
    }
    
    func resetShotFlow() {
        shotFlowState = .idle
        recommendationAccepted = false
        recommendation = nil
    }
    
    func acceptRecommendation() {
        guard shotFlowState == .showingRecommendation else { return }
        recommendationAccepted = true
        shotFlowState = .recommendationAccepted
    }
    
    // Main entry point: "Ask Caddie" gathers all context
    func askCaddie(profile: PlayerProfile, location: CLLocationCoordinate2D?, holeNumber: Int, photo: UIImage? = nil) async {
        guard let location = location else {
            state = .error("Location not available")
            shotFlowState = .error("Location not available")
            return
        }
        
        // Reset for new shot flow
        recommendationAccepted = false
        recommendation = nil
        state = .loading
        shotFlowState = photo != nil ? .waitingForPhoto : .sendingToAI
        let startedAt = Date()
        
        do {
            let course = CourseService.shared.getCurrentCourse()
            
            let holeContext = try await CourseService.shared.resolveCourseAndHole(at: location)
            var finalHoleContext = holeContext
            finalHoleContext.holeNumber = holeNumber
            
            let weather: WeatherSnapshot
            do {
                weather = try await WeatherService.shared.fetchWeather(at: location)
            } catch {
                weather = WeatherSnapshot(windMph: 0, windDirDeg: 0, tempF: 70, source: .fallbackStub)
            }
            
            let elevationSnapshot: ElevationSnapshot
            do {
                elevationSnapshot = try await ElevationService.shared.elevationDelta(
                    from: location,
                    to: finalHoleContext.centerOfGreen
                )
            } catch {
                elevationSnapshot = ElevationSnapshot(deltaYards: 0, source: .fallbackStub)
            }
            
            let playerLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let greenLocation = CLLocation(latitude: finalHoleContext.centerOfGreen.latitude, longitude: finalHoleContext.centerOfGreen.longitude)
            let distanceToCenter = playerLocation.distance(from: greenLocation) * 1.09361
            
            let shotContext = ShotContext(
                hole: holeNumber,
                playerCoordinate: location,
                targetCoordinate: finalHoleContext.centerOfGreen,
                distanceToCenter: distanceToCenter,
                elevationDelta: elevationSnapshot.deltaYards,
                windSpeedMph: weather.windMph,
                windDirectionDeg: weather.windDirDeg,
                temperatureF: weather.tempF,
                weatherSource: weather.source,
                elevationSource: elevationSnapshot.source
            )
            
            // Update state to waiting for recommendation
            shotFlowState = .waitingForRecommendation
            
            // getRecommendation now returns fallback instead of throwing (with automatic fallback chain)
            let rec = try await RecommenderService.shared.getRecommendation(
                profile: profile,
                context: shotContext,
                hazards: finalHoleContext.hazards,
                course: course,
                photo: photo
            )
            RecommenderService.shared.setLastDiagnosticsRequestDuration(Int(Date().timeIntervalSince(startedAt) * 1000))
            let recommendationId = UUID().uuidString
            lastRecommendationId = recommendationId
            
            currentDistance = distanceToCenter
            currentHole = holeNumber
            recommendation = rec
            sendRecommendationEvent(
                recommendationId: recommendationId,
                profile: profile,
                context: shotContext,
                courseName: course?.name,
                hazards: finalHoleContext.hazards,
                recommendation: rec,
                durationMs: Int(Date().timeIntervalSince(startedAt) * 1000)
            )
            
            // Move to showing recommendation state
            shotFlowState = .showingRecommendation
            recommendationAccepted = false
            
            // Check if it's a fallback recommendation
            if rec.narrative.contains("⚠️ Fallback recommendation") {
                state = .loaded // Show as loaded even if fallback
                DebugLogging.log("⚠️ Using fallback recommendation", category: "ShotFlow")
            } else {
                state = .loaded
            }
        } catch {
            // This should rarely happen now since getRecommendation returns fallback
            let errorMessage = "An error occurred: \(error.localizedDescription). Please try again."
            state = .error(errorMessage)
            shotFlowState = .error(errorMessage)
            print("Error asking caddie: \(error)")
        }
    }
    
    func sendFeedback(success: Bool, actualClub: String? = nil) {
        // This is for general feedback, not specific caddie feedback
        print("General Feedback: \(success ? "👍" : "👎")")
    }
    
    // Send feedback to backend for learning loop
    func sendCaddieFeedback(positive: Bool) {
        guard let recommendation = recommendation,
              let course = CourseService.shared.getCurrentCourse() else {
            print("Cannot send feedback: missing recommendation or course")
            return
        }
        
        Task {
            await FeedbackService.shared.sendCaddieFeedback(
                courseId: course.id,
                hole: currentHole,
                clubSuggested: recommendation.club,
                userFeedback: positive ? "positive" : "negative"
            )
        }
    }

    private func sendRecommendationEvent(
        recommendationId: String,
        profile: PlayerProfile,
        context: ShotContext,
        courseName: String?,
        hazards: [String],
        recommendation: ShotRecommendation,
        durationMs: Int
    ) {
        let diagnostics = RecommenderService.shared.lastDiagnostics
        let payload = RecommendationEventPayload(
            recommendationId: recommendationId,
            userId: AnalyticsService.shared.userId,
            sessionId: AnalyticsService.shared.sessionId,
            recommendationType: .shot,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            context: RecommendationEventContextSnapshot(
                courseName: courseName,
                city: nil,
                state: nil,
                holeNumber: context.hole,
                distanceToTarget: context.distanceToCenter,
                lie: context.lieType,
                shotType: "Approach",
                hazards: hazards
            ),
            profile: APIService.shared.makeProfileSnapshot(playerProfile: profile),
            output: RecommendationEventOutputSnapshot(
                aiSelectedClub: diagnostics?.aiChosenClub,
                finalRecommendedClub: recommendation.club,
                recommendationText: recommendation.narrative,
                normalizationOccurred: diagnostics?.normalizationOccurred ?? false,
                normalizationReason: diagnostics?.normalizationReason,
                fallbackOccurred: diagnostics?.fallbackUsed ?? false,
                fallbackReason: diagnostics?.fallbackReason,
                topCandidateClubs: diagnostics?.candidates.map { $0.club } ?? []
            ),
            diagnostics: RecommendationEventDiagnosticsSnapshot(
                targetDistanceYards: diagnostics?.targetDistanceYards ?? Int(context.distanceToCenter.rounded()),
                playsLikeDistanceYards: diagnostics?.playsLikeDistanceYards,
                weatherSourceQuality: diagnostics?.weatherSource ?? context.weatherSource.rawValue,
                elevationSourceQuality: diagnostics?.elevationSource ?? context.elevationSource.rawValue,
                photoIncluded: false,
                photoReferenced: false,
                requestDurationMs: diagnostics?.requestDurationMs ?? durationMs
            )
        )
        APIService.shared.sendRecommendationEventNonBlocking(payload)
    }
}
