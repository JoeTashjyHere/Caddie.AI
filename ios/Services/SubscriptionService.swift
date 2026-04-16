//
//  SubscriptionService.swift
//  Caddie.ai
//
//  StoreKit 2 subscription infrastructure.
//  Ready for App Store Connect product configuration.
//

import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    enum Tier: String, CaseIterable {
        case free = "free"
        case premium = "caddie_premium_monthly"
        case premiumAnnual = "caddie_premium_annual"

        var displayName: String {
            switch self {
            case .free: return "Free"
            case .premium: return "Caddie+"
            case .premiumAnnual: return "Caddie+ Annual"
            }
        }
    }

    struct SubscriptionStatus {
        var tier: Tier = .free
        var isActive: Bool = false
        var expiresAt: Date?
        var willRenew: Bool = false
    }

    @Published private(set) var status = SubscriptionStatus()
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false

    private let productIds: Set<String> = [
        Tier.premium.rawValue,
        Tier.premiumAnnual.rawValue
    ]

    private init() {
        Task { await loadProducts() }
        Task { await observeTransactions() }
    }

    // MARK: - Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: productIds)
            products = storeProducts.sorted { ($0.price as NSDecimalNumber).doubleValue < ($1.price as NSDecimalNumber).doubleValue }
        } catch {
            #if DEBUG
            print("[SUB] Failed to load products: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerification(verification)
                await updateSubscriptionStatus()
                await transaction.finish()
                AnalyticsService.shared.track("subscription_purchased", properties: [
                    "product": product.id,
                    "price": "\(product.price)"
                ])
                return true
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            #if DEBUG
            print("[SUB] Purchase failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await updateSubscriptionStatus()
    }

    // MARK: - Status

    func updateSubscriptionStatus() async {
        var activeTier: Tier = .free
        var expiresAt: Date?
        var willRenew = false

        for productId in productIds {
            guard let statuses = try? await Product.SubscriptionInfo.status(for: productId) else { continue }
            for s in statuses {
                guard case .verified(let renewalInfo) = s.renewalInfo,
                      case .verified(let transaction) = s.transaction else { continue }

                if s.state == .subscribed || s.state == .inGracePeriod {
                    if let tier = Tier(rawValue: transaction.productID) {
                        activeTier = tier
                    }
                    expiresAt = transaction.expirationDate
                    willRenew = renewalInfo.willAutoRenew
                }
            }
        }

        status = SubscriptionStatus(
            tier: activeTier,
            isActive: activeTier != .free,
            expiresAt: expiresAt,
            willRenew: willRenew
        )

        AdService.shared.setSubscribed(status.isActive)
    }

    // MARK: - Helpers

    private func checkVerification<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerification(result) {
                await updateSubscriptionStatus()
                await transaction.finish()
            }
        }
    }

    var premiumFeatures: [String] {
        [
            "No ads between holes",
            "Unlimited AI caddie recommendations",
            "Advanced shot analytics",
            "Priority support"
        ]
    }
}
