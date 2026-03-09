//
//  AIContextBuilder.swift
//  Caddie.ai
//
//  Safe context builder for AI requests - handles missing inputs gracefully
//

import Foundation

/// Safe formatting helpers to avoid force unwraps and handle missing values
struct SafeFormatter {
    /// Returns "Not provided" if value is nil or empty
    static func safeString(_ value: String?) -> String {
        guard let value = value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Not provided"
        }
        return value
    }
    
    /// Returns nil if value is nil (for optional numeric fields)
    static func safeInt(_ value: Int?) -> Int? {
        return value
    }
    
    /// Returns nil if value is nil (for optional numeric fields)
    static func safeDouble(_ value: Double?) -> Double? {
        return value
    }
    
    /// Returns empty array if value is nil
    static func safeArray<T>(_ value: [T]?) -> [T] {
        return value ?? []
    }
    
    /// Returns empty dictionary if value is nil
    static func safeDict(_ value: [String: Any]?) -> [String: Any] {
        return value ?? [:]
    }
    
    /// Returns "Unknown" for numeric values that should be strings when missing
    static func safeNumericString(_ value: Int?) -> String {
        guard let value = value else { return "Unknown" }
        return String(value)
    }
    
    /// Returns "Unknown" for numeric values that should be strings when missing
    static func safeNumericString(_ value: Double?) -> String {
        guard let value = value else { return "Unknown" }
        return String(format: "%.1f", value)
    }
}

/// Builder for safe AI context dictionaries
class AIContextBuilder {
    static let shared = AIContextBuilder()
    
    private init() {}
    
    /// Build safe context for full shot recommendation
    func buildFullShotContext(
        profile: PlayerProfile?,
        courseName: String?,
        city: String?,
        state: String?,
        holeNumber: Int?,
        distanceYards: Int?,
        shotType: String?,
        lie: String?,
        hazards: [String]?,
        environmentalContext: ShotContext?,
        historicalLearning: HistoricalLearning?
    ) -> [String: Any] {
        var context: [String: Any] = [:]
        
        // Player Profile
        var playerProfile: [String: Any] = [:]
        if let profile = profile {
            playerProfile["golfGoal"] = SafeFormatter.safeString(profile.golfGoal)
            playerProfile["skillLevel"] = SafeFormatter.safeString(profile.skillLevel)
            playerProfile["handedness"] = SafeFormatter.safeString(profile.handedness)
            playerProfile["puttingTendencies"] = SafeFormatter.safeString(profile.puttingTendencies.isEmpty ? nil : profile.puttingTendencies)
            playerProfile["greenRiskPreference"] = profile.greenRiskPreference.displayName
            
            // Clubs array
            var clubs: [[String: Any]] = []
            for club in SafeFormatter.safeArray(profile.clubs as [ClubDistance]?) {
                clubs.append([
                    "name": club.name,
                    "typicalDistance": club.carryYards,
                    "shotPreference": club.shotPreference.displayName,
                    "confidenceLevel": club.confidenceLevel.displayName,
                    "missLeftPct": club.missLeftPct,
                    "missRightPct": club.missRightPct
                ])
            }
            playerProfile["clubs"] = clubs
        } else {
            playerProfile["golfGoal"] = "Not provided"
            playerProfile["skillLevel"] = "Not provided"
            playerProfile["handedness"] = "Not provided"
            playerProfile["puttingTendencies"] = "Not provided"
            playerProfile["greenRiskPreference"] = "Not provided"
            playerProfile["clubs"] = []
        }
        context["playerProfile"] = playerProfile
        
        // Shot Context
        var shotContext: [String: Any] = [:]
        shotContext["courseName"] = SafeFormatter.safeString(courseName)
        shotContext["city"] = SafeFormatter.safeString(city)
        shotContext["state"] = SafeFormatter.safeString(state)
        shotContext["holeNumber"] = SafeFormatter.safeInt(holeNumber) ?? 0
        shotContext["distanceYards"] = SafeFormatter.safeInt(distanceYards) ?? 0
        shotContext["shotType"] = SafeFormatter.safeString(shotType)
        shotContext["lie"] = SafeFormatter.safeString(lie)
        shotContext["knownHazards"] = SafeFormatter.safeArray(hazards)
        
        // Environmental context
        if let env = environmentalContext {
            shotContext["windMph"] = env.windSpeedMph
            shotContext["windDirDeg"] = env.windDirectionDeg
            shotContext["tempF"] = env.temperatureF
            shotContext["elevationDeltaYards"] = env.elevationDelta
        } else {
            shotContext["windMph"] = 0.0
            shotContext["windDirDeg"] = 0.0
            shotContext["tempF"] = 70.0
            shotContext["elevationDeltaYards"] = 0.0
        }
        context["shotContext"] = shotContext
        
        // Historical Learning
        if let history = historicalLearning {
            context["historySummary"] = SafeFormatter.safeString(history.historySummary.isEmpty ? nil : history.historySummary)
            context["historyFeedback"] = SafeFormatter.safeString(history.historyFeedback.isEmpty ? nil : history.historyFeedback)
        } else {
            context["historySummary"] = "Not provided"
            context["historyFeedback"] = "Not provided"
        }
        
        // Log missing fields for debugging
        logMissingFields(context: context)
        
        return context
    }
    
    /// Build safe context for green reader
    func buildGreenReaderContext(
        profile: PlayerProfile?,
        courseName: String?,
        city: String?,
        state: String?,
        holeNumber: Int?,
        puttDistance: Int?,
        environmentalContext: ShotContext?,
        historicalLearning: HistoricalLearning?
    ) -> [String: Any] {
        var context: [String: Any] = [:]
        
        // Player Profile
        var playerProfile: [String: Any] = [:]
        if let profile = profile {
            playerProfile["golfGoal"] = SafeFormatter.safeString(profile.golfGoal)
            playerProfile["puttingTendencies"] = SafeFormatter.safeString(profile.puttingTendencies.isEmpty ? nil : profile.puttingTendencies)
            playerProfile["greenRiskPreference"] = profile.greenRiskPreference.displayName
        } else {
            playerProfile["golfGoal"] = "Not provided"
            playerProfile["puttingTendencies"] = "Not provided"
            playerProfile["greenRiskPreference"] = "Not provided"
        }
        context["playerProfile"] = playerProfile
        
        // Putt Context
        var puttContext: [String: Any] = [:]
        puttContext["courseName"] = SafeFormatter.safeString(courseName)
        puttContext["city"] = SafeFormatter.safeString(city)
        puttContext["state"] = SafeFormatter.safeString(state)
        puttContext["holeNumber"] = SafeFormatter.safeInt(holeNumber) ?? 0
        puttContext["puttDistance"] = SafeFormatter.safeInt(puttDistance) ?? 0
        context["puttContext"] = puttContext
        
        // Environmental context
        if let env = environmentalContext {
            context["tempF"] = env.temperatureF
            context["windMph"] = env.windSpeedMph
        } else {
            context["tempF"] = 70.0
            context["windMph"] = 0.0
        }
        
        // Historical Learning
        if let history = historicalLearning {
            context["historySummary"] = SafeFormatter.safeString(history.historySummary.isEmpty ? nil : history.historySummary)
            context["historyFeedback"] = SafeFormatter.safeString(history.historyFeedback.isEmpty ? nil : history.historyFeedback)
        } else {
            context["historySummary"] = "Not provided"
            context["historyFeedback"] = "Not provided"
        }
        
        // Log missing fields for debugging
        logMissingFields(context: context)
        
        return context
    }
    
    /// Log which fields are "Not provided" for debugging
    private func logMissingFields(context: [String: Any]) {
        var missingFields: [String] = []
        
        func checkForMissing(_ dict: [String: Any], prefix: String = "") {
            for (key, value) in dict {
                let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"
                
                if let stringValue = value as? String, stringValue == "Not provided" {
                    missingFields.append(fullKey)
                } else if let nestedDict = value as? [String: Any] {
                    checkForMissing(nestedDict, prefix: fullKey)
                } else if let array = value as? [Any], array.isEmpty {
                    missingFields.append("\(fullKey) (empty array)")
                }
            }
        }
        
        checkForMissing(context)
        
        if !missingFields.isEmpty {
            DebugLogging.log("⚠️ Missing fields in AI context: \(missingFields.joined(separator: ", "))", category: "AIContext")
        }
        
        // Log context summary (excluding base64 if present)
        var contextSummary = context
        // Remove any large base64 strings for logging
        if let imageBase64 = contextSummary["image"] as? String, imageBase64.count > 100 {
            contextSummary["image"] = "<base64 image data (\(imageBase64.count) chars)>"
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: contextSummary, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            DebugLogging.log("📤 AI Context JSON:\n\(jsonString)", category: "AIContext")
        }
    }
}
