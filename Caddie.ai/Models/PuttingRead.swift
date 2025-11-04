//
//  PuttingRead.swift
//  Caddie.ai
//
//  Created by Joe Tashjy on 11/4/25.
//

import Foundation

struct PuttingRead: Codable, Identifiable {
    var id: UUID
    var aimInchesRight: Double
    var paceHint: String
    var breakDescription: String
    var confidence: Double
    var notes: String?
    
    init(id: UUID = UUID(),
         aimInchesRight: Double,
         paceHint: String,
         breakDescription: String,
         confidence: Double,
         notes: String? = nil) {
        self.id = id
        self.aimInchesRight = aimInchesRight
        self.paceHint = paceHint
        self.breakDescription = breakDescription
        self.confidence = confidence
        self.notes = notes
    }
}

