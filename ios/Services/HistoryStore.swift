//
//  HistoryStore.swift
//  Caddie.ai
//
//  Persistence layer for recommendation history
//

import Foundation
import SwiftUI

@MainActor
final class HistoryStore: ObservableObject {
    
    @Published var items: [HistoryItem] = []
    
    private let userDefaultsKey = "history_items"
    private let maxItems = 200
    
    init() {
        load()
    }
    
    // MARK: - Persistence
    
    func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            items = []
            return
        }
        // Sort newest first
        items = decoded.sorted { $0.createdAt > $1.createdAt }
    }
    
    func save() {
        let snapshot = items
        Task.detached(priority: .utility) { [userDefaultsKey] in
            guard let encoded = try? JSONEncoder().encode(snapshot) else {
                print("⚠️ Failed to encode history items")
                return
            }
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    // MARK: - Public Methods
    
    /// Add a new history item to the top of the list and save immediately
    func add(_ item: HistoryItem) {
        // Insert at the beginning (most recent first)
        items.insert(item, at: 0)
        
        // Cap to max items (remove oldest)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        save()
    }
    
    /// Clear all history (for debug/testing)
    func clearAll() {
        items = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    func upsertFeedback(for recommendationId: String, feedback: RecommendationFeedbackRecord) {
        guard !recommendationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.recommendationId == recommendationId }) else { return }
        let existing = items[index]
        let updated = HistoryItem(
            id: existing.id,
            createdAt: existing.createdAt,
            type: existing.type,
            courseName: existing.courseName,
            distanceYards: existing.distanceYards,
            shotType: existing.shotType,
            lie: existing.lie,
            hazards: existing.hazards,
            recommendationText: existing.recommendationText,
            rawAIResponse: existing.rawAIResponse,
            thumbnailData: existing.thumbnailData,
            recommendationId: existing.recommendationId,
            feedback: feedback,
            shotMetadata: existing.shotMetadata,
            puttMetadata: existing.puttMetadata
        )
        items[index] = updated
        save()
    }
}
extension HistoryStore {
    /// Shot-only history items (newest first)
    var shotHistoryItems: [HistoryItem] {
        items.filter { $0.type == .shot }
    }

    /// Putt-only history items (newest first)
    var puttHistoryItems: [HistoryItem] {
        items.filter { $0.type == .putt }
    }

    /// Concatenated summary of the most recent N shot recommendations
    func recentShotSummary(n: Int) -> String {
        shotHistoryItems.prefix(n).map { $0.recommendationText }.joined(separator: "\n\n")
    }

    /// Concatenated summary of the most recent N putt recommendations
    func recentPuttSummary(n: Int) -> String {
        puttHistoryItems.prefix(n).map { $0.recommendationText }.joined(separator: "\n\n")
    }
}
