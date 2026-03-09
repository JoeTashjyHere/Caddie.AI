//
//  GreenRiskPreference.swift
//  Caddie.ai
//
//  Risk preference for putting/green play
//

import Foundation

enum GreenRiskPreference: String, CaseIterable, Codable {
    case aggressive = "Aggressive"
    case lagFocused = "Lag-focused"
    case hybrid = "Hybrid"
    
    var displayName: String {
        return rawValue
    }
}

