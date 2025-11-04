//
//  WeatherService.swift
//  Caddie.ai
//
//  Weather service stub - returns dummy data for now
//

import Foundation
import CoreLocation

struct WeatherSnapshot {
    var windMph: Double
    var windDirDeg: Double
    var tempF: Double
}

class WeatherService {
    static let shared = WeatherService()
    
    private init() {}
    
    func fetchWeather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        // Stub: Return dummy weather data
        // In production, this would call a weather API
        try await Task.sleep(nanoseconds: 500_000_000) // Simulate network delay
        
        return WeatherSnapshot(
            windMph: 8.0,
            windDirDeg: 180.0, // South wind
            tempF: 72.0
        )
    }
}

