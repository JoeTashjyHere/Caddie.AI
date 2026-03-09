//
//  CaddieCameraCaptureView.swift
//  Caddie.ai
//
//  Camera capture view (Apple Intelligence style)

import SwiftUI
import UIKit
import AVFoundation

struct CaddieCameraCaptureView: View {
    let onCancel: () -> Void
    let onCaptured: (UIImage) -> Void
    
    @State private var showCamera = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            Button("Cancel", action: onCancel)
                .padding()
                .foregroundColor(.white)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
        }
        .sheet(isPresented: $showCamera) {
            // Try camera first, fallback to library if unavailable (e.g., Simulator)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                CameraPickerWrapper(selectedImage: Binding(
                    get: { nil },
                    set: { image in
                        showCamera = false
                        if let image = image {
                            onCaptured(image)
                        } else {
                            onCancel()
                        }
                    }
                ))
            } else {
                // Fallback to photo library if camera unavailable
                ImagePicker(selectedImage: Binding(
                    get: { nil },
                    set: { image in
                        showCamera = false
                        if let image = image {
                            onCaptured(image)
                        } else {
                            onCancel()
                        }
                    }
                ))
            }
        }
    }
}

// MARK: - Camera Picker Wrapper

struct CameraPickerWrapper: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.cameraCaptureMode = .photo
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerWrapper
        
        init(_ parent: CameraPickerWrapper) {
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
            parent.selectedImage = nil
            parent.dismiss()
        }
    }
}

#Preview {
    CaddieCameraCaptureView(
        onCancel: {},
        onCaptured: { _ in }
    )
}

