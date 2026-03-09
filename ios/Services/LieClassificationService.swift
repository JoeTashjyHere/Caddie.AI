//
//  LieClassificationService.swift
//  Caddie.ai
//
//  Vision/ML abstraction for classifying lie type and shot category (putt vs full shot).
//  Stub implementation until backend/ML model exists.

import Foundation
import UIKit

/// Lie types inferred from photo analysis
enum LieType: String, CaseIterable, Codable {
    case fairway
    case rough
    case bunker
    case tee
    case green
    case woods
    case firstCut = "first_cut"
    
    var displayName: String {
        switch self {
        case .fairway: return "Fairway"
        case .rough: return "Rough"
        case .bunker: return "Bunker"
        case .tee: return "Tee"
        case .green: return "Green"
        case .woods: return "Woods"
        case .firstCut: return "First Cut"
        }
    }
    
    /// ShotContext lieType string
    var shotContextString: String { displayName }
}

/// Result of lie classification
struct LieClassificationResult {
    let lieType: LieType
    let isPutt: Bool
    let confidence: Double
}

@MainActor
class LieClassificationService: ObservableObject {
    static let shared = LieClassificationService()
    
    private init() {}
    
    /// Classify image to determine lie type and whether it's a putt.
    /// - Parameter image: Photo of the shot/lie
    /// - Returns: Lie type and putt vs full-shot classification
    func classify(image: UIImage) async -> LieClassificationResult {
        // Stub: Use OpenAI Vision when available, otherwise sensible defaults
        do {
            return try await classifyViaVision(image: image)
        } catch {
            return stubClassification(image: image)
        }
    }
    
    // MARK: - Vision Implementation
    
    private func classifyViaVision(image: UIImage) async throws -> LieClassificationResult {
        let systemPrompt = """
        You are a golf course analysis AI. Analyze this photo and return JSON only with:
        - isOnGreen: boolean (true if ball is on putting green or near hole with putter visible)
        - lie: string (one of: "Fairway", "Rough", "Bunker", "Tee", "Green", "Woods", "First Cut")
        - confidence: number 0-1
        """
        
        let userPrompt = "Analyze this golf photo. Return JSON only with isOnGreen, lie, and confidence."
        
        let jsonString = try await OpenAIClient.shared.completeWithVision(
            system: systemPrompt,
            user: userPrompt,
            image: image
        )
        
        let cleaned = stripMarkdownCodeFences(jsonString)
        guard let data = cleaned.data(using: .utf8) else {
            throw NSError(domain: "LieClassificationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])
        }
        
        struct VisionResponse: Codable {
            let isOnGreen: Bool
            let lie: String?
            let confidence: Double?
        }
        
        let response = try JSONDecoder().decode(VisionResponse.self, from: data)
        let lieRaw = (response.lie ?? "Fairway").lowercased().replacingOccurrences(of: " ", with: "_")
        let lieType: LieType = {
            switch lieRaw {
            case "fairway": return .fairway
            case "rough": return .rough
            case "bunker": return .bunker
            case "tee": return .tee
            case "green": return .green
            case "woods": return .woods
            case "first_cut", "firstcut": return .firstCut
            default: return .fairway
            }
        }()
        let confidence = response.confidence ?? 0.7
        
        return LieClassificationResult(
            lieType: lieType,
            isPutt: response.isOnGreen,
            confidence: confidence
        )
    }
    
    private func stubClassification(image: UIImage) -> LieClassificationResult {
        // Sensible default: assume fairway full shot when vision unavailable
        LieClassificationResult(
            lieType: .fairway,
            isPutt: false,
            confidence: 0.5
        )
    }
    
    private func stripMarkdownCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            if let idx = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: idx)...])
            } else {
                result = result.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            }
        }
        if result.hasSuffix("```") {
            result = String(result.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
