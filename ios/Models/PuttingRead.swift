//
//  PuttingRead.swift
//  Caddie.ai
//

import Foundation

/// New structured output format from AI (matches the prompt builder output format)
struct StructuredPuttingRead: Codable {
    let breakDirection: String
    let breakAmount: Double
    let speed: String
    let theLine: String
    let theSpeed: String
    let finalPicture: String
    let commitmentCue: String
    let narrative: String
    
    // New optional fields for varied putting reads
    let headline: String?
    let bullets: [String]?
    
    // Legacy fields for backward compatibility (optional)
    let puttingLine: String?
}

/// Legacy format for backward compatibility and UI display
struct PuttingRead: Codable {
    var breakDirection: String
    var breakAmount: Double
    var speed: String
    var narrative: String
    var puttingLine: String?
    var imageUrl: String?
    
    // New structured fields (optional for backward compatibility)
    var theLine: String?
    var theSpeed: String?
    var finalPicture: String?
    var commitmentCue: String?
    var headline: String?
    var bullets: [String]?
    
    init(breakDirection: String,
         breakAmount: Double,
         speed: String,
         narrative: String,
         puttingLine: String? = nil,
         imageUrl: String? = nil,
         theLine: String? = nil,
         theSpeed: String? = nil,
         finalPicture: String? = nil,
         commitmentCue: String? = nil,
         headline: String? = nil,
         bullets: [String]? = nil) {
        self.breakDirection = breakDirection
        self.breakAmount = breakAmount
        self.speed = speed
        self.narrative = narrative
        self.puttingLine = puttingLine
        self.imageUrl = imageUrl
        self.theLine = theLine
        self.theSpeed = theSpeed
        self.finalPicture = finalPicture
        self.commitmentCue = commitmentCue
        self.headline = headline
        self.bullets = bullets
    }
    
    /// Convert from new structured format
    init(from structured: StructuredPuttingRead) {
        self.breakDirection = structured.breakDirection
        self.breakAmount = structured.breakAmount
        self.speed = structured.speed
        self.narrative = structured.narrative
        self.puttingLine = structured.puttingLine ?? structured.theLine
        self.imageUrl = nil
        self.theLine = structured.theLine
        self.theSpeed = structured.theSpeed
        self.finalPicture = structured.finalPicture
        self.commitmentCue = structured.commitmentCue
        self.headline = structured.headline
        self.bullets = structured.bullets
    }
}

