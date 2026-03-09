//
//  ShotFlowState.swift
//  Caddie.ai
//
//  Shot pipeline state machine for robust shot flow handling
//

import Foundation

/// State machine for shot recommendation pipeline
enum ShotFlowState: Equatable {
    case idle
    case waitingForPhoto
    case sendingToAI
    case waitingForRecommendation
    case showingRecommendation
    case recommendationAccepted
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .idle, .error, .recommendationAccepted:
            return false
        default:
            return true
        }
    }
    
    var canAcceptRecommendation: Bool {
        self == .showingRecommendation
    }
    
    var isLoading: Bool {
        switch self {
        case .sendingToAI, .waitingForRecommendation:
            return true
        default:
            return false
        }
    }
}

