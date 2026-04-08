//
//  HistoryView.swift
//  Caddie.ai
//
//  Analytics home base: round recaps, handicap, recommendation history, practice insights

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var historyStore: HistoryStore

    @State private var selectedTab: HistorySection = .rounds
    @State private var selectedItem: HistoryItem?
    @State private var selectedRound: Round?
    @State private var roundToDelete: Round?
    @State private var itemToDelete: HistoryItem?

    private enum HistorySection: String, CaseIterable {
        case rounds = "Rounds"
        case shots = "Shots"
        case putts = "Putts"
        case insights = "Insights"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    handicapHeader

                    sectionPicker
                        .padding(.top, 8)

                    switch selectedTab {
                    case .rounds:
                        roundsSection
                    case .shots:
                        recommendationSection(type: .shot)
                    case .putts:
                        recommendationSection(type: .putt)
                    case .insights:
                        insightsSection
                    }
                }
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Analytics")
            .sheet(item: $selectedItem) { item in
                HistoryDetailView(item: item)
            }
            .sheet(item: $selectedRound) { round in
                RoundDetailSheet(round: round)
                    .environmentObject(scoreTrackingService)
            }
            .alert("Delete Round?", isPresented: Binding(
                get: { roundToDelete != nil },
                set: { if !$0 { roundToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let round = roundToDelete {
                        scoreTrackingService.deleteRound(round)
                        roundToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { roundToDelete = nil }
            } message: {
                Text("This round and its scores will be permanently removed from your history, handicap, and analytics.")
            }
            .alert("Delete Recommendation?", isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete {
                        historyStore.delete(item)
                        itemToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { itemToDelete = nil }
            } message: {
                Text("This recommendation will be permanently removed.")
            }
        }
    }

    // MARK: - Handicap Header

    private var handicapHeader: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                handicapCard
                quickStatsGrid
            }
            .padding(.horizontal)
            .padding(.top, 12)
        }
    }

    private var handicapCard: some View {
        let isOfficial = scoreTrackingService.handicapIsOfficial
        let title = isOfficial ? "Handicap" : "Handicap Est."

        return VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            if let hcp = scoreTrackingService.handicapEstimate {
                Text(String(format: "%.1f", hcp))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Text("--")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }

            let count = scoreTrackingService.handicapQualifyingRoundCount
            if count >= 5 {
                let poolSize = min(count, 20)
                let bestN = poolSize >= 20 ? 8 : (poolSize >= 10 ? 5 : max(1, poolSize / 2))
                Text("Best \(bestN) of \(poolSize)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            } else {
                Text("\(count)/5 rounds")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }

            if !isOfficial && scoreTrackingService.handicapEstimate != nil {
                Text("Limited Data")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: 120, height: 120)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.45, green: 0.3, blue: 0.75), Color(red: 0.35, green: 0.2, blue: 0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var quickStatsGrid: some View {
        let dist = scoreTrackingService.scoringDistribution()
        let completed = scoreTrackingService.completedRounds.count
        let avgVsPar = scoreTrackingService.averageVsPar

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                statTile(label: "Rounds", value: "\(completed)")
                statTile(label: "Avg vs Par", value: avgVsPar.map { $0 >= 0 ? "+\(String(format: "%.1f", $0))" : String(format: "%.1f", $0) } ?? "--")
            }
            HStack(spacing: 8) {
                statTile(label: "Birdies", value: "\(dist.birdiesOrBetter)")
                statTile(label: "Pars", value: "\(dist.pars)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(GolfTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GolfTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistorySection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = section }
                    } label: {
                        Text(section.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedTab == section ? .white : GolfTheme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selectedTab == section ? GolfTheme.grassGreen : Color(.secondarySystemBackground))
                            )
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Rounds Section

    private var roundsSection: some View {
        LazyVStack(spacing: 12) {
            let rounds = scoreTrackingService.completedRounds
            if rounds.isEmpty {
                emptyRoundsState
            } else {
                ForEach(rounds) { round in
                    RoundRecapCard(round: round)
                        .onTapGesture { selectedRound = round }
                        .contextMenu {
                            Button(role: .destructive) {
                                roundToDelete = round
                            } label: {
                                Label("Delete Round", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var emptyRoundsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 40))
                .foregroundColor(GolfTheme.grassGreen.opacity(0.5))
            Text("No completed rounds yet")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            Text("Play a round to see your scores and analytics here.")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Recommendation Section

    private func recommendationSection(type: RecommendationType) -> some View {
        let items = type == .shot ? historyStore.shotHistoryItems : historyStore.puttHistoryItems
        return LazyVStack(spacing: 8) {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: type == .shot ? "figure.golf" : "flag.fill")
                        .font(.system(size: 36))
                        .foregroundColor(GolfTheme.textSecondary.opacity(0.5))
                    Text("No \(type == .shot ? "shot" : "putting") recommendations yet")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
                .padding(.vertical, 40)
            } else {
                ForEach(items) { item in
                    HistoryItemRow(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItem = item }
                        .contextMenu {
                            Button(role: .destructive) {
                                itemToDelete = item
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .padding(.horizontal)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Insights Section

    private var insightsSection: some View {
        LazyVStack(spacing: 16) {
            if scoreTrackingService.completedRounds.count < 3 {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 40))
                        .foregroundColor(GolfTheme.grassGreen.opacity(0.5))
                    Text("Play at least 3 rounds to unlock insights")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 40)
            } else {
                parTypeInsight
                scoringTrendsInsight
                strengthsWeaknessesInsight
                practiceRecommendationsInsight
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var parTypeInsight: some View {
        let parTypes = scoreTrackingService.parTypeAverages()
        return insightCard(title: "Scoring by Par Type", icon: "chart.bar.fill", color: .blue) {
            VStack(spacing: 8) {
                ForEach(parTypes, id: \.parType) { pt in
                    HStack {
                        Text("Par \(pt.parType)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(GolfTheme.textPrimary)
                            .frame(width: 50, alignment: .leading)

                        let vsPar = pt.avgScore - Double(pt.parType)
                        let vsStr = vsPar >= 0 ? "+\(String(format: "%.1f", vsPar))" : String(format: "%.1f", vsPar)
                        Text("Avg \(String(format: "%.1f", pt.avgScore))")
                            .font(.system(size: 13))
                            .foregroundColor(GolfTheme.textSecondary)

                        Spacer()

                        Text(vsStr)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(vsPar <= 0 ? GolfTheme.grassGreen : .orange)

                        Text("(\(pt.count) holes)")
                            .font(.system(size: 11))
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var scoringTrendsInsight: some View {
        let dist = scoreTrackingService.scoringDistribution()
        let total = dist.birdiesOrBetter + dist.pars + dist.bogeys + dist.doublePlus
        guard total > 0 else { return AnyView(EmptyView()) }

        func pct(_ n: Int) -> String { "\(Int(Double(n) / Double(total) * 100))%" }

        return AnyView(insightCard(title: "Scoring Distribution", icon: "chart.pie.fill", color: .purple) {
            HStack(spacing: 12) {
                scoringBar(label: "Birdie+", count: dist.birdiesOrBetter, pct: pct(dist.birdiesOrBetter), color: .red)
                scoringBar(label: "Par", count: dist.pars, pct: pct(dist.pars), color: GolfTheme.grassGreen)
                scoringBar(label: "Bogey", count: dist.bogeys, pct: pct(dist.bogeys), color: .orange)
                scoringBar(label: "Dbl+", count: dist.doublePlus, pct: pct(dist.doublePlus), color: Color(red: 0.6, green: 0.4, blue: 0.2))
            }
        })
    }

    private func scoringBar(label: String, count: Int, pct: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(pct)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GolfTheme.textSecondary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GolfTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var strengthsWeaknessesInsight: some View {
        let holePerf = scoreTrackingService.holePerformance()
        guard holePerf.count >= 3 else { return AnyView(EmptyView()) }
        let sorted = holePerf.filter { $0.count >= 2 }.sorted { $0.avgVsPar < $1.avgVsPar }
        let best = Array(sorted.prefix(3))
        let worst = Array(sorted.suffix(3).reversed())

        return AnyView(insightCard(title: "Strongest & Weakest Holes", icon: "arrow.up.arrow.down", color: GolfTheme.grassGreen) {
            VStack(spacing: 12) {
                if !best.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Best Holes")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(GolfTheme.grassGreen)
                        ForEach(best, id: \.holeNumber) { h in
                            HStack {
                                Text("Hole \(h.holeNumber)")
                                    .font(.system(size: 13))
                                Spacer()
                                let vsStr = h.avgVsPar >= 0 ? "+\(String(format: "%.1f", h.avgVsPar))" : String(format: "%.1f", h.avgVsPar)
                                Text(vsStr)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(h.avgVsPar <= 0 ? GolfTheme.grassGreen : .orange)
                            }
                        }
                    }
                }
                if !worst.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Needs Work")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.orange)
                        ForEach(worst, id: \.holeNumber) { h in
                            HStack {
                                Text("Hole \(h.holeNumber)")
                                    .font(.system(size: 13))
                                Spacer()
                                let vsStr = h.avgVsPar >= 0 ? "+\(String(format: "%.1f", h.avgVsPar))" : String(format: "%.1f", h.avgVsPar)
                                Text(vsStr)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(h.avgVsPar <= 0 ? GolfTheme.grassGreen : .orange)
                            }
                        }
                    }
                }
            }
        })
    }

    private var practiceRecommendationsInsight: some View {
        let parTypes = scoreTrackingService.parTypeAverages()
        var recommendations: [String] = []

        if let worst = parTypes.max(by: { ($0.avgScore - Double($0.parType)) < ($1.avgScore - Double($1.parType)) }) {
            let vsPar = worst.avgScore - Double(worst.parType)
            if vsPar > 0.5 {
                recommendations.append("Focus on par \(worst.parType) holes — averaging +\(String(format: "%.1f", vsPar)) over par")
            }
        }

        let dist = scoreTrackingService.scoringDistribution()
        let total = dist.birdiesOrBetter + dist.pars + dist.bogeys + dist.doublePlus
        if total > 0 {
            let dpPct = Double(dist.doublePlus) / Double(total)
            if dpPct > 0.25 {
                recommendations.append("Reduce double bogeys — \(Int(dpPct * 100))% of your holes are double bogey or worse")
            }
        }

        if recommendations.isEmpty {
            recommendations.append("Keep playing rounds to build deeper practice insights")
        }

        return insightCard(title: "Practice Focus", icon: "sparkles", color: .orange) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(recommendations, id: \.self) { rec in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                        Text(rec)
                            .font(.system(size: 13))
                            .foregroundColor(GolfTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func insightCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(GolfTheme.textPrimary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Round Recap Card

struct RoundRecapCard: View {
    let round: Round

    private var holesPlayed: Int { round.playedHoles().count }
    private var totalStrokes: Int { round.totalStrokesPlayed() }
    private var totalPar: Int { round.totalParPlayed() }
    private var vsPar: Int { totalStrokes - totalPar }
    private var vsParString: String {
        guard totalPar > 0 else { return "--" }
        if vsPar == 0 { return "E" }
        return vsPar > 0 ? "+\(vsPar)" : "\(vsPar)"
    }
    private var roundType: String {
        switch round.persistedRoundLength {
        case .front9: return "Front 9"
        case .back9: return "Back 9"
        case .full18: return "18 Holes"
        case nil:
            if holesPlayed <= 9 { return "\(holesPlayed) Holes" }
            return "\(holesPlayed) Holes"
        }
    }
    private var resultLabel: String {
        if holesPlayed == 0 { return "Incomplete" }
        let expected = round.persistedRoundLength?.holeRange.count ?? 18
        if holesPlayed >= expected { return "Final (Thru \(holesPlayed))" }
        return "Partial (\(holesPlayed)/\(expected))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(round.courseName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(GolfTheme.textPrimary)
                        .lineLimit(2)
                    Text(roundType)
                        .font(.system(size: 13))
                        .foregroundColor(GolfTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GolfTheme.textSecondary)
            }

            HStack(spacing: 12) {
                vsParBadge
                statPill(label: "Par \(round.persistedRoundLength?.holeRange.count == 9 ? "3 Avg" : "Avg")", value: parTypeAvgLabel)
                statPill(label: "Birdies", value: "\(birdieCount)")
                statPill(label: "Pars", value: "\(parCount)")
            }

            HStack {
                Text(dateString)
                    .font(.system(size: 12))
                    .foregroundColor(GolfTheme.textSecondary)
                Spacer()
                Text(resultLabel)
                    .font(.system(size: 12))
                    .foregroundColor(GolfTheme.textSecondary)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }

    private var vsParBadge: some View {
        VStack(spacing: 2) {
            Text("To Par")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
            Text(vsParString)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Gross \(totalStrokes)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(width: 80, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: vsParGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var vsParGradientColors: [Color] {
        if totalPar == 0 { return [.gray, .gray.opacity(0.7)] }
        if vsPar <= 0 { return [GolfTheme.grassGreen, GolfTheme.grassGreen.opacity(0.7)] }
        if vsPar <= 5 { return [.orange, .orange.opacity(0.7)] }
        return [Color(red: 0.45, green: 0.3, blue: 0.75), Color(red: 0.35, green: 0.2, blue: 0.65)]
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(GolfTheme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GolfTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }

    private var birdieCount: Int {
        round.playedHoles().filter { h in
            guard let p = h.par else { return false }
            return h.strokes < p
        }.count
    }

    private var parCount: Int {
        round.playedHoles().filter { h in
            guard let p = h.par else { return false }
            return h.strokes == p
        }.count
    }

    private var parTypeAvgLabel: String {
        let par3s = round.playedHoles().filter { $0.par == 3 }
        guard !par3s.isEmpty else { return "--" }
        let avg = Double(par3s.map(\.strokes).reduce(0, +)) / Double(par3s.count)
        return String(format: "%.1f", avg)
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd/yyyy"
        return fmt.string(from: round.date)
    }
}

// MARK: - Round Detail Sheet

struct RoundDetailSheet: View {
    let round: Round
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    scorecardSection
                    quickStatsSection
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Round Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(GolfTheme.grassGreen)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(round.courseName)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(GolfTheme.textPrimary)

            let played = round.playedHoles().count
            let strokes = round.totalStrokesPlayed()
            let par = round.totalParPlayed()
            let vs = par > 0 ? strokes - par : 0
            let vsStr = par == 0 ? "--" : (vs == 0 ? "E" : (vs > 0 ? "+\(vs)" : "\(vs)"))

            HStack(spacing: 16) {
                Text("Score: \(strokes)")
                    .font(.system(size: 16, weight: .semibold))
                if par > 0 {
                    Text("Par: \(par)")
                        .font(.system(size: 16))
                        .foregroundColor(GolfTheme.textSecondary)
                    Text(vsStr)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(vs <= 0 ? GolfTheme.grassGreen : .orange)
                }
            }

            Text("\(played) holes played")
                .font(.system(size: 13))
                .foregroundColor(GolfTheme.textSecondary)

            Text(round.date.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 13))
                .foregroundColor(GolfTheme.textSecondary)
        }
    }

    private var scorecardSection: some View {
        let played = round.playedHoles().sorted { $0.holeNumber < $1.holeNumber }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Scorecard")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(GolfTheme.textPrimary)

            ForEach(played, id: \.holeNumber) { hole in
                HStack {
                    Text("Hole \(hole.holeNumber)")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 70, alignment: .leading)

                    if let par = hole.par {
                        Text("Par \(par)")
                            .font(.system(size: 13))
                            .foregroundColor(GolfTheme.textSecondary)
                            .frame(width: 50, alignment: .leading)

                        let diff = hole.strokes - par
                        Text("\(hole.strokes)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(width: 30, alignment: .trailing)

                        let lbl = diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")
                        Text(lbl)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(diff < 0 ? .red : diff == 0 ? GolfTheme.grassGreen : .orange)
                            .frame(width: 36, alignment: .trailing)
                    } else {
                        Spacer()
                        Text("\(hole.strokes)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }

    private var quickStatsSection: some View {
        let played = round.playedHoles()
        let birdies = played.filter { h in h.par.map { h.strokes < $0 } ?? false }.count
        let pars = played.filter { h in h.par.map { h.strokes == $0 } ?? false }.count
        let bogeys = played.filter { h in h.par.map { h.strokes == $0 + 1 } ?? false }.count
        let doubles = played.filter { h in h.par.map { h.strokes >= $0 + 2 } ?? false }.count

        return VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(GolfTheme.textPrimary)

            HStack(spacing: 12) {
                miniStat(label: "Birdies+", value: "\(birdies)", color: .red)
                miniStat(label: "Pars", value: "\(pars)", color: GolfTheme.grassGreen)
                miniStat(label: "Bogeys", value: "\(bogeys)", color: .orange)
                miniStat(label: "Dbl+", value: "\(doubles)", color: Color(red: 0.6, green: 0.4, blue: 0.2))
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
    }

    private func miniStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(GolfTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - History Item Row (preserved from original)

struct HistoryItemRow: View {
    let item: HistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.type == .shot ? "figure.golf" : "flag.fill")
                    .foregroundColor(item.type == .shot ? GolfTheme.grassGreen : GolfTheme.accentGold)
                    .font(.title3)

                Text(item.type.displayName)
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)

                Spacer()

                Text(relativeTimeString(from: item.createdAt))
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
            }

            if let courseName = item.courseName ?? item.shotMetadata?.courseName ?? item.puttMetadata?.courseName {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(GolfTheme.textSecondary)
                    Text(courseName)
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
            }

            if item.type == .shot {
                shotDetails
            } else {
                puttDetails
            }

            let previewLines = item.recommendationText.components(separatedBy: .newlines).prefix(2).joined(separator: " ")
            if !previewLines.isEmpty {
                Text(previewLines)
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private var shotDetails: some View {
        HStack(spacing: 12) {
            if let distance = item.shotMetadata?.distanceYards ?? item.distanceYards {
                detailChip(icon: "ruler.fill", text: "\(distance) yds", color: GolfTheme.grassGreen)
            }
            if let lie = item.shotMetadata?.lie ?? item.lie {
                detailChip(icon: "circle.grid.2x2.fill", text: lie.capitalized, color: .blue)
            }
            if let shotType = item.shotMetadata?.shotType ?? item.shotType {
                detailChip(icon: "target", text: shotType.capitalized, color: .purple)
            }
        }
    }

    private var puttDetails: some View {
        HStack(spacing: 12) {
            if let distance = item.puttMetadata?.puttDistanceFeet {
                detailChip(icon: "ruler.fill", text: "\(distance) ft", color: GolfTheme.accentGold)
            }
            if let breakDir = item.puttMetadata?.breakDirection, !breakDir.isEmpty {
                detailChip(icon: "arrow.left.and.right", text: breakDir, color: GolfTheme.accentGold)
            }
        }
    }

    private func detailChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(GolfTheme.captionFont)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }

    private func relativeTimeString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hr ago" }
        if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days) day\(days > 1 ? "s" : "") ago"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    HistoryView()
        .environmentObject(ScoreTrackingService.shared)
        .environmentObject(ProfileViewModel())
        .environmentObject(HistoryStore())
}
