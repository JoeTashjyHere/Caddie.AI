//
//  ShotRecommendation.swift
//  Caddie.ai
//

import Foundation

/// Structured caddie output (mandatory JSON block from recommender).
struct CaddieRecommendation: Codable, Equatable {
    var club: String
    var shotType: String
    var aim: String
    var strategy: String
    var confidence: String

    enum CodingKeys: String, CodingKey {
        case club, shotType, aim, strategy, confidence
    }

    init(
        club: String,
        shotType: String,
        aim: String,
        strategy: String,
        confidence: String
    ) {
        self.club = club
        self.shotType = shotType
        self.aim = aim
        self.strategy = strategy
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        club = try c.decodeIfPresent(String.self, forKey: .club) ?? "—"
        shotType = try c.decodeIfPresent(String.self, forKey: .shotType) ?? "—"
        aim = try c.decodeIfPresent(String.self, forKey: .aim) ?? "—"
        strategy = try c.decodeIfPresent(String.self, forKey: .strategy) ?? "—"
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence) ?? "Medium"
    }
}

/// New structured output format from AI (matches the prompt builder output format)
struct StructuredShotRecommendation: Codable {
    // Legacy keys (optional for new schema compatibility)
    let clubRecommendation: String?
    let shotShape: String?
    let targetLine: String?
    let idealCarryYards: Int?
    let idealTotalYards: Int?
    let caddieReasoning: String?
    let missStrategy: String?
    let confidenceCue: String?
    
    // New optional fields for varied, punchy recommendations
    let headline: String?
    let bullets: [String]?
    let commitCue: String?
    
    // New schema (club, aimOffsetYards, confidence)
    let club: String?
    let aimOffsetYards: Double?
    let confidence: Double?

    /// Nested `caddie` object from recommender JSON (club, shotType, aim, strategy, confidence).
    let caddie: CaddieRecommendation?
    
    // Legacy fields for backward compatibility (optional)
    let shotPlan: String?
    let missToPlayFor: String?
    let confidenceNote: String?
    let tacticalTips: [String]?
    
    /// Effective club (new "club" key or legacy "clubRecommendation")
    var effectiveClub: String {
        club ?? clubRecommendation ?? ""
    }
    
    /// Effective confidence (new or default)
    var effectiveConfidence: Double {
        confidence ?? 0.85
    }
    
    /// Effective aim offset (new or default)
    var effectiveAimOffsetYards: Double {
        aimOffsetYards ?? 0.0
    }

    /// Shot shape from JSON or sensible default for display and club normalization.
    var effectiveShotShape: String {
        let t = shotShape?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Straight" : t
    }
}

/// Legacy format for backward compatibility and UI display
struct ShotRecommendation: Codable, Identifiable {
    var id: UUID
    var club: String
    var aimOffsetYards: Double
    var shotShape: String
    var narrative: String
    var confidence: Double
    var avoidZones: [String]
    
    // New structured fields for varied recommendations
    var headline: String?
    var bullets: [String] = []
    var commitCue: String?
    
    // New structured fields (optional for backward compatibility)
    var shotPlan: String?
    var targetLine: String?
    var missToPlayFor: String?
    var confidenceNote: String?
    var tacticalTips: [String]?

    /// Populated when AI returns the `caddie` JSON block.
    var caddieStructured: CaddieRecommendation?
    
    init(id: UUID = UUID(),
         club: String,
         aimOffsetYards: Double = 0.0,
         shotShape: String = "Straight",
         narrative: String,
         confidence: Double = 0.85,
         avoidZones: [String] = [],
         headline: String? = nil,
         bullets: [String] = [],
         commitCue: String? = nil,
         shotPlan: String? = nil,
         targetLine: String? = nil,
         missToPlayFor: String? = nil,
         confidenceNote: String? = nil,
         tacticalTips: [String]? = nil,
         caddieStructured: CaddieRecommendation? = nil) {
        self.id = id
        self.club = club
        self.aimOffsetYards = aimOffsetYards
        self.shotShape = shotShape
        self.narrative = narrative
        self.confidence = confidence
        self.avoidZones = avoidZones
        self.headline = headline
        self.bullets = bullets
        self.commitCue = commitCue
        self.shotPlan = shotPlan
        self.targetLine = targetLine
        self.missToPlayFor = missToPlayFor
        self.confidenceNote = confidenceNote
        self.tacticalTips = tacticalTips
        self.caddieStructured = caddieStructured
    }
    
    /// Convert from new structured format
    init(from structured: StructuredShotRecommendation) {
        self.id = UUID()
        self.narrative = ""
        if let c = structured.caddie {
            self.caddieStructured = c
            self.club = c.club.isEmpty ? structured.effectiveClub : c.club
            self.shotShape = structured.effectiveShotShape
            self.confidence = Self.confidenceNumeric(from: c.confidence, fallback: structured.effectiveConfidence)
            self.narrative = [
                "\(c.club) — \(c.shotType)",
                "Aim: \(c.aim)",
                "Strategy: \(c.strategy)",
                "Confidence: \(c.confidence)"
            ].joined(separator: "\n")
        } else {
            self.caddieStructured = nil
            self.club = structured.effectiveClub
            self.shotShape = structured.effectiveShotShape
            self.confidence = structured.effectiveConfidence
        }
        self.aimOffsetYards = structured.effectiveAimOffsetYards
        
        // Store new optional fields when present
        self.headline = structured.headline
        self.bullets = structured.bullets ?? []
        self.commitCue = structured.commitCue ?? structured.confidenceCue
        
        // Build narrative when no nested caddie block
        if structured.caddie == nil, let headline = structured.headline, !headline.isEmpty {
            var narrativeParts: [String] = [headline]
            if let bullets = structured.bullets, !bullets.isEmpty {
                narrativeParts.append(contentsOf: bullets)
            }
            if let cue = structured.commitCue ?? structured.confidenceCue, !cue.isEmpty {
                narrativeParts.append("")
                narrativeParts.append(cue)
            }
            self.narrative = narrativeParts.joined(separator: "\n")
        } else if structured.caddie == nil, let reasoning = structured.caddieReasoning, !reasoning.isEmpty {
            // Fallback to legacy narrative format
            var narrativeParts: [String] = []
            narrativeParts.append("Club: \(structured.effectiveClub)")
            if let carry = structured.idealCarryYards, let total = structured.idealTotalYards {
                narrativeParts.append("Ideal: \(carry) yards carry, \(total) yards total")
            }
            if let target = structured.targetLine {
                narrativeParts.append("Target: \(target)")
            }
            narrativeParts.append("")
            narrativeParts.append("Caddie's Take: \(reasoning)")
            if let miss = structured.missStrategy {
                narrativeParts.append("")
                narrativeParts.append("Miss Strategy: \(miss)")
            }
            if let cue = structured.confidenceCue {
                narrativeParts.append("")
                narrativeParts.append(cue)
            }
            self.narrative = narrativeParts.joined(separator: "\n")
        } else if structured.caddie == nil {
            self.narrative = "\(structured.effectiveClub) – \(structured.effectiveShotShape)"
        }
        
        self.avoidZones = []
        self.shotPlan = structured.shotPlan ?? structured.caddieReasoning
        self.targetLine = structured.targetLine
        self.missToPlayFor = structured.missToPlayFor ?? structured.missStrategy
        self.confidenceNote = structured.confidenceNote ?? structured.confidenceCue
        self.tacticalTips = structured.tacticalTips
    }

    private static func confidenceNumeric(from band: String, fallback: Double) -> Double {
        switch band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return 0.9
        case "medium": return 0.65
        case "low": return 0.45
        default: return fallback
        }
    }
}

