//
//  AICaddieApp.swift
//  Caddie.ai
//

import SwiftUI

@main
struct CaddieAIApp: App {
    @StateObject private var locationService = LocationService.shared
    @StateObject private var profileViewModel = ProfileViewModel()
    @StateObject private var scoreTrackingService = ScoreTrackingService.shared
    @StateObject private var courseService = CourseService.shared
    @StateObject private var feedbackService = FeedbackService.shared
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var userProfileStore = UserProfileStore()
    @StateObject private var userIdentityStore = UserIdentityStore()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var authService = AuthService.shared
    @StateObject private var recommendationDiagnosticsStore = RecommendationDiagnosticsStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationService)
                .environmentObject(profileViewModel)
                .environmentObject(scoreTrackingService)
                .environmentObject(courseService)
                .environmentObject(feedbackService)
                .environmentObject(historyStore)
                .environmentObject(userProfileStore)
                .environmentObject(userIdentityStore)
                .environmentObject(sessionStore)
                .environmentObject(authService)
                .environmentObject(recommendationDiagnosticsStore)
                .onAppear {
                    AnalyticsService.shared.refreshSession()
                    AnalyticsService.shared.track(event: .appOpened)
                    AnalyticsService.shared.track(event: .sessionStarted(sessionId: sessionStore.currentSessionId))
                    profileViewModel.applyUserProfile(userProfileStore.profile)
                }
                .onChange(of: userProfileStore.profile) { _, newValue in
                    profileViewModel.applyUserProfile(newValue)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !userProfileStore.isOnboardingComplete },
                    set: { _ in }
                )) {
                    OnboardingCoordinatorView()
                        .environmentObject(userProfileStore)
                }
        }
    }
}
