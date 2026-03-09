//
//  ShotType.swift
//  Caddie.ai
//
//  Shared type describing shot categories (drive, approach, etc.)
//

import Foundation

enum ShotType: String, CaseIterable, Codable, Identifiable {
    case drive = "drive"
    case approach = "approach"
    case chip = "chip"
    case putt = "putt"
    case recovery = "recovery"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .drive: return "Drive"
        case .approach: return "Approach"
        case .chip: return "Chip"
        case .putt: return "Putt"
        case .recovery: return "Recovery"
        }
    }
}

