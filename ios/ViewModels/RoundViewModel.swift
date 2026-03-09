//
//  RoundViewModel.swift
//  Caddie.ai
//

import Foundation
import CoreLocation
import UIKit

@MainActor
class RoundViewModel: ObservableObject {
    @Published var currentCourse: Course?
    @Published var currentHole: Int = 1
    @Published var scores: [Int: Int] = [:] // [hole: strokes]
    @Published var aiRecommendation: ShotRecommendation?
    @Published var aiState: ViewState = .idle
    @Published var shotFlowState: ShotFlowState = .idle
    @Published var recommendationAccepted: Bool = false
    @Published var showSavedConfirmation = false
    @Published var capturedShots: [Int: [CapturedShot]] = [:] // [hole: [shots]]
    
    private let apiService = APIService.shared
    
    // Optional history store for saving recommendations
    var historyStore: HistoryStore?
    
    // Legacy computed properties for backward compatibility
    var isLoadingAI: Bool {
        aiState == .loading
    }
    
    var aiErrorMessage: String? {
        aiState.errorMessage
    }
    
    init() {
        // Load current course from CourseViewModel or UserDefaults
        if let data = UserDefaults.standard.data(forKey: "CurrentCourse"),
           let course = try? JSONDecoder().decode(Course.self, from: data) {
            currentCourse = course
        }
    }
    
    func startRound(course: Course) {
        currentCourse = course
        currentHole = 1
        scores = [:]
        aiRecommendation = nil
        aiState = .idle
        shotFlowState = .idle
        recommendationAccepted = false
        capturedShots = [:]
        
        // Haptic feedback for starting round
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Save course to UserDefaults
        if let encoded = try? JSONEncoder().encode(course) {
            UserDefaults.standard.set(encoded, forKey: "CurrentCourse")
        }
    }
    
    /// Resume a round from saved state
    func resumeRound(course: Course, savedScores: [Int: Int], savedHole: Int, savedShots: [Int: [CapturedShot]]) {
        currentCourse = course
        currentHole = savedHole
        scores = savedScores
        capturedShots = savedShots
        aiRecommendation = nil
        aiState = .idle
        shotFlowState = .idle
        recommendationAccepted = false
    }
    
    func addCapturedShot(_ shot: CapturedShot) {
        var shots = capturedShots[shot.holeNumber] ?? []
        
        if let backendId = shot.backendId,
           let index = shots.firstIndex(where: { $0.backendId == backendId }) {
            shots[index] = shot
        } else if let index = shots.firstIndex(where: { $0.id == shot.id }) {
            shots[index] = shot
        } else {
            shots.append(shot)
        }
        
        shots.sort { $0.timestamp > $1.timestamp }
        capturedShots[shot.holeNumber] = shots
    }
    
    func getCapturedShots(forHole hole: Int, shotType: ShotType) -> [CapturedShot] {
        return capturedShots[hole]?.filter { $0.shotType == shotType } ?? []
    }
    
    func getAllCapturedShots(forHole hole: Int) -> [CapturedShot] {
        return capturedShots[hole] ?? []
    }
    
    func setHole(_ hole: Int) {
        guard hole >= 1 && hole <= 18 else { return }
        currentHole = hole
        resetShotFlowForNewHole()
    }
    
    func resetShotFlowForNewHole() {
        shotFlowState = .idle
        recommendationAccepted = false
        aiRecommendation = nil
        aiState = .idle
    }
    
    func acceptRecommendation() {
        guard shotFlowState == .showingRecommendation else { return }
        recommendationAccepted = true
        shotFlowState = .recommendationAccepted
    }
    
    func resetForNewShot() {
        shotFlowState = .idle
        recommendationAccepted = false
        // Keep aiRecommendation until explicitly cleared or new shot starts
    }
    
    func setScore(_ strokes: Int, forHole hole: Int) {
        // Require recommendation acceptance before scoring (unless recommendation was already accepted)
        guard recommendationAccepted || shotFlowState == .idle || shotFlowState == .recommendationAccepted else {
            DebugLogging.log("⚠️ Attempted to set score without accepting recommendation", category: "ShotFlow")
            return
        }
        
        scores[hole] = strokes
        showSavedConfirmation = true
        
        // Haptic feedback for finishing a hole
        let successGenerator = UINotificationFeedbackGenerator()
        successGenerator.notificationOccurred(.success)
        
        // Reset shot flow for next shot
        resetForNewShot()
        
        // Hide confirmation after 1.5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showSavedConfirmation = false
        }
    }
    
    func nextHole() {
        if currentHole < 18 {
            currentHole += 1
            resetShotFlowForNewHole()
        }
    }
    
    func previousHole() {
        if currentHole > 1 {
            currentHole -= 1
            resetShotFlowForNewHole()
        }
    }
    
    func askCaddie(profile: PlayerProfile, location: CLLocationCoordinate2D?) async {
        guard let course = currentCourse else {
            aiState = .error("No course selected")
            shotFlowState = .error("No course selected")
            return
        }
        
        // Haptic feedback for asking Caddie
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Reset for new shot flow
        recommendationAccepted = false
        aiRecommendation = nil
        aiState = .loading
        shotFlowState = .sendingToAI
        
        // Build payload according to spec
        var payload: [String: Any] = [:]
        
        // Course info
        payload["course"] = [
            "id": course.id,
            "name": course.name
        ]
        
        // Hole
        payload["hole"] = currentHole
        
        // Location (if available)
        if let location = location {
            payload["location"] = [
                "latitude": location.latitude,
                "longitude": location.longitude
            ]
        } else {
            payload["location"] = NSNull()
        }
        
        // Weather (placeholder - nulls OK for now)
        payload["weather"] = NSNull()
        
        // Include all captured shots for this hole
        var shotsArray: [[String: Any]] = []
        if let shots = capturedShots[currentHole] {
            for shot in shots {
                var shotData: [String: Any] = [
                    "shotType": shot.shotType.rawValue,
                    "timestamp": ISO8601DateFormatter().string(from: shot.timestamp)
                ]
                
                if let club = shot.club {
                    shotData["club"] = club
                }
                if let distance = shot.distance {
                    shotData["distance"] = distance
                }
                if let backendId = shot.backendId {
                    shotData["shotId"] = backendId
                }
                if let imageURL = shot.imageURL {
                    shotData["imageUrl"] = imageURL
                }
                if let recommendation = shot.recommendation {
                    shotData["recommendation"] = [
                        "club": recommendation.club,
                        "aim": recommendation.aim,
                        "avoid": recommendation.avoid,
                        "confidence": recommendation.confidence
                    ]
                }
                if let context = shot.shotContext {
                    var contextPayload: [String: Any] = [
                        "shotType": context.shotType,
                        "surface": context.surface
                    ]
                    
                    if let conditions = context.conditions {
                        var conditionsPayload: [String: Any] = [:]
                        if let wind = conditions.wind {
                            conditionsPayload["wind"] = wind
                        }
                        if let elevation = conditions.elevation {
                            conditionsPayload["elevation"] = elevation
                        }
                        
                        if !conditionsPayload.isEmpty {
                            contextPayload["conditions"] = conditionsPayload
                        }
                    }
                    
                    shotData["shotContext"] = contextPayload
                }
                if let feedback = shot.userFeedback {
                    shotData["userFeedback"] = feedback
                }
                
                shotsArray.append(shotData)
            }
        }
        if !shotsArray.isEmpty {
            payload["capturedShots"] = shotsArray
        }
        
        // Player profile with clubs and per-club shot shape
        var clubsArray: [[String: Any]] = []
        for club in profile.clubs {
            clubsArray.append([
                "name": club.name,
                "carryYards": club.carryYards,
                "preferredShotShape": club.preferredShotShape.rawValue,
                "shotPreference": club.shotPreference.displayName,
                "confidenceLevel": club.confidenceLevel.displayName
            ])
        }
        
        payload["player"] = [
            "clubs": clubsArray,
            "missLeftPct": profile.missesLeftPct,
            "missRightPct": profile.missesRightPct
        ]
        
        // Build system and user prompts
        let systemPrompt = """
        You are an expert golf caddie AI. Analyze the player's profile and shot context, then provide a shot recommendation in JSON format.
        Return ONLY valid JSON matching this structure:
        {
            "id": "UUID string",
            "club": "Club name (e.g., '7i', 'PW', 'Driver')",
            "aimOffsetYards": 0.0,
            "shotShape": "Straight, Draw, or Fade",
            "narrative": "Detailed shot recommendation text",
            "confidence": 0.85,
            "avoidZones": ["List of hazards to avoid"]
        }
        """
        
        let userPromptJSON = try? JSONSerialization.data(withJSONObject: payload)
        let userPrompt = String(data: userPromptJSON ?? Data(), encoding: .utf8) ?? "{}"
        
        // Log the full payload for debugging
        let fullPayload: [String: Any] = [
            "system": systemPrompt,
            "user": payload  // Include the structured payload
        ]
        
        // Use APIService as single source of truth for base URL
        let completeURL = APIService.getBaseURL().appendingPathComponent("api/openai/complete")
        DebugLogging.logAPI(
            endpoint: "RoundViewModel.askCaddie",
            url: completeURL,
            method: "POST",
            payload: fullPayload
        )
        
        // Call API
        do {
            let requestPayload: [String: String] = [
                "system": systemPrompt,
                "user": userPrompt
            ]
            
            // Update state to waiting for recommendation
            shotFlowState = .waitingForRecommendation
            
            // Pass profile for fallback recommendation
            let recommendationMetadata: [String: Any] = [
                "courseName": course.name,
                "holeNumber": currentHole
            ]
            let recommendation = try await apiService.askCaddie(payload: requestPayload, fallbackProfile: profile, metadata: recommendationMetadata)
            aiRecommendation = recommendation
            saveShotToHistory(recommendation: recommendation)
            
            DebugLogging.logAPI(
                endpoint: "RoundViewModel.askCaddie",
                url: completeURL,
                method: "POST",
                payload: fullPayload,
                parsedModel: recommendation
            )
            
            // Haptic feedback for receiving recommendation
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)
            
            // Move to showing recommendation state
            shotFlowState = .showingRecommendation
            recommendationAccepted = false
            
            // If recommendation narrative contains fallback indicator, don't show error but log it
            if recommendation.narrative.contains("⚠️ Fallback recommendation") {
                aiState = .loaded // Don't show error, but recommendation is marked as fallback
                DebugLogging.log("⚠️ Using fallback recommendation", category: "ShotFlow")
            } else {
                aiState = .loaded
            }
        } catch let error as APIError {
            // Handle specific API errors with friendly messages
            let errorMessage: String
            switch error {
            case .serverError(let message):
                errorMessage = message
            case .invalidResponse:
                errorMessage = "Could not connect to the server. Please check your internet connection."
            case .invalidURL:
                errorMessage = "Invalid server configuration"
            case .timeout:
                errorMessage = "Request timed out. Please try again."
            case .missingResult:
                errorMessage = "Server response was incomplete"
            case .decodingError:
                errorMessage = "Could not understand server response"
            }
            
            // Haptic feedback for error
            let errorGenerator = UINotificationFeedbackGenerator()
            errorGenerator.notificationOccurred(.error)
            
            aiState = .error(errorMessage)
            shotFlowState = .error(errorMessage)
            DebugLogging.logAPI(
                endpoint: "RoundViewModel.askCaddie",
                url: completeURL,
                method: "POST",
                payload: fullPayload,
                error: error
            )
        } catch {
            let errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
            
            // Haptic feedback for error
            let errorGenerator = UINotificationFeedbackGenerator()
            errorGenerator.notificationOccurred(.error)
            
            aiState = .error(errorMessage)
            shotFlowState = .error(errorMessage)
            DebugLogging.logAPI(
                endpoint: "RoundViewModel.askCaddie",
                url: completeURL,
                method: "POST",
                payload: fullPayload,
                error: error
            )
            print("Error asking caddie: \(error)")
        }
    }
    
    func sendFeedback(helpful: Bool, shotId: String? = nil, suggestedClub: String? = nil) async {
        guard let course = currentCourse else {
            return
        }
        
        // Haptic feedback for thumbs up/down
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        let clubName = suggestedClub ?? aiRecommendation?.club ?? "unknown"
        
        let feedback = helpful ? "helpful" : "off"
        
        do {
            try await apiService.sendFeedback(
                courseId: course.id,
                hole: currentHole,
                suggestedClub: clubName,
                feedback: feedback,
                shotId: shotId
            )
            
            if let shotId {
                updateCapturedShotFeedback(shotId: shotId, feedback: feedback)
            }
        } catch {
            print("Error sending feedback: \(error)")
        }
    }
    
    private func updateCapturedShotFeedback(shotId: String, feedback: String) {
        for (hole, var shots) in capturedShots {
            if let index = shots.firstIndex(where: { $0.backendId == shotId }) {
                shots[index].userFeedback = feedback
                capturedShots[hole] = shots
            }
        }
    }
    
    private func saveShotToHistory(recommendation: ShotRecommendation) {
        guard let historyStore = historyStore else { return }
        let courseName = currentCourse?.name
        let text = "Recommended Club: \(recommendation.club)\n\n\(recommendation.narrative)"
        let shotMeta = ShotHistoryMetadata(
            distanceYards: nil,
            shotType: "Approach",
            lie: nil,
            clubRecommended: recommendation.club,
            courseName: courseName,
            holeNumber: currentHole,
            hazards: nil,
            weather: nil,
            timestamp: Date()
        )
        let raw = (try? JSONEncoder().encode(recommendation)).flatMap { String(data: $0, encoding: .utf8) }
        let item = HistoryItem(
            type: .shot,
            courseName: courseName,
            distanceYards: nil,
            shotType: "Approach",
            lie: nil,
            hazards: nil,
            recommendationText: text,
            rawAIResponse: raw,
            thumbnailData: nil,
            shotMetadata: shotMeta,
            puttMetadata: nil
        )
        historyStore.add(item)
    }
}
