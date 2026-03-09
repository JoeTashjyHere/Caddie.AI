//
//  ShimmerView.swift
//  Caddie.ai
//
//  Shimmer loading effect for course cards matching Apple HIG

import SwiftUI

struct ShimmerView: View {
    @State private var phase: CGFloat = -1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.1),
                        Color.gray.opacity(0.15),
                        Color.gray.opacity(0.1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                
                // Animated shimmer overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.4),
                        Color.white.opacity(0.6),
                        Color.white.opacity(0.4),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * (geometry.size.width * 2))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

struct CourseCardShimmer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Course name shimmer
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(height: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Par and distance shimmer
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 70, height: 14)
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 60, height: 14)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .overlay(
            ShimmerView()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }
}

