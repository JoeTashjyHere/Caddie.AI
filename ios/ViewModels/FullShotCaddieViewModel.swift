//
//  FullShotCaddieViewModel.swift
//  Caddie.ai
//
//  ViewModel managing the full-shot caddie flow

import Foundation
import SwiftUI
import CoreLocation
import UIKit

enum CaddieShotStep {
    case courseAndHole
    case distanceInput
    case photoCapture
    case lieConfirmation
    case recommendation
    case feedback
}

@MainActor
class FullShotCaddieViewModel: ObservableObject {
    @Published var step: CaddieShotStep = .courseAndHole
    @Published var shotContext: ShotContext?
    @Published var recommendation: ShotRecommendation?
    @Published var lastRecommendationId: String?
    @Published var capturedPhoto: UIImage?
    @Published var lieType: String = "Fairway"
    @Published var distanceToTarget: Double?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    let caddieSession: CaddieViewModel
    private let recommenderService = RecommenderService.shared
    private let weatherService = WeatherService.shared
    private let elevationService = ElevationService.shared
    private let locationService = LocationService.shared
    private let feedbackService = FeedbackService.shared

    private struct HoleContextInsights {
        let targetCoordinate: CLLocationCoordinate2D
        let hazards: [String]
    }
    
    // Optional history store (injected when available)
    var historyStore: HistoryStore?
    
    init(caddieSession: CaddieViewModel) {
        self.caddieSession = caddieSession
        
        // If session is ready, skip course/hole selection
        if caddieSession.session.isReady {
            step = .distanceInput
        }
    }
    
    // MARK: - Flow Navigation
    
    func proceedToNextStep() {
        switch step {
        case .courseAndHole:
            if caddieSession.session.isReady {
                step = .distanceInput
            }
        case .distanceInput:
            step = .photoCapture
        case .photoCapture:
            if capturedPhoto != nil {
                step = .lieConfirmation
            }
        case .lieConfirmation:
            step = .recommendation
            fetchRecommendation()
        case .recommendation:
            step = .feedback
        case .feedback:
            // Flow complete
            break
        }
    }
    
    func goBack() {
        switch step {
        case .distanceInput:
            step = .courseAndHole
        case .photoCapture:
            step = .distanceInput
        case .lieConfirmation:
            step = .photoCapture
        case .recommendation:
            step = .lieConfirmation
        case .feedback:
            step = .recommendation
        case .courseAndHole:
            break
        }
    }
    
    // MARK: - Context Building
    
    func setDistance(_ distance: Double) {
        distanceToTarget = distance
    }
    
    func setPhoto(_ photo: UIImage) {
        capturedPhoto = photo
    }
    
    func setLieType(_ lie: String) {
        lieType = lie
    }
    
    // MARK: - Recommendation
    
    private func fetchRecommendation() {
        guard let course = caddieSession.session.course,
              let holeNumber = caddieSession.session.currentHoleNumber,
              let distance = distanceToTarget,
              let location = locationService.coordinate else {
            errorMessage = "Missing required information for recommendation"
            return
        }
        
        isLoading = true
        errorMessage = nil
        let startedAt = Date()
        
        Task {
            do {
                // Build ShotContext
                let holeInsights = await getHoleContextInsights()
                let targetCoordinate = holeInsights.targetCoordinate
                let weather = try? await weatherService.fetchWeather(at: location)
                let elevationSnapshot = try? await elevationService.elevationDelta(
                    from: location,
                    to: targetCoordinate
                )
                
                let context = ShotContext(
                    hole: holeNumber,
                    playerCoordinate: location,
                    targetCoordinate: targetCoordinate,
                    distanceToCenter: distance,
                    elevationDelta: elevationSnapshot?.deltaYards ?? 0,
                    windSpeedMph: weather?.windMph ?? 0,
                    windDirectionDeg: weather?.windDirDeg ?? 0,
                    temperatureF: weather?.tempF ?? 70,
                    weatherSource: weather?.source ?? .unavailable,
                    elevationSource: elevationSnapshot?.source ?? .unavailable,
                    lieType: lieType
                )
                
                shotContext = context
                
                // Get recommendation
                // Profile should be injected - for now use a default
                let profile = profileViewModel?.profile ?? PlayerProfile.defaultProfile()
                DebugLogging.log(
                    """
                    FullShot request: distance=\(Int(distance))yd, lie=\(lieType), hazards=\(holeInsights.hazards.joined(separator: ", ")), weatherSource=\(weather?.source.rawValue ?? "unavailable"), elevationSource=\(elevationSnapshot?.source.rawValue ?? "unavailable"), hasPhoto=\(capturedPhoto != nil)
                    """,
                    category: "ShotFlow"
                )
                let recommendation = try await recommenderService.getRecommendation(
                    profile: profile,
                    context: context,
                    hazards: holeInsights.hazards,
                    course: course,
                    photo: capturedPhoto,
                    courseName: course.name,
                    city: nil,
                    state: nil,
                    holeNumber: holeNumber,
                    shotType: "Approach",
                    historyStore: historyStore
                )
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                RecommenderService.shared.setLastDiagnosticsRequestDuration(durationMs)
                
                self.recommendation = recommendation
                let recommendationId = UUID().uuidString
                self.lastRecommendationId = recommendationId
                isLoading = false
                
                // Save to history after successful recommendation
                saveRecommendationToHistory(
                    recommendation: recommendation,
                    course: course,
                    context: context,
                    recommendationId: recommendationId
                )
                sendRecommendationEvent(
                    recommendationId: recommendationId,
                    profile: profile,
                    context: context,
                    course: course,
                    hazards: holeInsights.hazards,
                    recommendation: recommendation,
                    durationMs: durationMs
                )
            } catch {
                errorMessage = "Failed to get recommendation: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    // MARK: - History Saving
    
    private func saveRecommendationToHistory(
        recommendation: ShotRecommendation,
        course: Course,
        context: ShotContext,
        recommendationId: String
    ) {
        guard let historyStore = historyStore else { return }
        
        // Format recommendation text (matching what user sees)
        let recommendationText = formatRecommendationText(
            recommendation: recommendation,
            distance: Int(context.distanceToCenter),
            lie: lieType
        )
        
        // Get raw JSON if available - strip markdown code fences
        let rawAIResponse: String?
        if let jsonData = try? JSONEncoder().encode(recommendation),
           var jsonString = String(data: jsonData, encoding: .utf8) {
            jsonString = stripMarkdownCodeFences(jsonString)
            rawAIResponse = jsonString
        } else {
            rawAIResponse = nil
        }
        
        // Create thumbnail from captured image if available
        let thumbnailData: Data?
        if let image = capturedPhoto {
            let maxWidth: CGFloat = 600
            let scale = min(1.0, maxWidth / image.size.width)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            thumbnailData = resizedImage?.jpegData(compressionQuality: 0.7)
        } else {
            thumbnailData = nil
        }
        
        // Format hazards as string
        let hazardsString = recommendation.avoidZones.isEmpty ? nil : recommendation.avoidZones.joined(separator: ", ")
        
        let weather = HistoryWeatherSnapshot(
            windMph: context.windSpeedMph,
            windDirDeg: context.windDirectionDeg,
            tempF: context.temperatureF,
            elevationDeltaYards: context.elevationDelta
        )
        
        let shotMetadata = ShotHistoryMetadata(
            distanceYards: Int(context.distanceToCenter),
            shotType: "Approach",
            lie: lieType,
            clubRecommended: recommendation.club,
            courseName: course.name,
            holeNumber: context.hole,
            hazards: hazardsString,
            weather: weather,
            timestamp: Date()
        )
        
        let historyItem = HistoryItem(
            type: .shot,
            courseName: course.name,
            distanceYards: Int(context.distanceToCenter),
            shotType: "Approach",
            lie: lieType,
            hazards: hazardsString,
            recommendationText: recommendationText,
            rawAIResponse: rawAIResponse,
            thumbnailData: thumbnailData,
            recommendationId: recommendationId,
            shotMetadata: shotMetadata
        )
        
        Task { @MainActor in
            historyStore.add(historyItem)
        }
    }

    private func sendRecommendationEvent(
        recommendationId: String,
        profile: PlayerProfile,
        context: ShotContext,
        course: Course,
        hazards: [String],
        recommendation: ShotRecommendation,
        durationMs: Int
    ) {
        let diagnostics = recommenderService.lastDiagnostics
        let payload = RecommendationEventPayload(
            recommendationId: recommendationId,
            userId: AnalyticsService.shared.userId,
            sessionId: AnalyticsService.shared.sessionId,
            recommendationType: .shot,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            context: RecommendationEventContextSnapshot(
                courseName: course.name,
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
                photoIncluded: diagnostics?.hasPhoto ?? (capturedPhoto != nil),
                photoReferenced: diagnostics?.photoReferencedInOutput ?? false,
                requestDurationMs: diagnostics?.requestDurationMs ?? durationMs
            )
        )
        APIService.shared.sendRecommendationEventNonBlocking(payload)
    }
    
    private func formatRecommendationText(recommendation: ShotRecommendation, distance: Int, lie: String) -> String {
        var text = "Recommended Club: \(recommendation.club)\n"
        
        if distance > 0 {
            text += "Distance: \(distance) yards\n"
        }
        
        if !lie.isEmpty {
            text += "Lie: \(lie.capitalized)\n"
        }
        
        if recommendation.aimOffsetYards != 0 {
            let offset = abs(recommendation.aimOffsetYards)
            let direction = recommendation.aimOffsetYards > 0 ? "right" : "left"
            text += "Aim: \(String(format: "%.0f", offset)) yards \(direction)\n"
        }
        
        if !recommendation.shotShape.isEmpty && recommendation.shotShape.lowercased() != "straight" {
            text += "Shot Shape: \(recommendation.shotShape)\n"
        }
        
        text += "\n\(recommendation.narrative)"
        
        if !recommendation.avoidZones.isEmpty {
            text += "\n\nHazards to Avoid:\n"
            for zone in recommendation.avoidZones {
                text += "• \(zone)\n"
            }
        }
        
        return text
    }
    
    private func stripMarkdownCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove leading ```json or ``` if present
        if result.hasPrefix("```") {
            let lines = result.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true {
                result = lines.dropFirst().joined(separator: "\n")
            }
        }
        
        // Remove trailing ``` if present
        if result.hasSuffix("```") {
            result = String(result.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return result
    }
    
    private func getHoleContextInsights() async -> HoleContextInsights {
        guard let course = caddieSession.session.course,
              let holeNumber = caddieSession.session.currentHoleNumber else {
            // Fallback to user location
            let fallback = locationService.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            return HoleContextInsights(targetCoordinate: fallback, hazards: [])
        }
        
        // Try to get green center from hole layout
        do {
            let layoutResponse = try await CourseMapperService.shared.fetchHoleLayout(
                courseId: course.id,
                holeNumber: holeNumber
            )
            let holeLayout = HoleLayout(from: layoutResponse)
            let inferredHazards = inferHazards(from: holeLayout)
            if let greenCenter = holeLayout.greenCenter {
                return HoleContextInsights(targetCoordinate: greenCenter, hazards: inferredHazards)
            }
            return HoleContextInsights(targetCoordinate: course.location?.clLocation ?? locationService.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0), hazards: inferredHazards)
        } catch {
            // Fallback
        }
        
        // Fallback to course location or user location
        if let courseLocation = course.location {
            return HoleContextInsights(targetCoordinate: courseLocation.clLocation, hazards: [])
        }
        
        let fallback = locationService.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        return HoleContextInsights(targetCoordinate: fallback, hazards: [])
    }

    private func inferHazards(from holeLayout: HoleLayout) -> [String] {
        var hazards: [String] = []
        if !holeLayout.waterPolygons.isEmpty {
            hazards.append("Water in play")
        }
        if !holeLayout.bunkerPolygons.isEmpty {
            hazards.append("Bunkers in play")
        }
        return hazards
    }
    
    // MARK: - Feedback
    
    func submitFeedback(clubUsed: String?, contactQuality: String?, resultHorizontal: String?, resultVertical: String?) {
        guard let context = shotContext,
              let recommendation = recommendation,
              let course = caddieSession.session.course else {
            return
        }
        
        // Create CapturedShot for logging
        let capturedShot = CapturedShot(
            shotType: .approach, // Default, could be determined from context
            club: clubUsed,
            distance: Int(context.distanceToCenter),
            timestamp: Date(),
            imageData: capturedPhoto?.jpegData(compressionQuality: 0.8),
            recommendation: nil, // Could convert ShotRecommendation to PhotoRecommendation
            shotContext: nil, // Could convert ShotContext to PhotoShotContext
            holeNumber: context.hole
        )
        
        // Log feedback
        let feedback = ShotFeedback(
            courseName: course.name,
            courseId: course.id,
            holeNumber: context.hole,
            clubSuggested: recommendation.club,
            userRating: true // Could be determined from result
        )
        
        feedbackService.recordFeedback(feedback)
        if let recommendationId = lastRecommendationId {
            let note = "Club used: \(clubUsed ?? "N/A"), Contact: \(contactQuality ?? "N/A"), Result: \(resultHorizontal ?? "N/A") / \(resultVertical ?? "N/A")"
            feedbackService.submitRecommendationFeedback(
                recommendationId: recommendationId,
                recommendationType: .shot,
                helpful: true,
                feedbackReason: nil,
                freeTextNote: note,
                rating: nil,
                historyStore: historyStore
            )
        }
        
        // Send to backend if needed
        Task {
            await feedbackService.sendCaddieFeedback(
                courseId: course.id,
                hole: context.hole,
                clubSuggested: recommendation.club,
                userFeedback: "Club: \(clubUsed ?? "N/A"), Contact: \(contactQuality ?? "N/A"), Result: \(resultHorizontal ?? "N/A") / \(resultVertical ?? "N/A")"
            )
        }
    }
    
    // Profile will be injected via environment in the view
    var profileViewModel: ProfileViewModel?
}
