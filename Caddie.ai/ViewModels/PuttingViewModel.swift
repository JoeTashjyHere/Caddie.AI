//
//  PuttingViewModel.swift
//  Caddie.ai
//
//  View model for the Putting tab
//

import Foundation
import UIKit
import CoreLocation

@MainActor
class PuttingViewModel: ObservableObject {
    @Published var result: PuttingRead?
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    
    func analyze(image: UIImage, location: CLLocationCoordinate2D?) async {
        isAnalyzing = true
        errorMessage = nil
        
        defer {
            isAnalyzing = false
        }
        
        do {
            // Fetch weather for context
            let weather: WeatherSnapshot
            if let location = location {
                weather = try await WeatherService.shared.fetchWeather(at: location)
            } else {
                // Use default weather if location unavailable
                weather = WeatherSnapshot(windMph: 0, windDirDeg: 0, tempF: 72)
            }
            
            // Analyze putting
            let puttingRead = try await PuttingVisionService.shared.analyzePutting(
                image: image,
                weather: weather
            )
            
            result = puttingRead
        } catch {
            errorMessage = error.localizedDescription
            print("Error analyzing putting: \(error)")
        }
    }
}

