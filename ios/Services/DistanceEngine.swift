//
//  DistanceEngine.swift
//  Caddie.ai
//
//  Haversine-based distance calculations for Play Mode.
//

import Foundation
import CoreLocation

enum DistanceEngine {
    private static let metersToYards = 1.09361
    
    /// Haversine distance in meters
    static func haversineMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLoc = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLoc.distance(from: toLoc)
    }
    
    /// Distance in yards (for display)
    static func yards(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        haversineMeters(from: from, to: to) * metersToYards
    }
    
    /// Distance to green center
    static func distanceToGreen(
        userPosition: CLLocationCoordinate2D,
        greenCenter: CLLocationCoordinate2D?
    ) -> Double? {
        guard let center = greenCenter else { return nil }
        return yards(from: userPosition, to: center)
    }
    
    /// Front of green distance
    static func distanceToFront(
        userPosition: CLLocationCoordinate2D,
        greenFront: CLLocationCoordinate2D?
    ) -> Double? {
        guard let front = greenFront else { return nil }
        return yards(from: userPosition, to: front)
    }
    
    /// Back of green distance
    static func distanceToBack(
        userPosition: CLLocationCoordinate2D,
        greenBack: CLLocationCoordinate2D?
    ) -> Double? {
        guard let back = greenBack else { return nil }
        return yards(from: userPosition, to: back)
    }

    /// Round engine: yards to green center only (front/back reserved for future POI data).
    static func distanceSnapshotToGreenCenter(
        user: CLLocationCoordinate2D?,
        greenCenter: CLLocationCoordinate2D?
    ) -> DistanceSnapshot? {
        guard let u = user, let g = greenCenter else { return nil }
        let c = yards(from: u, to: g)
        return DistanceSnapshot(front: nil, center: c, back: nil)
    }
}
