//
//  PlayView.swift
//  Caddie.ai
//
//  Main play view with map and shot recommendations
//

import SwiftUI
import MapKit

struct PlayView: View {
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @StateObject private var viewModel = PlayViewModel()
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Map view
                Map(coordinateRegion: $mapRegion, showsUserLocation: true, userTrackingMode: .none)
                    .frame(height: 300)
                    .onChange(of: locationService.coordinate) { oldValue, newValue in
                        if let coordinate = newValue {
                            mapRegion = MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                        }
                    }
                
                // Content area
                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.isLoading {
                            ProgressView("Getting recommendation...")
                                .padding()
                        } else if let recommendation = viewModel.recommendation {
                            RecommendationCardView(
                                recommendation: recommendation,
                                onThumbsUp: {
                                    viewModel.sendFeedback(success: true)
                                },
                                onThumbsDown: {
                                    viewModel.sendFeedback(success: false)
                                }
                            )
                            .padding()
                        } else {
                            if let error = viewModel.errorMessage {
                                Text("Error: \(error)")
                                    .foregroundColor(.red)
                                    .padding()
                            }
                            
                            PrimaryButton(title: "Get Recommendation") {
                                Task {
                                    await viewModel.getRecommendation(
                                        profile: profileViewModel.profile,
                                        location: locationService.coordinate
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Play")
            .onAppear {
                locationService.startUpdating()
                if let coordinate = locationService.coordinate {
                    mapRegion = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                }
            }
        }
    }
}

#Preview {
    PlayView()
        .environmentObject(LocationService.shared)
        .environmentObject(ProfileViewModel())
}

