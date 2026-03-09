//
//  CourseInsights.swift
//  Caddie.ai
//
//  Model for course intelligence data
//

import Foundation

struct CourseInsights: Codable {
    let courseId: String
    let mostPlayedHoles: [Int]
    let trickyHoles: [TrickyHole]
    let clubInsights: [ClubInsight]
    let aiNotes: [String]
    let holeDetails: [HoleDetail]
    
    struct TrickyHole: Codable, Identifiable {
        let hole: Int
        let avgOverPar: String
        let note: String
        
        var id: Int { hole }
    }
    
    struct ClubInsight: Codable, Identifiable {
        let club: String
        let avg: Int
        let profile: Int
        let note: String
        
        var id: String { club }
    }
    
    struct HoleDetail: Codable, Identifiable {
        let hole: Int
        let shots: [HoleShot]
        
        var id: Int { hole }
    }
    
    struct HoleShot: Codable, Identifiable {
        let id: String
        let timestamp: String?
        let shotType: String
        let recommendation: PhotoRecommendation?
        let userFeedback: String?
        let imageUrl: String?
        let club: String?
        let distance: Int?
        let shotContext: PhotoShotContext?
        
        var date: Date? {
            guard let timestamp else { return nil }
            return ISO8601DateFormatter().date(from: timestamp)
        }
    }
}

