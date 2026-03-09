//
//  PlayViewModel.swift
//  Caddie.ai
//
//  View model for the Play tab
//

import Foundation
import CoreLocation

@MainActor
class PlayViewModel: ObservableObject {
    @Published var recommendation: ShotRecommendation?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func getRecommendation(profile: PlayerProfile, location: CLLocationCoordinate2D?) async {
        guard let location = location else {
            errorMessage = "Location not available"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        do {
            // Fetch hole context
            let holeContext = try await CourseService.shared.resolveCourseAndHole(at: location)
            
            // Fetch weather
            let weather = try await WeatherService.shared.fetchWeather(at: location)
            
            // Fetch elevation
            let elevationDelta = try await ElevationService.shared.elevationDeltaYards(
                from: location,
                to: holeContext.centerOfGreen
            )
            
            // Calculate distance to center
            let playerLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let greenLocation = CLLocation(latitude: holeContext.centerOfGreen.latitude, longitude: holeContext.centerOfGreen.longitude)
            let distanceToCenter = playerLocation.distance(from: greenLocation) * 1.09361 // Convert meters to yards
            
            // Build shot context
            let shotContext = ShotContext(
                hole: holeContext.holeNumber,
                playerCoordinate: location,
                targetCoordinate: holeContext.centerOfGreen,
                distanceToCenter: distanceToCenter,
                elevationDelta: elevationDelta,
                windSpeedMph: weather.windMph,
                windDirectionDeg: weather.windDirDeg,
                temperatureF: weather.tempF
            )
            
            // Get recommendation
            let rec = try await RecommenderService.shared.getRecommendation(
                profile: profile,
                context: shotContext,
                hazards: holeContext.hazards
            )
            
            recommendation = rec
        } catch {
            errorMessage = error.localizedDescription
            print("Error getting recommendation: \(error)")
        }
    }
    
    func sendFeedback(success: Bool) {
        // Stub: Store feedback signal for later persistence
        print("Feedback: \(success ? "👍" : "👎")")
        // TODO: Wire to persistence/analytics
    }
}

