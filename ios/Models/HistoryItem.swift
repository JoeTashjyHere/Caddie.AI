//
//  HistoryItem.swift
//  Caddie.ai
//
//  Unified model for storing recommendation history (both shot and green reader)
//

import Foundation

enum RecommendationType: String, Codable {
    case shot
    case putt
    
    var displayName: String {
        switch self {
        case .shot: return "Shot Recommendation"
        case .putt: return "Putt Recommendation"
        }
    }
}

struct HistoryWeatherSnapshot: Codable, Equatable {
    let windMph: Double?
    let windDirDeg: Double?
    let tempF: Double?
    let elevationDeltaYards: Double?
}

struct ShotHistoryMetadata: Codable, Equatable {
    let distanceYards: Int?
    let shotType: String?
    let lie: String?
    let clubRecommended: String?
    let courseName: String?
    let holeNumber: Int?
    let hazards: String?
    let weather: HistoryWeatherSnapshot?
    let timestamp: Date
}

struct PuttHistoryMetadata: Codable, Equatable {
    let puttDistanceFeet: Int?
    let breakDirection: String?
    let speedRecommendation: String?
    let greenSlopeInference: String?
    let courseName: String?
    let holeNumber: Int?
    let timestamp: Date
}

enum RecommendationFeedbackReason: String, Codable, CaseIterable, Identifiable {
    case wrongClub = "wrong_club"
    case tooAggressive = "too_aggressive"
    case tooConservative = "too_conservative"
    case badLieRead = "bad_lie_read"
    case badTarget = "bad_target"
    case notClear = "not_clear"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wrongClub: return "Wrong club"
        case .tooAggressive: return "Too aggressive"
        case .tooConservative: return "Too conservative"
        case .badLieRead: return "Bad lie read"
        case .badTarget: return "Bad target"
        case .notClear: return "Not clear"
        case .other: return "Other"
        }
    }
}

struct RecommendationFeedbackRecord: Codable, Equatable {
    let helpful: Bool
    let feedbackReason: RecommendationFeedbackReason?
    let freeTextNote: String?
    let rating: Int?
    let submittedAt: Date
}

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let type: RecommendationType
    let courseName: String?
    let distanceYards: Int?
    let shotType: String?
    let lie: String?
    let hazards: String?
    let recommendationText: String
    let rawAIResponse: String?
    let thumbnailData: Data?
    let recommendationId: String?
    let feedback: RecommendationFeedbackRecord?
    let shotMetadata: ShotHistoryMetadata?
    let puttMetadata: PuttHistoryMetadata?
    
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        type: RecommendationType,
        courseName: String? = nil,
        distanceYards: Int? = nil,
        shotType: String? = nil,
        lie: String? = nil,
        hazards: String? = nil,
        recommendationText: String,
        rawAIResponse: String? = nil,
        thumbnailData: Data? = nil,
        recommendationId: String? = nil,
        feedback: RecommendationFeedbackRecord? = nil,
        shotMetadata: ShotHistoryMetadata? = nil,
        puttMetadata: PuttHistoryMetadata? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.courseName = courseName
        self.distanceYards = distanceYards
        self.shotType = shotType
        self.lie = lie
        self.hazards = hazards
        self.recommendationText = recommendationText
        self.rawAIResponse = rawAIResponse
        self.thumbnailData = thumbnailData
        self.recommendationId = recommendationId
        self.feedback = feedback
        self.shotMetadata = shotMetadata
        self.puttMetadata = puttMetadata
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        
        // Map old types to new RecommendationType
        if let typeString = try container.decodeIfPresent(String.self, forKey: .type) {
            if typeString == "greenRead" {
                type = .putt
            } else if let decoded = RecommendationType(rawValue: typeString) {
                type = decoded
            } else {
                type = .shot
            }
        } else {
            type = .shot
        }
        
        courseName = try container.decodeIfPresent(String.self, forKey: .courseName)
        distanceYards = try container.decodeIfPresent(Int.self, forKey: .distanceYards)
        shotType = try container.decodeIfPresent(String.self, forKey: .shotType)
        lie = try container.decodeIfPresent(String.self, forKey: .lie)
        hazards = try container.decodeIfPresent(String.self, forKey: .hazards)
        recommendationText = try container.decode(String.self, forKey: .recommendationText)
        rawAIResponse = try container.decodeIfPresent(String.self, forKey: .rawAIResponse)
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        recommendationId = try container.decodeIfPresent(String.self, forKey: .recommendationId)
        feedback = try container.decodeIfPresent(RecommendationFeedbackRecord.self, forKey: .feedback)
        shotMetadata = try container.decodeIfPresent(ShotHistoryMetadata.self, forKey: .shotMetadata)
        puttMetadata = try container.decodeIfPresent(PuttHistoryMetadata.self, forKey: .puttMetadata)
    }
}
