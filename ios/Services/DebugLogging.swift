//
//  DebugLogging.swift
//  Caddie.ai
//
//  Verbose logging utility for API calls and debugging
//

import Foundation

struct DebugLogging {
    // Toggle this to enable/disable verbose logging
    // Set to false to disable all debug logging
    // Set to true to enable verbose API logging in Xcode console
    #if DEBUG
    static var enabled: Bool = true  // Change to false to disable logging
    #else
    static var enabled: Bool = false  // Always disabled in release builds
    #endif
    
    // MARK: - Logging Methods
    
    static func log(_ message: String, category: String = "General") {
        guard enabled else { return }
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        print("🔍 [\(timestamp)] [\(category)] \(message)")
    }
    
    static func logAPI(
        endpoint: String,
        url: URL?,
        method: String = "GET",
        payload: Any? = nil,
        responseStatus: Int? = nil,
        responseData: Data? = nil,
        parsedModel: Any? = nil,
        error: Error? = nil
    ) {
        guard enabled else { return }
        
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        var logLines: [String] = []
        
        logLines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logLines.append("🔵 API Call: \(endpoint)")
        logLines.append("   Time: \(timestamp)")
        
        // URL
        if let url = url {
            logLines.append("   URL: \(url.absoluteString)")
        } else {
            logLines.append("   URL: ❌ Invalid URL")
        }
        
        // Method
        logLines.append("   Method: \(method)")
        
        // Payload
        if let payload = payload {
            let payloadString = formatPayload(payload)
            logLines.append("   Payload:")
            logLines.append("   \(payloadString.indented())")
        }
        
        // Response Status
        if let status = responseStatus {
            let statusEmoji = (200...299).contains(status) ? "✅" : "❌"
            logLines.append("   Response Status: \(statusEmoji) \(status)")
        }
        
        // Response Data
        if let data = responseData {
            let responseString = String(data: data, encoding: .utf8) ?? "<binary data>"
            let truncated = truncateLongString(responseString, maxLength: 500)
            logLines.append("   Response Data:")
            logLines.append("   \(truncated.indented())")
        }
        
        // Parsed Model
        if let model = parsedModel {
            let modelString = formatModel(model)
            logLines.append("   Parsed Model:")
            logLines.append("   \(modelString.indented())")
        }
        
        // Error
        if let error = error {
            logLines.append("   Error: ❌ \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                logLines.append("   Decoding Error Details:")
                logLines.append("   \(formatDecodingError(decodingError).indented())")
            }
        }
        
        logLines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        print(logLines.joined(separator: "\n"))
    }
    
    // MARK: - Helper Methods
    
    private static func formatPayload(_ payload: Any) -> String {
        if let dict = payload as? [String: Any] {
            return formatDictionary(dict)
        } else if let array = payload as? [Any] {
            return formatArray(array)
        } else if let string = payload as? String {
            return string
        } else {
            return String(describing: payload)
        }
    }
    
    private static func formatDictionary(_ dict: [String: Any]) -> String {
        var lines: [String] = []
        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            let formattedValue = formatValue(value)
            lines.append("\(key): \(formattedValue)")
        }
        return lines.joined(separator: "\n")
    }
    
    private static func formatArray(_ array: [Any]) -> String {
        return array.map { formatValue($0) }.joined(separator: ", ")
    }
    
    private static func formatValue(_ value: Any) -> String {
        if let string = value as? String {
            // Check if it's base64 encoded (long string that looks like base64)
            if string.count > 100 {
                let base64Pattern = "^[A-Za-z0-9+/=]+$"
                if let regex = try? NSRegularExpression(pattern: base64Pattern, options: []),
                   regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count)) != nil {
                    return truncateBase64(string)
                }
            }
            // Truncate very long strings
            if string.count > 200 {
                return "\"\(String(string.prefix(100)))...\(String(string.suffix(20)))\""
            }
            return "\"\(string)\""
        } else if let dict = value as? [String: Any] {
            return "{ \(formatDictionary(dict)) }"
        } else if let array = value as? [Any] {
            return "[ \(formatArray(array)) ]"
        } else {
            return String(describing: value)
        }
    }
    
    private static func truncateBase64(_ base64: String) -> String {
        if base64.count <= 40 {
            return "\"\(base64)\""
        }
        let first20 = String(base64.prefix(20))
        let last20 = String(base64.suffix(20))
        return "\"\(first20)...[\(base64.count - 40) chars]...\(last20)\""
    }
    
    private static func truncateLongString(_ string: String, maxLength: Int = 500) -> String {
        if string.count <= maxLength {
            return string
        }
        let first = String(string.prefix(maxLength / 2))
        let last = String(string.suffix(maxLength / 2))
        return "\(first)\n... [\(string.count - maxLength) chars truncated] ...\n\(last)"
    }
    
    private static func formatModel(_ model: Any) -> String {
        // Try to encode as JSON for readable output
        if let encodable = model as? Encodable {
            if let jsonData = try? JSONEncoder().encode(encodable),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        }
        return String(describing: model)
    }
    
    private static func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch: Expected \(type), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "Value not found: Expected \(type), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .keyNotFound(let key, let context):
            return "Key not found: \(key.stringValue), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        case .dataCorrupted(let context):
            return "Data corrupted: \(context.debugDescription), at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
        @unknown default:
            return "Unknown decoding error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Extensions

extension String {
    func indented(by spaces: Int = 3) -> String {
        let indent = String(repeating: " ", count: spaces)
        return self.split(separator: "\n")
            .map { "\(indent)\($0)" }
            .joined(separator: "\n")
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

struct RecommendationHealthSnapshot: Codable {
    var totalShotRecommendations: Int = 0
    var normalizationCount: Int = 0
    var fallbackCount: Int = 0
    var aiChangedCount: Int = 0
    var photoIncludedNotReferencedCount: Int = 0
    var weatherNotLiveCount: Int = 0
    var elevationNotLiveCount: Int = 0
    var mostRecentDiagnostics: [ShotRecommendationDiagnostics] = []

    var normalizationRate: Double { rate(normalizationCount) }
    var fallbackRate: Double { rate(fallbackCount) }
    var aiChangedRate: Double { rate(aiChangedCount) }
    var photoNotReferencedRate: Double { rate(photoIncludedNotReferencedCount) }
    var weatherNotLiveRate: Double { rate(weatherNotLiveCount) }
    var elevationNotLiveRate: Double { rate(elevationNotLiveCount) }

    private func rate(_ value: Int) -> Double {
        guard totalShotRecommendations > 0 else { return 0 }
        return Double(value) / Double(totalShotRecommendations)
    }
}

@MainActor
final class RecommendationDiagnosticsStore: ObservableObject {
    static let shared = RecommendationDiagnosticsStore()

    @Published private(set) var snapshot = RecommendationHealthSnapshot()

    private let storageKey = "recommendation_diagnostics_health_v1"
    private let maxRecentDiagnostics = 10

    private init() {
        load()
    }

    func record(_ diagnostics: ShotRecommendationDiagnostics) {
        snapshot.totalShotRecommendations += 1

        if diagnostics.normalizationOccurred {
            snapshot.normalizationCount += 1
        }
        if diagnostics.fallbackUsed {
            snapshot.fallbackCount += 1
        }
        if let aiChosen = diagnostics.aiChosenClub?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !aiChosen.isEmpty,
           aiChosen != diagnostics.finalClub.lowercased() {
            snapshot.aiChangedCount += 1
        }
        if diagnostics.hasPhoto && !diagnostics.photoReferencedInOutput {
            snapshot.photoIncludedNotReferencedCount += 1
        }
        if diagnostics.weatherSource != EnvironmentalDataSource.liveAPI.rawValue {
            snapshot.weatherNotLiveCount += 1
        }
        if diagnostics.elevationSource != EnvironmentalDataSource.liveAPI.rawValue {
            snapshot.elevationNotLiveCount += 1
        }

        snapshot.mostRecentDiagnostics.insert(diagnostics, at: 0)
        if snapshot.mostRecentDiagnostics.count > maxRecentDiagnostics {
            snapshot.mostRecentDiagnostics = Array(snapshot.mostRecentDiagnostics.prefix(maxRecentDiagnostics))
        }

        save()
    }

    func reset() {
        snapshot = RecommendationHealthSnapshot()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    func updateRequestDuration(correlationId: String, durationMs: Int) {
        guard let idx = snapshot.mostRecentDiagnostics.firstIndex(where: { $0.correlationId == correlationId }) else {
            return
        }
        snapshot.mostRecentDiagnostics[idx].requestDurationMs = durationMs
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(RecommendationHealthSnapshot.self, from: data) else {
            snapshot = RecommendationHealthSnapshot()
            return
        }
        snapshot = decoded
    }

    private func save() {
        let latest = snapshot
        Task.detached(priority: .utility) { [storageKey] in
            guard let encoded = try? JSONEncoder().encode(latest) else { return }
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
