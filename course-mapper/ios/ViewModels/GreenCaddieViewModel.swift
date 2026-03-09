//
//  GreenCaddieViewModel.swift
//  Caddie.AI iOS Client
//
//  View model for green reading mode
//

import Foundation
import SwiftUI
import Combine

@MainActor
class GreenCaddieViewModel: ObservableObject {
    @Published var greenId: Int
    @Published var ballLat: Double
    @Published var ballLon: Double
    @Published var holeLat: Double
    @Published var holeLon: Double
    
    @Published var readingResponse: GreenReadResponse?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var fetchTask: Task<Void, Never>?
    private var debounceTimer: Timer?
    
    init(greenId: Int, ballLat: Double, ballLon: Double, holeLat: Double, holeLon: Double) {
        self.greenId = greenId
        self.ballLat = ballLat
        self.ballLon = ballLon
        self.holeLat = holeLat
        self.holeLon = holeLon
    }
    
    // Convenience initializer for previews
    convenience init(greenId: Int) {
        self.init(
            greenId: greenId,
            ballLat: 38.8706,
            ballLon: -77.0294,
            holeLat: 38.87061,
            holeLon: -77.02939
        )
    }
    
    func updateBallPosition(lat: Double, lon: Double) {
        ballLat = lat
        ballLon = lon
        debouncedFetch()
    }
    
    func updateHolePosition(lat: Double, lon: Double) {
        holeLat = lat
        holeLon = lon
        debouncedFetch()
    }
    
    func fetchRead() {
        // Cancel any existing task
        fetchTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        let request = GreenReadRequest(
            ballLat: ballLat,
            ballLon: ballLon,
            holeLat: holeLat,
            holeLon: holeLon
        )
        
        fetchTask = Task {
            do {
                let response = try await APIClient.shared.getGreenRead(
                    greenId: greenId,
                    request: request
                )
                
                if !Task.isCancelled {
                    self.readingResponse = response
                    self.isLoading = false
                    self.errorMessage = nil
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    print("Error fetching green read: \(error)")
                }
            }
        }
    }
    
    private func debouncedFetch() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fetchRead()
            }
        }
    }
    
    deinit {
        fetchTask?.cancel()
        debounceTimer?.invalidate()
    }
}

