//
//  Course.swift
//  Caddie.ai
//

import Foundation
import CoreLocation

struct Course: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var location: Coordinate?
    var par: Int?
    
    // Backend may send lat/lon directly
    var lat: Double?
    var lon: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, name, par, lat, lon, location
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        par = try container.decodeIfPresent(Int.self, forKey: .par)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lon = try container.decodeIfPresent(Double.self, forKey: .lon)
        location = try container.decodeIfPresent(Coordinate.self, forKey: .location)
        
        // If we have lat/lon but no location, create location from lat/lon
        if let lat = lat, let lon = lon, location == nil {
            location = Coordinate(latitude: lat, longitude: lon)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(par, forKey: .par)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lon, forKey: .lon)
    }
    
    struct Coordinate: Codable, Equatable {
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
    
    init(id: String = UUID().uuidString, name: String, location: Coordinate? = nil, par: Int? = nil, lat: Double? = nil, lon: Double? = nil) {
        self.id = id
        self.name = name
        self.par = par
        self.lat = lat
        self.lon = lon
        
        // If lat/lon provided, create location from them
        if let lat = lat, let lon = lon {
            self.location = Coordinate(latitude: lat, longitude: lon)
        } else {
            self.location = location
        }
    }
}

