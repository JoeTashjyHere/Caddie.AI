//
//  HazardEngine.swift
//  Caddie.ai
//
//  Tee-relative hazard computation: evaluates each hazard POI
//  relative to a specific tee coordinate and the green center.
//

import Foundation
import CoreLocation

struct TeeRelativeHazard {
    let type: String
    let locationLabel: String?
    let fairwaySide: String?
    let coordinate: CLLocationCoordinate2D
    let distanceFromTee: Int     // straight-line yards
    let carryDistance: Int        // yards along centerline
    let lateralOffset: Int       // yards left(-)/right(+) of centerline
    let isInPlay: Bool
}

enum HazardEngine {

    /// Evaluate hazards relative to a specific tee and green.
    static func computeHazards(
        tee: CLLocationCoordinate2D,
        green: CLLocationCoordinate2D,
        hazardPois: [HazardPoi],
        holeYardage: Int
    ) -> [TeeRelativeHazard] {
        guard !hazardPois.isEmpty else { return [] }

        let centerBearing = DistanceEngine.bearingDegrees(from: tee, to: green)
        let maxDriveYards: Double = 300
        let minRelevantYards: Double = 50

        return hazardPois.map { h in
            let distYards = DistanceEngine.yards(from: tee, to: h.coordinate)
            let bearingToHazard = DistanceEngine.bearingDegrees(from: tee, to: h.coordinate)
            let angleDiff = (bearingToHazard - centerBearing) * .pi / 180

            let carryYards = distYards * cos(angleDiff)
            let lateralYards = distYards * sin(angleDiff)

            let isInPlay =
                carryYards > minRelevantYards &&
                carryYards < Double(holeYardage) + 30 &&
                carryYards <= maxDriveYards + 50 &&
                abs(lateralYards) < 80

            return TeeRelativeHazard(
                type: h.type,
                locationLabel: h.locationLabel,
                fairwaySide: h.fairwaySide,
                coordinate: h.coordinate,
                distanceFromTee: Int(round(distYards)),
                carryDistance: Int(round(carryYards)),
                lateralOffset: Int(round(lateralYards)),
                isInPlay: isInPlay
            )
        }
    }
}
