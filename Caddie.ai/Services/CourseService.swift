//
//  CourseService.swift
//  Caddie.ai
//
//  Course service stub - returns dummy hole context for now
//

import Foundation
import CoreLocation

struct HoleContext {
    var holeNumber: Int
    var centerOfGreen: CLLocationCoordinate2D
    var hazards: [String]
}

class CourseService {
    static let shared = CourseService()
    
    private init() {}
    
    func resolveCourseAndHole(at coordinate: CLLocationCoordinate2D) async throws -> HoleContext {
        // Stub: Return dummy hole 7 with current location as green
        // In production, this would use course mapping data to determine hole and green location
        try await Task.sleep(nanoseconds: 400_000_000) // Simulate network delay
        
        return HoleContext(
            holeNumber: 7,
            centerOfGreen: coordinate, // For now, use current location as green
            hazards: ["Water left", "Bunker right"]
        )
    }
}

