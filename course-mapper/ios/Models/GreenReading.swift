//
//  GreenReading.swift
//  Caddie.AI iOS Client
//
//  Green reading request/response models
//

import Foundation

struct GreenReadRequest: Codable {
    let ballLat: Double
    let ballLon: Double
    let holeLat: Double
    let holeLon: Double
    
    enum CodingKeys: String, CodingKey {
        case ballLat = "ball_lat"
        case ballLon = "ball_lon"
        case holeLat = "hole_lat"
        case holeLon = "hole_lon"
    }
}

struct GreenReadResponse: Codable {
    let aimLine: [Coordinate]
    let fallLineFromHole: [Coordinate]?
    let aimOffsetFeet: Double
    let ballSlopePercent: Double
    let holeSlopePercent: Double
    let maxSlopeAlongLine: Double?
    let debugInfo: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case aimLine = "aim_line"
        case fallLineFromHole = "fall_line_from_hole"
        case aimOffsetFeet = "aim_offset_feet"
        case ballSlopePercent = "ball_slope_percent"
        case holeSlopePercent = "hole_slope_percent"
        case maxSlopeAlongLine = "max_slope_along_line"
        case debugInfo = "debug_info"
    }
}

struct Coordinate: Codable {
    let lat: Double
    let lon: Double
    
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

import CoreLocation



