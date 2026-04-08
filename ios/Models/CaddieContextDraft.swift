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
    /// Backend course id (e.g. from `ActiveRoundContext`).
    var courseId: String?
    /// Par for the active hole (from course context).
    var holePar: Int?
    var teeName: String?
    /// Text-only recommendation (no camera image).
    var quickModeNoPhoto: Bool = false
    /// When true, city/state are not required (round has verified `courseId`).
    var isRoundBackedContext: Bool = false
    
    init(course: Course? = nil,
         holeNumber: Int? = nil,
         distanceYards: Double? = nil,
         shotType: ShotType = .approach,
         lie: String? = nil,
         isOnGreenOverride: Bool? = nil,
         courseName: String? = nil,
         city: String? = nil,
         state: String? = nil,
         hazards: String? = nil,
         courseId: String? = nil,
         holePar: Int? = nil,
         teeName: String? = nil,
         quickModeNoPhoto: Bool = false,
         isRoundBackedContext: Bool = false) {
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
        self.courseId = courseId
        self.holePar = holePar
        self.teeName = teeName
        self.quickModeNoPhoto = quickModeNoPhoto
        self.isRoundBackedContext = isRoundBackedContext
    }
    
    /// Helper for legacy checks — backend course id is required for recommendations.
    var hasRequiredFields: Bool {
        let courseNameValid = courseName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let courseIdValid = courseId.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        return courseNameValid && courseIdValid
    }
}

/// Structured input for text-only putting analysis (no photo required).
struct PuttingContext: Codable, Equatable {
    let courseId: String
    let courseName: String
    let holeNumber: Int?
    let distanceFeet: Double
    let slope: String?
    let greenSpeed: String?
    let holePar: Int?

    init(courseId: String, courseName: String, holeNumber: Int?, distanceFeet: Double, slope: String? = nil, greenSpeed: String? = nil, holePar: Int? = nil) {
        self.courseId = courseId
        self.courseName = courseName
        self.holeNumber = holeNumber
        self.distanceFeet = distanceFeet
        self.slope = slope
        self.greenSpeed = greenSpeed
        self.holePar = holePar
    }

    init?(from draft: CaddieContextDraft) {
        guard let cid = draft.courseId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty,
              let name = draft.courseName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let distFeet: Double = {
            if let yards = draft.distanceYards { return yards * 3 }
            return 0
        }()
        self.courseId = cid
        self.courseName = name
        self.holeNumber = draft.holeNumber
        self.distanceFeet = distFeet
        self.slope = nil
        self.greenSpeed = nil
        self.holePar = draft.holePar
    }
}

