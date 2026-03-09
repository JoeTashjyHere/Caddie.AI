//
//  CaddieShotViewModelTests.swift
//  Caddie.aiTests
//
//  Tests for CaddieShotViewModel: ShotContext building, classification, auto-hole tracking.

import XCTest
@testable import Caddie_ai
import CoreLocation

@MainActor
final class CaddieShotViewModelTests: XCTestCase {
    
    func testCanGetRecommendationRequiresPhotoAndDistance() {
        let vm = CaddieShotViewModel()
        
        XCTAssertFalse(vm.canGetRecommendation)
        
        vm.setPhoto(UIImage())
        XCTAssertFalse(vm.canGetRecommendation)
        
        vm.setPhoto(nil)
        vm.setTargetDistance(150)
        XCTAssertFalse(vm.canGetRecommendation)
        
        vm.setPhoto(UIImage())
        vm.setTargetDistance(150)
        XCTAssertTrue(vm.canGetRecommendation)
    }
    
    func testCanGetRecommendationRejectsZeroDistance() {
        let vm = CaddieShotViewModel()
        vm.setPhoto(UIImage())
        vm.setTargetDistance(0)
        XCTAssertFalse(vm.canGetRecommendation)
        
        vm.setTargetDistance(150)
        XCTAssertTrue(vm.canGetRecommendation)
    }
    
    func testSelectCourseAndHoleUpdatesState() {
        let vm = CaddieShotViewModel()
        let course = Course(id: "test-1", name: "Test Course", par: 72)
        
        vm.selectCourse(course)
        XCTAssertEqual(vm.currentCourse?.id, "test-1")
        XCTAssertEqual(vm.currentCourse?.name, "Test Course")
        
        vm.selectHole(5)
        XCTAssertEqual(vm.currentHoleNumber, 5)
    }
    
    func testNewShotResetsState() {
        let vm = CaddieShotViewModel()
        vm.setPhoto(UIImage())
        vm.setTargetDistance(150)
        vm.recommendationResult = .fullShot(ShotRecommendation(
            club: "7i",
            narrative: "Test",
            confidence: 0.8
        ))
        
        vm.newShot()
        
        XCTAssertNil(vm.currentPhoto)
        XCTAssertNil(vm.targetDistanceYards)
        XCTAssertNil(vm.recommendationResult)
        XCTAssertNil(vm.lastShotContext)
    }
    
    func testLieClassificationStubReturnsSensibleDefaults() async {
        let service = LieClassificationService.shared
        let image = UIImage()
        
        let result = await service.classify(image: image)
        
        XCTAssertTrue(["Fairway", "Rough", "Bunker", "Tee", "Green", "Woods", "First Cut"].contains(result.lieType.displayName))
        XCTAssertGreaterThanOrEqual(result.confidence, 0)
        XCTAssertLessThanOrEqual(result.confidence, 1)
    }
    
    func testLieTypeDisplayNames() {
        XCTAssertEqual(LieType.fairway.displayName, "Fairway")
        XCTAssertEqual(LieType.bunker.displayName, "Bunker")
        XCTAssertEqual(LieType.green.displayName, "Green")
        XCTAssertEqual(LieType.rough.displayName, "Rough")
    }
    
    func testCaddieRecommendationResultCases() {
        let rec = ShotRecommendation(club: "7i", narrative: "Test", confidence: 0.8)
        let read = PuttingRead(
            breakDirection: "Right",
            breakAmount: 2.0,
            speed: "Medium",
            narrative: "Test putt"
        )
        
        let fullShot = CaddieRecommendationResult.fullShot(rec)
        let putt = CaddieRecommendationResult.putt(read)
        
        switch fullShot {
        case .fullShot(let r): XCTAssertEqual(r.club, "7i")
        case .putt: XCTFail("Expected fullShot")
        }
        
        switch putt {
        case .fullShot: XCTFail("Expected putt")
        case .putt(let r): XCTAssertEqual(r.breakDirection, "Right")
        }
    }
}
