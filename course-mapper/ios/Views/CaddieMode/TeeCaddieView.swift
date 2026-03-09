//
//  TeeCaddieView.swift
//  Caddie.AI iOS Client
//
//  Tee mode view showing hole layout
//

import SwiftUI

struct TeeCaddieView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hole Layout Diagram
                holeLayoutDiagram
                    .frame(height: 400)
                    .padding()
                
                // Distance Markers
                distanceMarkersSection
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Hole Layout Diagram
    
    private var holeLayoutDiagram: some View {
        GeometryReader { geometry in
            ZStack {
                // Background (sky)
                Color.blue.opacity(0.2)
                
                // Fairway
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.6))
                    .frame(width: geometry.size.width * 0.6, height: geometry.size.height * 0.7)
                    .offset(x: 0, y: -geometry.size.height * 0.15)
                
                // Hazards
                // Water on left
                Ellipse()
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: geometry.size.width * 0.2, height: geometry.size.height * 0.3)
                    .offset(x: -geometry.size.width * 0.3, y: geometry.size.height * 0.1)
                
                // Bunker on right
                Ellipse()
                    .fill(Color.brown.opacity(0.7))
                    .frame(width: geometry.size.width * 0.15, height: geometry.size.height * 0.2)
                    .offset(x: geometry.size.width * 0.3, y: geometry.size.height * 0.0)
                
                // Tee box (bottom)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .frame(width: geometry.size.width * 0.3, height: geometry.size.height * 0.1)
                    .offset(x: 0, y: geometry.size.height * 0.4)
                
                // Green (top)
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: geometry.size.width * 0.2, height: geometry.size.width * 0.2)
                    .offset(x: 0, y: -geometry.size.height * 0.4)
                
                // Direction arrow
                Image(systemName: "arrow.up")
                    .font(.title)
                    .foregroundColor(.white)
                    .offset(x: 0, y: -geometry.size.height * 0.4)
            }
        }
    }
    
    // MARK: - Distance Markers
    
    private var distanceMarkersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distances")
                .font(.headline)
            
            HStack {
                DistanceMarker(label: "100", color: .yellow)
                DistanceMarker(label: "150", color: .white)
                DistanceMarker(label: "200", color: .blue)
                DistanceMarker(label: "250", color: .red)
            }
        }
    }
}

struct DistanceMarker: View {
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
            Text(label)
                .font(.caption)
        }
    }
}

// MARK: - Preview

#Preview {
    TeeCaddieView()
}



