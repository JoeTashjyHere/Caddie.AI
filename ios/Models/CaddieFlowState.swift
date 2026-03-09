//
//  CaddieFlowState.swift
//  Caddie.ai
//
//  State machine for the unified Caddie flow

import Foundation

enum CaddieFlowState: Equatable {
    case idle                           // CaddieHomeView ready
    case capturingPhoto                 // camera presented
    case confirmingContext              // context sheet presented
    case analyzingShot                  // analyzing photo/lie
    case requestingRecommendation       // network/AI in-flight
    case showingRecommendation          // recommendation displayed
    case requestingPuttingRead          // requesting putting read
    case showingPuttingRead             // putting read displayed
    case error(message: String)         // error UI; user can retry
}

enum ConfidenceLevel: String, Equatable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}


