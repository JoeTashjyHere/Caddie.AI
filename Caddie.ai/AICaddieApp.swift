//
//  AICaddieApp.swift
//  Caddie.ai
//
//  App entry point for AI Caddie
//

import SwiftUI

@main
struct AICaddieApp: App {
    @StateObject private var locationService = LocationService.shared
    @StateObject private var profileViewModel = ProfileViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationService)
                .environmentObject(profileViewModel)
        }
    }
}

