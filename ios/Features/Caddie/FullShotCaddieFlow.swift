//
//  FullShotCaddieFlow.swift
//  Caddie.ai
//
//  Multi-step flow for full-shot caddie recommendations

import SwiftUI
import UIKit

struct FullShotCaddieFlow: View {
    @ObservedObject var viewModel: FullShotCaddieViewModel
    @ObservedObject var courseViewModel: CourseViewModel
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var historyStore: HistoryStore
    @Environment(\.dismiss) var dismiss
    
    init(viewModel: FullShotCaddieViewModel, courseViewModel: CourseViewModel) {
        self.viewModel = viewModel
        self.courseViewModel = courseViewModel
        // Inject profile view model
        viewModel.profileViewModel = nil // Will be set via environment
    }
    
    var body: some View {
        Group {
            // Inject profile view model
            let _ = {
                viewModel.profileViewModel = profileViewModel
            }()
            
            switch viewModel.step {
            case .courseAndHole:
                CaddieCourseSelectionView(viewModel: viewModel, courseViewModel: courseViewModel)
            case .distanceInput:
                CaddieDistanceInputView(viewModel: viewModel)
            case .photoCapture:
                CaddiePhotoCaptureView(viewModel: viewModel)
            case .lieConfirmation:
                CaddieLieConfirmationView(viewModel: viewModel)
            case .recommendation:
                CaddieRecommendationView(viewModel: viewModel)
            case .feedback:
                CaddieShotFeedbackView(viewModel: viewModel)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Inject historyStore into viewModel
            viewModel.historyStore = historyStore
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.step != .courseAndHole {
                    Button("Back") {
                        viewModel.goBack()
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Course Selection Step

struct CaddieCourseSelectionView: View {
    @ObservedObject var viewModel: FullShotCaddieViewModel
    @ObservedObject var courseViewModel: CourseViewModel
    @EnvironmentObject var locationService: LocationService
    @State private var selectedHole: Int?
    
    var body: some View {
        VStack(spacing: 24) {
            // Course selection
            CourseSelectionView()
                .environmentObject(courseViewModel)
                .environmentObject(locationService)
                .frame(maxHeight: 400)
            
            // Hole selection (if course is selected)
            if viewModel.caddieSession.session.course != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Hole")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(1...18, id: \.self) { hole in
                                Button {
                                    viewModel.caddieSession.selectHole(hole)
                                    selectedHole = hole
                                } label: {
                                    Text("\(hole)")
                                        .font(GolfTheme.headlineFont)
                                        .foregroundColor(selectedHole == hole || viewModel.caddieSession.session.currentHoleNumber == hole ? .white : GolfTheme.textPrimary)
                                        .frame(width: 50, height: 50)
                                        .background(selectedHole == hole || viewModel.caddieSession.session.currentHoleNumber == hole ? GolfTheme.grassGreen : GolfTheme.cream)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Button {
                    if viewModel.caddieSession.session.isReady {
                        viewModel.proceedToNextStep()
                    }
                } label: {
                    Text("Continue")
                        .font(GolfTheme.headlineFont)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.caddieSession.session.isReady ? GolfTheme.grassGreen : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .disabled(!viewModel.caddieSession.session.isReady)
                .padding(.horizontal)
            }
        }
        .background(GolfTheme.cream.ignoresSafeArea())
        .onAppear {
            selectedHole = viewModel.caddieSession.session.currentHoleNumber
        }
        .onChange(of: courseViewModel.currentCourse) { oldValue, newValue in
            if let course = newValue {
                viewModel.caddieSession.selectCourse(course)
            }
        }
    }
}

// MARK: - Distance Input Step

struct CaddieDistanceInputView: View {
    @ObservedObject var viewModel: FullShotCaddieViewModel
    @State private var distanceText: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Distance to Target")
                    .font(GolfTheme.titleFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .padding(.top)
                
                Text("Enter the distance in yards to your target")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                TextField("Yards", text: $distanceText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                
                Button {
                    if let distance = Double(distanceText) {
                        viewModel.setDistance(distance)
                        viewModel.proceedToNextStep()
                    }
                } label: {
                    Text("Continue")
                        .font(GolfTheme.headlineFont)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(distanceText.isEmpty ? Color.gray : GolfTheme.grassGreen)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .disabled(distanceText.isEmpty)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
        }
        .background(GolfTheme.cream.ignoresSafeArea())
    }
}

// MARK: - Photo Capture Step

struct CaddiePhotoCaptureView: View {
    @ObservedObject var viewModel: FullShotCaddieViewModel
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Capture Your Lie")
                    .font(GolfTheme.titleFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .padding(.top)
                
                Text("Take a photo of your ball position and lie")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if let image = selectedImage ?? viewModel.capturedPhoto {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .cornerRadius(16)
                        .padding()
                    
                    Button {
                        selectedImage = nil
                        viewModel.capturedPhoto = nil
                    } label: {
                        Text("Retake")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.grassGreen)
                    }
                } else {
                    VStack(spacing: 16) {
                        Button {
                            showingCamera = true
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                                Text("Take Photo")
                                    .font(GolfTheme.headlineFont)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(GolfTheme.grassGreen)
                            .cornerRadius(16)
                        }
                        
                        Button {
                            showingImagePicker = true
                        } label: {
                            Text("Choose from Library")
                                .font(GolfTheme.bodyFont)
                                .foregroundColor(GolfTheme.grassGreen)
                        }
                    }
                    .padding(.horizontal)
                }
                
                if selectedImage != nil || viewModel.capturedPhoto != nil {
                    Button {
                        if let image = selectedImage {
                            viewModel.setPhoto(image)
                        }
                        viewModel.proceedToNextStep()
                    } label: {
                        Text("Continue")
                            .font(GolfTheme.headlineFont)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(GolfTheme.grassGreen)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
        }
        .background(GolfTheme.cream.ignoresSafeArea())
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(selectedImage: $selectedImage)
        }
    }
}

// MARK: - Lie Confirmation Step

struct CaddieLieConfirmationView: View {
    @ObservedObject var viewModel: FullShotCaddieViewModel
    @State private var selectedLie: String = "Fairway"
    
    let lieTypes = ["Fairway", "Rough", "Bunker", "Tee", "Green"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Confirm Lie Type")
                    .font(GolfTheme.titleFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .padding(.top)
                
                if let photo = viewModel.capturedPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .cornerRadius(16)
                        .padding()
                }
                
                VStack(spacing: 12) {
                    ForEach(lieTypes, id: \.self) { lie in
                        Button {
                            selectedLie = lie
                        } label: {
                            HStack {
                                Text(lie)
                                    .font(GolfTheme.bodyFont)
                                    .foregroundColor(selectedLie == lie ? .white : GolfTheme.textPrimary)
                                Spacer()
                                if selectedLie == lie {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding()
                            .background(selectedLie == lie ? GolfTheme.grassGreen : GolfTheme.cream)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
                
                Button {
                    viewModel.setLieType(selectedLie)
                    viewModel.proceedToNextStep()
                } label: {
                    Text("Continue")
                        .font(GolfTheme.headlineFont)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(GolfTheme.grassGreen)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
        }
        .background(GolfTheme.cream.ignoresSafeArea())
        .onAppear {
            selectedLie = viewModel.lieType
        }
    }
}

// MARK: - Recommendation Step

struct CaddieRecommendationView: View {
    @ObservedObject var viewModel: FullShotCaddieViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Analyzing your shot...")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if let recommendation = viewModel.recommendation {
                    RecommendationCardView(
                        recommendation: recommendation,
                        onThumbsUp: {
                            viewModel.proceedToNextStep()
                        },
                        onThumbsDown: {
                            viewModel.proceedToNextStep()
                        },
                        distance: viewModel.distanceToTarget.map { Int($0) },
                        lie: viewModel.lieType
                    )
                    .padding()
                    
                    Button {
                        viewModel.proceedToNextStep()
                    } label: {
                        Text("Log Shot Outcome")
                            .font(GolfTheme.headlineFont)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(GolfTheme.accentGold)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Error")
                            .font(GolfTheme.headlineFont)
                        Text(error)
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
                Spacer()
            }
            .padding()
        }
        .background(GolfTheme.cream.ignoresSafeArea())
    }
}

// MARK: - Feedback Step

struct CaddieShotFeedbackView: View {
    @ObservedObject var viewModel: FullShotCaddieViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var clubUsed: String = ""
    @State private var contactQuality: String = "Good"
    @State private var resultHorizontal: String = "Straight"
    @State private var resultVertical: String = "Pin High"
    
    let contactOptions = ["Poor", "Fair", "Good", "Great"]
    let horizontalOptions = ["Left", "Straight", "Right"]
    let verticalOptions = ["Short", "Pin High", "Long"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("How did it go?")
                    .font(GolfTheme.titleFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .padding(.top)
                
                Text("Help improve recommendations by logging your shot outcome")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Club used
                VStack(alignment: .leading, spacing: 8) {
                    Text("Club Used")
                        .font(GolfTheme.headlineFont)
                    TextField("e.g., 7 Iron", text: $clubUsed)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)
                
                // Contact quality
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact Quality")
                        .font(GolfTheme.headlineFont)
                    Picker("Contact", selection: $contactQuality) {
                        ForEach(contactOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                // Result - Horizontal
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result - Left/Right")
                        .font(GolfTheme.headlineFont)
                    Picker("Horizontal", selection: $resultHorizontal) {
                        ForEach(horizontalOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                // Result - Vertical
                VStack(alignment: .leading, spacing: 8) {
                    Text("Result - Distance")
                        .font(GolfTheme.headlineFont)
                    Picker("Vertical", selection: $resultVertical) {
                        ForEach(verticalOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                Button {
                    viewModel.submitFeedback(
                        clubUsed: clubUsed.isEmpty ? nil : clubUsed,
                        contactQuality: contactQuality,
                        resultHorizontal: resultHorizontal,
                        resultVertical: resultVertical
                    )
                    dismiss()
                } label: {
                    Text("Submit")
                        .font(GolfTheme.headlineFont)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(GolfTheme.grassGreen)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
        }
        .background(GolfTheme.cream.ignoresSafeArea())
    }
}

