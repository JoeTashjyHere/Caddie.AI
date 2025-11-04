//
//  ElevationService.swift
//  Caddie.ai
//
//  Elevation service stub - returns dummy elevation delta for now
//

import Foundation
import CoreLocation

class ElevationService {
    static let shared = ElevationService()
    
    private init() {}
    
    func elevationDeltaYards(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> Double {
        // Stub: Return dummy elevation delta
        // In production, this would calculate elevation difference using terrain data
        try await Task.sleep(nanoseconds: 300_000_000) // Simulate network delay
        
        return 5.0 // 5 yards uphill
    }
}

