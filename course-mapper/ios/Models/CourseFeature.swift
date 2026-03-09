//
//  CourseFeature.swift
//  Caddie.AI iOS Client
//
//  Course feature model (greens, fairways, bunkers, etc.)
//

import Foundation
import CoreLocation

struct CourseFeature: Codable, Identifiable {
    let id: Int
    let courseId: Int
    let featureType: FeatureType
    let holeNumber: Int?
    let geometry: GeoJSONFeature
    
    enum CodingKeys: String, CodingKey {
        case id
        case courseId = "course_id"
        case featureType = "feature_type"
        case holeNumber = "hole_number"
        case geometry
    }
    
    enum FeatureType: String, Codable {
        case green
        case fairway
        case bunker
        case water
        case rough
        case teeBox = "tee_box"
    }
    
    // Simplified bounds for visualization
    var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        geometry.bounds
    }
}

// MARK: - GeoJSON Models

struct GeoJSONFeature: Codable {
    let type: String
    let geometry: GeoJSONGeometry
    let properties: [String: String]?
    
    var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        geometry.bounds
    }
}

struct GeoJSONGeometry: Codable {
    let type: String
    let coordinates: GeoJSONCoordinates
    
    var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        coordinates.bounds
    }
}

enum GeoJSONCoordinates: Codable {
    case point([Double])
    case multiPoint([[Double]])
    case lineString([[Double]])
    case multiLineString([[[Double]]])
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try different coordinate structures
        if let point = try? container.decode([Double].self), point.count >= 2 {
            self = .point(point)
            return
        }
        if let multiPoint = try? container.decode([[Double]].self) {
            self = .multiPoint(multiPoint)
            return
        }
        if let lineString = try? container.decode([[Double]].self) {
            self = .lineString(lineString)
            return
        }
        if let multiLineString = try? container.decode([[[Double]]].self) {
            self = .multiLineString(multiLineString)
            return
        }
        if let polygon = try? container.decode([[[Double]]].self) {
            self = .polygon(polygon)
            return
        }
        if let multiPolygon = try? container.decode([[[[Double]]]].self) {
            self = .multiPolygon(multiPolygon)
            return
        }
        
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unable to decode GeoJSON coordinates"
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .point(let coords):
            try container.encode(coords)
        case .multiPoint(let coords):
            try container.encode(coords)
        case .lineString(let coords):
            try container.encode(coords)
        case .multiLineString(let coords):
            try container.encode(coords)
        case .polygon(let coords):
            try container.encode(coords)
        case .multiPolygon(let coords):
            try container.encode(coords)
        }
    }
    
    var bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        var allLons: [Double] = []
        var allLats: [Double] = []
        
        func extractCoordinates(_ value: Any) {
            if let point = value as? [Double], point.count >= 2 {
                allLons.append(point[0])
                allLats.append(point[1])
            } else if let array = value as? [Any] {
                for item in array {
                    extractCoordinates(item)
                }
            }
        }
        
        switch self {
        case .point(let coords):
            if coords.count >= 2 {
                allLons.append(coords[0])
                allLats.append(coords[1])
            }
        case .multiPoint(let coords):
            for point in coords where point.count >= 2 {
                allLons.append(point[0])
                allLats.append(point[1])
            }
        case .lineString(let coords):
            for point in coords where point.count >= 2 {
                allLons.append(point[0])
                allLats.append(point[1])
            }
        case .multiLineString(let coords):
            for line in coords {
                for point in line where point.count >= 2 {
                    allLons.append(point[0])
                    allLats.append(point[1])
                }
            }
        case .polygon(let coords):
            for ring in coords {
                for point in ring where point.count >= 2 {
                    allLons.append(point[0])
                    allLats.append(point[1])
                }
            }
        case .multiPolygon(let coords):
            for polygon in coords {
                for ring in polygon {
                    for point in ring where point.count >= 2 {
                        allLons.append(point[0])
                        allLats.append(point[1])
                    }
                }
            }
        }
        
        guard !allLats.isEmpty, !allLons.isEmpty else { return nil }
        
        return (
            minLat: allLats.min()!,
            maxLat: allLats.max()!,
            minLon: allLons.min()!,
            maxLon: allLons.max()!
        )
    }
}



