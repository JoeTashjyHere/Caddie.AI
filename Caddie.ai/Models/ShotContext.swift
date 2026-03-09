//
//  ShotContext.swift
//  Caddie.ai
//
//  Created by Joe Tashjy on 11/4/25.
//

import Foundation
import CoreLocation

struct ShotContext: Codable {
    var hole: Int
    var playerCoordinate: Coordinate
    var targetCoordinate: Coordinate?
    var distanceToCenter: Double
    var elevationDelta: Double
    var windSpeedMph: Double
    var windDirectionDeg: Double
    var temperatureF: Double
    var lieType: String
    
    struct Coordinate: Codable {
        var latitude: Double
        var longitude: Double
        
        init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
        
        init(from clLocation: CLLocationCoordinate2D) {
            self.latitude = clLocation.latitude
            self.longitude = clLocation.longitude
        }
        
        var clLocation: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    
    init(hole: Int,
         playerCoordinate: CLLocationCoordinate2D,
         targetCoordinate: CLLocationCoordinate2D? = nil,
         distanceToCenter: Double,
         elevationDelta: Double,
         windSpeedMph: Double,
         windDirectionDeg: Double,
         temperatureF: Double,
         lieType: String = "Fairway") {
        self.hole = hole
        self.playerCoordinate = Coordinate(from: playerCoordinate)
        self.targetCoordinate = targetCoordinate.map { Coordinate(from: $0) }
        self.distanceToCenter = distanceToCenter
        self.elevationDelta = elevationDelta
        self.windSpeedMph = windSpeedMph
        self.windDirectionDeg = windDirectionDeg
        self.temperatureF = temperatureF
        self.lieType = lieType
    }
}

