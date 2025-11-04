//
//  Persistence.swift
//  Caddie.ai
//
//  Persistence service using UserDefaults to save/load PlayerProfile
//

import Foundation

class Persistence {
    static let shared = Persistence()
    private let profileKey = "PlayerProfile"
    
    private init() {}
    
    func saveProfile(_ profile: PlayerProfile) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)
        UserDefaults.standard.set(data, forKey: profileKey)
    }
    
    func loadProfile() -> PlayerProfile? {
        guard let data = UserDefaults.standard.data(forKey: profileKey) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(PlayerProfile.self, from: data)
    }
}

