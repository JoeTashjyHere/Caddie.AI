//
//  PrimaryButton.swift
//  Caddie.ai
//
//  Reusable SwiftUI button style
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .cornerRadius(12)
        }
    }
}

#Preview {
    PrimaryButton(title: "Get Recommendation") {
        print("Tapped")
    }
    .padding()
}

