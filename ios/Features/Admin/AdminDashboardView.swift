//
//  AdminDashboardView.swift
//  Caddie.ai
//
//  Founder command center: KPIs, engagement metrics, user list.
//

import SwiftUI

struct AdminDashboardView: View {
    @StateObject private var viewModel = AdminDashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    kpiSection
                    engagementSection
                    recommendationSection
                    geometryHealthSummarySection
                    geometryCourseListSection
                    userListSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(GolfTheme.screenBackground.ignoresSafeArea())
            .navigationTitle("Command Center")
            .refreshable { await viewModel.refresh() }
            .onAppear { Task { await viewModel.refresh() } }
        }
    }

    // MARK: - KPIs

    private var kpiSection: some View {
        ProfileSectionCard(title: "Key Metrics") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 14) {
                kpiTile(value: "\(viewModel.dashboard.totalUsers)", label: "Total Users", icon: "person.2.fill", color: GolfTheme.accentBlue)
                kpiTile(value: "\(viewModel.dashboard.dailyActiveUsers)", label: "DAU", icon: "chart.line.uptrend.xyaxis", color: GolfTheme.grassGreen)
                kpiTile(value: "\(viewModel.dashboard.weeklyActiveUsers)", label: "WAU", icon: "calendar", color: .orange)
                kpiTile(value: "\(viewModel.dashboard.totalRounds)", label: "Total Rounds", icon: "flag.fill", color: .purple)
            }
        }
    }

    private func kpiTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Engagement

    private var engagementSection: some View {
        ProfileSectionCard(title: "Engagement") {
            metricRow("Total Shots", value: "\(viewModel.dashboard.totalShots)")
            metricRow("Total Putts", value: "\(viewModel.dashboard.totalPutts)")
            metricRow("Onboarding Rate", value: String(format: "%.0f%%", viewModel.dashboard.onboardingCompletionRate * 100))
            metricRow("Avg Rounds / User", value: String(format: "%.1f", viewModel.dashboard.avgRoundsPerUser))
        }
    }

    // MARK: - Recommendations

    private var recommendationSection: some View {
        ProfileSectionCard(title: "Recommendations") {
            metricRow("Total", value: "\(viewModel.dashboard.totalRecommendations)")
            metricRow("Normalization Rate", value: String(format: "%.1f%%", viewModel.dashboard.normalizationRate * 100))
            metricRow("Fallback Rate", value: String(format: "%.1f%%", viewModel.dashboard.fallbackRate * 100))
        }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Geometry Health Summary

    private var geometryHealthSummarySection: some View {
        ProfileSectionCard(title: "Course Geometry / Map Alignment Health") {
            let gh = viewModel.geometryHealth
            metricRow("Average Geometry Score", value: "\(gh.avgGeometryScore)%")
            metricRow("Real Tee Coverage", value: "\(gh.realTeePct)%")
            metricRow("Fallback Tee (due-north)", value: "\(gh.fallbackTeePct)%")
            metricRow("Valid Bearing", value: "\(gh.validBearingPct)%")
            metricRow("Map Alignment Ready", value: "\(gh.mapAlignmentReadyPct)%")

            if gh.fallbackTeePct > 30 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    Text("NEEDS DATA IMPROVEMENT — \(gh.fallbackTeePct)% of holes use due-north fallback tees")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: - Geometry Course List

    private var geometryCourseListSection: some View {
        ProfileSectionCard(title: "Geometry by Course (\(viewModel.geometryCourses.count))") {
            if viewModel.geometryCourses.isEmpty {
                Text("No geometry data loaded yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }

            ForEach(viewModel.geometryCourses) { course in
                DisclosureGroup {
                    ForEach(course.holes) { hole in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Hole \(hole.holeNumber)")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                if hole.fallbackWarning {
                                    Text("⚠️ FALLBACK")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                                if hole.mapAlignmentReady {
                                    Text("✅ READY")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                } else {
                                    Text("⚠️ NOT READY")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.red)
                                }
                            }
                            HStack(spacing: 12) {
                                Text("Tee: \(hole.teeSource)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("Green: \(hole.greenSource)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                if let bearing = hole.bearing {
                                    Text("Brg: \(String(format: "%.0f", bearing))°")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Text("Haz: \(hole.hazardCount)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name)
                                .font(.system(size: 14, weight: .semibold))
                            if let city = course.city, let state = course.state {
                                Text("\(city), \(state)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(course.geometryScore)%")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(course.geometryScore >= 80 ? .green : course.geometryScore >= 50 ? .orange : .red)
                            if course.fallbackTeePct > 0 {
                                Text("⚠️ \(course.fallbackTeePct)% fallback")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - User List

    private var userListSection: some View {
        ProfileSectionCard(title: "Users (\(viewModel.users.count))") {
            if viewModel.users.isEmpty {
                Text("No user data available yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }

            ForEach(viewModel.users) { user in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(user.displayName)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("\(user.roundsPlayed) rounds")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 16) {
                        if let email = user.email, !email.isEmpty {
                            Label(email, systemImage: "envelope")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        if let handicap = user.handicap {
                            Label("HCP \(handicap)", systemImage: "number")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AdminDashboardViewModel: ObservableObject {
    struct Dashboard {
        var totalUsers = 0
        var dailyActiveUsers = 0
        var weeklyActiveUsers = 0
        var totalRounds = 0
        var totalShots = 0
        var totalPutts = 0
        var onboardingCompletionRate: Double = 0
        var avgRoundsPerUser: Double = 0
        var totalRecommendations = 0
        var normalizationRate: Double = 0
        var fallbackRate: Double = 0
    }

    struct AdminUser: Identifiable {
        let id: String
        var displayName: String
        var email: String?
        var phone: String?
        var handicap: String?
        var roundsPlayed: Int
        var lastActiveAt: Date?
        var clubCount: Int
    }

    struct GeometryHealthSummary {
        var avgGeometryScore = 0
        var realTeePct = 0
        var fallbackTeePct = 0
        var validBearingPct = 0
        var mapAlignmentReadyPct = 0
    }

    struct GeometryCourse: Identifiable {
        let id: String
        let name: String
        let city: String?
        let state: String?
        let geometryScore: Int
        let fallbackTeePct: Int
        let validBearingPct: Int
        let mapAlignmentReadyPct: Int
        let holes: [GeometryHole]
    }

    struct GeometryHole: Identifiable {
        var id: Int { holeNumber }
        let holeNumber: Int
        let teeSource: String
        let greenSource: String
        let bearing: Double?
        let bearingQuality: String
        let mapAlignmentReady: Bool
        let fallbackWarning: Bool
        let hazardCount: Int
    }

    @Published var dashboard = Dashboard()
    @Published var users: [AdminUser] = []
    @Published var geometryHealth = GeometryHealthSummary()
    @Published var geometryCourses: [GeometryCourse] = []
    @Published var isLoading = false

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        await fetchDashboard()
        await fetchUsers()
        await fetchGeometryHealth()
    }

    private func fetchDashboard() async {
        guard let url = URL(string: APIConfig.baseURLString + "/api/admin/dashboard") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dashboard.totalUsers = json["totalUsers"] as? Int ?? 0
                dashboard.dailyActiveUsers = json["dailyActiveUsers"] as? Int ?? 0
                dashboard.weeklyActiveUsers = json["weeklyActiveUsers"] as? Int ?? 0
                dashboard.totalRounds = json["totalRounds"] as? Int ?? 0
                dashboard.totalShots = json["totalShots"] as? Int ?? 0
                dashboard.totalPutts = json["totalPutts"] as? Int ?? 0
                dashboard.onboardingCompletionRate = json["onboardingCompletionRate"] as? Double ?? 0
                dashboard.avgRoundsPerUser = json["avgRoundsPerUser"] as? Double ?? 0
                dashboard.totalRecommendations = json["totalRecommendations"] as? Int ?? 0
                dashboard.normalizationRate = json["normalizationRate"] as? Double ?? 0
                dashboard.fallbackRate = json["fallbackRate"] as? Double ?? 0
            }
        } catch {
            #if DEBUG
            print("[ADMIN] Dashboard fetch failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func fetchGeometryHealth() async {
        guard let url = URL(string: APIConfig.baseURLString + "/api/admin/geometry-health") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let summary = json["summary"] as? [String: Any] {
                    geometryHealth.avgGeometryScore = summary["avg_geometry_score"] as? Int ?? 0
                    geometryHealth.realTeePct = summary["real_tee_pct"] as? Int ?? 0
                    geometryHealth.fallbackTeePct = summary["fallback_tee_pct"] as? Int ?? 0
                    geometryHealth.validBearingPct = summary["valid_bearing_pct"] as? Int ?? 0
                    geometryHealth.mapAlignmentReadyPct = summary["map_alignment_ready_pct"] as? Int ?? 0
                }
                if let coursesJSON = json["courses"] as? [[String: Any]] {
                    geometryCourses = coursesJSON.compactMap { c in
                        guard let id = c["id"] as? String,
                              let name = c["name"] as? String else { return nil }
                        let holesJSON = c["holes"] as? [[String: Any]] ?? []
                        let holes: [GeometryHole] = holesJSON.compactMap { h in
                            guard let hn = h["hole_number"] as? Int else { return nil }
                            return GeometryHole(
                                holeNumber: hn,
                                teeSource: h["tee_source"] as? String ?? "UNKNOWN",
                                greenSource: h["green_source"] as? String ?? "UNKNOWN",
                                bearing: h["bearing"] as? Double,
                                bearingQuality: h["bearing_quality"] as? String ?? "UNKNOWN",
                                mapAlignmentReady: h["map_alignment_ready"] as? Bool ?? false,
                                fallbackWarning: h["fallback_warning"] as? Bool ?? false,
                                hazardCount: h["hazard_count"] as? Int ?? 0
                            )
                        }
                        return GeometryCourse(
                            id: id,
                            name: name,
                            city: c["city"] as? String,
                            state: c["state"] as? String,
                            geometryScore: c["geometry_score"] as? Int ?? 0,
                            fallbackTeePct: c["fallback_tee_pct"] as? Int ?? 0,
                            validBearingPct: c["valid_bearing_pct"] as? Int ?? 0,
                            mapAlignmentReadyPct: c["map_alignment_ready_pct"] as? Int ?? 0,
                            holes: holes
                        )
                    }
                }
            }
        } catch {
            #if DEBUG
            print("[ADMIN] Geometry health fetch failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func fetchUsers() async {
        guard let url = URL(string: APIConfig.baseURLString + "/api/admin/users") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                users = json.compactMap { dict in
                    guard let id = dict["id"] as? String ?? dict["userId"] as? String else { return nil }
                    return AdminUser(
                        id: id,
                        displayName: dict["name"] as? String ?? "Unknown",
                        email: dict["email"] as? String,
                        phone: dict["phone"] as? String,
                        handicap: dict["handicap"] as? String,
                        roundsPlayed: dict["roundsPlayed"] as? Int ?? 0,
                        clubCount: dict["clubCount"] as? Int ?? 0
                    )
                }
            }
        } catch {
            #if DEBUG
            print("[ADMIN] Users fetch failed: \(error.localizedDescription)")
            #endif
        }
    }
}

#Preview {
    AdminDashboardView()
}
