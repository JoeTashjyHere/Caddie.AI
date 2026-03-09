//
//  LocationService.swift
//  Caddie.ai
//

import Foundation
import CoreLocation
import Combine

@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUpdatingLocation: Bool = false
    
    // Identifier that changes when coordinate changes (for onChange triggers)
    var coordinateIdentifier: String {
        coordinate?.latitude.description ?? "none"
    }
    
    // Helper to check if we have a valid location
    var hasValidLocation: Bool {
        lastLocation != nil
    }
    
    private let locationManager = CLLocationManager()
    private var locationUpdateTimer: Timer?
    private var simulatorMockTimer: Timer?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
        
        // Check if running in simulator and inject mock location if needed
        #if targetEnvironment(simulator)
        setupSimulatorLocation()
        #endif
    }
    
    // MARK: - Simulator Location Injection
    
    #if targetEnvironment(simulator)
    private func setupSimulatorLocation() {
        // If no location is received within 2 seconds, inject Pebble Beach mock location
        simulatorMockTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.lastLocation == nil && self?.authorizationStatus == .authorizedWhenInUse {
                    let pebbleBeach = CLLocation(
                        latitude: 36.5703,
                        longitude: -121.9480
                    )
                    print("📍 Simulator detected — using mock Pebble Beach location.")
                    self?.handleLocationUpdate(pebbleBeach)
                }
            }
        }
    }
    #endif
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        guard authorizationStatus == .notDetermined else {
            // Already determined, start updating if authorized
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                startUpdating()
            }
            return
        }
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Location Updates
    
    func startUpdating() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            // Request authorization first
            requestAuthorization()
            return
        }
        
        guard !isUpdatingLocation else { return }
        
        locationManager.startUpdatingLocation()
        isUpdatingLocation = true
        
        // Stop updating after 30 seconds if we have a location
        locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.lastLocation != nil {
                    self?.stopUpdating()
                }
            }
        }
        
        #if targetEnvironment(simulator)
        // In simulator, inject location after 1 second if not received
        simulatorMockTimer?.invalidate()
        simulatorMockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.lastLocation == nil {
                    let pebbleBeach = CLLocation(
                        latitude: 36.5703,
                        longitude: -121.9480
                    )
                    print("📍 Simulator detected — using mock Pebble Beach location.")
                    self?.handleLocationUpdate(pebbleBeach)
                }
            }
        }
        #endif
    }
    
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        isUpdatingLocation = false
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
    }
    
    // MARK: - Location Update Handler
    
    private func handleLocationUpdate(_ location: CLLocation) {
        lastLocation = location
        coordinate = location.coordinate
        
        // Stop updating if we have a good location
        if location.horizontalAccuracy > 0 && location.horizontalAccuracy < 100 {
            stopUpdating()
        }
        
        // Cancel simulator mock timer
        simulatorMockTimer?.invalidate()
        simulatorMockTimer = nil
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                handleLocationUpdate(location)
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("📍 Location error: \(error.localizedDescription)")
            // Don't stop updating on error - might be temporary
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let oldStatus = authorizationStatus
            authorizationStatus = manager.authorizationStatus
            
            // Handle authorization changes
            switch authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if oldStatus != authorizationStatus {
                    // Authorization just granted, start updating
                    startUpdating()
                }
            case .denied, .restricted:
                stopUpdating()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}
