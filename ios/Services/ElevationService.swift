//
//  ElevationService.swift
//  Caddie.ai
//

import Foundation
import CoreLocation

struct ElevationSnapshot {
    var deltaYards: Double
    var source: EnvironmentalDataSource
}

class ElevationService {
    static let shared = ElevationService()
    
    private init() {}
    
    func elevationDeltaYards(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> Double {
        let snapshot = try await elevationDelta(from: from, to: to)
        return snapshot.deltaYards
    }

    func elevationDelta(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> ElevationSnapshot {
        let urlString = "https://api.open-meteo.com/v1/elevation?latitude=\(from.latitude),\(to.latitude)&longitude=\(from.longitude),\(to.longitude)"
        guard let url = URL(string: urlString) else {
            return ElevationSnapshot(deltaYards: 0, source: .fallbackStub)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return ElevationSnapshot(deltaYards: 0, source: .fallbackStub)
            }

            let decoded = try JSONDecoder().decode(OpenMeteoElevationResponse.self, from: data)
            if let startMeters = decoded.elevation?.first, let endMeters = decoded.elevation?.last {
                let deltaMeters = endMeters - startMeters
                return ElevationSnapshot(deltaYards: deltaMeters * 1.09361, source: .liveAPI)
            }
        } catch {
            DebugLogging.log("Elevation API fetch failed, using fallback: \(error.localizedDescription)", category: "Environment")
        }

        return ElevationSnapshot(deltaYards: 0, source: .fallbackStub)
    }
}

private struct OpenMeteoElevationResponse: Codable {
    let elevation: [Double]?
}
