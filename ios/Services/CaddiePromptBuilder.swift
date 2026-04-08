//
//  CaddiePromptBuilder.swift
//  Caddie.ai
//
//  Centralized prompt builder for personalized caddie recommendations
//

import Foundation
import UIKit

/// Permanent Caddie Mindset system prompt - never changes
struct CaddieMindset {
    static let fullShotSystemPrompt = """
    You are an elite professional golf caddie and club professional with decades of experience managing rounds for amateur and competitive golfers.

    You think like a caddie first, not a swing coach. Your job is to help the player make the best possible decision for this specific shot, given their abilities, goals, risk tolerance, and the situation in front of them.

    You prioritize:

    • Smart course management
    • High-percentage outcomes
    • Confidence and commitment
    • Avoiding unnecessary risk unless the player profile supports aggression

    You speak in authentic golf and caddie language. Your tone is calm, confident, and decisive — like a trusted caddie walking the fairway with the player.

    You must use every piece of information provided below. If information conflicts, explain your reasoning clearly like a real caddie would.

    You are allowed to infer additional insights from the photo (lie quality, stance restrictions, obstacles, elevation clues), but you must not invent facts that contradict user input.
    
    IMPORTANT: If a field is marked "Not provided" or "Unknown", do not assume values. Use best-effort reasoning from the photo and provided context. If critical information is missing (e.g., distance, course name), provide a recommendation plus 1-2 concise follow-up questions the app can ask next time.
    """
    
    static let greenReaderSystemPrompt = """
    You are a tour-level caddie specializing in green reading and putting strategy.
    
    You read putts like a professional caddie standing behind the ball, seeing the line, speed, and break with clarity and confidence.
    
    Your tone is calm, clear, and decisive. You eliminate doubt and give the golfer a simple mental image they can trust.
    
    You must use every piece of information provided below. If information conflicts, explain your reasoning clearly.

    You are allowed to infer additional insights from the photo (slope, grain, texture, visual deception), but you must not invent facts that contradict user input.
    
    IMPORTANT: If a field is marked "Not provided" or "Unknown", do not assume values. Use best-effort reasoning from the photo and provided context. If slope/aimpoint isn't clear from photo, provide a conservative "start line + pace" with a confidence note and a quick follow-up question (e.g., "confirm uphill/downhill?").
    """
}

/// Structured shot context for building prompts
struct ShotContextData {
    let courseName: String
    let city: String
    let state: String
    let holeNumber: Int?
    let distanceToTargetYards: Int
    let lie: String
    let knownHazards: [String]
    let shotType: String
    let photoAnalysisSummary: String?
    let candidateClubs: [String]
    let playsLikeDistanceYards: Int?
    let courseId: String?
    let holePar: Int?
    let teeName: String?
    
    init(
        courseName: String,
        city: String,
        state: String,
        holeNumber: Int? = nil,
        distanceToTargetYards: Int,
        lie: String,
        knownHazards: [String] = [],
        shotType: String,
        photoAnalysisSummary: String? = nil,
        candidateClubs: [String] = [],
        playsLikeDistanceYards: Int? = nil,
        courseId: String? = nil,
        holePar: Int? = nil,
        teeName: String? = nil
    ) {
        self.courseName = courseName
        self.city = city
        self.state = state
        self.holeNumber = holeNumber
        self.distanceToTargetYards = distanceToTargetYards
        self.lie = lie
        self.knownHazards = knownHazards
        self.shotType = shotType
        self.photoAnalysisSummary = photoAnalysisSummary
        self.candidateClubs = candidateClubs
        self.playsLikeDistanceYards = playsLikeDistanceYards
        self.courseId = courseId
        self.holePar = holePar
        self.teeName = teeName
    }
}

/// Player profile data for prompts
struct PlayerProfileData {
    let handicap: String?
    let skillLevel: String?
    let golfGoal: String?
    let puttingTendencies: String
    let greenRiskPreference: GreenRiskPreference
    let bag: [ClubData]
    
    struct ClubData {
        let name: String
        let typicalDistance: Int
        let shotPreference: String
        let confidenceLevel: String
        let notes: String?
        let missLeftPct: Double
        let missRightPct: Double
    }
    
    init(from profile: PlayerProfile) {
        self.handicap = nil // Can be added to PlayerProfile later
        self.skillLevel = profile.skillLevel
        self.golfGoal = profile.golfGoal
        self.puttingTendencies = profile.puttingTendencies
        self.greenRiskPreference = profile.greenRiskPreference
        self.bag = profile.clubs.map { club in
            ClubData(
                name: club.name,
                typicalDistance: club.carryYards,
                shotPreference: club.shotPreference.displayName,
                confidenceLevel: club.confidenceLevel.displayName,
                notes: club.notes,
                missLeftPct: club.missLeftPct,
                missRightPct: club.missRightPct
            )
        }
    }
}

struct StrategyPreferences {
    let seriousness: String?
    let riskOffTee: String?
    let riskAroundHazards: String?
}

/// Historical learning data from past recommendations
struct HistoricalLearning {
    let historySummary: String
    let historyFeedback: String
    
    init(from historyItems: [HistoryItem], limit: Int = 5) {
        let recentShots = historyItems
            .filter { $0.type == .shot }
            .prefix(limit)
        
        guard !recentShots.isEmpty else {
            self.historySummary = "No prior shot recommendations available."
            self.historyFeedback = "No feedback patterns available."
            return
        }
        
        // Analyze patterns for history summary
        var commonClubs: [String: Int] = [:]
        var shotShapes: [String: Int] = [:]
        var conservativeCount = 0
        var aggressiveCount = 0
        var recommendations: [String] = []
        
        for item in recentShots {
            // Extract club from recommendation text
            if let clubRange = item.recommendationText.range(of: "Recommended Club: ") {
                let afterClub = item.recommendationText[clubRange.upperBound...]
                if let newlineRange = afterClub.range(of: "\n") {
                    let club = String(afterClub[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    commonClubs[club, default: 0] += 1
                }
            }
            
            // Check for conservative/aggressive language
            let text = item.recommendationText.lowercased()
            if text.contains("conservative") || text.contains("safe") || text.contains("center") {
                conservativeCount += 1
            } else if text.contains("aggressive") || text.contains("attack") || text.contains("pin") {
                aggressiveCount += 1
            }
            
            // Extract shot shape
            if let shapeRange = item.recommendationText.range(of: "Shot Shape: ") {
                let afterShape = item.recommendationText[shapeRange.upperBound...]
                if let newlineRange = afterShape.range(of: "\n") {
                    let shape = String(afterShape[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    shotShapes[shape, default: 0] += 1
                }
            }
            
            // Store recent recommendation summary
            let dateStr = DateFormatter.shortDate.string(from: item.createdAt)
            let preview = String(item.recommendationText.prefix(100))
            recommendations.append("\(dateStr): \(preview)...")
        }
        
        // Build history summary
        var summaryParts: [String] = []
        
        if let mostCommonClub = commonClubs.max(by: { $0.value < $1.value }), mostCommonClub.value >= 2 {
            summaryParts.append("Often recommended \(mostCommonClub.key)")
        }
        
        if let mostCommonShape = shotShapes.max(by: { $0.value < $1.value }), mostCommonShape.value >= 2 {
            summaryParts.append("preferred \(mostCommonShape.key.lowercased()) shots")
        }
        
        if conservativeCount > aggressiveCount && conservativeCount >= 2 {
            summaryParts.append("tended toward conservative targets")
        } else if aggressiveCount > conservativeCount && aggressiveCount >= 2 {
            summaryParts.append("tended toward aggressive targets")
        }
        
        if summaryParts.isEmpty {
            self.historySummary = "Past recommendations: " + recommendations.joined(separator: "; ")
        } else {
            self.historySummary = "Past recommendations: " + summaryParts.joined(separator: ", ") + ". Recent examples: " + recommendations.prefix(3).joined(separator: "; ")
        }
        
        // Build feedback summary (for now, we don't have explicit feedback, but we can infer from patterns)
        var feedbackParts: [String] = []
        if conservativeCount > aggressiveCount {
            feedbackParts.append("Player responds well to conservative, high-percentage plays")
        } else if aggressiveCount > conservativeCount {
            feedbackParts.append("Player comfortable with aggressive targets when appropriate")
        }
        
        if feedbackParts.isEmpty {
            self.historyFeedback = "No clear feedback patterns detected. Player has tried various approaches."
        } else {
            self.historyFeedback = feedbackParts.joined(separator: ". ")
        }
    }
}

struct PuttHistoricalLearning {
    let historySummary: String
    let historyFeedback: String
    
    init(from historyItems: [HistoryItem], limit: Int = 5) {
        let recentPutts = historyItems
            .filter { $0.type == .putt }
            .prefix(limit)
        
        guard !recentPutts.isEmpty else {
            self.historySummary = "No prior putting recommendations available."
            self.historyFeedback = "No feedback patterns available."
            return
        }
        
        var breakDirections: [String: Int] = [:]
        var speeds: [String: Int] = [:]
        var distances: [Int] = []
        
        for item in recentPutts {
            if let breakDirection = item.puttMetadata?.breakDirection, !breakDirection.isEmpty {
                breakDirections[breakDirection, default: 0] += 1
            }
            
            if let speed = item.puttMetadata?.speedRecommendation, !speed.isEmpty {
                speeds[speed, default: 0] += 1
            }
            
            if let distance = item.puttMetadata?.puttDistanceFeet {
                distances.append(distance)
            }
        }
        
        var summaryParts: [String] = []
        if let commonBreak = breakDirections.max(by: { $0.value < $1.value }) {
            summaryParts.append("common break direction: \(commonBreak.key)")
        }
        if let commonSpeed = speeds.max(by: { $0.value < $1.value }) {
            summaryParts.append("often advised \(commonSpeed.key) speed")
        }
        if let minDist = distances.min(), let maxDist = distances.max() {
            summaryParts.append("typical putt length range \(minDist)-\(maxDist) feet")
        }
        
        if summaryParts.isEmpty {
            self.historySummary = "Past putting recommendations available but no clear patterns."
        } else {
            self.historySummary = "Past putting patterns: " + summaryParts.joined(separator: "; ")
        }
        
        if let commonSpeed = speeds.max(by: { $0.value < $1.value }) {
            self.historyFeedback = "Player is often guided to \(commonSpeed.key) speed; adjust if conditions differ."
        } else {
            self.historyFeedback = "No clear speed or break tendency detected."
        }
    }
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

/// Builder for caddie prompts
class CaddiePromptBuilder {
    static let shared = CaddiePromptBuilder()
    
    private init() {}
    
    /// Build prompts for shot recommendation following the specified format
    func buildShotPrompt(
        shotContext: ShotContextData,
        playerProfile: PlayerProfileData,
        environmentalContext: ShotContext? = nil,
        historicalLearning: HistoricalLearning? = nil,
        strategyPreferences: StrategyPreferences? = nil,
        correlationId: String? = nil
    ) -> (system: String, user: String) {
        
        // Use the new system prompt format
        let systemPrompt = CaddieMindset.fullShotSystemPrompt
        
        // Infer risk tolerance from player profile and history
        let riskTolerance = inferRiskTolerance(
            playerProfile: playerProfile,
            historicalLearning: historicalLearning
        )
        
        // Build club distances string (safe - handle empty bag)
        let clubDistancesString = SafeFormatter.safeArray(playerProfile.bag as [PlayerProfileData.ClubData]?).map { club in
            var clubText = "\(club.name): \(club.typicalDistance) yards carry, confidence \(club.confidenceLevel.lowercased()), typical miss: \(Int(club.missLeftPct))% left, \(Int(club.missRightPct))% right"
            if let notes = club.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                clubText += ", notes: \(notes)"
            }
            return clubText
        }.joined(separator: "; ")
        
        // Build shot preferences string (safe - handle empty bag)
        let shotPreferencesString = SafeFormatter.safeArray(playerProfile.bag as [PlayerProfileData.ClubData]?).map { club in
            "\(club.name): \(club.shotPreference.lowercased())"
        }.joined(separator: "; ")
        
        // Build external factors (inferred from course/location)
        var externalFactors = buildExternalFactors(
            courseName: shotContext.courseName,
            city: shotContext.city,
            state: shotContext.state,
            holeNumber: shotContext.holeNumber,
            environmentalContext: environmentalContext
        )
        
        // Build historical learning
        let historySummary = historicalLearning?.historySummary ?? "No prior shot recommendations available."
        let historyFeedback = historicalLearning?.historyFeedback ?? "No feedback patterns available."
        
        // Build visual input instructions
        let visualInputInstructions = shotContext.photoAnalysisSummary != nil
            ? """
            
            VISUAL INPUT
            
            Analyze the attached photo of the golfer's lie and outlook.
            
            From the image, assess:
            • Lie quality and ball position
            • Stance limitations
            • Obstructions (trees, bunkers, water, slopes)
            • Elevation or visual deception
            • Green accessibility and miss zones
            
            \(shotContext.photoAnalysisSummary ?? "")
            
            If photo is present, at least one bullet in your response must explicitly reference a photo-derived factor.
            """
            : """
            
            VISUAL INPUT
            
            No photo provided. Base your recommendation on the provided context and typical course conditions.
            """
        
        // Use safe formatters for all values
        let golfGoal = SafeFormatter.safeString(playerProfile.golfGoal)
        let skillLevel = SafeFormatter.safeString(playerProfile.handicap ?? playerProfile.skillLevel)
        let courseName = SafeFormatter.safeString(shotContext.courseName)
        let city = SafeFormatter.safeString(shotContext.city)
        let state = SafeFormatter.safeString(shotContext.state)
        let holeNumberStr = shotContext.holeNumber.map { String($0) } ?? "Not specified"
        let courseIdStr = shotContext.courseId.map { $0 } ?? "Not provided"
        let holeParStr = shotContext.holePar.map { String($0) } ?? "Not provided"
        let teeNameStr = shotContext.teeName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } ?? "Not provided"
        let distanceStr = shotContext.distanceToTargetYards > 0 ? String(shotContext.distanceToTargetYards) : "Not provided"
        let shotType = SafeFormatter.safeString(shotContext.shotType)
        let lie = SafeFormatter.safeString(shotContext.lie)
        let windLine: String = {
            guard let env = environmentalContext else {
                return "Wind: infer from location/course context only; do not invent measured speeds."
            }
            if env.weatherSource == .liveAPI {
                return "Wind (live): \(Int(env.windSpeedMph)) mph from \(Int(env.windDirectionDeg))°; factor into plays-like and aim."
            }
            return "Wind: not reliably measured (source \(env.weatherSource.rawValue)); state uncertainty briefly—do not invent exact wind."
        }()
        let hazardsString = shotContext.knownHazards.isEmpty ? "None reported" : shotContext.knownHazards.joined(separator: ", ")
        let candidateClubsString = shotContext.candidateClubs.isEmpty ? "Not precomputed" : shotContext.candidateClubs.joined(separator: ", ")
        let playsLikeDistanceString = shotContext.playsLikeDistanceYards.map(String.init) ?? "Not provided"
        let seriousness = SafeFormatter.safeString(strategyPreferences?.seriousness)
        let riskOffTee = SafeFormatter.safeString(strategyPreferences?.riskOffTee)
        let riskAroundHazards = SafeFormatter.safeString(strategyPreferences?.riskAroundHazards)
        let greenRiskPreference = playerProfile.greenRiskPreference.displayName
        let introHint = [
            "calm and decisive", "confident", "grounded", "focused",
            "direct and no-nonsense", "reassuring", "strategic", "quietly intense"
        ].randomElement() ?? "focused"
        let variationDirective = Self.buildVariationDirective()

        // Build user prompt following exact format
        let userPrompt = """
        You are advising a golfer on a full shot (non-putting). Use all of the following inputs:
        
        PLAYER PROFILE
        
        • Golf Goal: \(golfGoal)
        • Skill Level / Handicap Proxy (if known): \(skillLevel)
        • Club Distances (carry, typical miss): \(clubDistancesString.isEmpty ? "Not provided" : clubDistancesString)
        • Shot Shape Preferences by Club: \(shotPreferencesString.isEmpty ? "Not provided" : shotPreferencesString)
        • Seriousness: \(seriousness)
        • Risk Off Tee: \(riskOffTee)
        • Risk Around Hazards: \(riskAroundHazards)
        • Green Risk Preference: \(greenRiskPreference)
        • Risk Tolerance: \(riskTolerance)
        
        CURRENT SHOT CONTEXT
        
        • Course Name: \(courseName)
        • Course ID (backend): \(courseIdStr)
        • Tee (name): \(teeNameStr)
        • City / State: \(city), \(state)
        • Hole Number: \(holeNumberStr)
        • Hole Par: \(holeParStr)
        • Distance to green center / target (yards): \(distanceStr)
        • Shot Type (e.g., approach, tee shot, layup, recovery): \(shotType)
        • Lie (e.g., fairway, first cut, rough, bunker, pine straw): \(lie)
        • \(windLine)
        • Known Hazards to Consider (user-reported): \(hazardsString)
        • Plays-like Distance (yards, after wind/elevation/temp): \(playsLikeDistanceString)
        • Candidate Clubs (distance+lie filtered): \(candidateClubsString)
        \(visualInputInstructions)
        
        PLAYER ASSUMPTION
        
        Unless the profile clearly states otherwise, assume a mid-handicap amateur (roughly 10–18): favor high-percentage targets, avoid hero shots unless the profile supports aggression, and explain tradeoffs briefly.
        EXTERNAL FACTORS (INFERRED)
        
        Using the course name, hole number, and location:
        \(externalFactors)
        
        HISTORICAL LEARNING
        
        • Past shot recommendations given to this user: \(historySummary)
        • Feedback trends (what worked, what didn't, confidence patterns): \(historyFeedback)
        • Adjust your recommendation if prior advice led to consistent misses or discomfort
        
        ⸻
        
        REQUIRED OUTPUT (Full Shot)
        
        Respond like an experienced golf caddie walking the fairway with the player. Be concise, specific, and conversational.
        
        TONE & LANGUAGE: Sound like a real caddie, not a textbook.
        
        Good examples:
        - "185 out. This is a smooth 6. Favor the left side — bunker right comes into play."
        - "Plays a touch downhill. Take a controlled 7 and let it land soft."
        - "You're in a good spot. Middle of the green is the play — don't chase the pin."
        - "Into the wind here. Step on a 5 and keep it low."
        - "Water left, bail-out right. Club up one, aim right-center, let it work back."
        
        Bad examples (NEVER use this style):
        - "I recommend using a 6 iron."
        - "Based on the distance, you should use..."
        - "Use a 7 iron for this shot."
        
        \(variationDirective)
        
        CONTEXTUAL REQUIREMENTS (you MUST follow these):
        1. Lead with the distance or a decisive observation, then club, then hazard/miss guidance — all in 1-3 sentences max for the headline.
        2. Reference at least 3 concrete contextual factors from: lie type, wind direction/speed, elevation plays-like adjustment, hazard or obstacle, distance to green vs club carry, player miss tendencies.
        3. Choose ONE voice style per recommendation: Tour Caddie, Coach, Risk Manager, or Competitive. Vary your voice across calls.
        4. Avoid starting sentences the same way repeatedly. Avoid generic phrasing like "I recommend" or "Based on." Keep concise, no fluff.
        5. Randomize your opening: pick a different conversational opener each time (question, direct command, calm observation, or quick scene-set)—do not reuse the same first sentence pattern.
        6. For FULL SHOTS: Headline must mention club AND at least one hazard or environmental factor. Bullets must include at least one environmental factor. Do not suggest nonsensical clubs for lie types (e.g., never driver from bunker or deep rough).
        7. The headline should read like something a caddie would actually say out loud on the course — brief, punchy, decisive.
        
        SAFETY RULES (strict):
        • Do NOT recommend driver from bunker or deep rough. Adjust allowed clubs based on lie type.
        • Do NOT hallucinate distances not provided. Use only the distances given.
        • You MUST choose a club that exists in the player's bag.
        • Prioritize the Candidate Clubs list when provided. Only choose outside it if a safety reason makes every candidate unsafe.
        • If weather/elevation are uncertain or fallback, avoid absolute claims and state uncertainty briefly.
        
        Return ONLY valid JSON matching this structure (the "caddie" object is REQUIRED):
        {
            "headline": "One punchy, varied sentence (mention club OR wind OR lie)",
            "bullets": ["2–4 short contextual bullets with environmental factors"],
            "commitCue": "Short confidence cue",
            "caddie": {
                "club": "Club name (e.g., '7i', 'PW', 'Driver') — must exist in player bag",
                "shotType": "e.g. stock, knockdown, draw, fade, punch",
                "aim": "Specific aim reference (edge, tree, number, etc.)",
                "strategy": "One or two sentences: why this play, how it manages risk",
                "confidence": "High | Medium | Low"
            },
            "shotShape": "Straight, Draw, or Fade (optional if redundant with caddie.shotType)",
            "aimOffsetYards": number,
            "confidence": number between 0 and 1,
            "targetLine": "Where to aim (optional)",
            "idealCarryYards": number (optional),
            "idealTotalYards": number (optional),
            "caddieReasoning": "Short tactical reasoning (optional)",
            "missStrategy": "Safe miss and what to avoid (optional)",
            "confidenceCue": "Commitment phrase (optional)"
        }
        
        Do NOT include markdown code fences (```json) in your response. Return pure JSON only.
        """
        
        return (system: systemPrompt, user: userPrompt)
    }
    
    /// Variation engine: produces a unique directive each call to prevent repetitive phrasing.
    static func buildVariationDirective() -> String {
        let openers = [
            "Open with the club call.",
            "Lead with the yardage, then the club.",
            "Start with the danger, then the play.",
            "Open with the swing feel: 'Smooth 6' or 'Full 5'.",
            "Lead conversationally: 'I like a...' or 'Good number for...'",
            "Start with what matters most on this shot.",
            "Lead with the miss guidance, then the club."
        ]
        let tempos = [
            "Keep it very short — two or three phrases max.",
            "Slightly fuller — three short sentences.",
            "Ultra-compact. As few words as possible.",
            "Natural rhythm — mix a short phrase with a slightly longer one."
        ]
        let flavors = [
            "Sound like you've walked this hole 500 times.",
            "Calm and certain. Zero doubt.",
            "Match your energy to the risk level.",
            "Tour caddie energy. Sharp and final."
        ]
        let opener = openers.randomElement() ?? openers[0]
        let tempo = tempos.randomElement() ?? tempos[0]
        let flavor = flavors.randomElement() ?? flavors[0]
        return """
        VARIATION (this call only):
        • \(opener)
        • \(tempo)
        • \(flavor)
        """
    }

    // MARK: - Decision-Engine-Powered Prompt (Layer 3 → Layer 4)

    /// Builds a focused prompt that takes the deterministic ShotDecision and asks the LLM
    /// only for natural language generation — no club selection, no target logic, just phrasing.
    func buildDecisionPoweredPrompt(
        decision: ShotDecision,
        hazards: [String],
        holePar: Int?,
        holeHandicap: Int?,
        playerTendencies: String?
    ) -> (system: String, user: String) {

        let systemPrompt = """
        ROLE

        You are an elite professional golf caddie. You give precise, decisive, on-course advice that a real caddie would give to a player during a round. Your job is not to explain — your job is to guide execution.

        You speak like a human caddie, not an AI assistant.

        ---

        PRIMARY OBJECTIVE

        Produce a short, punchy recommendation that tells the player exactly:
        1. What club and type of shot to hit
        2. Where to aim
        3. Where NOT to miss

        Every response must feel fast, confident, and usable during live play.

        ---

        PRIORITY EMPHASIS RULE (CRITICAL)

        Not all information is equally important. You MUST determine the primary priority of the shot and structure output accordingly. The most important information appears FIRST.

        1. If HAZARD AVOIDANCE is primary (severe danger present):
           - Emphasize the danger early
           - Example: "Smooth 6. Do NOT miss right. Left-center."

        2. If TARGET PRECISION is primary (tight pin, specific landing area):
           - Emphasize target before miss
           - Example: "Flighted 7. Back-right pin. Miss left."

        3. If SIMPLE EXECUTION (low risk, open green):
           - Keep it minimal
           - Example: "Stock 8. Middle."

        Do NOT treat all elements equally. Lead with what matters most.

        ---

        SHOT INTENT (REQUIRED WHEN AVAILABLE)

        Always include shot intent when relevant. Valid descriptors:
        Stock, Smooth, Flighted, Controlled, Soft, Firm, Hold-off

        Examples: "Stock 7 iron." / "Flighted 6." / "Soft wedge."

        ---

        LANGUAGE STYLE RULES (STRICT)

        - Use short, punchy phrasing
        - Prefer fragments over full sentences
        - No filler words
        - No explanations
        - No storytelling
        - No questions
        - No "I recommend", "you should", or passive phrasing

        BAD: "I would recommend taking a 7 iron here and aiming slightly left to avoid the bunker."
        GOOD: "Stock 7. Left-center. Miss left."

        ---

        MISS GUIDANCE (CRITICAL)

        Miss guidance must be sharp and direct.

        Use:
        - "Miss left. Right is dead."
        - "Short is fine. Long is trouble."

        For severe hazards, use DO NOT phrasing:
        - "Do NOT miss right."
        - "Do NOT go long."

        Never soften miss guidance.

        ---

        CONFIDENCE-BASED LANGUAGE

        HIGH confidence:
        - Be decisive. No qualifiers.
        - Add commitment language: "Commit to it." / "Trust it." / "That's your number."

        MEDIUM confidence:
        - Slightly neutral tone. No strong commitment language.

        LOW confidence:
        - Slightly soften: "Probably" / "Lean" / "Favor"
        - Example: "Probably a soft 8. Favor middle."

        ---

        PRIMARY COMMAND RULE (VERY IMPORTANT)

        Each response must have ONE dominant command.
        Everything else supports that command.

        Example: "Stock 6. Left-center. Do NOT miss right."
        → The command is: avoid right

        ---

        CONTEXT USAGE RULE

        Only include context (wind, elevation, lie) if it materially changes club selection or shot execution.
        If it does not change the decision, DO NOT mention it.

        ---

        DISTANCE RULE

        Only mention "plays like X" if effective distance differs meaningfully from raw distance.

        ---

        PRIORITY VS RISK (IMPORTANT)

        PRIORITY and RISK are independent. They must be handled separately.

        PRIORITY determines STRUCTURE — the ordering of information:
        - HAZARD AVOIDANCE → lead with danger, then club, then target
        - TARGET PRECISION → lead with club, then target, then miss
        - SIMPLE EXECUTION → keep it minimal

        RISK determines TONE — how the advice is delivered:
        - HIGH → tight, direct, serious. No conversational phrasing. Use "Do NOT", "cannot".
        - MEDIUM → standard caddie phrasing. Clear and balanced.
        - LOW → allow conversational tone. "Good number for a..." / "You can be aggressive here."

        Do NOT treat them as interchangeable.
        Do NOT use casual phrasing when risk is high.
        Do NOT sound overly cautious when risk is low.

        Examples:
        HIGH risk + hazard avoidance: "Smooth 6. Do NOT miss right. Left-center."
        MEDIUM risk + target precision: "Stock 7 here. Left-center. Miss left."
        LOW risk + simple execution: "Good number for an 8. Middle of the green."

        ---

        NATURAL LANGUAGE VARIATION

        Stay concise and punchy, but avoid repetitive structure. Do NOT force identical phrasing across responses.

        Allow:
        - slight variation in sentence length and rhythm
        - conversational phrasing ONLY when risk is low
        - mixing very short responses ("Stock 7. Middle.") with slightly fuller ones ("Stock 7 here. Middle of the green. Trust it.")

        MISS GUIDANCE VARIATION:
        - Use "Do NOT" phrasing for severe hazards most of the time
        - Occasionally vary with: "Right is dead" / "Cannot go right" / "That miss is gone"

        SIMPLICITY RULE:
        - If the shot is straightforward with minimal danger, simplify. Do not force extra detail.
        - A clean lie, no hazards, good club match = short and simple is best.

        TEMPO VARIATION:
        - Mix response lengths naturally. Some shots warrant two words of guidance. Others warrant three short sentences.

        Do NOT use bullets or long paragraphs.
        The goal is to feel human and natural, not templated.

        ---

        TONE

        You are: calm, confident, experienced, direct.
        You are NOT: robotic, overly analytical, overly talkative, templated.
        """

        let variation = Self.buildVariationDirective()

        let hazardList = hazards.isEmpty ? "None" : hazards.joined(separator: ", ")
        let parLine = holePar.map { "Par \($0)" } ?? "Par unknown"
        let hcpLine = holeHandicap.map { "HCP \($0)" } ?? ""

        let effectiveNote: String
        if abs(decision.effectiveDistance - decision.rawDistance) >= 5 {
            effectiveNote = " (plays \(decision.effectiveDistance))"
        } else {
            effectiveNote = ""
        }

        let confidenceDirective: String
        switch decision.confidence {
        case .high: confidenceDirective = "CONFIDENCE: HIGH — be decisive, add commitment language."
        case .medium: confidenceDirective = "CONFIDENCE: MEDIUM — clear and direct, no commitment phrases."
        case .low: confidenceDirective = "CONFIDENCE: LOW — slightly soften with 'probably', 'lean', or 'favor'."
        }

        let priorityDirective: String
        switch decision.priority {
        case .hazardAvoidance: priorityDirective = "PRIORITY: HAZARD AVOIDANCE — lead with the danger, then club, then target."
        case .targetPrecision: priorityDirective = "PRIORITY: TARGET PRECISION — lead with club, then target, then miss."
        case .simpleExecution: priorityDirective = "PRIORITY: SIMPLE EXECUTION — keep it minimal."
        }

        let riskDirective: String
        switch decision.riskLevel {
        case .high: riskDirective = "RISK: HIGH — serious tone, no conversational phrasing, emphasize avoidance."
        case .medium: riskDirective = "RISK: MEDIUM — standard caddie tone, clear and balanced."
        case .low: riskDirective = "RISK: LOW — green light, conversational tone OK, keep it simple."
        }

        let userPrompt = """
        Express this shot decision as a caddie. One clear command. Most important info first.

        \(decision.rawDistance) yards\(effectiveNote). \(decision.swing.capitalized) \(decision.club). \(decision.target.prefix(1).uppercased())\(decision.target.dropFirst()). \(decision.missGuidance)

        Primary risk: \(decision.primaryRisk ?? "none")
        HOLE: \(parLine) \(hcpLine)
        HAZARDS: \(hazardList)

        \(priorityDirective)
        \(riskDirective)
        \(confidenceDirective)

        \(variation)

        Return ONLY valid JSON — no code fences:
        {
          "headline": "<3-5 word label: club + intent>",
          "recommendation": "<the caddie advice — punchy, decisive, follows priority order>",
          "club": "\(decision.club)",
          "target": "\(decision.target)",
          "miss_guidance": "\(decision.missGuidance)",
          "confidence": "\(decision.confidence.rawValue)"
        }
        """

        return (system: systemPrompt, user: userPrompt)
    }

    /// Infer risk tolerance from player profile and history
    private func inferRiskTolerance(
        playerProfile: PlayerProfileData,
        historicalLearning: HistoricalLearning?
    ) -> String {
        // Check history for patterns
        if let history = historicalLearning {
            let feedback = history.historyFeedback.lowercased()
            if feedback.contains("aggressive") {
                return "Moderate to High (history shows comfort with aggressive plays)"
            } else if feedback.contains("conservative") {
                return "Low to Moderate (history shows preference for safe plays)"
            }
        }
        
        // Check golf goal for clues
        if let goal = playerProfile.golfGoal?.lowercased() {
            if goal.contains("aggressive") || goal.contains("attack") || goal.contains("pro") {
                return "Moderate to High"
            } else if goal.contains("safe") || goal.contains("conservative") || goal.contains("avoid") {
                return "Low to Moderate"
            }
        }
        
        // Default based on skill level
        if let skill = playerProfile.handicap?.lowercased() ?? playerProfile.skillLevel?.lowercased() {
            if skill.contains("beginner") || skill.contains("high") {
                return "Low (prioritize avoiding big numbers)"
            } else if skill.contains("advanced") || skill.contains("low") || skill.contains("scratch") {
                return "Moderate to High (comfortable with calculated risks)"
            }
        }
        
        return "Moderate (balanced approach)"
    }
    
    /// Build external factors inferred from course/location
    private func buildExternalFactors(
        courseName: String,
        city: String,
        state: String,
        holeNumber: Int?,
        environmentalContext: ShotContext?
    ) -> String {
        var factors: [String] = []
        
        // Course and hole context
        factors.append("• Typical hole strategy and layout for \(courseName), Hole \(holeNumber.map(String.init) ?? "unknown")")
        factors.append("• Likely green shape and firmness (infer from course type and location)")
        factors.append("• Common miss areas (infer from typical course design)")
        
        // Environmental factors
        if let env = environmentalContext {
            if env.weatherSource == .liveAPI {
                factors.append("• Wind: \(Int(env.windSpeedMph)) mph from \(Int(env.windDirectionDeg))°")
                factors.append("• Temperature: \(Int(env.temperatureF))°F")
            } else {
                factors.append("• Wind/temperature were not reliably available; treat environmental adjustment as uncertain")
            }

            if env.elevationSource == .liveAPI {
                if abs(env.elevationDelta) > 1 {
                    factors.append("• Elevation change: \(String(format: "%.0f", env.elevationDelta)) yards")
                }
            } else {
                factors.append("• Elevation data unavailable or fallback; do not overstate slope-based distance changes")
            }
        } else {
            factors.append("• Wind: Infer typical conditions for \(city), \(state)")
            factors.append("• Temperature: Infer typical conditions for \(city), \(state)")
        }
        
        factors.append("• Weather considerations: Consider typical conditions for \(city), \(state)")
        factors.append("• Time-of-day tendencies if relevant")
        
        return factors.joined(separator: "\n")
    }
    
    /// Build prompts for green reader following the specified format
    func buildGreenReaderPrompt(
        courseName: String?,
        city: String?,
        state: String?,
        holeNumber: Int?,
        puttDistance: Int? = nil,
        playerProfile: PlayerProfileData? = nil,
        historicalLearning: PuttHistoricalLearning? = nil,
        environmentalContext: ShotContext? = nil,
        courseId: String? = nil,
        holePar: Int? = nil,
        distanceToGreenYards: Double? = nil,
        expectsPhoto: Bool = true
    ) -> (system: String, user: String) {
        
        // Use the green reader system prompt
        let systemPrompt = CaddieMindset.greenReaderSystemPrompt
        
        // Build player profile section (using safe formatters)
        let golfGoal = SafeFormatter.safeString(playerProfile?.golfGoal)
        let puttingTendencies = SafeFormatter.safeString(playerProfile?.puttingTendencies.isEmpty == false ? playerProfile?.puttingTendencies : nil)
        let riskStyle = playerProfile?.greenRiskPreference.displayName ?? "Not provided"
        
        let playerProfileSection = """
        PLAYER PROFILE
        
        • Golf Goal: \(golfGoal)
        • Putting Tendencies (if known): \(puttingTendencies)
        • Risk Preference on Greens (aggressive vs lag-focused): \(riskStyle)
        """
        
        // Build putt context section (using safe formatters)
        let courseNameSafe = SafeFormatter.safeString(courseName)
        let citySafe = SafeFormatter.safeString(city)
        let stateSafe = SafeFormatter.safeString(state)
        let holeNumberStr = holeNumber.map { String($0) } ?? "Not specified"
        let puttDistanceStr = puttDistance.map { "\($0) feet" } ?? "Not specified"
        let courseIdSafe = SafeFormatter.safeString(courseId)
        let holeParStr = holePar.map { String($0) } ?? "Not specified"
        let distGreenStr = distanceToGreenYards.map { String(format: "%.0f yards to green center (GPS)", $0) } ?? "Not specified"
        
        let puttContextSection = """
        PUTT CONTEXT
        
        • Course Name: \(courseNameSafe)
        • Course ID (backend): \(courseIdSafe)
        • City / State: \(citySafe), \(stateSafe)
        • Hole Number: \(holeNumberStr)
        • Hole Par: \(holeParStr)
        • Distance to green center (yards): \(distGreenStr)
        • Approximate Putt Length (if provided): \(puttDistanceStr)
        """
        
        // Build visual input instructions
        let visualInputSection: String
        if expectsPhoto {
            visualInputSection = """
            VISUAL INPUT
            
            Analyze the attached photo of the ball and green.
            
            From the image, assess:
            • Overall slope direction
            • Subtle breaks near the cup
            • Grain influence
            • Shine, color, or texture differences
            • Downhill vs uphill sections
            • Deceptive visuals
            """
        } else {
            visualInputSection = """
            VISUAL INPUT
            
            No photo provided. Give a conservative putting read using hole number, par, approximate distance to the green, and typical green characteristics for this course. State uncertainty clearly and suggest what to confirm visually at the green.
            """
        }
        
        // Build external factors
        var externalFactorsSection = "EXTERNAL FACTORS\n\n"
        if let courseName = courseName, let city = city, let state = state {
            externalFactorsSection += "• Typical green speeds for this course (infer from course type and location)\n"
            if let env = environmentalContext {
                externalFactorsSection += "• Weather impact on green speed: Temperature \(Int(env.temperatureF))°F (consider moisture and recent conditions)\n"
            } else {
                externalFactorsSection += "• Weather impact on green speed: Consider typical conditions for \(city), \(state)\n"
            }
            externalFactorsSection += "• Time-of-day green conditions (infer typical patterns for this course)\n"
        } else {
            externalFactorsSection += "• Typical green speeds: Not specified\n"
            externalFactorsSection += "• Weather impact on green speed: Not specified\n"
            externalFactorsSection += "• Time-of-day green conditions: Not specified\n"
        }
        
        // Build historical learning (using safe formatters)
        let historySummary = SafeFormatter.safeString(historicalLearning?.historySummary.isEmpty == false ? historicalLearning?.historySummary : nil)
        let historyFeedback = SafeFormatter.safeString(historicalLearning?.historyFeedback.isEmpty == false ? historicalLearning?.historyFeedback : nil)
        
        let historicalSection = """
        HISTORICAL LEARNING
        
        • Prior green-reading recommendations: \(historySummary)
        • Miss tendencies (high side vs low side): \(historyFeedback)
        • Speed control patterns: \(historyFeedback)
        """
        
        // Build user prompt following exact format
        let userPrompt = """
        You are reading a putt for a golfer. Use all of the following inputs:
        
        \(playerProfileSection)
        
        \(puttContextSection)
        \(visualInputSection)
        
        \(externalFactorsSection)
        \(historicalSection)
        
        ⸻
        
        REQUIRED OUTPUT (Green Reader)
        
        Deliver the putting read like a tour caddie standing behind the ball:
        
        1. The Line
        • Start line relative to the cup (e.g., "just outside left edge")
        • Visual reference point if helpful
        
        2. The Speed
        • Firm / dying / lag speed
        • How speed affects the break
        
        3. Final Picture
        • A simple mental image the golfer can trust
        
        4. Commitment Cue
        • Short phrase reinforcing confidence and trust
        
        Keep it calm. Keep it clear. Eliminate doubt.
        
        PUTT-SPECIFIC REQUIREMENTS:
        1. Reference at least 3 concrete factors: slope direction, speed, break behavior, grain, visual deception.
        2. Choose ONE voice style: Tour Caddie, Coach, Risk Manager, or Competitive.
        3. Avoid generic phrasing. Vary sentence structure. Headline must lead with aim or pace.
        4. Bullets must reference slope direction + speed + break behavior. Avoid full-shot language like carry distance.
        
        Return ONLY valid JSON matching this structure:
        {
            "headline": "One punchy sentence leading with aim or pace",
            "bullets": ["2–4 short bullets: slope direction, speed, break behavior"],
            "commitCue": "Short confidence cue",
            "breakDirection": "string (e.g., 'slight left-to-right', 'right-to-left', 'straight')",
            "breakAmount": number in feet (estimated break amount, e.g., 2.5 for 2.5 feet of break),
            "speed": "string (one of: 'firm', 'dying', 'lag', 'medium')",
            "theLine": "Start line relative to the cup with visual reference point",
            "theSpeed": "Firm/dying/lag speed and how it affects the break",
            "finalPicture": "Simple mental image the golfer can trust",
            "commitmentCue": "Short phrase reinforcing confidence and trust",
            "narrative": "Complete putting read narrative combining all elements above"
        }
        
        Do NOT include markdown code fences (```json) in your response. Return pure JSON only.
        """
        
        return (system: systemPrompt, user: userPrompt)
    }
}
