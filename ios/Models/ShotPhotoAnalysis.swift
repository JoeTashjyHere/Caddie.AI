//
//  ShotPhotoAnalysis.swift
//  Caddie.ai
//
//  Analysis result from photo (AI vision or photo endpoint)

import Foundation

struct ShotPhotoAnalysis: Codable, Equatable {
    var isOnGreen: Bool
    var lie: String?
    var confidence: Double?
    
    init(isOnGreen: Bool = false, lie: String? = nil, confidence: Double? = nil) {
        self.isOnGreen = isOnGreen
        self.lie = lie
        self.confidence = confidence
    }
}


