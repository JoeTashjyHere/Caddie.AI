//
//  AdService.swift
//  Caddie.ai
//
//  Monetization infrastructure: ad placement management.
//  Ready for Google AdMob or Apple Search Ads integration.
//

import Foundation

@MainActor
final class AdService: ObservableObject {
    static let shared = AdService()

    enum Placement: String, CaseIterable {
        case betweenHoles = "between_holes"
        case postRoundSummary = "post_round_summary"
        case historyTab = "history_tab"
        case caddieResult = "caddie_result"
    }

    @Published private(set) var isSubscribed = false

    private init() {
        loadSubscriptionState()
    }

    func shouldShowAd(at placement: Placement) -> Bool {
        guard !isSubscribed else { return false }

        switch placement {
        case .betweenHoles:
            return true
        case .postRoundSummary:
            return true
        case .historyTab:
            return true
        case .caddieResult:
            return false
        }
    }

    func recordImpression(placement: Placement) {
        AnalyticsService.shared.track("ad_impression", properties: [
            "placement": placement.rawValue
        ])
    }

    func recordTap(placement: Placement) {
        AnalyticsService.shared.track("ad_tap", properties: [
            "placement": placement.rawValue
        ])
    }

    func setSubscribed(_ subscribed: Bool) {
        isSubscribed = subscribed
        UserDefaults.standard.set(subscribed, forKey: "caddie_is_subscribed")
    }

    private func loadSubscriptionState() {
        isSubscribed = UserDefaults.standard.bool(forKey: "caddie_is_subscribed")
    }
}
