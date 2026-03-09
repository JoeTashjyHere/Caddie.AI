//
//  CaddieUnifiedViewModel.swift
//  Caddie.ai
//
//  Unified ViewModel for the camera-first Caddie experience

import Foundation
import SwiftUI
import CoreLocation
import UIKit

// Mode enum to track if we're in green reader or full shot flow
enum CaddieMode {
    case fullShot
    case greenReader
}

@MainActor
final class CaddieUnifiedViewModel: ObservableObject {
    @Published var state: CaddieFlowState = .idle
    @Published var draft = CaddieContextDraft()
    @Published var capturedImage: UIImage?
    @Published var photoAnalysis: ShotPhotoAnalysis?
    @Published var recommendation: ShotRecommendation?
    @Published var puttingRead: PuttingRead?
    @Published var shotContext: ShotContext?
    @Published var confidence: ConfidenceLevel = .low
    @Published var bannerMessage: String?
    
    // Track current mode (green reader vs full shot)
    private var currentMode: CaddieMode = .fullShot
    
    private let recommender: RecommenderService
    private let courseService: CourseService
    private let weatherService: WeatherService
    private let elevationService: ElevationService
    private let apiService: APIService
    
    // Optional history store (injected when available)
    var historyStore: HistoryStore?
    
    init(recommender: RecommenderService = RecommenderService.shared,
         courseService: CourseService = CourseService.shared,
         weatherService: WeatherService = WeatherService.shared,
         elevationService: ElevationService = ElevationService.shared,
         apiService: APIService = APIService.shared) {
        self.recommender = recommender
        self.courseService = courseService
        self.weatherService = weatherService
        self.elevationService = elevationService
        self.apiService = apiService
    }
    
    // MARK: - Public Methods
    
    func onAppear(locationService: LocationService) {
        Task {
            await refreshAutoContext(locationService: locationService)
        }
    }
    
    func startPhotoCapture(mode: CaddieMode = .fullShot) {
        currentMode = mode
        state = .capturingPhoto
    }
    
    func handleCapturedPhoto(_ image: UIImage, profile: PlayerProfile) {
        capturedImage = image
        
        // If green reader mode, skip context confirmation and go straight to analysis
        if currentMode == .greenReader {
            // For green reader, analyze immediately with photo
            state = .analyzingShot
            Task {
                await requestPuttingReadFromPhoto(profile: profile)
            }
        } else {
            state = .confirmingContext
        }
        recomputeConfidence()
    }
    
    func openContextSheet() {
        state = .confirmingContext
    }
    
    func cancelContextSheet() {
        state = .idle
    }
    
    func analyzeShot(profile: PlayerProfile, locationService: LocationService) {
        state = .analyzingShot
        bannerMessage = nil
        
        Task {
            do {
                // Attempt photo analysis
                var analysis = ShotPhotoAnalysis()
                
                if let image = capturedImage {
                    // Try /photo/analyze endpoint first
                    do {
                        analysis = try await analyzePhotoViaAPI(image: image)
                    } catch {
                        // Fallback to OpenAI Vision
                        analysis = try await analyzePhotoViaVision(image: image)
                    }
                }
                
                // Apply override if set
                if let override = draft.isOnGreenOverride {
                    analysis.isOnGreen = override
                }
                
                photoAnalysis = analysis
                
                // Update draft lie if analysis found one
                if let analyzedLie = analysis.lie, draft.lie == nil {
                    draft.lie = analyzedLie
                }
                
                // Route based on green detection
                if analysis.isOnGreen {
                    await requestPuttingRead(profile: profile, locationService: locationService)
                } else {
                    await requestRecommendation(profile: profile, locationService: locationService)
                }
                
                recomputeConfidence()
            } catch {
                state = .error(message: "Analysis failed: \(error.localizedDescription)")
            }
        }
    }
    
    func requestRecommendation(profile: PlayerProfile, locationService: LocationService) async {
        state = .requestingRecommendation
        bannerMessage = nil
        
        do {
            // Location is now optional - build context even without location
            let ctx = try await buildShotContext(profile: profile, locationService: locationService)
            shotContext = ctx
            
            // Use course from draft, or create a temporary Course object if only courseName is available
            var courseForContext = draft.course
            if courseForContext == nil, let courseName = draft.courseName, !courseName.isEmpty {
                // Create a temporary course object with just the name for AI context
                courseForContext = Course(id: "manual-\(courseName)", name: courseName)
            }
            
            // Parse hazards from draft.hazards string (comma-separated or newline-separated)
            let hazardsList = parseHazardsString(draft.hazards)
            
            // Log the context being sent
            DebugLogging.log("📤 Sending shot recommendation request with context: courseName=\(draft.courseName ?? "nil"), city=\(draft.city ?? "nil"), state=\(draft.state ?? "nil"), holeNumber=\(draft.holeNumber?.description ?? "nil")", category: "ShotFlow")
            
            let rec = try await recommender.getRecommendation(
                profile: profile,
                context: ctx,
                hazards: hazardsList,
                course: courseForContext,
                photo: capturedImage,
                courseName: draft.courseName,
                city: draft.city,
                state: draft.state,
                holeNumber: draft.holeNumber,
                shotType: draft.shotType.displayName,
                historyStore: historyStore
            )
            
            recommendation = rec
            state = .showingRecommendation
            
            // Save to history after successful recommendation
            saveShotRecommendationToHistory(rec: rec, courseForContext: courseForContext, ctx: ctx)
        } catch {
            state = .error(message: "Failed to get recommendation: \(error.localizedDescription)")
        }
    }
    
    // MARK: - History Saving Methods
    
    /// Save shot recommendation to history
    private func saveShotRecommendationToHistory(rec: ShotRecommendation, courseForContext: Course?, ctx: ShotContext) {
        guard let historyStore = historyStore else { return }
        
        // Format recommendation text (matching what user sees in RecommendationCardView)
        let recommendationText = formatShotRecommendationText(rec: rec, distance: Int(ctx.distanceToCenter), lie: draft.lie)
        
        // Get raw JSON if available - strip markdown code fences
        let rawAIResponse: String?
        if let jsonData = try? JSONEncoder().encode(rec),
           var jsonString = String(data: jsonData, encoding: .utf8) {
            // Strip markdown code fences if present
            jsonString = stripMarkdownCodeFences(jsonString)
            rawAIResponse = jsonString
        } else {
            rawAIResponse = nil
        }
        
        // Create thumbnail from captured image if available (compress to 300-600px wide)
        let thumbnailData: Data?
        if let image = capturedImage {
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
        let hazardsString = rec.avoidZones.isEmpty ? nil : rec.avoidZones.joined(separator: ", ")
        
        let weather = HistoryWeatherSnapshot(
            windMph: ctx.windSpeedMph,
            windDirDeg: ctx.windDirectionDeg,
            tempF: ctx.temperatureF,
            elevationDeltaYards: ctx.elevationDelta
        )
        
        let shotMetadata = ShotHistoryMetadata(
            distanceYards: Int(ctx.distanceToCenter),
            shotType: draft.shotType.displayName,
            lie: draft.lie,
            clubRecommended: rec.club,
            courseName: courseForContext?.name ?? draft.courseName,
            holeNumber: draft.holeNumber,
            hazards: hazardsString ?? draft.hazards,
            weather: weather,
            timestamp: Date()
        )
        
        let historyItem = HistoryItem(
            type: .shot,
            courseName: courseForContext?.name ?? draft.courseName,
            distanceYards: Int(ctx.distanceToCenter),
            shotType: draft.shotType.displayName,
            lie: draft.lie,
            hazards: hazardsString ?? draft.hazards,
            recommendationText: recommendationText,
            rawAIResponse: rawAIResponse,
            thumbnailData: thumbnailData,
            shotMetadata: shotMetadata
        )
        
        Task { @MainActor in
            historyStore.add(historyItem)
        }
    }
    
    /// Format shot recommendation text for history display
    private func formatShotRecommendationText(rec: ShotRecommendation, distance: Int, lie: String?) -> String {
        var text = "Recommended Club: \(rec.club)\n"
        
        if distance > 0 {
            text += "Distance: \(distance) yards\n"
        }
        
        if let lie = lie {
            text += "Lie: \(lie.capitalized)\n"
        }
        
        if rec.aimOffsetYards != 0 {
            let offset = abs(rec.aimOffsetYards)
            let direction = rec.aimOffsetYards > 0 ? "right" : "left"
            text += "Aim: \(String(format: "%.0f", offset)) yards \(direction)\n"
        }
        
        if !rec.shotShape.isEmpty && rec.shotShape.lowercased() != "straight" {
            text += "Shot Shape: \(rec.shotShape)\n"
        }
        
        text += "\n\(rec.narrative)"
        
        if !rec.avoidZones.isEmpty {
            text += "\n\nHazards to Avoid:\n"
            for zone in rec.avoidZones {
                text += "• \(zone)\n"
            }
        }
        
        return text
    }
    
    /// Parse hazards string into array (handles comma, newline, or space separation)
    private func parseHazardsString(_ hazardsString: String?) -> [String] {
        guard let hazardsString = hazardsString, !hazardsString.isEmpty else {
            return []
        }
        
        // Split by comma, newline, or multiple spaces
        let components = hazardsString
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        return components
    }
    
    /// Strip markdown code fences from JSON strings
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
    
    /// Save putting read to history
    private func savePuttingReadToHistory(puttingRead: PuttingRead) {
        guard let historyStore = historyStore else { return }
        
        // Format recommendation text (matching what user sees in PuttingReadCardView)
        var recommendationText = "Putting Read\n\n"
        recommendationText += "Break: \(puttingRead.breakDirection)\n"
        recommendationText += "Amount: \(String(format: "%.1f", puttingRead.breakAmount)) feet\n"
        recommendationText += "Speed: \(puttingRead.speed)\n\n"
        recommendationText += puttingRead.narrative
        
        if let puttingLine = puttingRead.puttingLine {
            recommendationText += "\n\nPutting Line: \(puttingLine)"
        }
        
        // Get raw JSON if available - strip markdown code fences
        let rawAIResponse: String?
        if let jsonData = try? JSONEncoder().encode(puttingRead),
           var jsonString = String(data: jsonData, encoding: .utf8) {
            // Strip markdown code fences if present
            jsonString = stripMarkdownCodeFences(jsonString)
            rawAIResponse = jsonString
        } else {
            rawAIResponse = nil
        }
        
        // Create thumbnail from captured image if available (compress to 300-600px wide)
        let thumbnailData: Data?
        if let image = capturedImage {
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
        
        let puttMetadata = PuttHistoryMetadata(
            puttDistanceFeet: nil,
            breakDirection: puttingRead.breakDirection,
            speedRecommendation: puttingRead.speed,
            greenSlopeInference: puttingRead.theLine ?? puttingRead.puttingLine,
            courseName: draft.course?.name ?? draft.courseName,
            holeNumber: draft.holeNumber,
            timestamp: Date()
        )
        
        let historyItem = HistoryItem(
            type: .putt,
            courseName: draft.course?.name ?? draft.courseName,
            distanceYards: nil,
            shotType: nil,
            lie: nil,
            hazards: nil,
            recommendationText: recommendationText,
            rawAIResponse: rawAIResponse,
            thumbnailData: thumbnailData,
            puttMetadata: puttMetadata
        )
        
        Task { @MainActor in
            historyStore.add(historyItem)
        }
    }
    
    func requestPuttingRead(profile: PlayerProfile, locationService: LocationService) async {
        state = .requestingPuttingRead
        
        do {
            // If we have course + hole, try to use CourseMapperService
            if let course = draft.course, let holeNumber = draft.holeNumber {
                do {
                    // Try CourseMapperService for green contours
                    let puttingViewModel = PuttingViewModel()
                    if let location = locationService.coordinate,
                       let imageData = capturedImage?.jpegData(compressionQuality: 0.8) {
                        await puttingViewModel.analyzePutting(
                            imageData: imageData,
                            courseId: course.id,
                            holeNumber: holeNumber,
                            lat: location.latitude,
                            lon: location.longitude
                        )
                        if let read = puttingViewModel.puttingRead {
                            puttingRead = read
                            state = .showingPuttingRead
                            return
                        }
                    }
                } catch {
                    // Fallback to AI vision analysis
                }
            }
            
            // Use AI vision to analyze putting photo
            if let image = capturedImage {
                puttingRead = try await generatePuttingReadViaVision(image: image, profile: profile)
            } else {
                // Fallback: Generate general putting read via AI text
                puttingRead = try await generatePuttingReadViaAI(profile: profile)
            }
            state = .showingPuttingRead
            
            // Save to history after successful putting read
            if let puttingRead = puttingRead {
                savePuttingReadToHistory(puttingRead: puttingRead)
            }
        } catch {
            state = .error(message: "Failed to get putting read: \(error.localizedDescription)")
        }
    }
    
    // New method: Request putting read directly from photo (for green reader flow)
    func requestPuttingReadFromPhoto(profile: PlayerProfile) async {
        state = .requestingPuttingRead
        
        guard let image = capturedImage else {
            state = .error(message: "No photo available")
            return
        }
        
        do {
            // Use AI vision to analyze putting photo
            puttingRead = try await generatePuttingReadViaVision(image: image, profile: profile)
            state = .showingPuttingRead
            
            // Save to history after successful putting read
            if let puttingRead = puttingRead {
                savePuttingReadToHistory(puttingRead: puttingRead)
            }
        } catch {
            state = .error(message: "Failed to analyze putting: \(error.localizedDescription)")
        }
    }
    
    // Generate putting read using vision API
    private func generatePuttingReadViaVision(image: UIImage, profile: PlayerProfile) async throws -> PuttingRead {
        // Get historical learning from history (filter for green reads)
        let historicalLearning: PuttHistoricalLearning?
        if let historyStore = historyStore {
            // HistoryStore is @MainActor, so we need to access items from main actor context
            let historyItems = await MainActor.run { historyStore.items }
            // Filter for green reads only
            let greenReadItems = historyItems.filter { $0.type == .putt }
            historicalLearning = PuttHistoricalLearning(from: greenReadItems, limit: 5)
        } else {
            historicalLearning = nil
        }
        
        // Build player profile data
        let playerProfileData = PlayerProfileData(from: profile)
        
        // Get environmental context if available
        var environmentalContext: ShotContext?
        if let ctx = shotContext {
            environmentalContext = ctx
        }
        
        // Build prompts using CaddiePromptBuilder
        let (systemPrompt, userPrompt) = CaddiePromptBuilder.shared.buildGreenReaderPrompt(
            courseName: draft.courseName ?? draft.course?.name,
            city: draft.city,
            state: draft.state,
            holeNumber: draft.holeNumber,
            puttDistance: nil, // Can be added later if user provides distance
            playerProfile: playerProfileData,
            historicalLearning: historicalLearning,
            environmentalContext: environmentalContext
        )
        
        let jsonString = try await OpenAIClient.shared.completeWithVision(
            system: systemPrompt,
            user: userPrompt,
            image: image
        )
        
        let cleanedJSON = stripMarkdownCodeFences(jsonString)
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw NSError(domain: "CaddieUnifiedViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])
        }
        
        // Try new structured format first
        if let structured = try? JSONDecoder().decode(StructuredPuttingRead.self, from: jsonData) {
            return PuttingRead(from: structured)
        }
        
        // Fallback to legacy format
        return try JSONDecoder().decode(PuttingRead.self, from: jsonData)
    }
    
    func newShot() {
        capturedImage = nil
        photoAnalysis = nil
        recommendation = nil
        puttingRead = nil
        shotContext = nil
        // Keep draft course/hole if detected; user can clear distance if needed
        draft.distanceYards = nil
        draft.lie = nil
        draft.isOnGreenOverride = nil
        state = .idle
        recomputeConfidence()
    }
    
    // MARK: - Private Helpers
    
    private func buildShotContext(profile: PlayerProfile, locationService: LocationService) async throws -> ShotContext {
        // Location is now optional - use defaults if unavailable
        let location: CLLocationCoordinate2D?
        if let coord = locationService.coordinate {
            location = coord
        } else {
            // Use a default coordinate if location unavailable (will use defaults for weather/elevation)
            location = nil
        }
        
        // Get target coordinate (green center if available, otherwise use location or default)
        var targetCoordinate: CLLocationCoordinate2D
        if let location = location {
            targetCoordinate = location
            
            // Try to get green center if course/hole available
            if let course = draft.course, let holeNumber = draft.holeNumber {
                do {
                    let layoutResponse = try await CourseMapperService.shared.fetchHoleLayout(
                        courseId: course.id,
                        holeNumber: holeNumber
                    )
                    let holeLayout = HoleLayout(from: layoutResponse)
                    if let greenCenter = holeLayout.greenCenter {
                        targetCoordinate = greenCenter
                    }
                } catch {
                    // Use location as fallback
                }
            }
        } else {
            // Default coordinate if no location (will be ignored in context)
            targetCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        
        // Get weather - use defaults if location unavailable
        var weather: WeatherSnapshot
        if let location = location {
            do {
                weather = try await weatherService.fetchWeather(at: location)
            } catch {
                weather = WeatherSnapshot(windMph: 0, windDirDeg: 0, tempF: 70, source: .fallbackStub)
            }
        } else {
            // Default weather when location unavailable
            weather = WeatherSnapshot(windMph: 0, windDirDeg: 0, tempF: 70, source: .unavailable)
        }
        
        // Get elevation delta - use 0 if location unavailable
        var elevationSnapshot = ElevationSnapshot(deltaYards: 0, source: .unavailable)
        if let location = location {
            do {
                elevationSnapshot = try await elevationService.elevationDelta(
                    from: location,
                    to: targetCoordinate
                )
            } catch {
                // Use 0 as fallback
                elevationSnapshot = ElevationSnapshot(deltaYards: 0, source: .fallbackStub)
            }
        }
        
        // Calculate distance - use manual entry or default
        let distance: Double
        if let distanceYards = draft.distanceYards {
            distance = distanceYards
        } else if let location = location {
            let playerLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let targetLocation = CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude)
            distance = playerLocation.distance(from: targetLocation) * 1.09361 // meters to yards
        } else {
            // Default distance when location unavailable
            distance = 150.0
        }
        
        // Use provided location or default coordinate
        let playerCoord = location ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        
        return ShotContext(
            hole: draft.holeNumber ?? 1,
            playerCoordinate: playerCoord,
            targetCoordinate: targetCoordinate,
            distanceToCenter: distance,
            elevationDelta: elevationSnapshot.deltaYards,
            windSpeedMph: weather.windMph,
            windDirectionDeg: weather.windDirDeg,
            temperatureF: weather.tempF,
            weatherSource: weather.source,
            elevationSource: elevationSnapshot.source,
            lieType: draft.lie ?? "Fairway"
        )
    }
    
    private func analyzePhotoViaAPI(image: UIImage) async throws -> ShotPhotoAnalysis {
        // Try existing /photo/analyze endpoint
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "CaddieUnifiedViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image"])
        }
        
        // This would call the existing photo analyze endpoint
        // For now, fallback to vision
        throw NSError(domain: "CaddieUnifiedViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "API endpoint not yet integrated"])
    }
    
    private func analyzePhotoViaVision(image: UIImage) async throws -> ShotPhotoAnalysis {
        let systemPrompt = """
        You are a golf course analysis AI. Analyze this photo and return JSON with:
        - isOnGreen: boolean (true if ball is on putting green)
        - lie: string (one of: "Fairway", "Rough", "Bunker", "Tee", "Green")
        - confidence: number 0-1
        """
        
        let userPrompt = "Analyze this golf photo and return JSON only with isOnGreen, lie, and confidence fields."
        
        let jsonString = try await OpenAIClient.shared.completeWithVision(
            system: systemPrompt,
            user: userPrompt,
            image: image
        )
        
        // Parse JSON response
        let cleanedJSON = stripMarkdownCodeFences(jsonString)
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw NSError(domain: "CaddieUnifiedViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])
        }
        
        let analysis = try JSONDecoder().decode(ShotPhotoAnalysis.self, from: jsonData)
        return analysis
    }
    
    private func generatePuttingReadViaAI(profile: PlayerProfile? = nil) async throws -> PuttingRead {
        // Get historical learning from history (filter for green reads)
        let historicalLearning: PuttHistoricalLearning?
        if let historyStore = historyStore {
            let historyItems = await MainActor.run { historyStore.items }
            let greenReadItems = historyItems.filter { $0.type == .putt }
            historicalLearning = PuttHistoricalLearning(from: greenReadItems, limit: 5)
        } else {
            historicalLearning = nil
        }
        
        // Build player profile data (use provided profile or default)
        let profileToUse = profile ?? PlayerProfile()
        let playerProfileData = PlayerProfileData(from: profileToUse)
        
        // Build prompts using CaddiePromptBuilder
        let (systemPrompt, userPrompt) = CaddiePromptBuilder.shared.buildGreenReaderPrompt(
            courseName: draft.courseName ?? draft.course?.name,
            city: draft.city,
            state: draft.state,
            holeNumber: draft.holeNumber,
            puttDistance: nil,
            playerProfile: playerProfileData,
            historicalLearning: historicalLearning,
            environmentalContext: shotContext
        )
        
        let jsonString = try await OpenAIClient.shared.complete(
            system: systemPrompt,
            user: userPrompt
        )
        
        let cleanedJSON = stripMarkdownCodeFences(jsonString)
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw NSError(domain: "CaddieUnifiedViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])
        }
        
        // Try new structured format first
        if let structured = try? JSONDecoder().decode(StructuredPuttingRead.self, from: jsonData) {
            return PuttingRead(from: structured)
        }
        
        // Fallback to legacy format
        return try JSONDecoder().decode(PuttingRead.self, from: jsonData)
    }
    
    func recomputeConfidence() {
        let hasDistance = draft.distanceYards != nil
        let hasRequiredFields = draft.hasRequiredFields
        let hasPhoto = capturedImage != nil
        
        if hasDistance && hasRequiredFields && hasPhoto {
            confidence = .high
        } else if hasDistance && hasRequiredFields {
            confidence = .medium
        } else {
            confidence = .low
        }
    }
    
    func refreshAutoContext(locationService: LocationService) async {
        // Auto-course selection disabled - user must manually enter course context
        // This method is kept for compatibility but does not auto-select courses
        recomputeConfidence()
    }
}
