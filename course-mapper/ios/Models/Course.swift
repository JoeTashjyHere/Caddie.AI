//
//  Course.swift
//  Caddie.AI iOS Client
//
//  Course model matching backend API
//

import Foundation
import CoreLocation

struct Course: Codable, Identifiable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let country: String?
    let distanceKm: Double?
    
    // Optional center coordinates
    let centerLat: Double?
    let centerLon: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case city
        case state
        case country
        case distanceKm = "distance_km"
        case centerLat
        case centerLon
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = centerLat, let lon = centerLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}



