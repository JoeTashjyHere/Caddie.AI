//
//  PuttingVisionService.swift
//  Caddie.ai
//
//  Service that sends putting photos to backend vision endpoint
//

import Foundation
import UIKit

class PuttingVisionService {
    static let shared = PuttingVisionService()
    
    private init() {}
    
    func analyzePutting(image: UIImage, weather: WeatherSnapshot) async throws -> PuttingRead {
        // Convert image to JPEG and base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "PuttingVisionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // Build context JSON
        let contextJSON = """
        {
            "windMph": \(weather.windMph),
            "windDirDeg": \(weather.windDirDeg),
            "tempF": \(weather.tempF)
        }
        """
        
        // Call vision endpoint
        let resultJSON = try await OpenAIClient.shared.vision(imageBase64: base64Image, contextJSON: contextJSON)
        
        // Strip markdown code fences if present (e.g., ```json ... ```)
        let cleanedJSON = stripMarkdownCodeFences(resultJSON)
        
        // Parse JSON response
        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw NSError(domain: "PuttingVisionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON string"])
        }
        
        let puttingRead = try JSONDecoder().decode(PuttingRead.self, from: jsonData)
        return puttingRead
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
}

