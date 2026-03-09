//
//  ContentView.swift
//  Caddie.ai
//
//  Main tab view with Play, Putting, and Profile tabs
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var profileViewModel: ProfileViewModel
    
    var body: some View {
        TabView {
            PlayView()
                .tabItem {
                    Label("Play", systemImage: "figure.golf")
                }
            
            PuttingView()
                .tabItem {
                    Label("Putting", systemImage: "camera")
                }
            
            ProfileView()
                .environmentObject(profileViewModel)
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationService.shared)
        .environmentObject(ProfileViewModel())
}
