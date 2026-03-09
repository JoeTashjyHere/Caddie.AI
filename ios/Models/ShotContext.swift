//
//  ShotContext.swift
//  Caddie.ai
//

import Foundation
import CoreLocation

struct ShotContext: Codable {
    var hole: Int
    var playerCoordinate: CLLocationCoordinate2D
    var targetCoordinate: CLLocationCoordinate2D
    var distanceToCenter: Double
    var elevationDelta: Double
    var windSpeedMph: Double
    var windDirectionDeg: Double
    var temperatureF: Double
    var weatherSource: EnvironmentalDataSource
    var elevationSource: EnvironmentalDataSource
    var lieType: String
    
    // GPS-based distances from course mapper
    var distanceToGreenCenter: Double?
    var distanceToFront: Double?
    var distanceToBack: Double?
    
    // Hazard detection flags
    var hasWaterLeft: Bool = false
    var hasBunkerRight: Bool = false
    var hasWaterRight: Bool = false
    var hasBunkerLeft: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case hole
        case playerLatitude
        case playerLongitude
        case targetLatitude
        case targetLongitude
        case distanceToCenter
        case elevationDelta
        case windSpeedMph
        case windDirectionDeg
        case temperatureF
        case weatherSource
        case elevationSource
        case lieType
        case distanceToGreenCenter
        case distanceToFront
        case distanceToBack
        case hasWaterLeft
        case hasBunkerRight
        case hasWaterRight
        case hasBunkerLeft
    }
    
    init(hole: Int,
         playerCoordinate: CLLocationCoordinate2D,
         targetCoordinate: CLLocationCoordinate2D,
         distanceToCenter: Double,
         elevationDelta: Double,
         windSpeedMph: Double,
         windDirectionDeg: Double,
         temperatureF: Double,
         weatherSource: EnvironmentalDataSource = .unavailable,
         elevationSource: EnvironmentalDataSource = .unavailable,
         lieType: String = "Fairway",
         distanceToGreenCenter: Double? = nil,
         distanceToFront: Double? = nil,
         distanceToBack: Double? = nil,
         hasWaterLeft: Bool = false,
         hasBunkerRight: Bool = false,
         hasWaterRight: Bool = false,
         hasBunkerLeft: Bool = false) {
        self.hole = hole
        self.playerCoordinate = playerCoordinate
        self.targetCoordinate = targetCoordinate
        self.distanceToCenter = distanceToCenter
        self.elevationDelta = elevationDelta
        self.windSpeedMph = windSpeedMph
        self.windDirectionDeg = windDirectionDeg
        self.temperatureF = temperatureF
        self.weatherSource = weatherSource
        self.elevationSource = elevationSource
        self.lieType = lieType
        self.distanceToGreenCenter = distanceToGreenCenter
        self.distanceToFront = distanceToFront
        self.distanceToBack = distanceToBack
        self.hasWaterLeft = hasWaterLeft
        self.hasBunkerRight = hasBunkerRight
        self.hasWaterRight = hasWaterRight
        self.hasBunkerLeft = hasBunkerLeft
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hole = try container.decode(Int.self, forKey: .hole)
        let playerLat = try container.decode(Double.self, forKey: .playerLatitude)
        let playerLon = try container.decode(Double.self, forKey: .playerLongitude)
        playerCoordinate = CLLocationCoordinate2D(latitude: playerLat, longitude: playerLon)
        let targetLat = try container.decode(Double.self, forKey: .targetLatitude)
        let targetLon = try container.decode(Double.self, forKey: .targetLongitude)
        targetCoordinate = CLLocationCoordinate2D(latitude: targetLat, longitude: targetLon)
        distanceToCenter = try container.decode(Double.self, forKey: .distanceToCenter)
        elevationDelta = try container.decode(Double.self, forKey: .elevationDelta)
        windSpeedMph = try container.decode(Double.self, forKey: .windSpeedMph)
        windDirectionDeg = try container.decode(Double.self, forKey: .windDirectionDeg)
        temperatureF = try container.decode(Double.self, forKey: .temperatureF)
        weatherSource = try container.decodeIfPresent(EnvironmentalDataSource.self, forKey: .weatherSource) ?? .unavailable
        elevationSource = try container.decodeIfPresent(EnvironmentalDataSource.self, forKey: .elevationSource) ?? .unavailable
        lieType = try container.decode(String.self, forKey: .lieType)
        distanceToGreenCenter = try container.decodeIfPresent(Double.self, forKey: .distanceToGreenCenter)
        distanceToFront = try container.decodeIfPresent(Double.self, forKey: .distanceToFront)
        distanceToBack = try container.decodeIfPresent(Double.self, forKey: .distanceToBack)
        hasWaterLeft = try container.decodeIfPresent(Bool.self, forKey: .hasWaterLeft) ?? false
        hasBunkerRight = try container.decodeIfPresent(Bool.self, forKey: .hasBunkerRight) ?? false
        hasWaterRight = try container.decodeIfPresent(Bool.self, forKey: .hasWaterRight) ?? false
        hasBunkerLeft = try container.decodeIfPresent(Bool.self, forKey: .hasBunkerLeft) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hole, forKey: .hole)
        try container.encode(playerCoordinate.latitude, forKey: .playerLatitude)
        try container.encode(playerCoordinate.longitude, forKey: .playerLongitude)
        try container.encode(targetCoordinate.latitude, forKey: .targetLatitude)
        try container.encode(targetCoordinate.longitude, forKey: .targetLongitude)
        try container.encode(distanceToCenter, forKey: .distanceToCenter)
        try container.encode(elevationDelta, forKey: .elevationDelta)
        try container.encode(windSpeedMph, forKey: .windSpeedMph)
        try container.encode(windDirectionDeg, forKey: .windDirectionDeg)
        try container.encode(temperatureF, forKey: .temperatureF)
        try container.encode(weatherSource, forKey: .weatherSource)
        try container.encode(elevationSource, forKey: .elevationSource)
        try container.encode(lieType, forKey: .lieType)
        try container.encodeIfPresent(distanceToGreenCenter, forKey: .distanceToGreenCenter)
        try container.encodeIfPresent(distanceToFront, forKey: .distanceToFront)
        try container.encodeIfPresent(distanceToBack, forKey: .distanceToBack)
        try container.encode(hasWaterLeft, forKey: .hasWaterLeft)
        try container.encode(hasBunkerRight, forKey: .hasBunkerRight)
        try container.encode(hasWaterRight, forKey: .hasWaterRight)
        try container.encode(hasBunkerLeft, forKey: .hasBunkerLeft)
    }
}
