//
//  ShotRecommendationScenarioTests.swift
//  Caddie.aiTests
//

import XCTest
@testable import Caddie_ai

@MainActor
final class ShotRecommendationScenarioTests: XCTestCase {
    func testScenarioRunnerProducesDynamicClubChoices() {
        let profile = PlayerProfile(
            name: "Test Golfer",
            clubs: [
                ClubDistance(clubTypeId: ClubType.driver.rawValue, distanceYards: 250, confidenceLevelId: ClubConfidenceLevel.confident.rawValue),
                ClubDistance(clubTypeId: ClubType.iron5.rawValue, distanceYards: 175, confidenceLevelId: ClubConfidenceLevel.notConfident.rawValue),
                ClubDistance(clubTypeId: ClubType.iron7.rawValue, distanceYards: 145, confidenceLevelId: ClubConfidenceLevel.confident.rawValue),
                ClubDistance(clubTypeId: ClubType.iron9.rawValue, distanceYards: 120, confidenceLevelId: ClubConfidenceLevel.veryConfident.rawValue),
                ClubDistance(clubTypeId: ClubType.pitchingWedge.rawValue, distanceYards: 105, confidenceLevelId: ClubConfidenceLevel.veryConfident.rawValue),
                ClubDistance(clubTypeId: ClubType.sandWedge.rawValue, distanceYards: 85, confidenceLevelId: ClubConfidenceLevel.confident.rawValue)
            ]
        )

        let scenarios: [ShotRecommendationScenario] = [
            ShotRecommendationScenario(name: "70y rough obstacle left", distanceYards: 70, lie: "Rough", shotType: "Approach", hazards: ["Trees left"], windMph: 5, windDirDeg: 180, temperatureF: 72, elevationDelta: 0),
            ShotRecommendationScenario(name: "100y fairway calm", distanceYards: 100, lie: "Fairway", shotType: "Approach", hazards: [], windMph: 0, windDirDeg: 0, temperatureF: 72, elevationDelta: 0),
            ShotRecommendationScenario(name: "134y tee no wind", distanceYards: 134, lie: "Tee", shotType: "Drive", hazards: [], windMph: 0, windDirDeg: 0, temperatureF: 70, elevationDelta: 0),
            ShotRecommendationScenario(name: "125y fairway water short", distanceYards: 125, lie: "Fairway", shotType: "Approach", hazards: ["Water short"], windMph: 8, windDirDeg: 0, temperatureF: 68, elevationDelta: 2),
            ShotRecommendationScenario(name: "180y rough low long-iron confidence", distanceYards: 180, lie: "Rough", shotType: "Approach", hazards: ["Bunker right"], windMph: 10, windDirDeg: 20, temperatureF: 65, elevationDelta: 5)
        ]

        let diagnostics = RecommenderService.shared.runScenarioDiagnostics(profile: profile, scenarios: scenarios)

        XCTAssertEqual(diagnostics.count, scenarios.count)
        XCTAssertTrue(diagnostics.allSatisfy { !$0.candidates.isEmpty })

        let uniqueFinalClubs = Set(diagnostics.map { $0.finalClub })
        XCTAssertGreaterThanOrEqual(uniqueFinalClubs.count, 2, "Scenario runner regressed to repeated single-club output")
    }
}
