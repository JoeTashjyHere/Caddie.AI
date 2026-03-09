//
//  HoleLayout.swift
//  Caddie.ai
//
//  Models for hole layout data from course-mapper API (GeoJSON)

import Foundation
import CoreLocation
import MapKit

// MARK: - Hole Layout Response

struct HoleLayoutResponse: Codable {
    let greens: [GeoJSONFeature]
    let fairways: [GeoJSONFeature]
    let bunkers: [GeoJSONFeature]
    let water: [GeoJSONFeature]
    let tees: [GeoJSONFeature]
}

// MARK: - GeoJSON Models

struct GeoJSONFeature: Codable {
    let type: String
    let geometry: GeoJSONGeometry
    let properties: [String: String]?
}

struct GeoJSONGeometry: Codable {
    let type: String  // "Point", "Polygon", "MultiPolygon", etc.
    let coordinates: GeoJSONCoordinates
}

// MARK: - GeoJSON Coordinates (handles variable depth)

enum GeoJSONCoordinates: Codable {
    case point([Double])                                    // [lon, lat]
    case lineString([[Double]])                            // [[lon, lat], ...]
    case polygon([[[Double]]])                             // [[[lon, lat], ...], ...] - array of rings (first is exterior)
    case multiPolygon([[[[Double]]]])                      // [[[[lon, lat], ...], ...], ...] - array of polygons
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try point: [Double]
        do {
            let point = try container.decode([Double].self)
            if point.count >= 2 {
                self = .point(point)
                return
            }
        } catch {
            // Not a point, continue
        }
        
        // Try line string: [[Double]]
        do {
            let line = try container.decode([[Double]].self)
            // Check if first element is a point [lon, lat] (2 elements)
            if let first = line.first, first.count == 2 {
                self = .lineString(line)
                return
            }
        } catch {
            // Not a line string, continue
        }
        
        // Try polygon: [[[Double]]] - array of rings
        do {
            let polygon = try container.decode([[[Double]]].self)
            // Check if first ring has at least one point [lon, lat]
            if let firstRing = polygon.first, let firstPoint = firstRing.first, firstPoint.count == 2 {
                self = .polygon(polygon)
                return
            }
        } catch {
            // Not a polygon, continue
        }
        
        // Try multi-polygon: [[[[Double]]]] - array of polygons
        do {
            let multi = try container.decode([[[[Double]]]].self)
            self = .multiPolygon(multi)
            return
        } catch {
            // Not a multi-polygon, continue
        }
        
        // If all else fails, throw error with current container context
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unable to parse GeoJSON coordinates. Expected point, lineString, polygon, or multiPolygon format."
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .point(let coords):
            try container.encode(coords)
        case .polygon(let coords):
            try container.encode(coords)
        case .multiPolygon(let coords):
            try container.encode(coords)
        case .lineString(let coords):
            try container.encode(coords)
        }
    }
}

// MARK: - Hole Layout Helper

struct HoleLayout {
    let greenPolygons: [MKPolygon]
    let fairwayPolygons: [MKPolygon]
    let bunkerPolygons: [MKPolygon]
    let waterPolygons: [MKPolygon]
    let teePolygons: [MKPolygon]
    
    var greenCenter: CLLocationCoordinate2D? {
        calculateCentroid(of: greenPolygons)
    }
    
    var greenFront: CLLocationCoordinate2D? {
        // Find northernmost point of green (closest to tee)
        guard let green = greenPolygons.first else { return nil }
        
        let points = green.points()
        var northernmost: CLLocationCoordinate2D? = nil
        var maxLat: Double = -90
        
        for i in 0..<green.pointCount {
            let coord = points[i].coordinate
            if coord.latitude > maxLat {
                maxLat = coord.latitude
                northernmost = coord
            }
        }
        
        return northernmost ?? greenCenter
    }
    
    var greenBack: CLLocationCoordinate2D? {
        // Find southernmost point of green (farthest from tee)
        guard let green = greenPolygons.first else { return nil }
        
        let points = green.points()
        var southernmost: CLLocationCoordinate2D? = nil
        var minLat: Double = 90
        
        for i in 0..<green.pointCount {
            let coord = points[i].coordinate
            if coord.latitude < minLat {
                minLat = coord.latitude
                southernmost = coord
            }
        }
        
        return southernmost ?? greenCenter
    }
    
    private func calculateCentroid(of polygons: [MKPolygon]) -> CLLocationCoordinate2D? {
        guard let firstPoly = polygons.first else { return nil }
        
        let points = firstPoly.points()
        var totalLat: Double = 0
        var totalLon: Double = 0
        
        for i in 0..<firstPoly.pointCount {
            let point = points[i]
            totalLat += point.coordinate.latitude
            totalLon += point.coordinate.longitude
        }
        
        return CLLocationCoordinate2D(
            latitude: totalLat / Double(firstPoly.pointCount),
            longitude: totalLon / Double(firstPoly.pointCount)
        )
    }
}

extension HoleLayout {
    init(from response: HoleLayoutResponse) {
        self.greenPolygons = response.greens.flatMap { $0.toMKPolygons() }
        self.fairwayPolygons = response.fairways.flatMap { $0.toMKPolygons() }
        self.bunkerPolygons = response.bunkers.flatMap { $0.toMKPolygons() }
        self.waterPolygons = response.water.flatMap { $0.toMKPolygons() }
        self.teePolygons = response.tees.flatMap { $0.toMKPolygons() }
    }
}

extension GeoJSONFeature {
    func toMKPolygons() -> [MKPolygon] {
        var polygons: [MKPolygon] = []
        
        guard geometry.type == "Polygon" || geometry.type == "MultiPolygon" else {
            return polygons
        }
        
        switch geometry.coordinates {
        case .polygon(let rings):
            // rings is [[[Double]]] - array of rings, each ring is [[lon, lat], ...]
            // First ring is exterior, rest are holes
            if let exteriorRing = rings.first, !exteriorRing.isEmpty {
                var points: [MKMapPoint] = []
                
                // Each ring is [[lon, lat], [lon, lat], ...]
                // exteriorRing is [[Double]] where each element is [lon, lat]
                for coordArray in exteriorRing {
                    // coordArray is [Double] representing [lon, lat]
                    if coordArray.count >= 2 {
                        let lat = coordArray[1]
                        let lon = coordArray[0]
                        points.append(MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                    }
                }
                
                if points.count >= 3 {
                    let polygon = MKPolygon(points: points, count: points.count)
                    polygons.append(polygon)
                }
            }
            
        case .multiPolygon(let polygonsArray):
            // polygonsArray is [[[[Double]]]] - array of polygons
            for polygonRings in polygonsArray {
                // polygonRings is [[[Double]]] - array of rings
                if let exteriorRing = polygonRings.first, !exteriorRing.isEmpty {
                    var points: [MKMapPoint] = []
                    
                    // Each ring is [[lon, lat], [lon, lat], ...]
                    // exteriorRing is [[Double]] where each element is [lon, lat]
                    for coordArray in exteriorRing {
                        // coordArray is [Double] representing [lon, lat]
                        if coordArray.count >= 2 {
                            let lat = coordArray[1]
                            let lon = coordArray[0]
                            points.append(MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                        }
                    }
                    
                    if points.count >= 3 {
                        let polygon = MKPolygon(points: points, count: points.count)
                        polygons.append(polygon)
                    }
                }
            }
            
        default:
            break
        }
        
        return polygons
    }
}
