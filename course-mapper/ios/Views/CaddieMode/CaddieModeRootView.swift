//
//  CaddieModeRootView.swift
//  Caddie.AI iOS Client
//
//  Main Caddie mode screen with mode switching
//

import SwiftUI

struct CaddieModeRootView: View {
    @StateObject private var viewModel = CaddieModeViewModel()
    @State private var greenCaddieViewModel: GreenCaddieViewModel?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Mode Picker
                modePickerSection
                
                // Content Area
                contentSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Bottom Info Card
                bottomInfoCard
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.courseDisplayName)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(viewModel.holeDisplayInfo)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Mode Picker
    
    private var modePickerSection: some View {
        Picker("Mode", selection: $viewModel.selectedMode) {
            ForEach(CaddieMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        Group {
            switch viewModel.selectedMode {
            case .tee:
                TeeCaddieView()
            case .approach:
                ApproachCaddieView()
            case .green:
                GreenCaddieView(
                    greenId: viewModel.currentGreenFeatureId ?? 1,
                    initialBallLat: viewModel.ballLat,
                    initialBallLon: viewModel.ballLon,
                    initialHoleLat: viewModel.holeLat,
                    initialHoleLon: viewModel.holeLon,
                    onViewModelCreated: { vm in
                        greenCaddieViewModel = vm
                    }
                )
            }
        }
    }
    
    // MARK: - Bottom Info Card
    
    private var bottomInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch viewModel.selectedMode {
            case .tee:
                TeeInfoCard()
            case .approach:
                ApproachInfoCard()
            case .green:
                if let greenVM = greenCaddieViewModel {
                    GreenInfoCard(viewModel: greenVM)
                } else {
                    GreenInfoCardPlaceholder()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
    }
}

// MARK: - Info Cards

struct TeeInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suggested Club: 3W")
                .font(.headline)
            Text("Target: 245 yds, fairway width: 32 yds")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct ApproachInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suggested Club: 7I")
                .font(.headline)
            Text("160 to center, plays 155 (downhill)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct GreenInfoCard: View {
    @ObservedObject var viewModel: GreenCaddieViewModel
    
    var body: some View {
        Group {
            if let response = viewModel.readingResponse {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aim Offset: \(formatOffset(response.aimOffsetFeet))")
                        .font(.headline)
                    HStack {
                        Text("Ball slope: \(String(format: "%.1f", response.ballSlopePercent))%")
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Hole slope: \(String(format: "%.1f", response.holeSlopePercent))%")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            } else if viewModel.isLoading {
                Text("Calculating read...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                GreenInfoCardPlaceholder()
            }
        }
    }
    
    private func formatOffset(_ feet: Double) -> String {
        let inches = abs(feet * 12)
        let direction = feet >= 0 ? "right" : "left"
        if inches < 12 {
            return String(format: "%.0f in %@", inches, direction)
        } else {
            let wholeFeet = Int(feet)
            let remainingInches = Int((feet - Double(wholeFeet)) * 12)
            if remainingInches == 0 {
                return "\(abs(wholeFeet)) ft \(direction)"
            } else {
                return "\(abs(wholeFeet)) ft \(remainingInches) in \(direction)"
            }
        }
    }
}

struct GreenInfoCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Green Reading")
                .font(.headline)
            Text("Tap and drag to adjust ball/hole positions")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    CaddieModeRootView()
}
