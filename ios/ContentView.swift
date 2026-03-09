//
//  ContentView.swift
//  Caddie.ai
//

import SwiftUI

struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var selectedTab: Binding<Int> {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
}

struct ContentView: View {
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var courseService: CourseService
    @EnvironmentObject var feedbackService: FeedbackService
    @EnvironmentObject var historyStore: HistoryStore
    @EnvironmentObject var userProfileStore: UserProfileStore

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CaddieHomeView()
                .environmentObject(locationService)
                .environmentObject(profileViewModel)
                .environmentObject(scoreTrackingService)
                .environmentObject(feedbackService)
                .environmentObject(courseService)
                .environmentObject(historyStore)
                .environmentObject(userProfileStore)
                .environment(\.selectedTab, $selectedTab)
                .tabItem {
                    Label("Caddie", systemImage: "camera.viewfinder")
                }
                .tag(0)

            HistoryView()
                .environmentObject(scoreTrackingService)
                .environmentObject(profileViewModel)
                .environmentObject(historyStore)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            ProfileView()
                .environmentObject(profileViewModel)
                .environmentObject(userProfileStore)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(2)
        }
        .accentColor(GolfTheme.grassGreen)
        .onAppear {
            checkPhaseAndRedirect()
        }
        .onChange(of: scoreTrackingService.phase) { _, _ in
            checkPhaseAndRedirect()
        }
    }

    private func checkPhaseAndRedirect() {
        // Intentionally no tab auto-redirection in Caddie-first IA.
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationService.shared)
        .environmentObject(ProfileViewModel())
        .environmentObject(ScoreTrackingService.shared)
        .environmentObject(CourseService.shared)
        .environmentObject(FeedbackService.shared)
        .environmentObject(HistoryStore())
        .environmentObject(UserProfileStore())
}
