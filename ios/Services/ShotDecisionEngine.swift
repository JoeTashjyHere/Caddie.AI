//
//  ShotDecisionEngine.swift
//  Caddie.ai
//
//  Deterministic decision layer. Generates a structured shot recommendation
//  BEFORE calling the LLM. All club selection, target logic, and miss guidance
//  are computed here using player bag data, hazards, wind, and elevation.

import Foundation
import CoreLocation

// MARK: - Decision Output

struct ShotDecision: Codable {
    let club: String
    let swing: String
    let effectiveDistance: Int
    let rawDistance: Int
    let target: String
    let primaryRisk: String?
    let secondaryRisk: String?
    let missGuidance: String
    let aggression: Aggression
    let confidence: Confidence
    let priority: ShotPriority
    let riskLevel: RiskLevel

    enum Aggression: String, Codable {
        case aggressive, neutral, conservative
    }

    enum Confidence: String, Codable {
        case high, medium, low
    }

    enum ShotPriority: String, Codable {
        case hazardAvoidance
        case targetPrecision
        case simpleExecution
    }

    enum RiskLevel: String, Codable {
        case low, medium, high
    }

    /// Deterministic fallback text when LLM fails.
    /// PRIORITY controls ordering, RISK controls tone.
    var fallbackText: String {
        var parts: [String] = []

        switch priority {
        case .hazardAvoidance:
            parts.append("\(swing.capitalized) \(club).")
            if !missGuidance.isEmpty { parts.append(missGuidance) }
            parts.append("\(target.prefix(1).uppercased() + target.dropFirst()).")
        case .targetPrecision:
            parts.append("\(swing.capitalized) \(club).")
            parts.append("\(target.prefix(1).uppercased() + target.dropFirst()).")
            if !missGuidance.isEmpty { parts.append(missGuidance) }
        case .simpleExecution:
            if riskLevel == .low {
                parts.append("Good number for a \(swing) \(club).")
                parts.append("\(target.prefix(1).uppercased() + target.dropFirst()).")
            } else {
                parts.append("\(swing.capitalized) \(club).")
                parts.append("\(target.prefix(1).uppercased() + target.dropFirst()).")
            }
        }

        if confidence == .high && riskLevel != .low {
            let commits = ["Commit to it.", "Trust it.", "That's your number."]
            parts.append(commits.randomElement() ?? commits[0])
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Engine

enum ShotDecisionEngine {

    // MARK: - Public API

    static func decide(
        distanceYards: Double,
        lie: String,
        hazards: [String],
        holePar: Int?,
        holeHandicap: Int?,
        wind: WindInput?,
        elevation: ElevationInput?,
        bag: [ClubDistance],
        playerMissLeftPct: Double,
        playerMissRightPct: Double,
        shotBearing: Double?
    ) -> ShotDecision {
        let raw = Int(distanceYards.rounded())
        let effective = computeEffectiveDistance(
            raw: distanceYards,
            lie: lie,
            wind: wind,
            elevation: elevation,
            shotBearing: shotBearing
        )
        let parsed = parseHazards(hazards)
        let selectedClub = selectClub(
            effectiveDistance: effective,
            lie: lie,
            bag: bag,
            hazards: parsed
        )
        let target = computeTarget(
            hazards: parsed,
            playerMissLeftPct: playerMissLeftPct,
            playerMissRightPct: playerMissRightPct
        )
        let miss = computeMissGuidance(
            hazards: parsed,
            playerMissLeftPct: playerMissLeftPct,
            playerMissRightPct: playerMissRightPct
        )
        let swing = computeSwing(
            club: selectedClub,
            effectiveDistance: effective,
            wind: wind
        )
        let aggression = computeAggression(
            hazards: parsed,
            lie: lie,
            clubMatchGap: abs(selectedClub.carryYards - effective)
        )
        let confidence = computeConfidence(
            club: selectedClub,
            clubMatchGap: abs(selectedClub.carryYards - effective),
            lie: lie,
            hazards: parsed
        )

        let priority = computePriority(hazards: parsed)
        let riskLevel = computeRiskLevel(hazards: parsed)

        return ShotDecision(
            club: selectedClub.name,
            swing: swing,
            effectiveDistance: effective,
            rawDistance: raw,
            target: target,
            primaryRisk: parsed.primary?.description,
            secondaryRisk: parsed.secondary?.description,
            missGuidance: miss,
            aggression: aggression,
            confidence: confidence,
            priority: priority,
            riskLevel: riskLevel
        )
    }

    // MARK: - Step 1: Effective Distance

    struct WindInput {
        let speedMph: Double
        let directionDeg: Double
        let source: EnvironmentalDataSource
    }

    struct ElevationInput {
        let deltaYards: Double
        let source: EnvironmentalDataSource
    }

    private static func computeEffectiveDistance(
        raw: Double,
        lie: String,
        wind: WindInput?,
        elevation: ElevationInput?,
        shotBearing: Double?
    ) -> Int {
        var adjusted = raw

        if let wind = wind, wind.source == .liveAPI, wind.speedMph > 2 {
            let bearing = shotBearing ?? 0
            let delta = (wind.directionDeg - bearing) * .pi / 180
            let headComponent = cos(delta)
            let windEffect = headComponent * wind.speedMph * 0.8
            adjusted += windEffect
        }

        if let elev = elevation, elev.source == .liveAPI {
            adjusted += elev.deltaYards
        }

        let normalizedLie = lie.lowercased()
        if normalizedLie.contains("rough") || normalizedLie.contains("thick") {
            adjusted += 5
        } else if normalizedLie.contains("flyer") {
            adjusted -= 5
        } else if normalizedLie.contains("bunker") || normalizedLie.contains("sand") {
            adjusted += 8
        } else if normalizedLie.contains("pine") || normalizedLie.contains("straw") || normalizedLie.contains("needles") {
            adjusted += 3
        }

        return max(1, Int(adjusted.rounded()))
    }

    // MARK: - Step 2: Club Selection

    private static func selectClub(
        effectiveDistance: Int,
        lie: String,
        bag: [ClubDistance],
        hazards: ParsedHazards
    ) -> ClubDistance {
        let normalizedLie = lie.lowercased()
        let viable = bag.filter { club in
            if normalizedLie.contains("bunker") || normalizedLie.contains("sand") {
                let wedgeTypes: Set<String> = ["sandwedge", "lobwedge", "gapwedge", "pitchingwedge", "iron9", "iron8"]
                return wedgeTypes.contains(club.clubTypeId.lowercased().replacingOccurrences(of: "_", with: ""))
                    || wedgeTypes.contains(club.clubType.rawValue.lowercased())
            }
            if normalizedLie.contains("deep rough") || normalizedLie.contains("woods") {
                if club.clubType == .driver { return false }
            }
            if club.confidenceLevel == .avoidAtAllCosts { return false }
            return true
        }

        let pool = viable.isEmpty ? bag : viable

        var scored = pool.map { club -> (club: ClubDistance, score: Double) in
            let gap = abs(club.carryYards - effectiveDistance)
            var score = Double(gap)

            switch club.confidenceLevel {
            case .veryConfident: score -= 4
            case .confident: score -= 0
            case .neutral: score += 6
            case .notConfident: score += 14
            case .avoidAtAllCosts: score += 50
            }

            return (club, score)
        }.sorted { $0.score < $1.score }

        guard let best = scored.first else {
            return bag.first ?? ClubDistance(id: UUID(), name: "7 Iron", carryYards: 155)
        }

        if hazards.shortIsDangerous, best.club.carryYards < effectiveDistance {
            if let longerClub = scored.first(where: { $0.club.carryYards >= effectiveDistance }) {
                return longerClub.club
            }
        }
        if hazards.longIsDangerous, best.club.carryYards > effectiveDistance + 10 {
            if let shorterClub = scored.first(where: { $0.club.carryYards <= effectiveDistance + 5 && $0.club.carryYards >= effectiveDistance - 10 }) {
                return shorterClub.club
            }
        }

        return best.club
    }

    // MARK: - Step 3: Target Logic

    private static func computeTarget(
        hazards: ParsedHazards,
        playerMissLeftPct: Double,
        playerMissRightPct: Double
    ) -> String {
        if hazards.rightSide && hazards.leftSide {
            return pick(["middle of the green", "center of the green", "fat part of the green"])
        }
        if hazards.rightSide {
            return pick(["left-center of the green", "left-center", "left side of the green"])
        }
        if hazards.leftSide {
            return pick(["right-center of the green", "right-center", "right side of the green"])
        }
        if hazards.shortIsDangerous {
            return "back-center of the green"
        }
        if hazards.longIsDangerous {
            return "front-center of the green"
        }

        if playerMissRightPct > playerMissLeftPct + 15 {
            return "left-center of the green"
        }
        if playerMissLeftPct > playerMissRightPct + 15 {
            return "right-center of the green"
        }

        return pick(["center of the green", "middle of the green", "fat part of the green"])
    }

    // MARK: - Step 4: Miss Guidance

    private static func computeMissGuidance(
        hazards: ParsedHazards,
        playerMissLeftPct: Double,
        playerMissRightPct: Double
    ) -> String {
        let dead = hazards.deathSide

        if hazards.rightSide && hazards.leftSide {
            if dead != nil {
                return pick([
                    "Trouble both sides. Do NOT miss \(dead!).",
                    "Danger both sides. Cannot go \(dead!)."
                ])
            }
            return "Trouble both sides. Hit the center."
        }

        if let dead = dead {
            switch dead {
            case "right": return pick(["Do NOT miss right. Right is dead.", "Cannot go right. That miss is gone.", "Miss left. Right is dead."])
            case "left": return pick(["Do NOT miss left. Left is dead.", "Cannot go left. That miss is gone.", "Miss right. Left is dead."])
            case "short": return pick(["Do NOT be short. Short is dead.", "Make sure you carry it. Short is gone."])
            case "long": return pick(["Do NOT go long. Long is dead.", "Stay short. Long is gone."])
            default: break
            }
        }

        if hazards.rightSide {
            return pick(["Miss left. Right is trouble.", "Favor the left side."])
        }
        if hazards.leftSide {
            return pick(["Miss right. Left is trouble.", "Favor the right side."])
        }
        if hazards.shortIsDangerous {
            return "Do NOT be short."
        }
        if hazards.longIsDangerous {
            return "Short is fine. Long is trouble."
        }

        return pick(["No major trouble. Middle of the green.", "Middle is fine.", "Green light. Center of the green."])
    }

    private static func pick(_ options: [String]) -> String {
        options.randomElement() ?? options[0]
    }

    // MARK: - Step 5: Swing + Aggression + Confidence

    private static func computeSwing(
        club: ClubDistance,
        effectiveDistance: Int,
        wind: WindInput?
    ) -> String {
        let gap = club.carryYards - effectiveDistance
        let hasHeadwind = (wind?.speedMph ?? 0) > 8

        if gap >= 8 {
            return "smooth"
        }
        if gap <= -5 || hasHeadwind {
            return "full"
        }
        if abs(gap) <= 3 {
            return "stock"
        }
        return "controlled"
    }

    private static func computeAggression(
        hazards: ParsedHazards,
        lie: String,
        clubMatchGap: Int
    ) -> ShotDecision.Aggression {
        let lowerLie = lie.lowercased()
        let badLie = lowerLie.contains("rough") || lowerLie.contains("bunker") || lowerLie.contains("sand")

        if hazards.hasSevere || (badLie && hazards.hasAny) {
            return .conservative
        }
        if !hazards.hasAny && !badLie && clubMatchGap <= 5 {
            return .aggressive
        }
        return .neutral
    }

    private static func computeConfidence(
        club: ClubDistance,
        clubMatchGap: Int,
        lie: String,
        hazards: ParsedHazards
    ) -> ShotDecision.Confidence {
        var score = 0

        switch club.confidenceLevel {
        case .veryConfident: score += 3
        case .confident: score += 2
        case .neutral: score += 1
        case .notConfident: score -= 1
        case .avoidAtAllCosts: score -= 3
        }

        if clubMatchGap <= 5 { score += 2 }
        else if clubMatchGap <= 12 { score += 1 }
        else { score -= 1 }

        if lie.lowercased().contains("fairway") || lie.lowercased().contains("tee") { score += 1 }
        if lie.lowercased().contains("rough") { score -= 1 }
        if lie.lowercased().contains("bunker") { score -= 2 }

        if hazards.hasSevere { score -= 1 }

        if score >= 5 { return .high }
        if score >= 2 { return .medium }
        return .low
    }

    // MARK: - Step 6: Priority + Risk

    private static func computePriority(hazards: ParsedHazards) -> ShotDecision.ShotPriority {
        if hazards.hasSevere {
            return .hazardAvoidance
        }
        if hazards.hasGreenSide || hazards.hasLandingZone {
            return .hazardAvoidance
        }
        if hazards.hasAny {
            return .targetPrecision
        }
        return .simpleExecution
    }

    private static func computeRiskLevel(hazards: ParsedHazards) -> ShotDecision.RiskLevel {
        if hazards.hasSevere {
            return .high
        }
        if hazards.hasGreenSide || hazards.hasLandingZone {
            return .medium
        }
        if hazards.hasAny {
            return .medium
        }
        return .low
    }

    // MARK: - Hazard Parsing

    struct ParsedHazards {
        let rightSide: Bool
        let leftSide: Bool
        let shortIsDangerous: Bool
        let longIsDangerous: Bool
        let hasSevere: Bool
        let hasGreenSide: Bool
        let hasLandingZone: Bool
        let hasAny: Bool
        let raw: [String]

        var primary: HazardSide? {
            if hasSevere {
                if rightSide { return .right }
                if leftSide { return .left }
                if shortIsDangerous { return .short }
                if longIsDangerous { return .long }
            }
            if rightSide { return .right }
            if leftSide { return .left }
            return nil
        }

        var secondary: HazardSide? {
            guard primary != nil else { return nil }
            if primary != .left && leftSide { return .left }
            if primary != .right && rightSide { return .right }
            if primary != .short && shortIsDangerous { return .short }
            if primary != .long && longIsDangerous { return .long }
            return nil
        }

        var deathSide: String? {
            let lower = raw.map { $0.lowercased() }
            let hasWater = lower.contains { $0.contains("water") }
            let hasOB = lower.contains { $0.contains("ob") || $0.contains("out of bounds") }
            guard hasWater || hasOB else { return nil }
            for h in lower {
                if (h.contains("water") || h.contains("ob")) {
                    if h.contains("right") { return "right" }
                    if h.contains("left") { return "left" }
                    if h.contains("short") || h.contains("front") { return "short" }
                    if h.contains("long") || h.contains("back") { return "long" }
                }
            }
            return nil
        }

        enum HazardSide: CustomStringConvertible {
            case right, left, short, long
            var description: String {
                switch self {
                case .right: return "right side"
                case .left: return "left side"
                case .short: return "short"
                case .long: return "long"
                }
            }
        }
    }

    private static func parseHazards(_ hazards: [String]) -> ParsedHazards {
        let lower = hazards.map { $0.lowercased() }
        let rightSide = lower.contains { $0.contains("right") }
        let leftSide = lower.contains { $0.contains("left") }
        let shortDanger = lower.contains { $0.contains("water") && ($0.contains("short") || $0.contains("front")) }
        let longDanger = lower.contains { ($0.contains("long") || $0.contains("back")) && ($0.contains("bunker") || $0.contains("ob") || $0.contains("water")) }
        let severe = lower.contains { $0.contains("water") || $0.contains("ob") || $0.contains("out of bounds") }

        let greenSide = lower.contains { h in
            let isBunkerOrHazard = h.contains("bunker") || h.contains("sand") || h.contains("water")
            let nearGreen = h.contains("green") || h.contains("front") || h.contains("back") || h.contains("pin")
            return isBunkerOrHazard && nearGreen
        }
        let landingZone = lower.contains { h in
            h.contains("fairway") || h.contains("landing") || h.contains("cross")
        }

        return ParsedHazards(
            rightSide: rightSide,
            leftSide: leftSide,
            shortIsDangerous: shortDanger,
            longIsDangerous: longDanger,
            hasSevere: severe,
            hasGreenSide: greenSide,
            hasLandingZone: landingZone,
            hasAny: !hazards.isEmpty,
            raw: hazards
        )
    }
}
