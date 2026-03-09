//
//  ShotInputViewModel.swift
//  Caddie.ai
//

import Foundation
import CoreLocation

@MainActor
class ShotInputViewModel: ObservableObject {
    @Published var distance: String = ""
    @Published var hole: Int = 1
    @Published var windSpeed: String = ""
    @Published var windDirection: String = ""
    @Published var temperature: String = ""
    
    func createShotContext(playerLocation: CLLocationCoordinate2D, targetLocation: CLLocationCoordinate2D) -> ShotContext? {
        guard let distanceValue = Double(distance),
              let windSpeedValue = Double(windSpeed),
              let windDirValue = Double(windDirection),
              let tempValue = Double(temperature) else {
            return nil
        }
        
        return ShotContext(
            hole: hole,
            playerCoordinate: playerLocation,
            targetCoordinate: targetLocation,
            distanceToCenter: distanceValue,
            elevationDelta: 0,
            windSpeedMph: windSpeedValue,
            windDirectionDeg: windDirValue,
            temperatureF: tempValue
        )
    }
}

