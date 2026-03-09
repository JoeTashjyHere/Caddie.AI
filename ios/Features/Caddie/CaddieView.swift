//
//  CaddieView.swift
//  Caddie.ai
//
//  Root view for the Caddie tab

import SwiftUI

struct CaddieView: View {
    @StateObject private var viewModel: CaddieViewModel
    @StateObject private var courseViewModel: CourseViewModel
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var historyStore: HistoryStore
    
    init() {
        _viewModel = StateObject(wrappedValue: CaddieViewModel())
        _courseViewModel = StateObject(wrappedValue: CourseViewModel())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Auto-hole tracking toggle
                    Toggle("Auto-hole tracking",
                           isOn: Binding(
                               get: { viewModel.session.autoHoleTrackingEnabled },
                               set: { viewModel.setAutoHoleTrackingEnabled($0) }
                           ))
                    .padding()
                    .background(GolfTheme.cream)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    
                    // Session summary
                    CaddieSessionSummaryView(session: viewModel.session)
                    
                    // Hole suggestion banner
                    if let suggestedHole = viewModel.pendingHoleSuggestion {
                        holeSuggestionBanner(suggestedHole: suggestedHole)
                    }
                    
                    // Main action buttons
                    VStack(spacing: 16) {
                        NavigationLink {
                            FullShotCaddieFlow(
                                viewModel: FullShotCaddieViewModel(caddieSession: viewModel),
                                courseViewModel: courseViewModel
                            )
                            .environmentObject(historyStore)
                        } label: {
                            HStack {
                                Image(systemName: "figure.golf")
                                    .font(.title2)
                                Text("Full-Shot Caddie")
                                    .font(GolfTheme.headlineFont)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(GolfTheme.grassGreen)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: GolfTheme.grassGreen.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        
                        NavigationLink {
                            CaddieGreenReaderWrapper(
                                caddieSession: viewModel,
                                courseViewModel: courseViewModel
                            )
                        } label: {
                            HStack {
                                Image(systemName: "flag.2.crossed")
                                    .font(.title2)
                                Text("Green Reader")
                                    .font(GolfTheme.headlineFont)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(GolfTheme.accentGold)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: GolfTheme.accentGold.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Caddie")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await viewModel.refreshCourseFromGPS()
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundColor(GolfTheme.grassGreen)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func holeSuggestionBanner(suggestedHole: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hole Detection")
                    .font(GolfTheme.headlineFont)
                    .foregroundColor(GolfTheme.textPrimary)
                Text("Looks like you're at Hole \(suggestedHole). Switch?")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Dismiss") {
                    viewModel.dismissHoleSuggestion()
                }
                .foregroundColor(GolfTheme.textSecondary)
                
                Button("Switch") {
                    viewModel.acceptHoleSuggestion()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(GolfTheme.grassGreen)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Session Summary View

struct CaddieSessionSummaryView: View {
    let session: CaddieSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Session")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            if let course = session.course {
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundColor(GolfTheme.grassGreen)
                    Text(course.name)
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)
                }
                
                if let holeNumber = session.currentHoleNumber {
                    HStack {
                        Image(systemName: "number")
                            .foregroundColor(GolfTheme.accentGold)
                        Text("Hole \(holeNumber)")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textPrimary)
                    }
                } else {
                    Text("No hole selected")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                }
            } else {
                Text("No course selected")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    CaddieView()
        .environmentObject(LocationService.shared)
        .environmentObject(ProfileViewModel())
}

