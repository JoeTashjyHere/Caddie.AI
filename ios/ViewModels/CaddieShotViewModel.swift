//
//  CaddieShotViewModel.swift
//  Caddie.ai
//
//  Unified ViewModel for the single-screen Caddie tab.
//  Owns course/hole, photo, distance, and routes to full-shot or putting pipeline.

import Foundation
import SwiftUI
import CoreLocation
import Combine
import MapKit
import UIKit

/// Result of getRecommendation - either full shot or putt
enum CaddieRecommendationResult {
    case fullShot(ShotRecommendation)
    case putt(PuttingRead)
}

@MainActor
final class CaddieShotViewModel: ObservableObject {
    // MARK: - Published State
    
    @Published var currentCourse: Course?
    @Published var currentHoleNumber: Int?
    @Published var currentPhoto: UIImage?
    @Published var targetDistanceYards: Double?
    @Published var targetDistanceText: String = ""
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var requestState: RequestState = .idle
    
    /// Current recommendation (full shot or putt)
    @Published var recommendationResult: CaddieRecommendationResult?
    
    /// ShotContext used for the last recommendation (for feedback)
    @Published var lastShotContext: ShotContext?
    @Published var lastRecommendationId: String?
    @Published var lastRecommendationType: RecommendationType?
    
    /// Auto-hole tracking: high confidence = no banner; low = show "Tap to pick hole"
    @Published var holeDetectionUncertain: Bool = false
    
    /// Pending hole suggestion from auto-tracking (when different from current)
    @Published var pendingHoleSuggestion: Int?
    
    // MARK: - Dependencies
    
    private let locationService: LocationService
    private let courseService: CourseService
    private let weatherService: WeatherService
    private let elevationService: ElevationService
    private let recommender: RecommenderService
    private let lieClassifier: LieClassificationService
    
    var historyStore: HistoryStore?
    
    private var cancellables = Set<AnyCancellable>()
    private var holeDetectionTask: Task<Void, Never>?
    private var activeRequestID = UUID()
    private var inFlightTask: Task<Void, Never>?
    private var lastShotRequest: ShotRequestSnapshot?
    private var lastPuttRequest: PuttRequestSnapshot?

    private struct ShotRequestSnapshot {
        let profile: PlayerProfile
        let draft: CaddieContextDraft
        let correlationId: String
    }

    private struct PuttRequestSnapshot {
        let profile: PlayerProfile
        let draft: CaddieContextDraft?
        let correlationId: String
    }
    
    // MARK: - Init
    
    init(
        locationService: LocationService = .shared,
        courseService: CourseService = .shared,
        weatherService: WeatherService = .shared,
        elevationService: ElevationService = .shared,
        recommender: RecommenderService = .shared,
        lieClassifier: LieClassificationService = .shared
    ) {
        self.locationService = locationService
        self.courseService = courseService
        self.weatherService = weatherService
        self.elevationService = elevationService
        self.recommender = recommender
        self.lieClassifier = lieClassifier
        
        loadSession()
    }
    
    // MARK: - Public API
    
    var canGetRecommendation: Bool {
        currentPhoto != nil && targetDistanceYards != nil && (targetDistanceYards ?? 0) > 0
    }
    
    func setPhoto(_ image: UIImage?) {
        currentPhoto = image
        if image != nil {
            requestState = .ready
        } else if !requestState.isSubmitting {
            requestState = .idle
        }
    }
    
    func setTargetDistance(_ yards: Double?) {
        targetDistanceYards = yards
        if yards != nil, !requestState.isSubmitting {
            requestState = .ready
        }
    }
    
    func selectCourse(_ course: Course) {
        currentCourse = course
        saveSession()
    }
    
    func selectHole(_ holeNumber: Int) {
        currentHoleNumber = holeNumber
        pendingHoleSuggestion = nil
        holeDetectionUncertain = false
        saveSession()
    }
    
    func acceptHoleSuggestion() {
        if let hole = pendingHoleSuggestion {
            selectHole(hole)
        }
    }
    
    func dismissHoleSuggestion() {
        pendingHoleSuggestion = nil
    }
    
    func refreshCourseFromGPS() async {
        // Intentionally disabled until Apple Maps-based realtime course lookup is integrated.
        errorMessage = "Auto course detection is temporarily disabled. Enter course in Confirm Context."
    }
    
    func fetchNearbyCourses() async -> [Course] {
        // Intentionally disabled until Apple Maps-based realtime course lookup is integrated.
        return []
    }

    func getShotRecommendation(
        profile: PlayerProfile,
        draft: CaddieContextDraft,
        correlationId: String = UUID().uuidString,
        shouldStoreRetrySnapshot: Bool = true
    ) async {
        guard !requestState.isSubmitting else { return }
        guard let photo = currentPhoto else {
            failRequest("Take a photo to continue", debugId: correlationId)
            return
        }

        let courseName = draft.courseName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = draft.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = draft.state?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let validCourseName = courseName, !validCourseName.isEmpty,
              let validCity = city, !validCity.isEmpty,
              let validState = state, !validState.isEmpty,
              let holeNumber = draft.holeNumber, (1...18).contains(holeNumber),
              let distance = draft.distanceYards, distance > 0 else {
            failRequest("Complete course, city/state, hole, and distance before requesting.", debugId: correlationId)
            return
        }

        if shouldStoreRetrySnapshot {
            lastShotRequest = ShotRequestSnapshot(profile: profile, draft: draft, correlationId: correlationId)
        }

        let requestID = UUID()
        activeRequestID = requestID

        beginSubmitting()
        let startedAt = Date()
        inFlightTask?.cancel()

        inFlightTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let selectedCourse = draft.course {
                    currentCourse = selectedCourse
                } else if currentCourse == nil {
                    currentCourse = Course(id: "manual-\(validCourseName)", name: validCourseName)
                }
                currentHoleNumber = holeNumber
                saveSession()

                let lieValue = draft.lie ?? "Fairway"
                let ctx = try await buildShotContext(
                    distance: distance,
                    lieType: lieValue,
                    holeNumber: holeNumber,
                    course: currentCourse
                )

                guard activeRequestID == requestID, !Task.isCancelled else { return }
                lastShotContext = ctx

                let hazards = parseHazards(draft.hazards)
                let recommendation = try await requestFullShotRecommendation(
                    profile: profile,
                    context: ctx,
                    photo: photo,
                    course: currentCourse,
                    courseName: validCourseName,
                    city: validCity,
                    state: validState,
                    holeNumber: holeNumber,
                    shotType: draft.shotType.displayName,
                    hazards: hazards,
                    correlationId: correlationId
                )

                guard activeRequestID == requestID, !Task.isCancelled else { return }
                recommendationResult = .fullShot(recommendation)
                let recommendationId = UUID().uuidString
                lastRecommendationId = recommendationId
                lastRecommendationType = .shot
                saveShotRecommendationToHistory(
                    recommendation,
                    context: ctx,
                    recommendationId: recommendationId,
                    shotType: draft.shotType.displayName,
                    courseName: validCourseName,
                    holeNumber: holeNumber,
                    hazards: hazards
                )
                completeSuccess()

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                RecommenderService.shared.setLastDiagnosticsRequestDuration(durationMs)
                sendShotRecommendationEvent(
                    recommendationId: recommendationId,
                    profile: profile,
                    draft: draft,
                    context: ctx,
                    recommendation: recommendation,
                    hazards: hazards,
                    durationMs: durationMs
                )
                trackRecommendationEvent(
                    eventType: "recommendation_completed",
                    recommendationType: "shot",
                    correlationId: correlationId,
                    draft: draft,
                    recommendationText: recommendation.narrative,
                    success: true,
                    durationMs: durationMs,
                    errorMessage: nil
                )
            } catch {
                guard activeRequestID == requestID, !Task.isCancelled else { return }
                let message = normalizeErrorMessage(error)
                failRequest(message, debugId: correlationId)
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                trackRecommendationEvent(
                    eventType: "recommendation_failed",
                    recommendationType: "shot",
                    correlationId: correlationId,
                    draft: draft,
                    recommendationText: nil,
                    success: false,
                    durationMs: durationMs,
                    errorMessage: message
                )
            }
        }

        await inFlightTask?.value
    }

    func getPuttingRecommendation(
        profile: PlayerProfile,
        draft: CaddieContextDraft? = nil,
        correlationId: String = UUID().uuidString,
        shouldStoreRetrySnapshot: Bool = true
    ) async {
        guard !requestState.isSubmitting else { return }
        guard currentPhoto != nil else {
            failRequest("Take a photo to continue", debugId: correlationId)
            return
        }

        if shouldStoreRetrySnapshot {
            lastPuttRequest = PuttRequestSnapshot(profile: profile, draft: draft, correlationId: correlationId)
        }

        let requestID = UUID()
        activeRequestID = requestID

        beginSubmitting()
        let startedAt = Date()
        inFlightTask?.cancel()

        inFlightTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let draftCourse = draft?.course {
                    currentCourse = draftCourse
                }
                if let draftHole = draft?.holeNumber {
                    currentHoleNumber = draftHole
                }

                let contextDistance = draft?.distanceYards ?? 0
                let ctx = try await buildShotContext(
                    distance: contextDistance,
                    lieType: "Green",
                    holeNumber: draft?.holeNumber ?? currentHoleNumber,
                    course: draft?.course ?? currentCourse
                )

                guard activeRequestID == requestID, !Task.isCancelled else { return }
                lastShotContext = ctx

                let puttingRead = try await requestPuttingRead(profile: profile, context: ctx, correlationId: correlationId)
                guard activeRequestID == requestID, !Task.isCancelled else { return }

                recommendationResult = .putt(puttingRead)
                let recommendationId = UUID().uuidString
                lastRecommendationId = recommendationId
                lastRecommendationType = .putt
                savePuttingReadToHistory(
                    puttingRead,
                    recommendationId: recommendationId,
                    courseName: draft?.courseName ?? currentCourse?.name,
                    holeNumber: draft?.holeNumber ?? currentHoleNumber
                )
                completeSuccess()

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                sendPuttRecommendationEvent(
                    recommendationId: recommendationId,
                    draft: draft,
                    recommendation: puttingRead,
                    durationMs: durationMs
                )
                trackRecommendationEvent(
                    eventType: "recommendation_completed",
                    recommendationType: "putt",
                    correlationId: correlationId,
                    draft: draft,
                    recommendationText: puttingRead.narrative,
                    success: true,
                    durationMs: durationMs,
                    errorMessage: nil
                )
            } catch {
                guard activeRequestID == requestID, !Task.isCancelled else { return }
                let message = normalizeErrorMessage(error)
                failRequest(message, debugId: correlationId)
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                trackRecommendationEvent(
                    eventType: "recommendation_failed",
                    recommendationType: "putt",
                    correlationId: correlationId,
                    draft: draft,
                    recommendationText: nil,
                    success: false,
                    durationMs: durationMs,
                    errorMessage: message
                )
            }
        }

        await inFlightTask?.value
    }
    
    /// Main entry: get recommendation from photo + distance.
    func getRecommendation(profile: PlayerProfile) async {
        guard !requestState.isSubmitting else { return }
        guard canGetRecommendation,
              let photo = currentPhoto,
              let distance = targetDistanceYards, distance > 0 else {
            failRequest("Add a photo and distance to continue", debugId: UUID().uuidString)
            return
        }
        
        beginSubmitting()
        
        defer { isLoading = false }
        
        do {
            // 1. Classify lie and putt vs full shot
            let classification = await lieClassifier.classify(image: photo)
            
            // 2. Build ShotContext
            let ctx = try await buildShotContext(
                distance: distance,
                lieType: classification.lieType.shotContextString
            )
            lastShotContext = ctx
            
            // 3. Route to putting or full-shot pipeline
            if classification.isPutt {
                let puttingRead = try await requestPuttingRead(profile: profile, context: ctx, correlationId: UUID().uuidString)
                recommendationResult = .putt(puttingRead)
                let recommendationId = UUID().uuidString
                lastRecommendationId = recommendationId
                lastRecommendationType = .putt
                savePuttingReadToHistory(
                    puttingRead,
                    recommendationId: recommendationId,
                    courseName: currentCourse?.name,
                    holeNumber: currentHoleNumber
                )
                requestState = .success
            } else {
                let rec = try await requestFullShotRecommendation(
                    profile: profile,
                    context: ctx,
                    photo: photo,
                    course: currentCourse,
                    courseName: currentCourse?.name,
                    city: nil,
                    state: nil,
                    holeNumber: currentHoleNumber,
                    shotType: "Approach",
                    hazards: [],
                    correlationId: UUID().uuidString
                )
                recommendationResult = .fullShot(rec)
                let recommendationId = UUID().uuidString
                lastRecommendationId = recommendationId
                lastRecommendationType = .shot
                saveShotRecommendationToHistory(
                    rec,
                    context: ctx,
                    recommendationId: recommendationId,
                    shotType: "Approach",
                    courseName: currentCourse?.name,
                    holeNumber: currentHoleNumber,
                    hazards: []
                )
                requestState = .success
            }
        } catch {
            let debugId = UUID().uuidString
            failRequest(error.localizedDescription, debugId: debugId)
        }
    }
    
    /// Dismiss recommendation overlay and reset for next shot
    func newShot() {
        activeRequestID = UUID()
        inFlightTask?.cancel()
        isLoading = false
        requestState = .idle
        recommendationResult = nil
        lastShotContext = nil
        lastRecommendationId = nil
        lastRecommendationType = nil
        currentPhoto = nil
        targetDistanceText = ""
        targetDistanceYards = nil
        errorMessage = nil
    }

    func retryLastRequest() async {
        if let lastShotRequest {
            await getShotRecommendation(
                profile: lastShotRequest.profile,
                draft: lastShotRequest.draft,
                correlationId: UUID().uuidString,
                shouldStoreRetrySnapshot: false
            )
            return
        }

        if let lastPuttRequest {
            await getPuttingRecommendation(
                profile: lastPuttRequest.profile,
                draft: lastPuttRequest.draft,
                correlationId: UUID().uuidString,
                shouldStoreRetrySnapshot: false
            )
        }
    }

    private func beginSubmitting() {
        isLoading = true
        errorMessage = nil
        recommendationResult = nil
        lastShotContext = nil
        requestState = .submitting
    }

    private func completeSuccess() {
        isLoading = false
        errorMessage = nil
        requestState = .success
    }

    private func failRequest(_ message: String, debugId: String) {
        isLoading = false
        errorMessage = message
        requestState = .failure(errorMessage: message, debugId: debugId)
    }

    private func normalizeErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Request failed."
        }
        if let openAIError = error as? OpenAIError {
            return openAIError.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }

    private func trackRecommendationEvent(
        eventType: String,
        recommendationType: String,
        correlationId: String,
        draft: CaddieContextDraft?,
        recommendationText: String?,
        success: Bool,
        durationMs: Int,
        errorMessage: String?
    ) {
        AnalyticsService.shared.track(
            AnalyticsEvent(
                id: UUID().uuidString,
                eventType: eventType,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                userId: AnalyticsService.shared.userId,
                sessionId: AnalyticsService.shared.sessionId,
                recommendationType: recommendationType,
                correlationId: correlationId,
                courseName: draft?.courseName ?? currentCourse?.name,
                city: draft?.city,
                state: draft?.state,
                holeNumber: draft?.holeNumber ?? currentHoleNumber,
                distanceToTarget: draft?.distanceYards,
                lie: draft?.lie,
                shotType: draft?.shotType.displayName,
                hazards: draft?.hazards,
                recommendationText: recommendationText,
                success: success,
                durationMs: durationMs,
                errorMessage: errorMessage,
                feedbackRating: nil,
                feedbackComments: nil
            )
        )
    }

    private func sendShotRecommendationEvent(
        recommendationId: String,
        profile: PlayerProfile,
        draft: CaddieContextDraft,
        context: ShotContext,
        recommendation: ShotRecommendation,
        hazards: [String],
        durationMs: Int
    ) {
        let diagnostics = recommender.lastDiagnostics
        let event = RecommendationEventPayload(
            recommendationId: recommendationId,
            userId: AnalyticsService.shared.userId,
            sessionId: AnalyticsService.shared.sessionId,
            recommendationType: .shot,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            context: RecommendationEventContextSnapshot(
                courseName: draft.courseName ?? currentCourse?.name,
                city: draft.city,
                state: draft.state,
                holeNumber: draft.holeNumber ?? currentHoleNumber,
                distanceToTarget: draft.distanceYards ?? context.distanceToCenter,
                lie: draft.lie ?? context.lieType,
                shotType: draft.shotType.displayName,
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
                photoIncluded: diagnostics?.hasPhoto ?? (currentPhoto != nil),
                photoReferenced: diagnostics?.photoReferencedInOutput ?? false,
                requestDurationMs: diagnostics?.requestDurationMs ?? durationMs
            )
        )
        APIService.shared.sendRecommendationEventNonBlocking(event)
    }

    private func sendPuttRecommendationEvent(
        recommendationId: String,
        draft: CaddieContextDraft?,
        recommendation: PuttingRead,
        durationMs: Int
    ) {
        let event = RecommendationEventPayload(
            recommendationId: recommendationId,
            userId: AnalyticsService.shared.userId,
            sessionId: AnalyticsService.shared.sessionId,
            recommendationType: .putt,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            context: RecommendationEventContextSnapshot(
                courseName: draft?.courseName ?? currentCourse?.name,
                city: draft?.city,
                state: draft?.state,
                holeNumber: draft?.holeNumber ?? currentHoleNumber,
                distanceToTarget: draft?.distanceYards,
                lie: "green",
                shotType: "putt",
                hazards: []
            ),
            profile: nil,
            output: RecommendationEventOutputSnapshot(
                aiSelectedClub: nil,
                finalRecommendedClub: nil,
                recommendationText: recommendation.narrative,
                normalizationOccurred: false,
                normalizationReason: nil,
                fallbackOccurred: false,
                fallbackReason: nil,
                topCandidateClubs: []
            ),
            diagnostics: RecommendationEventDiagnosticsSnapshot(
                targetDistanceYards: draft?.distanceYards.map { Int($0.rounded()) },
                playsLikeDistanceYards: nil,
                weatherSourceQuality: nil,
                elevationSourceQuality: nil,
                photoIncluded: currentPhoto != nil,
                photoReferenced: false,
                requestDurationMs: durationMs
            )
        )
        APIService.shared.sendRecommendationEventNonBlocking(event)
    }
    
    // MARK: - Private: Build ShotContext
    
    private func buildShotContext(
        distance: Double,
        lieType: String,
        holeNumber: Int? = nil,
        course: Course? = nil
    ) async throws -> ShotContext {
        let coord = locationService.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        var targetCoord = coord
        let resolvedHole = holeNumber ?? currentHoleNumber
        let resolvedCourse = course ?? currentCourse
        
        if let course = resolvedCourse, let holeNum = resolvedHole {
            do {
                let layout = try await CourseMapperService.shared.fetchHoleLayout(courseId: course.id, holeNumber: holeNum)
                let holeLayout = HoleLayout(from: layout)
                if let greenCenter = holeLayout.greenCenter {
                    targetCoord = greenCenter
                }
            } catch { /* use coord */ }
        }
        
        var weather = WeatherSnapshot(windMph: 0, windDirDeg: 0, tempF: 70, source: .unavailable)
        if locationService.coordinate != nil {
            do {
                weather = try await weatherService.fetchWeather(at: coord)
            } catch { /* defaults */ }
        }
        
        var elevationSnapshot = ElevationSnapshot(deltaYards: 0, source: .unavailable)
        if locationService.coordinate != nil {
            do {
                elevationSnapshot = try await elevationService.elevationDelta(from: coord, to: targetCoord)
            } catch { /* 0 */ }
        }
        
        return ShotContext(
            hole: resolvedHole ?? 1,
            playerCoordinate: coord,
            targetCoordinate: targetCoord,
            distanceToCenter: distance,
            elevationDelta: elevationSnapshot.deltaYards,
            windSpeedMph: weather.windMph,
            windDirectionDeg: weather.windDirDeg,
            temperatureF: weather.tempF,
            weatherSource: weather.source,
            elevationSource: elevationSnapshot.source,
            lieType: lieType
        )
    }
    
    // MARK: - Private: Full Shot
    
    private func requestFullShotRecommendation(
        profile: PlayerProfile,
        context: ShotContext,
        photo: UIImage,
        course: Course?,
        courseName: String?,
        city: String?,
        state: String?,
        holeNumber: Int?,
        shotType: String,
        hazards: [String],
        correlationId: String
    ) async throws -> ShotRecommendation {
        try await recommender.getRecommendation(
            profile: profile,
            context: context,
            hazards: hazards,
            course: course,
            photo: photo,
            courseName: courseName,
            city: city,
            state: state,
            holeNumber: holeNumber,
            shotType: shotType,
            historyStore: historyStore,
            correlationId: correlationId
        )
    }

    private func parseHazards(_ hazardsText: String?) -> [String] {
        guard let hazardsText = hazardsText, !hazardsText.isEmpty else {
            return []
        }

        return hazardsText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Private: Putting
    
    private func requestPuttingRead(
        profile: PlayerProfile,
        context: ShotContext,
        correlationId: String
    ) async throws -> PuttingRead {
        let puttingVM = PuttingViewModel()
        
        if let course = currentCourse,
           let holeNum = currentHoleNumber,
           let imageData = currentPhoto?.jpegData(compressionQuality: 0.8),
           let coord = locationService.coordinate {
            await puttingVM.analyzePutting(
                imageData: imageData,
                courseId: course.id,
                holeNumber: holeNum,
                lat: coord.latitude,
                lon: coord.longitude,
                correlationId: correlationId
            )
            if let read = puttingVM.puttingRead { return read }
        }
        
        // Fallback: vision-based putting read
        guard let image = currentPhoto else {
            throw NSError(domain: "CaddieShotViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No photo for putting analysis"])
        }
        
        let historicalLearning: PuttHistoricalLearning?
        if let historyStore = historyStore {
            let historyItems = await MainActor.run { historyStore.items }
            let puttItems = historyItems.filter { $0.type == .putt }
            historicalLearning = PuttHistoricalLearning(from: puttItems, limit: 5)
        } else {
            historicalLearning = nil
        }

        let (systemPrompt, userPrompt) = CaddiePromptBuilder.shared.buildGreenReaderPrompt(
            courseName: currentCourse?.name,
            city: nil,
            state: nil,
            holeNumber: currentHoleNumber,
            puttDistance: nil,
            playerProfile: PlayerProfileData(from: profile),
            historicalLearning: historicalLearning,
            environmentalContext: context
        )
        
        let jsonString = try await OpenAIClient.shared.completeWithVision(
            system: systemPrompt,
            user: userPrompt,
            image: image,
            correlationId: correlationId
        )
        
        let cleaned = stripMarkdownCodeFences(jsonString)
        guard let data = cleaned.data(using: .utf8) else {
            throw NSError(domain: "CaddieShotViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse putting read"])
        }
        
        if let structured = try? JSONDecoder().decode(StructuredPuttingRead.self, from: data) {
            return PuttingRead(from: structured)
        }
        return try JSONDecoder().decode(PuttingRead.self, from: data)
    }
    
    private func stripMarkdownCodeFences(_ text: String) -> String {
        var r = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.hasPrefix("```") {
            if let i = r.firstIndex(of: "\n") {
                r = String(r[r.index(after: i)...])
            } else {
                r = r.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            }
        }
        if r.hasSuffix("```") { r = String(r.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return r
    }
    
    // MARK: - History
    
    private func saveShotRecommendationToHistory(
        _ rec: ShotRecommendation,
        context: ShotContext,
        recommendationId: String,
        shotType: String,
        courseName: String?,
        holeNumber: Int?,
        hazards: [String]
    ) {
        guard let historyStore = historyStore else { return }
        let text = "Recommended Club: \(rec.club)\nDistance: \(Int(context.distanceToCenter)) yards\n\n\(rec.narrative)"
        let rawJSON = (try? JSONEncoder().encode(rec)).flatMap { String(data: $0, encoding: .utf8) }
        let thumbnailData = currentPhoto.flatMap { resizeForThumbnail($0)?.jpegData(compressionQuality: 0.7) }
        
        let metadata = ShotHistoryMetadata(
            distanceYards: Int(context.distanceToCenter),
            shotType: shotType,
            lie: context.lieType,
            clubRecommended: rec.club,
            courseName: courseName ?? currentCourse?.name,
            holeNumber: holeNumber ?? currentHoleNumber,
            hazards: hazards.isEmpty ? (rec.avoidZones.isEmpty ? nil : rec.avoidZones.joined(separator: ", ")) : hazards.joined(separator: ", "),
            weather: HistoryWeatherSnapshot(
                windMph: context.windSpeedMph,
                windDirDeg: context.windDirectionDeg,
                tempF: context.temperatureF,
                elevationDeltaYards: context.elevationDelta
            ),
            timestamp: Date()
        )
        
        let item = HistoryItem(
            type: .shot,
            courseName: courseName ?? currentCourse?.name,
            distanceYards: Int(context.distanceToCenter),
            shotType: shotType,
            lie: context.lieType,
            hazards: hazards.isEmpty ? (rec.avoidZones.isEmpty ? nil : rec.avoidZones.joined(separator: ", ")) : hazards.joined(separator: ", "),
            recommendationText: text,
            rawAIResponse: rawJSON,
            thumbnailData: thumbnailData,
            recommendationId: recommendationId,
            shotMetadata: metadata
        )
        historyStore.add(item)
    }
    
    private func savePuttingReadToHistory(
        _ read: PuttingRead,
        recommendationId: String,
        courseName: String?,
        holeNumber: Int?
    ) {
        guard let historyStore = historyStore else { return }
        var text = "Putting Read\n\nBreak: \(read.breakDirection)\nAmount: \(String(format: "%.1f", read.breakAmount)) feet\nSpeed: \(read.speed)\n\n\(read.narrative)"
        if let line = read.puttingLine { text += "\n\nPutting Line: \(line)" }
        
        let rawJSON = (try? JSONEncoder().encode(read)).flatMap { String(data: $0, encoding: .utf8) }
        let thumbnailData = currentPhoto.flatMap { resizeForThumbnail($0)?.jpegData(compressionQuality: 0.7) }
        
        let metadata = PuttHistoryMetadata(
            puttDistanceFeet: nil,
            breakDirection: read.breakDirection,
            speedRecommendation: read.speed,
            greenSlopeInference: read.theLine ?? read.puttingLine,
            courseName: courseName ?? currentCourse?.name,
            holeNumber: holeNumber ?? currentHoleNumber,
            timestamp: Date()
        )
        
        let item = HistoryItem(
            type: .putt,
            courseName: courseName ?? currentCourse?.name,
            distanceYards: nil,
            shotType: nil,
            lie: nil,
            hazards: nil,
            recommendationText: text,
            rawAIResponse: rawJSON,
            thumbnailData: thumbnailData,
            recommendationId: recommendationId,
            puttMetadata: metadata
        )
        historyStore.add(item)
    }
    
    private func resizeForThumbnail(_ image: UIImage) -> UIImage? {
        let maxW: CGFloat = 600
        let scale = min(1, maxW / image.size.width)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        image.draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }
    
    // MARK: - Auto-Hole Tracking
    
    private func setupLocationSubscription() {
        locationService.$coordinate
            .compactMap { $0 }
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] coord in
                self?.checkCurrentHole(at: coord)
            }
            .store(in: &cancellables)
    }
    
    private func checkCurrentHole() {
        guard let coord = locationService.coordinate else { return }
        checkCurrentHole(at: coord)
    }
    
    private func checkCurrentHole(at coordinate: CLLocationCoordinate2D) {
        guard let course = currentCourse else {
            holeDetectionUncertain = true
            return
        }
        
        holeDetectionTask?.cancel()
        holeDetectionTask = Task {
            var detectedHole: Int?
            var minDist = Double.greatestFiniteMagnitude
            
            for holeNum in 1...18 {
                guard !Task.isCancelled else { return }
                do {
                    let layout = try await CourseMapperService.shared.fetchHoleLayout(courseId: course.id, holeNumber: holeNum)
                    let holeLayout = HoleLayout(from: layout)
                    
                    if let greenCenter = holeLayout.greenCenter {
                        let dist = metersToYards(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: CLLocation(latitude: greenCenter.latitude, longitude: greenCenter.longitude)))
                        if dist < 50 && dist < minDist {
                            minDist = dist
                            detectedHole = holeNum
                        }
                    }
                    
                    for poly in holeLayout.greenPolygons {
                        if isInPolygon(coordinate, poly) {
                            let pt = poly.points()[0].coordinate
                            let dist = metersToYards(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: CLLocation(latitude: pt.latitude, longitude: pt.longitude)))
                            if dist < minDist {
                                minDist = dist
                                detectedHole = holeNum
                            }
                        }
                    }
                } catch { continue }
            }
            
            await MainActor.run {
                if let hole = detectedHole {
                    if hole != currentHoleNumber {
                        pendingHoleSuggestion = hole
                    }
                    holeDetectionUncertain = false
                } else {
                    holeDetectionUncertain = currentHoleNumber == nil
                }
            }
        }
    }
    
    private func metersToYards(_ m: Double) -> Double { m * 1.09361 }
    
    private func isInPolygon(_ point: CLLocationCoordinate2D, _ polygon: MKPolygon) -> Bool {
        let mp = MKMapPoint(point)
        let pts = polygon.points()
        var inside = false
        var j = polygon.pointCount - 1
        for i in 0..<polygon.pointCount {
            let pi = pts[i], pj = pts[j]
            if (pi.y > mp.y) != (pj.y > mp.y),
               mp.x < (pj.x - pi.x) * (mp.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
    
    // MARK: - Persistence
    
    private func saveSession() {
        if let c = currentCourse, let d = try? JSONEncoder().encode(c) {
            UserDefaults.standard.set(d, forKey: "CaddieShotCourse")
        }
        if let h = currentHoleNumber {
            UserDefaults.standard.set(h, forKey: "CaddieShotHole")
        }
    }
    
    private func loadSession() {
        if let d = UserDefaults.standard.data(forKey: "CaddieShotCourse"),
           let c = try? JSONDecoder().decode(Course.self, from: d) {
            currentCourse = c
        }
        currentHoleNumber = UserDefaults.standard.object(forKey: "CaddieShotHole") as? Int
    }
}
