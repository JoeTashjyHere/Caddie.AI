//
//  ProfileViewModel.swift
//  Caddie.ai
//
//  View model for the Profile tab
//

import Foundation

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var profile: PlayerProfile
    
    init() {
        // Load from persistence or use default
        if let savedProfile = Persistence.shared.loadProfile() {
            self.profile = savedProfile
        } else {
            self.profile = PlayerProfile()
        }
    }
    
    func saveProfile() {
        do {
            try Persistence.shared.saveProfile(profile)
        } catch {
            print("Error saving profile: \(error)")
        }
    }
}

