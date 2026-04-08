//
//  Persistence.swift
//  Caddie.ai
//

import Foundation

class Persistence {
    static let shared = Persistence()
    
    private let profileKey = "SavedPlayerProfile"
    
    private init() {}
    
    func saveProfile(_ profile: PlayerProfile) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)
        UserDefaults.standard.set(data, forKey: profileKey)
        UserDefaults.standard.synchronize()
    }
    
    func loadProfile() -> PlayerProfile? {
        guard let data = UserDefaults.standard.data(forKey: profileKey) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(PlayerProfile.self, from: data)
    }
}


@MainActor
final class UserProfileStore: ObservableObject {
    @Published var profile: UserProfile = UserProfile()
    @Published var isOnboardingComplete: Bool = false

    private let profileKey = "caddie_user_profile"
    private let onboardingKey = "caddie_onboarding_complete"
    private let legacyProfileKey = "SavedPlayerProfile"

    init() {
        load()
    }

    func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decoded
        } else if let migrated = migrateLegacyProfile() {
            profile = migrated
            save()
        } else {
            profile = UserProfile()
        }

        let storedComplete = defaults.bool(forKey: onboardingKey)
        isOnboardingComplete = storedComplete && validateRequiredFields(profile)
        if storedComplete != isOnboardingComplete {
            defaults.set(isOnboardingComplete, forKey: onboardingKey)
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        if let encoded = try? JSONEncoder().encode(profile) {
            defaults.set(encoded, forKey: profileKey)
        }

        let completion = validateRequiredFields(profile)
        isOnboardingComplete = completion
        defaults.set(completion, forKey: onboardingKey)
    }

    func resetOnboarding() {
        profile = UserProfile()
        isOnboardingComplete = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: profileKey)
        defaults.set(false, forKey: onboardingKey)
    }

    func updateProfile(_ updates: (inout UserProfile) -> Void) {
        updates(&profile)
        save()
    }

    func validateRequiredFields(_ profile: UserProfile) -> Bool {
        let firstNameValid = !profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRequiredClubs = hasRequiredClubSet(profile.clubDistances)
        return firstNameValid && hasRequiredClubs
    }

    func ensureRequiredClubRows() {
        var clubs = profile.clubDistances
        let required: [ClubType] = [.driver, .iron7]

        for clubType in required where !clubs.contains(where: { $0.clubTypeId == clubType.rawValue }) {
            clubs.append(ClubDistance(clubTypeId: clubType.rawValue, distanceYards: 0))
        }

        profile.clubDistances = clubs
        save()
    }

    private func hasRequiredClubSet(_ clubs: [ClubDistance]) -> Bool {
        let ids = Set(clubs.map { $0.clubTypeId })
        let hasDriver = ids.contains(ClubType.driver.rawValue)
        let has7Iron = ids.contains(ClubType.iron7.rawValue)
        let driverHasDistance = clubs.first { $0.clubTypeId == ClubType.driver.rawValue }?.distanceYards ?? 0 > 0
        let ironHasDistance = clubs.first { $0.clubTypeId == ClubType.iron7.rawValue }?.distanceYards ?? 0 > 0
        return hasDriver && has7Iron && driverHasDistance && ironHasDistance
    }

    private func migrateLegacyProfile() -> UserProfile? {
        let defaults = UserDefaults.standard
        guard let legacyData = defaults.data(forKey: legacyProfileKey),
              let legacy = try? JSONDecoder().decode(PlayerProfile.self, from: legacyData) else {
            return nil
        }

        return UserProfile(
            firstName: legacy.name.components(separatedBy: " ").first ?? "",
            lastName: legacy.name.components(separatedBy: " ").dropFirst().joined(separator: " ").isEmpty ? nil : legacy.name.components(separatedBy: " ").dropFirst().joined(separator: " "),
            email: "",
            phone: nil,
            averageScore: nil,
            yearsPlaying: nil,
            golfGoal: legacy.golfGoal,
            seriousness: nil,
            riskOffTee: nil,
            riskAroundHazards: nil,
            greenRiskPreference: legacy.greenRiskPreference.displayName,
            puttingTendencies: legacy.puttingTendencies,
            clubDistances: legacy.clubs,
            shotPreferencesByClub: Dictionary(uniqueKeysWithValues: legacy.clubs.map { ($0.name, $0.preferredShotShape.rawValue.capitalized) })
        )
    }
}

@MainActor
final class UserIdentityStore: ObservableObject {
    @Published private(set) var currentUserId: String

    private let key = "caddie_user_id"

    init() {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            currentUserId = existing
        } else {
            let created = UUID().uuidString
            defaults.set(created, forKey: key)
            currentUserId = created
        }
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var currentSessionId: String = UUID().uuidString
}
