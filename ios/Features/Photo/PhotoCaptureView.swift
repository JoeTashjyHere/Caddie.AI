//
//  PhotoCaptureView.swift
//  Caddie.ai
//
//  View for capturing photo with metadata (club, shotType, distance)
//

import SwiftUI
import PhotosUI
import UIKit

struct PhotoCaptureView: View {
    let course: Course
    let holeNumber: Int
    let shotType: ShotType
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var uploadState: ViewState = .idle
    @State private var shotFlowState: ShotFlowState = .idle
    @State private var recommendationAccepted: Bool = false
    
    @State private var selectedClub: String = ""
    @State private var distance: String = ""
    @State private var recommendation: PhotoRecommendation?
    @State private var shotContext: PhotoShotContext?
    @State private var showContextSheet = false
    @State private var contextDraft = CaddieContextDraft()
    @State private var pendingImageForAnalysis: UIImage?
    
    @State private var capturedShot: CapturedShot?
    @State private var uploadedShotId: String?
    @State private var uploadedImageURL: String?
    
    // Legacy computed properties for backward compatibility
    private var isUploading: Bool {
        uploadState == .loading
    }
    
    private var errorMessage: String? {
        uploadState.errorMessage
    }
    
    var onCapture: (CapturedShot) -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(course.displayName)
                            .font(GolfTheme.titleFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        Text("Hole \(holeNumber) • \(shotType.displayName)")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .padding(.top)
                    
                    // Metadata input section
                    metadataInputSection
                    
                    // Photo selection/preview
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
                            VStack(spacing: 0) {
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
                                .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                            
                            // Save button below recommendation
                            saveButton
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
                            VStack(spacing: 0) {
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
                                .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                            
                            // Save button below recommendation
                            saveButton
                        }
                    }
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Capture Shot")
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
            .sheet(isPresented: $showContextSheet) {
                ContextConfirmSheet(
                    draft: $contextDraft,
                    confidence: .medium,
                    hasPhoto: pendingImageForAnalysis != nil,
                    isSubmitting: isUploading,
                    onGetRecommendation: {
                        showContextSheet = false
                        if let image = pendingImageForAnalysis {
                            Task {
                                await uploadPhoto(image: image)
                            }
                        }
                    }
                )
            }
        }
        .interactiveDismissDisabled(isUploading)
        .onAppear {
            // Initialize with first club if available
            if selectedClub.isEmpty, let firstClub = profileViewModel.profile.clubs.first {
                selectedClub = firstClub.name
            }
        }
    }
    
    // MARK: - Metadata Input Section
    
    private var metadataInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shot Details")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            // Club picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Club")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
                
                Picker("Club", selection: $selectedClub) {
                    Text("None").tag("")
                    ForEach(profileViewModel.profile.clubs, id: \.name) { club in
                        Text(club.name).tag(club.name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(8)
            }
            
            // Distance input
            VStack(alignment: .leading, spacing: 8) {
                Text("Distance (yards)")
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textSecondary)
                
                TextField("Enter distance", text: $distance)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
    
    // MARK: - Photo Selection Section
    
    private var photoSelectionSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(GolfTheme.grassGreen)
            
            Text("Capture your shot")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Text("Take or select a photo of your lie")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 16) {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    showingImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Choose")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(GolfTheme.grassGreen)
                    .cornerRadius(12)
                }
                
                Button(action: {
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
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            
            HStack(spacing: 12) {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    selectedImage = nil
                    recommendation = nil
                    shotContext = nil
                    uploadedShotId = nil
                    uploadedImageURL = nil
                    uploadState = .idle
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
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    startAnalyzeFlow(with: image)
                }) {
                    HStack {
                        if isUploading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Analyze")
                        }
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isUploading ? GolfTheme.textSecondary : GolfTheme.grassGreen)
                    .cornerRadius(12)
                }
                .disabled(isUploading || selectedClub.isEmpty)
                .opacity(isUploading || selectedClub.isEmpty ? 0.7 : 1.0)
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Save Button (shown below recommendation card)
    
    private var saveButton: some View {
        Button(action: {
            saveCapturedShot()
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Shot")
            }
            .font(GolfTheme.bodyFont)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(GolfTheme.grassGreen)
            .cornerRadius(12)
        }
        .padding(.horizontal)
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
            "shotType": contextDraft.shotType.rawValue
        ]
        if !selectedClub.isEmpty {
            payloadDict["club"] = selectedClub
        }
        if let distanceValue = effectiveDistanceInt() {
            payloadDict["distance"] = distanceValue
        }
        if let courseName = contextDraft.courseName {
            payloadDict["courseName"] = courseName
        }
        if let city = contextDraft.city {
            payloadDict["city"] = city
        }
        if let state = contextDraft.state {
            payloadDict["state"] = state
        }
        if let lie = contextDraft.lie {
            payloadDict["lie"] = lie
        }
        if let hazards = contextDraft.hazards {
            payloadDict["hazards"] = hazards
        }
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
        body.append(contextDraft.shotType.rawValue.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add selected club if available
        if !selectedClub.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"club\"\r\n\r\n".data(using: .utf8)!)
            body.append(selectedClub.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Add distance if available
        if let distanceValue = effectiveDistanceInt() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"distance\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(distanceValue)".data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        if let courseName = contextDraft.courseName {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"courseName\"\r\n\r\n".data(using: .utf8)!)
            body.append(courseName.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        if let city = contextDraft.city {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"city\"\r\n\r\n".data(using: .utf8)!)
            body.append(city.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        if let state = contextDraft.state {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"state\"\r\n\r\n".data(using: .utf8)!)
            body.append(state.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        if let lie = contextDraft.lie {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"lie\"\r\n\r\n".data(using: .utf8)!)
            body.append(lie.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        if let hazards = contextDraft.hazards {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"hazards\"\r\n\r\n".data(using: .utf8)!)
            body.append(hazards.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
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
                let error = NSError(domain: "PhotoCaptureView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
                uploadState = .error("Invalid server response. Please try again.")
                DebugLogging.logAPI(endpoint: "photo/analyze", url: url, method: "POST", payload: payloadDict, responseData: data, error: error)
                logger.logPhotoUpload(courseId: course.id, holeNumber: holeNumber, shotType: shotType.rawValue, success: false, error: error)
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let responseString = String(data: data, encoding: .utf8) ?? ""
                let errorMessage: String
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    errorMessage = errorResponse.error ?? "Photo upload failed. Please try again."
                } else {
                    errorMessage = "Photo upload failed (Status: \(httpResponse.statusCode)). Please try again."
                }
                uploadState = .error(errorMessage)
                let error = NSError(domain: "PhotoCaptureView", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: responseString])
                DebugLogging.logAPI(endpoint: "photo/analyze", url: url, method: "POST", payload: payloadDict, responseStatus: httpResponse.statusCode, responseData: data, error: error)
                logger.logPhotoUpload(courseId: course.id, holeNumber: holeNumber, shotType: shotType.rawValue, success: false, error: error)
                return
            }
            
            // Update state to waiting for recommendation
            shotFlowState = .waitingForRecommendation
            
            // Parse response defensively
            do {
                let responseData = try JSONDecoder().decode(PhotoUploadResponse.self, from: data)
                recommendation = responseData.recommendation
                shotContext = responseData.shotContext
                uploadedShotId = responseData.shotId
                uploadedImageURL = responseData.imageUrl
                
                DebugLogging.logAPI(endpoint: "photo/analyze", url: url, method: "POST", payload: payloadDict, responseStatus: httpResponse.statusCode, parsedModel: responseData)
                logger.logPhotoUpload(courseId: course.id, holeNumber: holeNumber, shotType: shotType.rawValue, success: true, error: nil)
                
                // Success haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
                
                uploadState = .loaded
                shotFlowState = .showingRecommendation
                recommendationAccepted = false
                
            } catch {
                // Parsing error - try fallback chain through RecommenderService
                DebugLogging.log("⚠️ Photo upload parsing failed, attempting text AI fallback", category: "ShotFlow")
                
                // Fallback to text-based AI recommendation
                shotFlowState = .waitingForRecommendation
                
                // Build shot context for fallback - declare outside do/catch for scope
                let distanceInt = Int(distance) ?? Int(locationService.coordinate != nil ? 150 : 0)
                
                do {
                    // Try to get recommendation via RecommenderService
                    let fallbackRec = try await getFallbackRecommendation(distance: distanceInt)
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
                    let offlineRec = getOfflineRecommendation(distance: distanceInt)
                    recommendation = PhotoRecommendation(
                        club: offlineRec.club,
                        aim: offlineRec.narrative,
                        avoid: "",
                        confidence: 0.6
                    )
                    shotFlowState = .showingRecommendation
                    uploadState = .loaded
                    
                    // Log fallback usage
                    DebugLogging.logAPI(endpoint: "photo/analyze", url: url, method: "POST", payload: payloadDict, responseStatus: httpResponse.statusCode, responseData: data, error: error)
                    logger.logPhotoUpload(courseId: course.id, holeNumber: holeNumber, shotType: shotType.rawValue, success: false, error: error)
                }
                
                // Error haptic feedback
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.error)
            }
            
        } catch {
            // Network error - try fallback chain
            DebugLogging.log("⚠️ Photo upload network error, attempting fallback chain", category: "ShotFlow")
            
            let distanceInt = Int(distance) ?? 150
            
            do {
                shotFlowState = .waitingForRecommendation
                let fallbackRec = try await getFallbackRecommendation(distance: distanceInt)
                recommendation = PhotoRecommendation(
                    club: fallbackRec.club,
                    aim: fallbackRec.narrative,
                    avoid: fallbackRec.avoidZones.joined(separator: ", "),
                    confidence: fallbackRec.confidence
                )
                shotFlowState = .showingRecommendation
                uploadState = .loaded
                DebugLogging.log("✅ Fallback recommendation received after network error", category: "ShotFlow")
            } catch {
                // Final fallback - offline
                DebugLogging.log("⚠️ All methods failed, using offline fallback", category: "ShotFlow")
                let offlineRec = getOfflineRecommendation(distance: distanceInt)
                recommendation = PhotoRecommendation(
                    club: offlineRec.club,
                    aim: offlineRec.narrative,
                    avoid: "",
                    confidence: 0.6
                )
                shotFlowState = .showingRecommendation
                uploadState = .loaded
                
                DebugLogging.logAPI(endpoint: "photo/analyze", url: url, method: "POST", payload: payloadDict, error: error)
                logger.logPhotoUpload(courseId: course.id, holeNumber: holeNumber, shotType: shotType.rawValue, success: false, error: error)
            }
            
            // Error haptic feedback
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.error)
        }
    }
    
    // MARK: - Save Captured Shot
    
    private func saveCapturedShot() {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        
        // Require recommendation acceptance before save.
        guard recommendationAccepted else {
            DebugLogging.log("⚠️ Attempted to save shot without accepting recommendation", category: "ShotFlow")
            return
        }
        
        let distanceInt: Int? = Int(distance)
        
        let shot = CapturedShot(
            shotType: shotType,
            club: selectedClub.isEmpty ? nil : selectedClub,
            distance: distanceInt,
            timestamp: Date(),
            imageData: imageData,
            imageURL: absoluteImageURL(from: uploadedImageURL),
            recommendation: recommendation,
            shotContext: shotContext,
            holeNumber: holeNumber,
            backendId: uploadedShotId
        )
        
        // Reset state for next shot
        resetShotFlow()
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        onCapture(shot)
        uploadedShotId = nil
        uploadedImageURL = nil
        capturedShot = shot
        dismiss()
    }
    
    private func resetShotFlow() {
        shotFlowState = .idle
        recommendationAccepted = false
        selectedImage = nil
    }

    private func startAnalyzeFlow(with image: UIImage) {
        pendingImageForAnalysis = image
        prefillContextDraft()

        if hasRequiredContextFields {
            Task {
                await uploadPhoto(image: image)
            }
        } else {
            showContextSheet = true
        }
    }

    private func prefillContextDraft() {
        contextDraft.course = course
        contextDraft.courseName = contextDraft.courseName ?? course.name
        contextDraft.holeNumber = holeNumber
        contextDraft.shotType = shotType
        contextDraft.lie = contextDraft.lie ?? "Fairway"
        if contextDraft.distanceYards == nil, let typedDistance = Double(distance), typedDistance > 0 {
            contextDraft.distanceYards = typedDistance
        }
    }

    private var hasRequiredContextFields: Bool {
        let hasCourseName = !(contextDraft.courseName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasCity = !(contextDraft.city?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasState = !(contextDraft.state?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasHole = (contextDraft.holeNumber.map { (1...18).contains($0) } ?? false)
        let hasDistance = (contextDraft.distanceYards ?? 0) > 0
        return hasCourseName && hasCity && hasState && hasHole && hasDistance
    }

    private func effectiveDistanceInt() -> Int? {
        if let draftDistance = contextDraft.distanceYards, draftDistance > 0 {
            return Int(draftDistance)
        }
        if let typed = Int(distance), typed > 0 {
            return typed
        }
        return nil
    }
    
    private func absoluteImageURL(from path: String?) -> String? {
        guard let path else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        // Use APIService as single source of truth for base URL
        return APIConfig.baseURLString + path
    }
    
    // MARK: - Fallback Recommendation Helpers
    
    private func getFallbackRecommendation(distance: Int) async throws -> ShotRecommendation {
        guard let location = locationService.coordinate else {
            throw NSError(domain: "PhotoCaptureView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location not available"])
        }
        
        // Build basic shot context
        let shotContext = ShotContext(
            hole: holeNumber,
            playerCoordinate: location,
            targetCoordinate: location, // Use player location as fallback
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
            photo: nil // No photo for text fallback
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
