//
//  ProfileViewModel.swift
//  Caddie.ai
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

    func applyUserProfile(_ userProfile: UserProfile) {
        profile.name = [userProfile.firstName, userProfile.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        profile.golfGoal = userProfile.golfGoal
        profile.puttingTendencies = userProfile.puttingTendencies ?? ""

        if let greenRisk = userProfile.greenRiskPreference,
           let mapped = GreenRiskPreference(rawValue: greenRisk) {
            profile.greenRiskPreference = mapped
        }

        if !userProfile.clubDistances.isEmpty {
            profile.clubs = userProfile.clubDistances
        }

        saveProfile()
    }

    func reloadFromPersistence() {
        if let savedProfile = Persistence.shared.loadProfile() {
            profile = savedProfile
        }
    }
    
    /// Remove a club from the bag by ID
    func removeClub(withId id: UUID) {
        profile.clubs.removeAll { $0.id == id }
        saveProfile()
    }
    
    /// Remove clubs at specific offsets (for IndexSet-based removal)
    func removeClub(at offsets: IndexSet) {
        profile.clubs.remove(atOffsets: offsets)
        saveProfile()
    }
}
