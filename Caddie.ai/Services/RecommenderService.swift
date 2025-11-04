//
//  RecommenderService.swift
//  Caddie.ai
//
//  Service that assembles prompt and calls OpenAIClient for shot recommendations
//

import Foundation

class RecommenderService {
    static let shared = RecommenderService()
    
    private init() {}
    
    func getRecommendation(profile: PlayerProfile, context: ShotContext, hazards: [String]) async throws -> ShotRecommendation {
        // Build system and user prompts
        let (systemPrompt, userPrompt) = buildPrompts(profile: profile, context: context, hazards: hazards)
        
        // Call OpenAI backend
        do {
            let resultJSON = try await OpenAIClient.shared.complete(system: systemPrompt, user: userPrompt)
            
            // Strip markdown code fences if present (e.g., ```json ... ```)
            let cleanedJSON = stripMarkdownCodeFences(resultJSON)
            
            // Parse JSON response
            guard let jsonData = cleanedJSON.data(using: .utf8) else {
                throw NSError(domain: "RecommenderService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON string"])
            }
            
            let recommendation = try JSONDecoder().decode(ShotRecommendation.self, from: jsonData)
            return recommendation
        } catch {
            // Fallback: deterministic club selection by distance
            print("Error getting AI recommendation: \(error). Using fallback.")
            return fallbackRecommendation(profile: profile, context: context)
        }
    }
    
    private func stripMarkdownCodeFences(_ jsonString: String) -> String {
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove opening code fence (```json or ```)
        if cleaned.hasPrefix("```") {
            if let jsonIndex = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: jsonIndex)...])
            } else {
                // No newline, just remove the fence
                cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
                cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            }
        }
        
        // Remove closing code fence (```)
        if cleaned.hasSuffix("```") {
            if let lastNewlineIndex = cleaned.lastIndex(of: "\n") {
                cleaned = String(cleaned[..<lastNewlineIndex])
            } else {
                cleaned = cleaned.replacingOccurrences(of: "```", with: "")
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func buildPrompts(profile: PlayerProfile, context: ShotContext, hazards: [String]) -> (system: String, user: String) {
        // System prompt: Instructions for the AI
        let systemPrompt = """
        You are an expert golf caddie AI. Analyze the player's profile and shot context, then provide a shot recommendation in JSON format.
        Return ONLY valid JSON matching this structure:
        {
            "id": "UUID string",
            "club": "Club name (e.g., '7i', 'PW', 'Driver')",
            "aimOffsetYards": 0.0,
            "shotShape": "Straight, Draw, or Fade",
            "narrative": "Detailed shot recommendation text",
            "confidence": 0.85,
            "avoidZones": ["List of hazards to avoid"]
        }
        """
        
        // User prompt: Structured data for the current shot
        let clubsJSON = profile.clubs.map { club in
            "{\"name\":\"\(club.name)\",\"yards\":\(club.carryYards)}"
        }.joined(separator: ",")
        
        let hazardsJSON = hazards.isEmpty ? "[]" : "[\(hazards.map { "\"\($0)\"" }.joined(separator: ","))]"
        
        let userPrompt = """
        {
            "player": {
                "shotShape": "\(profile.preferredShotShape)",
                "missLeftPct": \(profile.missesLeftPct),
                "missRightPct": \(profile.missesRightPct),
                "clubs": [\(clubsJSON)]
            },
            "context": {
                "hole": \(context.hole),
                "distanceYards": \(Int(context.distanceToCenter)),
                "elevationDeltaYards": \(Int(context.elevationDelta)),
                "windMph": \(context.windSpeedMph),
                "windDirDeg": \(context.windDirectionDeg),
                "tempF": \(context.temperatureF),
                "lie": "\(context.lieType)",
                "hazards": \(hazardsJSON)
            }
        }
        """
        
        return (system: systemPrompt, user: userPrompt)
    }
    
    private func fallbackRecommendation(profile: PlayerProfile, context: ShotContext) -> ShotRecommendation {
        // Find closest club by distance
        let targetDistance = Int(context.distanceToCenter)
        
        // Ensure we have clubs to work with
        guard !profile.clubs.isEmpty else {
            // Fallback if no clubs available
            return ShotRecommendation(
                club: "7i",
                aimOffsetYards: 0.0,
                shotShape: profile.preferredShotShape,
                narrative: "No clubs configured. Please set up your clubs in Profile.",
                confidence: 0.5,
                avoidZones: []
            )
        }
        
        let closestClub = profile.clubs.min(by: { abs($0.carryYards - targetDistance) < abs($1.carryYards - targetDistance) }) ?? profile.clubs[0]
        
        return ShotRecommendation(
            club: closestClub.name,
            aimOffsetYards: 0.0,
            shotShape: profile.preferredShotShape,
            narrative: "Hit \(closestClub.name) at \(targetDistance) yards. Aim for center of green.",
            confidence: 0.7,
            avoidZones: []
        )
    }
}

