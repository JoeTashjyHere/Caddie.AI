//
//  PrimaryButton.swift
//  Caddie.ai
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isPrimary: Bool = true
    var isEnabled: Bool = true
    
    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(GolfButtonStyle(isPrimary: isPrimary))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Get Recommendation", action: {
            print("Tapped")
        })
        .padding()
        
        PrimaryButton(title: "Secondary Action", action: {
            print("Tapped")
        }, isPrimary: false)
        .padding()
        
        PrimaryButton(title: "Disabled", action: {
            print("Tapped")
        }, isEnabled: false)
        .padding()
    }
}

