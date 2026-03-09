//
//  CaddieContextDraft.swift
//  Caddie.ai
//
//  Draft context data collected during the Caddie flow

import Foundation

struct CaddieContextDraft: Equatable {
    var course: Course?
    var holeNumber: Int?
    var distanceYards: Double?
    var shotType: ShotType = .approach
    var lie: String?
    var isOnGreenOverride: Bool? = nil
    var courseName: String? = nil  // Required: Course name (manual entry)
    var city: String? = nil  // Required: City
    var state: String? = nil  // Required: State (2-letter or full name)
    var hazards: String? = nil  // User-entered hazards description
    
    init(course: Course? = nil,
         holeNumber: Int? = nil,
         distanceYards: Double? = nil,
         shotType: ShotType = .approach,
         lie: String? = nil,
         isOnGreenOverride: Bool? = nil,
         courseName: String? = nil,
         city: String? = nil,
         state: String? = nil,
         hazards: String? = nil) {
        self.course = course
        self.holeNumber = holeNumber
        self.distanceYards = distanceYards
        self.shotType = shotType
        self.lie = lie
        self.isOnGreenOverride = isOnGreenOverride
        self.courseName = courseName
        self.city = city
        self.state = state
        self.hazards = hazards
    }
    
    // Helper to check if required fields are filled
    var hasRequiredFields: Bool {
        let courseNameValid = courseName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let cityValid = city?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let stateValid = state?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return courseNameValid && cityValid && stateValid
    }
}

