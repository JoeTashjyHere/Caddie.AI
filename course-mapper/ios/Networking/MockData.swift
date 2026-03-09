//
//  MockData.swift
//  Caddie.AI iOS Client
//
//  Mock data for previews and development
//

import Foundation

enum MockData {
    static let nearbyCourses: [Course] = [
        Course(
            id: "1",
            name: "East Potomac Golf Links",
            city: "Washington",
            state: "DC",
            country: "USA",
            distanceKm: 2.5,
            centerLat: 38.8706,
            centerLon: -77.0294
        ),
        Course(
            id: "2",
            name: "Pebble Beach Golf Links",
            city: "Pebble Beach",
            state: "CA",
            country: "USA",
            distanceKm: 5.2,
            centerLat: 36.568,
            centerLon: -121.95
        )
    ]
    
    static let courseFeatures: [CourseFeature] = [
        CourseFeature(
            id: 1,
            courseId: 1,
            featureType: .green,
            holeNumber: 1,
            geometry: GeoJSONFeature(
                type: "Feature",
                geometry: GeoJSONGeometry(
                    type: "Polygon",
                    coordinates: .polygon([[
                        [-77.0294, 38.8706],
                        [-77.0293, 38.8706],
                        [-77.0293, 38.8705],
                        [-77.0294, 38.8705],
                        [-77.0294, 38.8706]
                    ]])
                ),
                properties: ["feature_type": "green", "hole_number": "1"]
            )
        )
    ]
    
    static func createGreenReadResponse(ballLat: Double, ballLon: Double, holeLat: Double, holeLon: Double) -> GreenReadResponse {
        // Generate a curved aim line based on actual ball/hole positions
        var aimLine: [Coordinate] = []
        let steps = 20
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            // Simple curve (breaks right)
            let lat = ballLat + (holeLat - ballLat) * t
            let lon = ballLon + (holeLon - ballLon) * t + 0.00001 * sin(t * .pi)
            aimLine.append(Coordinate(lat: lat, lon: lon))
        }
        
        // Generate fall line from hole
        var fallLine: [Coordinate] = []
        for i in 0..<15 {
            let lat = holeLat - Double(i) * 0.00001
            let lon = holeLon - Double(i) * 0.000005
            fallLine.append(Coordinate(lat: lat, lon: lon))
        }
        
        return GreenReadResponse(
            aimLine: aimLine,
            fallLineFromHole: fallLine,
            aimOffsetFeet: 2.5,
            ballSlopePercent: 1.2,
            holeSlopePercent: 0.8,
            maxSlopeAlongLine: 2.1,
            debugInfo: nil
        )
    }
    
    // Legacy static property for backward compatibility
    static let greenReadResponse: GreenReadResponse = createGreenReadResponse(
        ballLat: 38.8706,
        ballLon: -77.0294,
        holeLat: 38.87061,
        holeLon: -77.02939
    )
}

