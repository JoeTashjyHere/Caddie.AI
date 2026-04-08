//
//  AILogger.swift
//  Caddie.ai
//
//  Centralized logging utility for AI-related operations
//

import Foundation

@MainActor
class AILogger {
    static let shared = AILogger()
    
    private init() {}
    
    /// Logs an AI request with truncated response for debugging
    func logRequest(endpoint: String, payload: [String: Any], response: String?, error: Error? = nil) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🤖 AI Request [\(timestamp)]")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Endpoint: \(endpoint)")
        
        // Log payload (truncated if too long)
        if let payloadJSON = try? JSONSerialization.data(withJSONObject: payload),
           let payloadString = String(data: payloadJSON, encoding: .utf8) {
            let truncatedPayload = truncateString(payloadString, maxLength: 500)
            print("📤 Payload: \(truncatedPayload)")
        }
        
        if let error = error {
            print("❌ Error: \(error.localizedDescription)")
            if let apiError = error as? APIError {
                print("   Type: \(apiError)")
            }
        } else if let response = response {
            let truncatedResponse = truncateString(response, maxLength: 500)
            print("📥 Response: \(truncatedResponse)")
        } else {
            print("⚠️  No response or error")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Logs a photo upload request
    func logPhotoUpload(courseId: String, holeNumber: Int, shotType: String, success: Bool, error: Error? = nil) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📸 Photo Upload [\(timestamp)]")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Course: \(courseId)")
        print("📍 Hole: \(holeNumber)")
        print("📍 Shot Type: \(shotType)")
        print(success ? "✅ Success" : "❌ Failed")
        
        if let error = error {
            print("   Error: \(error.localizedDescription)")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Logs a parsing error with context
    func logParsingError(endpoint: String, rawResponse: String, error: Error) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⚠️  Parsing Error [\(timestamp)]")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Endpoint: \(endpoint)")
        print("❌ Error: \(error.localizedDescription)")
        let truncatedResponse = truncateString(rawResponse, maxLength: 300)
        print("📥 Raw Response: \(truncatedResponse)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    /// Helper to truncate long strings
    private func truncateString(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        let truncated = String(string.prefix(maxLength))
        return "\(truncated)... [truncated \(string.count - maxLength) chars]"
    }
}

