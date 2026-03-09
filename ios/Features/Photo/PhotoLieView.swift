//
//  PhotoLieView.swift
//  Caddie.ai
//
//  View for capturing/uploading golf lie photo and getting AI recommendation
//

import SwiftUI
import PhotosUI
import UIKit
import CoreLocation

struct PhotoLieView: View {
    let course: Course
    let holeNumber: Int
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var uploadState: ViewState = .idle
    @State private var shotFlowState: ShotFlowState = .idle
    @State private var recommendationAccepted: Bool = false
    @State private var recommendation: PhotoRecommendation?
    @State private var shotContext: PhotoShotContext?
    @State private var showSuccess = false
    @State private var selectedShotType: ShotType = .approach
    
    // Legacy computed properties for backward compatibility
    private var isUploading: Bool {
        uploadState == .loading
    }
    
    private var errorMessage: String? {
        uploadState.errorMessage
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(course.name)
                            .font(GolfTheme.titleFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        Text("Hole \(holeNumber)")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .padding(.top)
                    
                    // Shot type picker (show before photo selection)
                    if selectedImage == nil {
                        shotTypePicker
                    }
                    
                    // Photo preview section
                    if let image = selectedImage {
                        photoPreviewSection(image: image)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedImage != nil)
                    } else {
                        photoSelectionSection
                    }
                    
                    // State-based content
                    switch uploadState {
                    case .loading:
                        LoadingView(message: "Analyzing photo...")
                            .padding(.horizontal)
                    case .loaded:
                        if let recommendation = recommendation {
                            PhotoRecommendationCardView(
                                recommendation: recommendation,
                                shotContext: shotContext,
                                onThumbsUp: {
                                    // Feedback can be added here if needed
                                },
                                onThumbsDown: {
                                    // Feedback can be added here if needed
                                }
                            )
                            .padding(.horizontal, 16)
                        }
                    case .error(let message):
                        ErrorView(message: message) {
                            if let image = selectedImage {
                                Task {
                                    await uploadPhoto(image: image)
                                }
                            }
                        }
                    case .idle, .empty:
                        if let recommendation = recommendation {
                            PhotoRecommendationCardView(
                                recommendation: recommendation,
                                shotContext: shotContext,
                                onThumbsUp: {
                                    // Feedback can be added here if needed
                                },
                                onThumbsDown: {
                                    // Feedback can be added here if needed
                                }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Photo Lie Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(GolfTheme.textSecondary)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker(selectedImage: $selectedImage)
            }
        }
    }
    
    // MARK: - Shot Type Picker
    
    private var shotTypePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shot Type")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Picker("Shot Type", selection: $selectedShotType) {
                ForEach(ShotType.allCases, id: \.self) { shotType in
                    Text(shotType.displayName).tag(shotType)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .padding(.horizontal)
    }
    
    // MARK: - Photo Selection Section
    
    private var photoSelectionSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(GolfTheme.grassGreen)
            
            Text("Capture your golf lie")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Text("Take or select a photo of your lie to get AI recommendations")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 16) {
                Button(action: {
                    // Haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    showingImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Choose Photo")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(GolfTheme.grassGreen)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    // Haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    showingCamera = true
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(GolfTheme.accentGold)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Photo Preview Section
    
    private func photoPreviewSection(image: UIImage) -> some View {
        VStack(spacing: 16) {
            // Photo preview
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 400)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    // Haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    
                    resetShotFlow()
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Retake")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(GolfTheme.cream)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GolfTheme.textSecondary.opacity(0.3), lineWidth: 1)
                    )
                }
                
                Button(action: {
                    // Haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    Task {
                        await uploadPhoto(image: image)
                    }
                }) {
                    HStack {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Use Photo")
                        }
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isUploading ? GolfTheme.textSecondary : GolfTheme.grassGreen)
                    .cornerRadius(12)
                }
                .disabled(isUploading)
                .opacity(isUploading ? 0.7 : 1.0)
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Upload Photo
    
    private func uploadPhoto(image: UIImage) async {
        // Reset state for new shot flow
        recommendationAccepted = false
        recommendation = nil
        shotContext = nil
        uploadState = .loading
        shotFlowState = .sendingToAI
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            uploadState = .error("Failed to process image")
            shotFlowState = .error("Failed to process image")
            return
        }
        
        // Use APIService as single source of truth for base URL
        let url = APIService.getBaseURL().appendingPathComponent("api/photo/analyze")
        
        // Build payload for logging
        var payloadDict: [String: Any] = [
            "courseId": course.id,
            "holeNumber": holeNumber,
            "shotType": selectedShotType.rawValue
        ]
        if let lat = locationService.coordinate?.latitude {
            payloadDict["lat"] = lat
        }
        if let lon = locationService.coordinate?.longitude {
            payloadDict["lon"] = lon
        }
        payloadDict["photo"] = "[multipart image data, \(imageData.count) bytes]"
        
        DebugLogging.logAPI(endpoint: "photo/analyze", url: url, method: "POST", payload: payloadDict)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Create multipart/form-data body
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add photo field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add playerProfile field
        let profileData = try? JSONEncoder().encode(profileViewModel.profile)
        let profileString = profileData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"playerProfile\"\r\n\r\n".data(using: .utf8)!)
        body.append(profileString.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add courseId field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"courseId\"\r\n\r\n".data(using: .utf8)!)
        body.append(course.id.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add holeNumber field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"holeNumber\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(holeNumber)".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add shotType field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"shotType\"\r\n\r\n".data(using: .utf8)!)
        body.append(selectedShotType.rawValue.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add lat field (if available)
        if let lat = locationService.coordinate?.latitude {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"lat\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lat)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add lon field (if available)
        if let lon = locationService.coordinate?.longitude {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"lon\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lon)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let logger = AILogger.shared
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                // Try fallback chain
                await tryFallbackChain(image: image)
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                // Try fallback chain
                await tryFallbackChain(image: image)
                return
            }
            
            // Update state to waiting for recommendation
            shotFlowState = .waitingForRecommendation
            
            // Parse response defensively
            do {
                let responseData = try JSONDecoder().decode(PhotoUploadResponse.self, from: data)
                recommendation = responseData.recommendation
                shotContext = responseData.shotContext
                
                DebugLogging.logAPI(endpoint: "photo/analyze", url: url, method: "POST", payload: payloadDict, responseStatus: httpResponse.statusCode, parsedModel: responseData)
                logger.logPhotoUpload(courseId: course.id, holeNumber: holeNumber, shotType: selectedShotType.rawValue, success: true, error: nil)
                
                // Success haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
                
                showSuccess = true
                uploadState = .loaded
                shotFlowState = .showingRecommendation
                recommendationAccepted = false
            } catch {
                // Parsing error - try fallback chain
                DebugLogging.log("⚠️ Photo upload parsing failed, attempting fallback chain", category: "ShotFlow")
                await tryFallbackChain(image: image)
            }
            
        } catch {
            // Network error - try fallback chain
            DebugLogging.log("⚠️ Photo upload network error, attempting fallback chain", category: "ShotFlow")
            await tryFallbackChain(image: image)
        }
    }
    
    private func resetShotFlow() {
        shotFlowState = .idle
        recommendationAccepted = false
        selectedImage = nil
        recommendation = nil
        uploadState = .idle
    }
    
    private func tryFallbackChain(image: UIImage) async {
        shotFlowState = .waitingForRecommendation
        
        // Calculate default distance if not available
        let defaultDistance = calculateDefaultDistance()
        
        do {
            // Try text-based AI recommendation
            let fallbackRec = try await getFallbackRecommendation(distance: defaultDistance)
            recommendation = PhotoRecommendation(
                club: fallbackRec.club,
                aim: fallbackRec.narrative,
                avoid: fallbackRec.avoidZones.joined(separator: ", "),
                confidence: fallbackRec.confidence
            )
            shotFlowState = .showingRecommendation
            uploadState = .loaded
            DebugLogging.log("✅ Fallback recommendation received", category: "ShotFlow")
        } catch {
            // Final fallback - offline recommendation
            DebugLogging.log("⚠️ All AI methods failed, using offline fallback", category: "ShotFlow")
            let offlineRec = getOfflineRecommendation(distance: defaultDistance)
            recommendation = PhotoRecommendation(
                club: offlineRec.club,
                aim: offlineRec.narrative,
                avoid: "",
                confidence: 0.6
            )
            shotFlowState = .showingRecommendation
            uploadState = .loaded
        }
    }
    
    private func calculateDefaultDistance() -> Int {
        // Try to get distance from course/hole context if available
        // For now, use a default approach shot distance
        return 150 // Default approach shot distance
    }
    
    private func getFallbackRecommendation(distance: Int) async throws -> ShotRecommendation {
        guard let location = locationService.coordinate else {
            throw NSError(domain: "PhotoLieView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location not available"])
        }
        
        // Build basic shot context
        let shotContext = ShotContext(
            hole: holeNumber,
            playerCoordinate: location,
            targetCoordinate: location,
            distanceToCenter: Double(distance),
            elevationDelta: 0,
            windSpeedMph: 0,
            windDirectionDeg: 0,
            temperatureF: 70,
            lieType: "Fairway"
        )
        
        // Try text-based AI recommendation (RecommenderService handles fallback chain internally)
        return try await RecommenderService.shared.getRecommendation(
            profile: profileViewModel.profile,
            context: shotContext,
            hazards: [],
            course: course,
            photo: nil
        )
    }
    
    private func getOfflineRecommendation(distance: Int) -> ShotRecommendation {
        let profile = profileViewModel.profile
        guard !profile.clubs.isEmpty else {
            return ShotRecommendation(
                club: "7i",
                aimOffsetYards: 0.0,
                shotShape: "Straight",
                narrative: "⚠️ Offline fallback: Using 7i for \(distance) yards. Aim for center of green.",
                confidence: 0.5,
                avoidZones: []
            )
        }
        
        let closestClub = profile.clubs.min(by: { abs($0.carryYards - distance) < abs($1.carryYards - distance) }) ?? profile.clubs[0]
        return ShotRecommendation(
            club: closestClub.name,
            aimOffsetYards: 0.0,
            shotShape: closestClub.preferredShotShape.rawValue.capitalized,
            narrative: "⚠️ Offline fallback: Using \(closestClub.name) for \(distance) yards. Aim for center of green.",
            confidence: 0.6,
            avoidZones: []
        )
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        
        init(_ parent: CameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Response Models

struct PhotoUploadResponse: Codable {
    let recommendation: PhotoRecommendation
    let shotContext: PhotoShotContext?
    let shotId: String?
    let imageUrl: String?
}

struct PhotoRecommendation: Codable {
    let club: String
    let aim: String
    let avoid: String
    let confidence: Double
    
    // Optional structured fields for varied recommendations (when backend supports)
    let headline: String?
    let bullets: [String]?
    let commitCue: String?
    
    init(club: String, aim: String, avoid: String, confidence: Double, headline: String? = nil, bullets: [String]? = nil, commitCue: String? = nil) {
        self.club = club
        self.aim = aim
        self.avoid = avoid
        self.confidence = confidence
        self.headline = headline
        self.bullets = bullets
        self.commitCue = commitCue
    }
}

struct PhotoShotContext: Codable {
    let shotType: String
    let surface: String
    let conditions: ShotConditions?
}

struct ShotConditions: Codable {
    let wind: String?
    let elevation: String?
}

struct ErrorResponse: Codable {
    let error: String?
}

