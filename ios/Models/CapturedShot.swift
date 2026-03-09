//
//  CapturedShot.swift
//  Caddie.ai
//
//  Model for tracking captured shots with photos and recommendations
//

import Foundation
import UIKit

struct CapturedShot: Codable, Identifiable {
    var id: UUID
    var shotType: ShotType
    var club: String?
    var distance: Int?
    var timestamp: Date
    var imageData: Data?
    var imageURL: String? // URL returned from backend after upload
    var recommendation: PhotoRecommendation?
    var shotContext: PhotoShotContext?
    var holeNumber: Int
    var backendId: String?
    var userFeedback: String?
    
    init(id: UUID = UUID(),
         shotType: ShotType,
         club: String? = nil,
         distance: Int? = nil,
         timestamp: Date = Date(),
         imageData: Data? = nil,
         imageURL: String? = nil,
         recommendation: PhotoRecommendation? = nil,
         shotContext: PhotoShotContext? = nil,
         holeNumber: Int,
         backendId: String? = nil,
         userFeedback: String? = nil) {
        self.id = id
        self.shotType = shotType
        self.club = club
        self.distance = distance
        self.timestamp = timestamp
        self.imageData = imageData
        self.imageURL = imageURL
        self.recommendation = recommendation
        self.shotContext = shotContext
        self.holeNumber = holeNumber
        self.backendId = backendId
        self.userFeedback = userFeedback
    }
    
    // Helper to get UIImage from imageData
    var image: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Codable Image Handling

extension CapturedShot {
    enum CodingKeys: String, CodingKey {
        case id, shotType, club, distance, timestamp, imageURL = "imageUrl", recommendation, shotContext, holeNumber, backendId, userFeedback
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        shotType = try container.decode(ShotType.self, forKey: .shotType)
        club = try container.decodeIfPresent(String.self, forKey: .club)
        distance = try container.decodeIfPresent(Int.self, forKey: .distance)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        recommendation = try container.decodeIfPresent(PhotoRecommendation.self, forKey: .recommendation)
        shotContext = try container.decodeIfPresent(PhotoShotContext.self, forKey: .shotContext)
        holeNumber = try container.decode(Int.self, forKey: .holeNumber)
        backendId = try container.decodeIfPresent(String.self, forKey: .backendId)
        userFeedback = try container.decodeIfPresent(String.self, forKey: .userFeedback)
        // imageData is not persisted, only stored in memory
        imageData = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(shotType, forKey: .shotType)
        try container.encodeIfPresent(club, forKey: .club)
        try container.encodeIfPresent(distance, forKey: .distance)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(recommendation, forKey: .recommendation)
        try container.encodeIfPresent(shotContext, forKey: .shotContext)
        try container.encode(holeNumber, forKey: .holeNumber)
        try container.encodeIfPresent(backendId, forKey: .backendId)
        try container.encodeIfPresent(userFeedback, forKey: .userFeedback)
        // imageData is not encoded, only imageURL
    }
}

