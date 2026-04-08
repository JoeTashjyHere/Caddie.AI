//
//  LocationSmoothing.swift
//  Caddie.ai
//
//  GPS smoothing for Play Mode: average last N points, ignore unrealistic jumps.
//

import Foundation
import CoreLocation

/// Smooths location updates for Play Mode. Averages last N points; rejects jumps > maxJumpMeters.
@MainActor
class LocationSmoothing: ObservableObject {
    static let defaultBufferSize = 5
    static let defaultMaxJumpMeters = 50.0
    
    @Published private(set) var smoothedCoordinate: CLLocationCoordinate2D?
    
    private var buffer: [CLLocationCoordinate2D] = []
    private let bufferSize: Int
    private let maxJumpMeters: Double
    
    init(bufferSize: Int = 5, maxJumpMeters: Double = 50.0) {
        self.bufferSize = bufferSize
        self.maxJumpMeters = maxJumpMeters
    }
    
    func update(with newCoordinate: CLLocationCoordinate2D) {
        let newLoc = CLLocation(latitude: newCoordinate.latitude, longitude: newCoordinate.longitude)
        
        if let last = buffer.last {
            let lastLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let distance = newLoc.distance(from: lastLoc)
            if distance > maxJumpMeters {
                return
            }
        }
        
        buffer.append(newCoordinate)
        if buffer.count > bufferSize {
            buffer.removeFirst()
        }
        
        let lat = buffer.map(\.latitude).reduce(0, +) / Double(buffer.count)
        let lon = buffer.map(\.longitude).reduce(0, +) / Double(buffer.count)
        smoothedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    func reset() {
        buffer.removeAll()
        smoothedCoordinate = nil
    }
}
