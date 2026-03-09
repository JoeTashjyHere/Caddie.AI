//
//  StatsView.swift
//  Caddie.ai
//

import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var scoreTrackingService: ScoreTrackingService
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Your Statistics")
                            .font(GolfTheme.titleFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        Text("\(scoreTrackingService.rounds.count) rounds tracked")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .padding(.top)
                    
                    if scoreTrackingService.rounds.isEmpty {
                        EmptyStateView(
                            icon: "chart.bar.fill",
                            title: "No Statistics Yet",
                            message: "Complete a round to see your statistics"
                        )
                        .padding(40)
                    } else {
                        // Key Statistics Cards
                        VStack(spacing: 16) {
                            statCard(
                                title: "Scoring Average",
                                value: String(format: "%.1f", scoringAverage),
                                subtitle: "vs Par",
                                icon: "target",
                                color: GolfTheme.grassGreen
                            )
                            
                            HStack(spacing: 16) {
                                statCard(
                                    title: "Fairways Hit",
                                    value: String(format: "%.0f%%", fairwaysHitPercent),
                                    subtitle: "Accuracy",
                                    icon: "arrow.right.circle.fill",
                                    color: GolfTheme.accentGold
                                )
                                
                                statCard(
                                    title: "GIR",
                                    value: String(format: "%.0f%%", girPercent),
                                    subtitle: "Greens in Regulation",
                                    icon: "flag.fill",
                                    color: Color.blue
                                )
                            }
                            
                            statCard(
                                title: "Putting Average",
                                value: String(format: "%.1f", puttingAverage),
                                subtitle: "Putts per round",
                                icon: "circle.fill",
                                color: Color.purple
                            )
                        }
                        .padding(.horizontal)
                        
                        // Trend Chart
                        if scoreTrackingService.rounds.count >= 2 {
                            trendChartCard
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Stats")
        }
    }
    
    // MARK: - Computed Statistics
    
    private var scoringAverage: Double {
        let rounds = scoreTrackingService.rounds
        guard !rounds.isEmpty else { return 0.0 }
        
        let totalScoreVsPar = rounds.reduce(0) { $0 + $1.scoreVsPar }
        return Double(totalScoreVsPar) / Double(rounds.count)
    }
    
    private var fairwaysHitPercent: Double {
        let rounds = scoreTrackingService.rounds
        guard !rounds.isEmpty else { return 0.0 }
        
        var totalFairways = 0
        var totalPar4And5 = 0
        
        for round in rounds {
            totalFairways += round.fairwaysHit
            totalPar4And5 += round.par4And5Holes
        }
        
        guard totalPar4And5 > 0 else { return 0.0 }
        return (Double(totalFairways) / Double(totalPar4And5)) * 100.0
    }
    
    private var girPercent: Double {
        let rounds = scoreTrackingService.rounds
        guard !rounds.isEmpty else { return 0.0 }
        
        var totalGIR = 0
        var totalHoles = 0
        
        for round in rounds {
            totalGIR += round.greensInRegulation
            totalHoles += round.holes.count
        }
        
        guard totalHoles > 0 else { return 0.0 }
        return (Double(totalGIR) / Double(totalHoles)) * 100.0
    }
    
    private var puttingAverage: Double {
        let rounds = scoreTrackingService.rounds
        guard !rounds.isEmpty else { return 0.0 }
        
        let totalPutts = rounds.reduce(0) { $0 + $1.totalPutts }
        guard !rounds.isEmpty else { return 0.0 }
        return Double(totalPutts) / Double(rounds.count)
    }
    
    private var last5Rounds: [Round] {
        Array(scoreTrackingService.rounds.suffix(5))
    }
    
    // MARK: - Views
    
    private func statCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
                Text(subtitle)
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var trendChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(GolfTheme.grassGreen)
                    .font(.title3)
                Text("Score Trend (Last 5 Rounds)")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(Array(last5Rounds.enumerated()), id: \.element.id) { index, round in
                        LineMark(
                            x: .value("Round", index + 1),
                            y: .value("Score", round.totalScore - round.par)
                        )
                        .foregroundStyle(GolfTheme.grassGreen)
                        .interpolationMethod(.catmullRom)
                        
                        PointMark(
                            x: .value("Round", index + 1),
                            y: .value("Score", round.totalScore - round.par)
                        )
                        .foregroundStyle(GolfTheme.grassGreen)
                        .symbolSize(60)
                    }
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
            } else {
                // Fallback for iOS < 16
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(last5Rounds.enumerated()), id: \.element.id) { index, round in
                        HStack {
                            Text("Round \(index + 1)")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(GolfTheme.cream)
                                        .frame(height: 20)
                                    
                                    Rectangle()
                                        .fill(GolfTheme.grassGreen)
                                        .frame(width: max(0, geometry.size.width * CGFloat(abs(round.totalScore - round.par)) / 20.0), height: 20)
                                }
                            }
                            .frame(height: 20)
                            
                            Text("\(round.totalScore - round.par > 0 ? "+" : "")\(round.totalScore - round.par)")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textPrimary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    StatsView()
        .environmentObject(ScoreTrackingService.shared)
}

