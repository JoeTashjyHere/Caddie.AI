//
//  CaddieViewModel.swift
//  Caddie.ai
//
//  ViewModel managing Caddie session, course/hole selection, and auto-hole tracking

import Foundation
import SwiftUI
import CoreLocation
import Combine
import MapKit

@MainActor
class CaddieViewModel: ObservableObject {
    @Published var session: CaddieSession
    @Published var pendingHoleSuggestion: Int? // Suggested hole number when auto-tracking detects movement
    @Published var isDetectingHole: Bool = false
    
    private let locationService: LocationService
    private let courseService: CourseService
    private var cancellables = Set<AnyCancellable>()
    private var holeDetectionTask: Task<Void, Never>?
    
    init(session: CaddieSession = CaddieSession(), 
         locationService: LocationService? = nil,
         courseService: CourseService? = nil) {
        self.session = session
        self.locationService = locationService ?? LocationService.shared
        self.courseService = courseService ?? CourseService.shared
        
        // Load saved session
        loadSession()
        
        // Subscribe to location updates for auto-hole tracking
        setupLocationSubscription()
    }
    
    // MARK: - Session Management
    
    func setAutoHoleTrackingEnabled(_ enabled: Bool) {
        session.autoHoleTrackingEnabled = enabled
        saveSession()
        
        if enabled {
            setupLocationSubscription()
            checkCurrentHole()
        } else {
            cancellables.removeAll()
            pendingHoleSuggestion = nil
        }
    }
    
    func selectCourse(_ course: Course) {
        session.course = course
        saveSession()
        
        // If auto-tracking is enabled, try to detect current hole
        if session.autoHoleTrackingEnabled {
            checkCurrentHole()
        }
    }
    
    func selectHole(_ holeNumber: Int) {
        session.currentHoleNumber = holeNumber
        pendingHoleSuggestion = nil
        saveSession()
    }
    
    func acceptHoleSuggestion() {
        if let suggestedHole = pendingHoleSuggestion {
            selectHole(suggestedHole)
        }
    }
    
    func dismissHoleSuggestion() {
        pendingHoleSuggestion = nil
    }
    
    // MARK: - GPS Course Detection
    
    func refreshCourseFromGPS() async {
        guard let location = locationService.coordinate else {
            return
        }
        
        do {
            let courses = try await courseService.getNearbyCourses(at: location)
            if let nearestCourse = courses.first {
                selectCourse(nearestCourse)
            }
        } catch {
            print("Error fetching course from GPS: \(error)")
        }
    }
    
    // MARK: - Auto-Hole Tracking
    
    private func setupLocationSubscription() {
        guard session.autoHoleTrackingEnabled else { return }
        
        // Subscribe to location updates
        locationService.$coordinate
            .compactMap { $0 }
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] coordinate in
                self?.checkCurrentHole(at: coordinate)
            }
            .store(in: &cancellables)
    }
    
    private func checkCurrentHole() {
        guard let location = locationService.coordinate else { return }
        checkCurrentHole(at: location)
    }
    
    private func checkCurrentHole(at coordinate: CLLocationCoordinate2D) {
        guard session.autoHoleTrackingEnabled,
              let course = session.course else {
            return
        }
        
        // Cancel previous detection task
        holeDetectionTask?.cancel()
        
        isDetectingHole = true
        holeDetectionTask = Task {
            defer { isDetectingHole = false }
            
            // Fetch hole layout for the course
            do {
                // Try to get hole layout from CourseMapperService
                let courseId = course.id
                var detectedHole: Int? = nil
                var minDistance: Double = Double.greatestFiniteMagnitude
                
                // Check holes 1-18
                for holeNumber in 1...18 {
                    do {
                        let layoutResponse = try await CourseMapperService.shared.fetchHoleLayout(
                            courseId: courseId,
                            holeNumber: holeNumber
                        )
                        
                        // Convert to HoleLayout
                        let holeLayout = HoleLayout(from: layoutResponse)
                        
                        // Check distance to green center
                        if let greenCenter = holeLayout.greenCenter {
                            let distance = calculateDistance(
                                from: coordinate,
                                to: greenCenter
                            )
                            
                            // If within 50 yards of green center, consider this the current hole
                            if distance < 50 && distance < minDistance {
                                minDistance = distance
                                detectedHole = holeNumber
                            }
                        }
                        
                        // Also check if coordinate is within any green polygon
                        for greenPolygon in holeLayout.greenPolygons {
                            if isCoordinateInPolygon(coordinate, polygon: greenPolygon) {
                                let distance = calculateDistance(
                                    from: coordinate,
                                    to: greenPolygon.points()[0].coordinate
                                )
                                if distance < minDistance {
                                    minDistance = distance
                                    detectedHole = holeNumber
                                }
                            }
                        }
                    } catch {
                        // Hole layout not available, continue to next hole
                        continue
                    }
                }
                
                // If we detected a different hole than current, suggest it
                if let detectedHole = detectedHole,
                   detectedHole != session.currentHoleNumber {
                    await MainActor.run {
                        self.pendingHoleSuggestion = detectedHole
                    }
                }
            } catch {
                // Fail gracefully - auto-hole tracking requires geometry data
                print("Auto-hole tracking: Unable to fetch hole geometry: \(error)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLoc = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLoc.distance(from: toLoc) * 1.09361 // Convert meters to yards
    }
    
    private func isCoordinateInPolygon(_ coordinate: CLLocationCoordinate2D, polygon: MKPolygon) -> Bool {
        // Simple point-in-polygon check using ray casting algorithm
        let point = MKMapPoint(coordinate)
        let points = polygon.points()
        var inside = false
        
        var j = polygon.pointCount - 1
        for i in 0..<polygon.pointCount {
            let pi = points[i]
            let pj = points[j]
            
            if ((pi.y > point.y) != (pj.y > point.y)) &&
               (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
    
    // Helper to get closest hole by distance (fallback if geometry not available)
    private func getClosestHoleByDistance(coordinate: CLLocationCoordinate2D, course: Course) async -> Int? {
        // This is a fallback - if we can't get geometry, we can't determine hole
        // In production, you might use course layout or other heuristics
        return nil
    }
    
    // MARK: - Persistence
    
    private func saveSession() {
        if let encoded = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(encoded, forKey: "CaddieSession")
        }
    }
    
    private func loadSession() {
        if let data = UserDefaults.standard.data(forKey: "CaddieSession"),
           let decoded = try? JSONDecoder().decode(CaddieSession.self, from: data) {
            session = decoded
        }
    }
}

