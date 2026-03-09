//
//  PuttingView.swift
//  Caddie.ai
//
//  View for uploading/taking a photo for putting analysis
//

import SwiftUI

struct PuttingView: View {
    @EnvironmentObject var locationService: LocationService
    @StateObject private var viewModel = PuttingViewModel()
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if viewModel.isAnalyzing {
                    ProgressView("Analyzing putt...")
                        .padding()
                } else if let result = viewModel.result {
                    PuttingResultView(result: result)
                        .padding()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.accentColor)
                        
                        Text("Take or choose a photo of your putt")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        PrimaryButton(title: "Choose/Take Photo") {
                            showingImagePicker = true
                        }
                        .padding(.horizontal)
                        
                        if let error = viewModel.errorMessage {
                            Text("Error: \(error)")
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Putting")
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .onChange(of: selectedImage) { oldValue, newValue in
                if let image = newValue {
                    Task {
                        await viewModel.analyze(
                            image: image,
                            location: locationService.coordinate
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    PuttingView()
        .environmentObject(LocationService.shared)
}

