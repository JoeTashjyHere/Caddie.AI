//
//  HoleDetectionEngine.swift
//  Caddie.ai
//
//  Nearest green-center hole detection (no polygons, no network). Debounced.
//

import Foundation
import CoreLocation

enum HoleDetectionConfidence: String {
    case high
    case medium
    case low
}

@MainActor
final class HoleDetectionEngine: ObservableObject {
    private weak var context: ActiveRoundContext?
    private var lastProcessedAt: Date = .distantPast
    private let debounceSeconds: TimeInterval = 2.5
    private var lastMediumLogHole: Int?

    func bind(_ ctx: ActiveRoundContext) {
        context = ctx
    }

    /// Process GPS update using only cached holes in the active round subset.
    func processLocation(
        _ user: CLLocationCoordinate2D,
        onHighConfidenceSwitch: @escaping (Int) -> Void
    ) {
        guard let ctx = context, ctx.isLoaded else { return }
        let candidates = ctx.activeHolesForDetection
        guard !candidates.isEmpty else { return }

        let now = Date()
        guard now.timeIntervalSince(lastProcessedAt) >= debounceSeconds else { return }
        lastProcessedAt = now

        var bestHole: Int?
        var bestYards = Double.greatestFiniteMagnitude

        for h in candidates {
            guard let g = h.greenCenter else { continue }
            let yds = DistanceEngine.yards(from: user, to: g)
            if yds < bestYards {
                bestYards = yds
                bestHole = h.holeNumber
            }
        }

        guard let nearest = bestHole else { return }

        let conf: HoleDetectionConfidence
        if bestYards < 30 {
            conf = .high
        } else if bestYards < 80 {
            conf = .medium
        } else {
            conf = .low
        }

        switch conf {
        case .high:
            if ctx.applyDetectedHole(nearest) {
                onHighConfidenceSwitch(nearest)
            }
        case .medium:
            if nearest != ctx.currentHole, lastMediumLogHole != nearest {
                lastMediumLogHole = nearest
                print("[HOLE] Detected hole: \(nearest) (confidence: MEDIUM)")
            }
        case .low:
            break
        }
    }
}
