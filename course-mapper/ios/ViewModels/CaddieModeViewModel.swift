//
//  CaddieModeViewModel.swift
//  Caddie.AI iOS Client
//
//  View model for Caddie mode root view
//

import Foundation
import SwiftUI

enum CaddieMode: String, CaseIterable {
    case tee = "Tee"
    case approach = "Approach"
    case green = "Green"
}

@MainActor
class CaddieModeViewModel: ObservableObject {
    @Published var selectedMode: CaddieMode = .tee
    @Published var currentCourse: Course?
    @Published var currentHole: Int = 1
    @Published var currentGreenFeatureId: Int?
    
    // Green mode positions
    @Published var ballLat: Double = 38.8706
    @Published var ballLon: Double = -77.0294
    @Published var holeLat: Double = 38.87061
    @Published var holeLon: Double = -77.02939
    
    // Mock course for now
    init() {
        // Set default course (can be loaded from API later)
        currentCourse = Course(
            id: "1",
            name: "East Potomac Golf Links",
            city: "Washington",
            state: "DC",
            country: "USA",
            distanceKm: nil,
            centerLat: 38.8706,
            centerLon: -77.0294
        )
        currentGreenFeatureId = 1
    }
    
    var courseDisplayName: String {
        guard let course = currentCourse else {
            return "No Course Selected"
        }
        var name = course.name
        if let state = course.state {
            name += " – \(state)"
        }
        return name
    }
    
    var holeDisplayInfo: String {
        "Hole \(currentHole)"
    }
}



