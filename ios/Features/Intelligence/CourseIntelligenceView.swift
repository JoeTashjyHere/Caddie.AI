//
//  CourseIntelligenceView.swift
//  Caddie.ai
//
//  View for displaying course intelligence and insights
//

import SwiftUI
import UIKit

struct CourseIntelligenceView: View {
    @EnvironmentObject var courseService: CourseService
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @StateObject private var viewModel = CourseIntelligenceViewModel()
    @StateObject private var courseViewModel = CourseViewModel()
    
    @State private var selectedCourse: Course?
    @State private var selectedHole: Int?
    @State private var showingCourseSelection = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Course selector
                    courseSelectorSection
                    
                    // Insights content
                    switch viewModel.state {
                    case .idle:
                        if let insights = viewModel.insights {
                            insightsContent(insights: insights)
                        } else {
                            emptyStateSection
                        }
                    case .loading:
                        loadingSection
                    case .loaded:
                        if let insights = viewModel.insights {
                            insightsContent(insights: insights)
                        } else {
                            emptyStateSection
                        }
                    case .error(let message):
                        ErrorView(message: message) {
                            if let courseId = selectedCourse?.id {
                                Task {
                                    await viewModel.fetchInsights(courseId: courseId)
                                }
                            }
                        }
                    case .empty:
                        emptyStateSection
                    }
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Course Intelligence")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if selectedCourse == nil {
                    if let course = courseService.currentCourse {
                        selectedCourse = course
                    } else {
                        selectedCourse = courseService.localCourses.first
                    }
                }
                
                if let courseId = selectedCourse?.id {
                    Task {
                        await viewModel.fetchInsights(courseId: courseId)
                    }
                }
            }
            .onChange(of: selectedCourse?.id) { oldValue, newValue in
                if let courseId = newValue {
                    Task {
                        await viewModel.fetchInsights(courseId: courseId)
                    }
                }
            }
            .onChange(of: courseViewModel.currentCourse) { _, newValue in
                if let course = newValue {
                    selectedCourse = course
                }
            }
            .sheet(item: Binding(
                get: { selectedHole.map { HoleDetailWrapper(hole: $0) } },
                set: { selectedHole = $0?.hole }
            )) { wrapper in
                if let insights = viewModel.insights {
                    HoleDetailView(
                        courseId: insights.courseId,
                        holeNumber: wrapper.hole
                    )
                    .environmentObject(viewModel)
                }
            }
            .sheet(isPresented: $showingCourseSelection) {
                CourseSelectionView()
                    .environmentObject(courseViewModel)
                    .environmentObject(locationService)
            }
        }
    }
    
    // MARK: - Course Selector
    
    private var courseSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Course")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                showingCourseSelection = true
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let course = selectedCourse {
                            Text(course.name)
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                            if let par = course.par {
                                Text("Par \(par)")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(GolfTheme.textSecondary)
                            } else {
                                Text("Tap to change course")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(GolfTheme.textSecondary)
                            }
                        } else {
                            Text("Tap to choose a course")
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(GolfTheme.textSecondary)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GolfTheme.textSecondary.opacity(0.15), lineWidth: 1)
                )
            }
            
            if !courseService.localCourses.isEmpty {
                Menu {
                    ForEach(courseService.localCourses, id: \.id) { course in
                        Button(course.name) {
                            selectedCourse = course
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .foregroundColor(GolfTheme.accentGold)
                        Text("Quick select from favorites")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
            }
            
            if selectedCourse == nil {
                Text("No course selected. Choose a course to unlock intelligence insights.")
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
                
                PrimaryButton(
                    title: "Select Course",
                    action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        showingCourseSelection = true
                    }
                )
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Loading Section
    
    private var loadingSection: some View {
        LoadingView(message: "Analyzing course data...")
    }
    
    // MARK: - Error Section
    
    private var errorSection: some View {
        ErrorView(message: viewModel.errorMessage ?? "Failed to load insights") {
            if let courseId = selectedCourse?.id {
                Task {
                    await viewModel.fetchInsights(courseId: courseId)
                }
            }
        }
        .padding(40)
    }
    
    // MARK: - Empty State
    
    private var emptyStateSection: some View {
        EmptyStateView(
            icon: "chart.bar.doc.horizontal",
            title: "No course selected",
            message: "Select a course to see intelligence insights"
        )
    }
    
    // MARK: - Insights Content
    
    private func insightsContent(insights: CourseInsights) -> some View {
        VStack(spacing: 24) {
            // Most Played Holes
            if !insights.mostPlayedHoles.isEmpty {
                mostPlayedHolesSection(insights: insights)
            }
            
            // Tricky Holes
            if !insights.trickyHoles.isEmpty {
                trickyHolesSection(insights: insights)
            }
            
            // Club Insights
            if !insights.clubInsights.isEmpty {
                clubInsightsSection(insights: insights)
            }
            
            // AI Notes
            if !insights.aiNotes.isEmpty {
                aiNotesSection(insights: insights)
            }
            
            if !insights.holeDetails.isEmpty {
                recentShotHistorySection(insights: insights)
            }
        }
    }
    
    // MARK: - Most Played Holes
    
    private func mostPlayedHolesSection(insights: CourseInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(GolfTheme.grassGreen)
                Text("Most Played Holes")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(insights.mostPlayedHoles, id: \.self) { hole in
                        Button(action: {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            selectedHole = hole
                        }) {
                            VStack(spacing: 8) {
                                Text("\(hole)")
                                    .font(GolfTheme.titleFont)
                                    .foregroundColor(GolfTheme.grassGreen)
                                Text("Hole")
                                    .font(GolfTheme.captionFont)
                                    .foregroundColor(GolfTheme.textSecondary)
                            }
                            .frame(width: 80, height: 80)
                            .background(GolfTheme.cream)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(GolfTheme.grassGreen.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Tricky Holes
    
    private func trickyHolesSection(insights: CourseInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Tricky Holes")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            ForEach(insights.trickyHoles) { trickyHole in
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    selectedHole = trickyHole.hole
                }) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hole \(trickyHole.hole)")
                                .font(GolfTheme.headlineFont)
                                .foregroundColor(GolfTheme.textPrimary)
                            Text(trickyHole.note)
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("+\(trickyHole.avgOverPar)")
                                .font(GolfTheme.headlineFont)
                                .foregroundColor(.orange)
                            Text("Avg over par")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(GolfTheme.textSecondary)
                            .font(.caption)
                    }
                    .padding()
                    .background(GolfTheme.cream)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Club Insights
    
    private func clubInsightsSection(insights: CourseInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "golf.circle.fill")
                    .foregroundColor(GolfTheme.accentGold)
                Text("Club Performance")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            ForEach(insights.clubInsights) { insight in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(insight.club)
                            .font(GolfTheme.headlineFont)
                            .foregroundColor(GolfTheme.grassGreen)
                        Spacer()
                        Text(insight.note)
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Average")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                            Text("\(insight.avg) yds")
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                            Text("\(insight.profile) yds")
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.textPrimary)
                        }
                        
                        Spacer()
                        
                        let diff = insight.avg - insight.profile
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Difference")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                            Text("\(diff > 0 ? "+" : "")\(diff) yds")
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(diff < 0 ? .orange : GolfTheme.grassGreen)
                        }
                    }
                }
                .padding()
                .background(GolfTheme.cream)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - AI Notes
    
    private func aiNotesSection(insights: CourseInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(GolfTheme.accentGold)
                Text("AI Notes")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            ForEach(Array(insights.aiNotes.enumerated()), id: \.offset) { index, note in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(GolfTheme.accentGold)
                        .font(.caption)
                    Text(note)
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(GolfTheme.cream)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private func recentShotHistorySection(insights: CourseInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundColor(Color.blue)
                Text("Recent Shot History")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
            }
            
            ForEach(insights.holeDetails) { detail in
                Button(action: {
                    selectedHole = detail.hole
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Hole \(detail.hole)")
                                .font(GolfTheme.headlineFont)
                                .foregroundColor(GolfTheme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(GolfTheme.textSecondary)
                                .font(.caption)
                        }
                        
                        if let latestShot = detail.shots.first {
                            Text("Last shot: \(latestShot.shotType.capitalized) • \(latestShot.recommendation?.club ?? latestShot.club ?? "Club TBD")")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        } else {
                            Text("No shot history yet")
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GolfTheme.cream)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GolfTheme.textSecondary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Helper Wrapper

struct HoleDetailWrapper: Identifiable {
    let id = UUID()
    let hole: Int
}

// MARK: - Hole Detail View

struct HoleDetailView: View {
    let courseId: String
    let holeNumber: Int
    @EnvironmentObject var viewModel: CourseIntelligenceViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var pastShots: [CourseInsights.HoleShot] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hole \(holeNumber)")
                            .font(GolfTheme.titleFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        Text("Course Intelligence")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top)
                    
                    if isLoading {
                        ProgressView()
                            .tint(GolfTheme.grassGreen)
                    } else if pastShots.isEmpty {
                        emptyStateView
                    } else {
                        pastShotsView
                    }
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Hole \(holeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(GolfTheme.grassGreen)
                }
            }
            .onAppear {
                loadPastShots()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .foregroundColor(GolfTheme.textSecondary)
                .font(.title)
            Text("No shots recorded")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            Text("Start playing to see shot history for this hole")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    private var pastShotsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Past Shots")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            ForEach(pastShots) { shot in
                pastShotCard(shot: shot)
            }
        }
    }
    
    private func pastShotCard(shot: CourseInsights.HoleShot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail and basic info
            HStack(alignment: .top, spacing: 12) {
                if let urlString = shot.imageUrl, let url = URL(string: absoluteImageURL(from: urlString)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty:
                            ProgressView()
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .padding(12)
                                .foregroundColor(GolfTheme.textSecondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 100, height: 100)
                    .cornerRadius(8)
                    .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(GolfTheme.cream)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(GolfTheme.textSecondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(shot.shotType.capitalized)
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    
                    if let club = shot.recommendation?.club ?? shot.club {
                        Text(club)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.grassGreen)
                    }
                    
                    if let distance = shot.distance {
                        Text("\(distance) yds")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    
                    if let date = shot.date {
                        Text(date, style: .date)
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
                
                Spacer()
            }
            
            // Recommendation history
            if let recommendation = shot.recommendation {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    Text("AI Recommendation")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                    
                    HStack {
                        Text("Club:")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        Text(recommendation.club)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.grassGreen)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aim:")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        Text(recommendation.aim)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avoid:")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        Text(recommendation.avoid)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(Color.orange)
                    }
                    
                    HStack {
                        Text("Confidence:")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        ProgressView(value: recommendation.confidence, total: 1.0)
                            .tint(GolfTheme.grassGreen)
                            .frame(width: 100)
                        Text("\(Int(recommendation.confidence * 100))%")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
            }
            
            if let context = shot.shotContext {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    
                    Text("Shot Context")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                    
                    Text("Surface: \(context.surface.capitalized)")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    
                    if let wind = context.conditions?.wind {
                        Text("Wind: \(wind)")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    
                    if let elevation = context.conditions?.elevation {
                        Text("Elevation: \(elevation)")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                }
            }
            
            // User feedback
            if let feedback = shot.userFeedback {
                HStack(spacing: 8) {
                    Image(systemName: feedback == "helpful" ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundColor(feedback == "helpful" ? GolfTheme.grassGreen : .red)
                    Text(feedback == "helpful" ? "Helpful" : "Off target")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func loadPastShots() {
        isLoading = true
        Task {
            let shots = viewModel.shots(for: holeNumber)
            pastShots = shots
            isLoading = false
        }
    }
    
    private func absoluteImageURL(from path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        // Use APIService as single source of truth for base URL
        return APIService.baseURLString + path
    }
}

