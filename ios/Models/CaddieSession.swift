//
//  CaddieSession.swift
//  Caddie.ai
//
//  Lightweight session model for Caddie feature (outside of scoring rounds)

import Foundation

struct CaddieSession: Codable, Equatable {
    var course: Course?
    var currentHoleNumber: Int?
    var autoHoleTrackingEnabled: Bool
    var startedAt: Date
    
    init(course: Course? = nil,
         currentHoleNumber: Int? = nil,
         autoHoleTrackingEnabled: Bool = true,
         startedAt: Date = Date()) {
        self.course = course
        self.currentHoleNumber = currentHoleNumber
        self.autoHoleTrackingEnabled = autoHoleTrackingEnabled
        self.startedAt = startedAt
    }
    
    // Helper to check if session has valid course and hole
    var isReady: Bool {
        course != nil && currentHoleNumber != nil
    }
}


