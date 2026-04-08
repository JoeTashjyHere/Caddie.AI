//
//  LocationService.swift
//  Caddie.ai
//

import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()
    
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var lastLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUpdatingLocation: Bool = false
    
    /// When true, location updates run continuously (no auto-stop).
    /// Used during active rounds for live distance tracking.
    @Published var continuousMode: Bool = false
    
    var coordinateIdentifier: String {
        guard let c = coordinate else { return "none" }
        return "\(c.latitude),\(c.longitude)"
    }
    
    var hasValidLocation: Bool {
        lastLocation != nil
    }
    
    private let locationManager = CLLocationManager()
    private var locationUpdateTimer: Timer?
    private var simulatorMockTimer: Timer?
    /// Watchdog that fires if no location update is received for too long during continuous mode.
    private var continuousWatchdog: Timer?
    /// Tracks the last time we received a location update (for staleness detection).
    private var lastUpdateTime: Date?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        #if targetEnvironment(simulator)
        setupSimulatorLocation()
        #endif
    }
    
    @objc private func appDidBecomeActive() {
        Task { @MainActor in
            if continuousMode {
                locationLog("App foregrounded — ensuring continuous updates")
                ensureContinuousUpdatesRunning()
            }
        }
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
            requestAuthorization()
            return
        }
        
        guard !isUpdatingLocation else { return }
        
        locationManager.startUpdatingLocation()
        isUpdatingLocation = true
        
        if !continuousMode {
            locationUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    if self?.lastLocation != nil, self?.continuousMode == false {
                        self?.stopUpdating()
                    }
                }
            }
        }
        
        #if targetEnvironment(simulator)
        simulatorMockTimer?.invalidate()
        simulatorMockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.lastLocation == nil {
                    let pebbleBeach = CLLocation(latitude: 36.5703, longitude: -121.9480)
                    self?.handleLocationUpdate(pebbleBeach)
                }
            }
        }
        #endif
    }
    
    /// Begin continuous location updates for active round play.
    /// Does not auto-stop — caller must call `stopContinuousUpdating()` when done.
    /// Includes a watchdog that auto-restarts updates if they stall.
    func startContinuousUpdating() {
        continuousMode = true
        locationUpdateTimer?.invalidate()
        locationUpdateTimer = nil
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 3
        applyBackgroundLocationSettings(enabled: true)
        lastUpdateTime = Date()

        if !isUpdatingLocation {
            locationManager.startUpdatingLocation()
            isUpdatingLocation = true
            locationLog("Continuous updates started")
        }

        startContinuousWatchdog()
    }
    
    func stopContinuousUpdating() {
        locationLog("Continuous updates stopped")
        continuousMode = false
        continuousWatchdog?.invalidate()
        continuousWatchdog = nil
        applyBackgroundLocationSettings(enabled: false)
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        stopUpdating()
    }

    /// Restart CLLocationManager updates if they have silently stopped.
    private func ensureContinuousUpdatesRunning() {
        guard continuousMode else { return }
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 3
        applyBackgroundLocationSettings(enabled: true)
        if !isUpdatingLocation {
            locationLog("Restarting location updates (were stopped)")
            locationManager.startUpdatingLocation()
            isUpdatingLocation = true
        }
        startContinuousWatchdog()
    }

    /// Periodic check: if no update received in 15s during continuous mode, force restart.
    private func startContinuousWatchdog() {
        continuousWatchdog?.invalidate()
        continuousWatchdog = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.continuousMode else { return }
                let stale = self.lastUpdateTime.map { Date().timeIntervalSince($0) > 12 } ?? true
                if stale {
                    self.locationLog("Watchdog: no update in >12s — forcing restart")
                    self.locationManager.stopUpdatingLocation()
                    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                    self.locationManager.distanceFilter = 3
                    self.locationManager.startUpdatingLocation()
                    self.isUpdatingLocation = true
                }
                if let loc = self.lastLocation, loc.horizontalAccuracy > 20 {
                    self.locationLog("Watchdog: accuracy degraded (\(String(format: "%.0f", loc.horizontalAccuracy))m) — requesting best")
                    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
                }
            }
        }
    }

    /// Whether the app bundle declares background location in UIBackgroundModes.
    /// Setting `allowsBackgroundLocationUpdates` without this capability crashes at runtime.
    private lazy var appSupportsBackgroundLocation: Bool = {
        guard let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] else { return false }
        return modes.contains("location")
    }()

    private func applyBackgroundLocationSettings(enabled: Bool) {
        guard appSupportsBackgroundLocation else {
            if enabled {
                locationLog("Background location capability not declared — skipping background mode")
            }
            return
        }
        locationManager.allowsBackgroundLocationUpdates = enabled
        locationManager.showsBackgroundLocationIndicator = enabled
    }

    private func locationLog(_ message: String) {
        #if DEBUG
        print("[LOC] \(message)")
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
        let prevAccuracy = lastLocation?.horizontalAccuracy
        lastLocation = location
        coordinate = location.coordinate
        lastUpdateTime = Date()
        
        if continuousMode {
            if let prev = prevAccuracy, abs(location.horizontalAccuracy - prev) > 10 {
                locationLog("Accuracy changed: \(String(format: "%.0f", prev))m → \(String(format: "%.0f", location.horizontalAccuracy))m")
            }
        } else {
            if location.horizontalAccuracy > 0 && location.horizontalAccuracy < 100 {
                stopUpdating()
            }
        }
        
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
            locationLog("Location error: \(error.localizedDescription)")
            if continuousMode {
                locationLog("Attempting restart after error")
                ensureContinuousUpdatesRunning()
            }
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
