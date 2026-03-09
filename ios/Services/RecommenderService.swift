//
//  RecommenderService.swift
//  Caddie.ai
//

import Foundation
import UIKit
import CoreLocation

// Import SafeFormatter from AIContextBuilder
// SafeFormatter is defined in AIContextBuilder.swift

struct CandidateClubDiagnostic: Codable {
    let club: String
    let carryYards: Int
    let confidenceLevel: String
    let notes: String?
    let distanceGapYards: Int
    let score: Double
    let rationale: [String]
}

struct ShotRecommendationDiagnostics: Codable {
    let correlationId: String
    let courseName: String
    let holeNumber: Int
    let shotType: String
    let lie: String
    let targetDistanceYards: Int
    let playsLikeDistanceYards: Int
    let weatherSource: String
    let elevationSource: String
    let hazards: [String]
    let hasPhoto: Bool
    let photoReferencedInOutput: Bool
    let candidates: [CandidateClubDiagnostic]
    let aiChosenClub: String?
    let finalClub: String
    let normalizationOccurred: Bool
    let normalizationReason: String?
    let fallbackUsed: Bool
    let fallbackReason: String?
    var requestDurationMs: Int?
}

struct ShotRecommendationScenario {
    let name: String
    let distanceYards: Double
    let lie: String
    let shotType: String
    let hazards: [String]
    let windMph: Double
    let windDirDeg: Double
    let temperatureF: Double
    let elevationDelta: Double
}

class RecommenderService {
    static let shared = RecommenderService()
    
    private let promptBuilder = CaddiePromptBuilder.shared
    private(set) var lastDiagnostics: ShotRecommendationDiagnostics?

    private struct ClubCandidate {
        let club: ClubDistance
        let score: Double
        let distanceGap: Int
        let rationale: [String]
    }

    private struct ClubSelectionContext {
        let playsLikeDistance: Int
        let candidates: [ClubCandidate]
    }
    
    private init() {}
    
    /// Get recommendation with automatic fallback chain:
    /// Photo → AI Vision → Text AI → Offline Fallback
    func getRecommendation(
        profile: PlayerProfile,
        context: ShotContext,
        hazards: [String],
        course: Course? = nil,
        photo: UIImage? = nil,
        courseName: String? = nil,
        city: String? = nil,
        state: String? = nil,
        holeNumber: Int? = nil,
        shotType: String? = nil,
        historyStore: HistoryStore? = nil,
        correlationId: String = UUID().uuidString
    ) async throws -> ShotRecommendation {
        
        // Use safe formatters with fallback to selected course if explicit fields are missing
        let resolvedCourseName = courseName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? courseName
            : course?.name
        let safeCourseName = SafeFormatter.safeString(resolvedCourseName)
        let safeCity = SafeFormatter.safeString(city)
        let safeState = SafeFormatter.safeString(state)
        let resolvedHole = holeNumber ?? context.hole
        let resolvedShotType = SafeFormatter.safeString(shotType ?? "Approach")
        let strategyPreferences = loadStrategyPreferences()
        let clubSelectionContext = buildClubSelectionContext(
            profile: profile,
            context: context,
            lie: context.lieType,
            shotType: resolvedShotType
        )
        let candidateClubNames = clubSelectionContext.candidates.map { $0.club.name }
        let candidateDebug = clubSelectionContext.candidates
            .map { "\($0.club.name)(\($0.club.carryYards)y,\($0.club.confidenceLevel.displayName),gap \($0.distanceGap),score \(String(format: "%.1f", $0.score)))" }
            .joined(separator: ", ")

        DebugLogging.log(
            """
            Shot inputs: distance=\(Int(context.distanceToCenter))yd playsLike=\(clubSelectionContext.playsLikeDistance)yd lie=\(context.lieType) shotType=\(resolvedShotType)
            Candidate clubs: \(candidateDebug)
            Context included: photo=\(photo != nil) hazards=\(!hazards.isEmpty) weatherSource=\(context.weatherSource.rawValue) elevationSource=\(context.elevationSource.rawValue) courseName=\(safeCourseName != "Not provided")
            """,
            category: "ClubSelection"
        )
        
        // Get historical learning from history
        let historicalLearning: HistoricalLearning?
        if let historyStore = historyStore {
            // HistoryStore is @MainActor, so we need to access items from main actor context
            let historyItems = await MainActor.run { historyStore.items }
            let shotItems = historyItems.filter { $0.type == .shot }
            historicalLearning = HistoricalLearning(from: shotItems, limit: 5)
        } else {
            historicalLearning = nil
        }
        
        // Build photo analysis summary if available
        var photoAnalysisSummary: String? = nil
        if photo != nil {
            photoAnalysisSummary = "Photo available - analyze lie, hazards, and green conditions from image"
        }
        
        // Use safe values - default to "Not provided" if missing
        let shotContextData = ShotContextData(
            courseName: safeCourseName,
            city: safeCity,
            state: safeState,
            holeNumber: resolvedHole,
            distanceToTargetYards: Int(context.distanceToCenter) > 0 ? Int(context.distanceToCenter) : 0,
            lie: SafeFormatter.safeString(context.lieType),
            knownHazards: SafeFormatter.safeArray(hazards as [String]?),
            shotType: resolvedShotType,
            photoAnalysisSummary: photoAnalysisSummary,
            candidateClubs: candidateClubNames,
            playsLikeDistanceYards: clubSelectionContext.playsLikeDistance
        )
        
        let playerProfileData = PlayerProfileData(from: profile)
        
        // Build prompts using CaddiePromptBuilder
        let (systemPrompt, userPrompt) = promptBuilder.buildShotPrompt(
            shotContext: shotContextData,
            playerProfile: playerProfileData,
            environmentalContext: context,
            historicalLearning: historicalLearning,
            strategyPreferences: strategyPreferences
        )
        
        let payload: [String: Any] = [
            "system": systemPrompt,
            "user": userPrompt,
            "hasPhoto": photo != nil,
            "context": [
                "hole": context.hole,
                "distanceYards": Int(context.distanceToCenter),
                "elevationDeltaYards": Int(context.elevationDelta),
                "windMph": context.windSpeedMph,
                "windDirDeg": context.windDirectionDeg,
                "tempF": context.temperatureF
            ]
        ]
        
        // Step 1: Try photo → AI Vision if photo is available
        if let photo = photo {
            DebugLogging.log("📸 Attempting AI Vision analysis with photo", category: "ShotFlow")
            
            do {
                let resultJSON = try await OpenAIClient.shared.completeWithVision(
                    system: systemPrompt,
                    user: userPrompt,
                    image: photo,
                    correlationId: correlationId
                )
                let cleanedJSON = stripMarkdownCodeFences(resultJSON)
                
                if let recommendation = try? parseRecommendation(from: cleanedJSON) {
                    let normalization = normalizeRecommendation(
                        recommendation,
                        profile: profile,
                        selectionContext: clubSelectionContext
                    )
                    let normalizedRecommendation = applyPhotoInfluenceGuardrail(
                        to: normalization.recommendation,
                        hasPhoto: photo != nil
                    )
                    recordDiagnostics(
                        correlationId: correlationId,
                        context: context,
                        courseName: safeCourseName,
                        holeNumber: resolvedHole,
                        shotType: resolvedShotType,
                        hazards: hazards,
                        hasPhoto: photo != nil,
                        selectionContext: clubSelectionContext,
                        aiChosenClub: recommendation.club,
                        finalRecommendation: normalizedRecommendation,
                        normalizationReason: normalization.reason,
                        fallbackReason: nil
                    )
                    DebugLogging.log("✅ AI Vision recommendation received", category: "ShotFlow")
                    DebugLogging.logAPI(endpoint: "RecommenderService.getRecommendation (vision)", url: nil as URL?, method: "POST", payload: payload, parsedModel: normalizedRecommendation)
                    return normalizedRecommendation
                } else {
                    DebugLogging.log("⚠️ AI Vision returned invalid JSON, falling back to text AI", category: "ShotFlow")
                }
            } catch {
                DebugLogging.log("⚠️ AI Vision failed: \(error.localizedDescription), falling back to text AI", category: "ShotFlow")
                DebugLogging.logAPI(endpoint: "RecommenderService.getRecommendation (vision)", url: nil as URL?, method: "POST", payload: payload, error: error)
            }
        }
        
        // Step 2: Fallback to text-based AI recommendation
        DebugLogging.log("🤖 Attempting text-based AI recommendation", category: "ShotFlow")
        
        do {
            let resultJSON = try await OpenAIClient.shared.complete(
                system: systemPrompt,
                user: userPrompt,
                correlationId: correlationId
            )
            let cleanedJSON = stripMarkdownCodeFences(resultJSON)
            
            if let recommendation = try? parseRecommendation(from: cleanedJSON) {
                let normalization = normalizeRecommendation(
                    recommendation,
                    profile: profile,
                    selectionContext: clubSelectionContext
                )
                    let normalizedRecommendation = applyPhotoInfluenceGuardrail(
                        to: normalization.recommendation,
                        hasPhoto: photo != nil
                    )
                recordDiagnostics(
                    correlationId: correlationId,
                    context: context,
                    courseName: safeCourseName,
                    holeNumber: resolvedHole,
                    shotType: resolvedShotType,
                    hazards: hazards,
                    hasPhoto: photo != nil,
                    selectionContext: clubSelectionContext,
                    aiChosenClub: recommendation.club,
                    finalRecommendation: normalizedRecommendation,
                    normalizationReason: normalization.reason,
                    fallbackReason: nil
                )
                DebugLogging.log("✅ Text AI recommendation received", category: "ShotFlow")
                DebugLogging.logAPI(endpoint: "RecommenderService.getRecommendation (text)", url: nil as URL?, method: "POST", payload: payload, parsedModel: normalizedRecommendation)
                return normalizedRecommendation
            } else {
                DebugLogging.log("⚠️ Text AI returned invalid JSON, falling back to offline", category: "ShotFlow")
            }
        } catch {
            DebugLogging.log("⚠️ Text AI failed: \(error.localizedDescription), falling back to offline", category: "ShotFlow")
            DebugLogging.logAPI(endpoint: "RecommenderService.getRecommendation (text)", url: nil as URL?, method: "POST", payload: payload, error: error)
        }
        
        // Step 3: Final fallback to offline recommendation
        DebugLogging.log("📊 Using offline fallback recommendation", category: "ShotFlow")
        let fallback = fallbackRecommendation(profile: profile, context: context)
        recordDiagnostics(
            correlationId: correlationId,
            context: context,
            courseName: safeCourseName,
            holeNumber: resolvedHole,
            shotType: resolvedShotType,
            hazards: hazards,
            hasPhoto: photo != nil,
            selectionContext: clubSelectionContext,
            aiChosenClub: nil,
            finalRecommendation: fallback,
            normalizationReason: nil,
            fallbackReason: "Vision/text AI response unavailable or unparsable"
        )
        DebugLogging.logAPI(endpoint: "RecommenderService.getRecommendation (offline fallback)", url: nil as URL?, method: "POST", payload: payload, parsedModel: fallback)
        return fallback
    }

    private func loadStrategyPreferences() -> StrategyPreferences? {
        guard let data = UserDefaults.standard.data(forKey: "caddie_user_profile"),
              let userProfile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        return StrategyPreferences(
            seriousness: userProfile.seriousness,
            riskOffTee: userProfile.riskOffTee,
            riskAroundHazards: userProfile.riskAroundHazards
        )
    }
    
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
    
    /// Parse recommendation from JSON (handles both new structured format and legacy format)
    private func parseRecommendation(from jsonString: String) throws -> ShotRecommendation {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw NSError(domain: "RecommenderService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON string"])
        }
        
        // Try new structured format first
        if let structured = try? JSONDecoder().decode(StructuredShotRecommendation.self, from: jsonData) {
            return ShotRecommendation(from: structured)
        }
        
        // Fallback to legacy format
        if let legacy = try? JSONDecoder().decode(ShotRecommendation.self, from: jsonData) {
            return legacy
        }
        
        throw NSError(domain: "RecommenderService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse recommendation JSON"])
    }

    private func normalizeRecommendation(
        _ recommendation: ShotRecommendation,
        profile: PlayerProfile,
        selectionContext: ClubSelectionContext
    ) -> (recommendation: ShotRecommendation, reason: String?) {
        var normalized = recommendation
        let bagByName = Dictionary(uniqueKeysWithValues: profile.clubs.map { (normalizeClubName($0.name), $0) })
        let requestedClub = normalizeClubName(recommendation.club)
        let topCandidate = selectionContext.candidates.first?.club

        if let club = bagByName[requestedClub] {
            let gap = abs(club.carryYards - selectionContext.playsLikeDistance)
            if gap > 35, let fallbackClub = topCandidate {
                normalized.club = fallbackClub.name
                normalized.shotShape = fallbackClub.preferredShotShape.rawValue.capitalized
                normalized.narrative += "\n\nAdjusted to \(fallbackClub.name) because the original club was \(gap) yards off plays-like distance."
                return (normalized, "AI club distance gap (\(gap)yd) exceeded threshold; switched to top candidate")
            }
            return (normalized, nil)
        }

        if let fallbackClub = topCandidate {
            normalized.club = fallbackClub.name
            normalized.shotShape = fallbackClub.preferredShotShape.rawValue.capitalized
            normalized.narrative += "\n\nAdjusted to \(fallbackClub.name) because the AI-selected club was not in your bag."
            return (normalized, "AI club not in bag; switched to top candidate")
        }

        return (normalized, nil)
    }

    private func buildClubSelectionContext(
        profile: PlayerProfile,
        context: ShotContext,
        lie: String,
        shotType: String
    ) -> ClubSelectionContext {
        let playsLikeDistance = calculatePlaysLikeDistance(context: context)
        let normalizedLie = lie.lowercased()
        let normalizedShotType = shotType.lowercased()

        let scored = profile.clubs.map { club -> ClubCandidate in
            let gap = abs(club.carryYards - playsLikeDistance)
            var score = Double(gap)
            var rationale: [String] = ["Distance gap: \(gap)yd"]
            score += confidencePenalty(for: club.confidenceLevel)
            rationale.append("Confidence: \(club.confidenceLevel.displayName)")

            if !isClubAllowed(club, forLie: normalizedLie, shotType: normalizedShotType) {
                score += 200
                rationale.append("Large penalty: not viable for lie/shot type")
            } else if normalizedLie.contains("rough"), isLongDistanceClub(club) {
                score += 10
                rationale.append("Penalty: long club from rough")
            }

            return ClubCandidate(club: club, score: score, distanceGap: gap, rationale: rationale)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.distanceGap < rhs.distanceGap
            }
            return lhs.score < rhs.score
        }

        let candidates = Array(scored.prefix(4))
        return ClubSelectionContext(
            playsLikeDistance: playsLikeDistance,
            candidates: candidates.isEmpty ? scored : candidates
        )
    }

    private func calculatePlaysLikeDistance(context: ShotContext) -> Int {
        let targetDistance = context.distanceToCenter
        let elevationAdjustment = context.elevationSource == .liveAPI ? context.elevationDelta : 0
        let shotBearing = bearingDegrees(from: context.playerCoordinate, to: context.targetCoordinate)
        let windComponent = headwindComponent(windDir: context.windDirectionDeg, shotDir: shotBearing)
        let windAdjustment = context.weatherSource == .liveAPI ? (windComponent * context.windSpeedMph * 0.8) : 0
        let temperatureAdjustment = context.weatherSource == .liveAPI ? ((70.0 - context.temperatureF) * 0.15) : 0
        let playsLike = targetDistance + elevationAdjustment + windAdjustment + temperatureAdjustment
        return max(1, Int(playsLike.rounded()))
    }

    private func bearingDegrees(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private func headwindComponent(windDir: Double, shotDir: Double) -> Double {
        let delta = (windDir - shotDir) * .pi / 180
        return cos(delta)
    }

    private func confidencePenalty(for confidence: ClubConfidenceLevel) -> Double {
        switch confidence {
        case .veryConfident: return -4
        case .confident: return 0
        case .neutral: return 6
        case .notConfident: return 14
        case .avoidAtAllCosts: return 26
        }
    }

    private func isLongDistanceClub(_ club: ClubDistance) -> Bool {
        switch club.clubType {
        case .driver, .wood3, .wood5, .wood7, .hybrid2, .hybrid3, .hybrid4, .hybrid5, .iron2, .iron3, .iron4, .iron5:
            return true
        default:
            return false
        }
    }

    private func isClubAllowed(_ club: ClubDistance, forLie lie: String, shotType: String) -> Bool {
        if lie.contains("bunker") {
            switch club.clubType {
            case .sandWedge, .lobWedge, .gapWedge, .pitchingWedge, .iron9, .iron8:
                return true
            default:
                return false
            }
        }

        if lie.contains("deep rough") || lie.contains("woods") {
            if club.clubType == .driver {
                return false
            }
        }

        if shotType.contains("drive"), lie.contains("tee") {
            return true
        }

        return true
    }

    private func normalizeClubName(_ club: String) -> String {
        club.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private func recordDiagnostics(
        correlationId: String,
        context: ShotContext,
        courseName: String,
        holeNumber: Int,
        shotType: String,
        hazards: [String],
        hasPhoto: Bool,
        selectionContext: ClubSelectionContext,
        aiChosenClub: String?,
        finalRecommendation: ShotRecommendation,
        normalizationReason: String?,
        fallbackReason: String?
    ) {
        let candidateDiagnostics = selectionContext.candidates.map {
            CandidateClubDiagnostic(
                club: $0.club.name,
                carryYards: $0.club.carryYards,
                confidenceLevel: $0.club.confidenceLevel.displayName,
                notes: $0.club.notes,
                distanceGapYards: $0.distanceGap,
                score: $0.score,
                rationale: $0.rationale
            )
        }

        let diagnostics = ShotRecommendationDiagnostics(
            correlationId: correlationId,
            courseName: courseName,
            holeNumber: holeNumber,
            shotType: shotType,
            lie: context.lieType,
            targetDistanceYards: Int(context.distanceToCenter.rounded()),
            playsLikeDistanceYards: selectionContext.playsLikeDistance,
            weatherSource: context.weatherSource.rawValue,
            elevationSource: context.elevationSource.rawValue,
            hazards: hazards,
            hasPhoto: hasPhoto,
            photoReferencedInOutput: hasPhoto && recommendationReferencesPhoto(finalRecommendation),
            candidates: candidateDiagnostics,
            aiChosenClub: aiChosenClub,
            finalClub: finalRecommendation.club,
            normalizationOccurred: normalizationReason != nil,
            normalizationReason: normalizationReason,
            fallbackUsed: fallbackReason != nil,
            fallbackReason: fallbackReason,
            requestDurationMs: nil
        )

        lastDiagnostics = diagnostics
        Task { @MainActor in
            RecommendationDiagnosticsStore.shared.record(diagnostics)
        }
        if let data = try? JSONEncoder().encode(diagnostics),
           let json = String(data: data, encoding: .utf8) {
            DebugLogging.log("ShotRecommendationDiagnostics: \(json)", category: "Diagnostics")
        }
    }

    func setLastDiagnosticsRequestDuration(_ durationMs: Int) {
        guard var diagnostics = lastDiagnostics else { return }
        diagnostics.requestDurationMs = durationMs
        lastDiagnostics = diagnostics
        Task { @MainActor in
            RecommendationDiagnosticsStore.shared.updateRequestDuration(
                correlationId: diagnostics.correlationId,
                durationMs: durationMs
            )
        }
    }

    private func recommendationReferencesPhoto(_ recommendation: ShotRecommendation) -> Bool {
        var textParts: [String] = [recommendation.narrative]
        if let headline = recommendation.headline {
            textParts.append(headline)
        }
        textParts.append(contentsOf: recommendation.bullets)
        let mergedText = textParts.map { $0.lowercased() }.joined(separator: " ")
        let photoTerms = ["photo", "image", "visual", "seen", "looks", "view", "from the picture"]
        return photoTerms.contains { mergedText.contains($0) }
    }

    private func applyPhotoInfluenceGuardrail(to recommendation: ShotRecommendation, hasPhoto: Bool) -> ShotRecommendation {
        guard hasPhoto else { return recommendation }
        guard !recommendationReferencesPhoto(recommendation) else { return recommendation }
        var updated = recommendation
        updated.narrative += "\n\nPhoto-informed note: Lie and visible obstacles were factored into this recommendation."
        return updated
    }

    #if DEBUG
    func runScenarioDiagnostics(profile: PlayerProfile, scenarios: [ShotRecommendationScenario]) -> [ShotRecommendationDiagnostics] {
        scenarios.map { scenario in
            let context = ShotContext(
                hole: 1,
                playerCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                targetCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.0001),
                distanceToCenter: scenario.distanceYards,
                elevationDelta: scenario.elevationDelta,
                windSpeedMph: scenario.windMph,
                windDirectionDeg: scenario.windDirDeg,
                temperatureF: scenario.temperatureF,
                weatherSource: .liveAPI,
                elevationSource: .liveAPI,
                lieType: scenario.lie
            )
            let selectionContext = buildClubSelectionContext(
                profile: profile,
                context: context,
                lie: scenario.lie,
                shotType: scenario.shotType
            )
            let chosen = selectionContext.candidates.first?.club.name ?? "N/A"
            let candidateDiagnostics = selectionContext.candidates.map {
                CandidateClubDiagnostic(
                    club: $0.club.name,
                    carryYards: $0.club.carryYards,
                    confidenceLevel: $0.club.confidenceLevel.displayName,
                    notes: $0.club.notes,
                    distanceGapYards: $0.distanceGap,
                    score: $0.score,
                    rationale: $0.rationale
                )
            }
            return ShotRecommendationDiagnostics(
                correlationId: "scenario-\(scenario.name)",
                courseName: "Scenario",
                holeNumber: 1,
                shotType: scenario.shotType,
                lie: scenario.lie,
                targetDistanceYards: Int(scenario.distanceYards.rounded()),
                playsLikeDistanceYards: selectionContext.playsLikeDistance,
                weatherSource: context.weatherSource.rawValue,
                elevationSource: context.elevationSource.rawValue,
                hazards: scenario.hazards,
                hasPhoto: false,
                photoReferencedInOutput: false,
                candidates: candidateDiagnostics,
                aiChosenClub: nil,
                finalClub: chosen,
                normalizationOccurred: false,
                normalizationReason: nil,
                fallbackUsed: false,
                fallbackReason: nil
            )
        }
    }
    #endif
    
    func fallbackRecommendation(profile: PlayerProfile, context: ShotContext) -> ShotRecommendation {
        let targetDistance = Int(context.distanceToCenter)
        guard !profile.clubs.isEmpty else {
            return ShotRecommendation(
                club: "7i",
                aimOffsetYards: 0.0,
                shotShape: "Straight",
                narrative: "⚠️ Fallback recommendation: No clubs configured. Please set up your clubs in Profile. Using default 7i.",
                confidence: 0.5,
                avoidZones: []
            )
        }
        let closestClub = profile.clubs.min(by: { abs($0.carryYards - targetDistance) < abs($1.carryYards - targetDistance) }) ?? profile.clubs[0]
        return ShotRecommendation(
            club: closestClub.name,
            aimOffsetYards: 0.0,
            shotShape: closestClub.preferredShotShape.rawValue.capitalized,
            narrative: "⚠️ Fallback recommendation: AI analysis unavailable. Using \(closestClub.name) for \(targetDistance) yards. Aim for center of green.",
            confidence: 0.7,
            avoidZones: []
        )
    }
}
