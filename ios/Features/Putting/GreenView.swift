//
//  GreenView.swift
//  Caddie.ai
//
//  View for capturing and analyzing putting green photos
//

import SwiftUI
import PhotosUI
import UIKit

struct GreenView: View {
    let course: Course
    let holeNumber: Int
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var historyStore: HistoryStore
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var puttingViewModel = PuttingViewModel()
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(course.displayName)
                            .font(GolfTheme.titleFont)
                            .foregroundColor(GolfTheme.textPrimary)
                        Text("Hole \(holeNumber) • Putting Analysis")
                            .font(GolfTheme.bodyFont)
                            .foregroundColor(GolfTheme.textSecondary)
                    }
                    .padding(.top)
                    
                    // Photo selection/preview
                    if let image = selectedImage {
                        photoPreviewSection(image: image)
                    } else {
                        photoSelectionSection
                    }
                    
                    // Loading state
                    if puttingViewModel.isLoading {
                        loadingSection
                    }
                    
                    // Putting read result
                    if let puttingRead = puttingViewModel.puttingRead {
                        puttingReadCard(puttingRead: puttingRead)
                    }
                    
                    // Error message
                    if let error = puttingViewModel.errorMessage {
                        errorCard(error: error)
                    }
                }
                .padding()
            }
            .background(GolfTheme.cream.ignoresSafeArea())
            .navigationTitle("Putting Analysis")
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
                CameraPickerView(selectedImage: $selectedImage)
            }
            .interactiveDismissDisabled(puttingViewModel.isLoading)
            .onAppear {
                puttingViewModel.historyStore = historyStore
            }
        }
    }
    
    // MARK: - Photo Selection Section
    
    private var photoSelectionSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(GolfTheme.grassGreen)
            
            Text("Capture the Green")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Text("Take or select a photo of the putting green to get AI putting read")
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
            
            HStack(spacing: 12) {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    selectedImage = nil
                    puttingViewModel.puttingRead = nil
                    puttingViewModel.errorMessage = nil
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
                    
                    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                        puttingViewModel.errorMessage = "Failed to process image"
                        return
                    }
                    
                    Task {
                        await puttingViewModel.analyzePutting(
                            imageData: imageData,
                            courseId: course.id,
                            holeNumber: holeNumber,
                            lat: locationService.coordinate?.latitude,
                            lon: locationService.coordinate?.longitude
                        )
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyze Green")
                    }
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(puttingViewModel.isLoading ? GolfTheme.textSecondary : GolfTheme.grassGreen)
                    .cornerRadius(12)
                }
                .disabled(puttingViewModel.isLoading)
                .opacity(puttingViewModel.isLoading ? 0.7 : 1.0)
            }
        }
        .padding()
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Loading Section
    
    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(GolfTheme.grassGreen)
            
            Text("Analyzing green...")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(GolfTheme.cream)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Putting Read Card
    
    private func puttingReadCard(puttingRead: PuttingRead) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with AI badge
            HStack {
                // Animated AI Badge
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    GolfTheme.grassGreen,
                                    GolfTheme.grassGreen.opacity(0.8)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: GolfTheme.grassGreen.opacity(0.4), radius: 8, x: 0, y: 4)
                    
                    Text("AI")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Putting Read")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                    
                    Text("Green Analysis")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                }
                
                Spacer()
            }
            .padding(20)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        GolfTheme.grassGreen.opacity(0.1),
                        GolfTheme.grassGreen.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Main content
            VStack(alignment: .leading, spacing: 20) {
                // Putting Line - Most prominent
                if let puttingLine = puttingRead.puttingLine {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Putting Line")
                            .font(GolfTheme.captionFont)
                            .foregroundColor(GolfTheme.textSecondary)
                        
                        Text(puttingLine)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(GolfTheme.grassGreen)
                    }
                    .padding(16)
                    .background(GolfTheme.grassGreen.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Divider()
                    .background(GolfTheme.textSecondary.opacity(0.2))
                
                // Key details in grid
                VStack(spacing: 16) {
                    // Break direction
                    detailRow(
                        icon: "arrow.left.arrow.right",
                        label: "Break Direction",
                        value: puttingRead.breakDirection,
                        color: GolfTheme.accentGold
                    )
                    
                    // Break amount
                    detailRow(
                        icon: "ruler.fill",
                        label: "Break Amount",
                        value: String(format: "%.1f inches", puttingRead.breakAmount),
                        color: Color.blue
                    )
                    
                    // Speed
                    detailRow(
                        icon: "speedometer",
                        label: "Recommended Speed",
                        value: puttingRead.speed,
                        color: GolfTheme.grassGreen
                    )
                }
                
                // Narrative
                VStack(alignment: .leading, spacing: 8) {
                    Text("Analysis")
                        .font(GolfTheme.captionFont)
                        .foregroundColor(GolfTheme.textSecondary)
                    
                    Text(puttingRead.narrative)
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(GolfTheme.cream)
                .cornerRadius(12)
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white,
                    GolfTheme.cream.opacity(0.3)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            GolfTheme.grassGreen.opacity(0.3),
                            GolfTheme.grassGreen.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: GolfTheme.grassGreen.opacity(0.3), radius: 16, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .scaleEffect(puttingViewModel.puttingRead != nil ? 1.0 : 0.95)
        .opacity(puttingViewModel.puttingRead != nil ? 1.0 : 0.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: puttingViewModel.puttingRead != nil)
    }
    
    private func detailRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(GolfTheme.captionFont)
                    .foregroundColor(GolfTheme.textSecondary)
                Text(value)
                    .font(GolfTheme.bodyFont)
                    .foregroundColor(GolfTheme.textPrimary)
                    .fontWeight(.medium)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Error Card
    
    private func errorCard(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            
            Text(error)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textPrimary)
                .multilineTextAlignment(.center)
            
            // Try Again button
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                if let image = selectedImage,
                   let imageData = image.jpegData(compressionQuality: 0.8) {
                    Task {
                        await puttingViewModel.analyzePutting(
                            imageData: imageData,
                            courseId: course.id,
                            holeNumber: holeNumber,
                            lat: locationService.coordinate?.latitude,
                            lon: locationService.coordinate?.longitude
                        )
                    }
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(GolfTheme.bodyFont)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(GolfTheme.grassGreen)
                .cornerRadius(12)
            }
            .disabled(puttingViewModel.isLoading)
            .opacity(puttingViewModel.isLoading ? 0.7 : 1.0)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    GreenView(
        course: Course(name: "Pebble Beach Golf Links", par: 72),
        holeNumber: 1
    )
    .environmentObject(LocationService.shared)
}

// MARK: - Camera Picker

struct CameraPickerView: UIViewControllerRepresentable {
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
        let parent: CameraPickerView
        
        init(_ parent: CameraPickerView) {
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

