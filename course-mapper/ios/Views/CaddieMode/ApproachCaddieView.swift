//
//  ApproachCaddieView.swift
//  Caddie.AI iOS Client
//
//  Approach mode view showing last 100-150 yards to green
//

import SwiftUI

struct ApproachCaddieView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Approach Zone Diagram
                approachZoneDiagram
                    .frame(height: 400)
                    .padding()
                
                // Yardage Info
                yardageInfoSection
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Approach Zone Diagram
    
    private var approachZoneDiagram: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.green.opacity(0.1)
                
                // Green (top center)
                Circle()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: geometry.size.width * 0.4, height: geometry.size.width * 0.4)
                    .offset(x: 0, y: -geometry.size.height * 0.3)
                
                // Green zones
                // Front
                Rectangle()
                    .fill(Color.green.opacity(0.4))
                    .frame(width: geometry.size.width * 0.4, height: geometry.size.height * 0.1)
                    .offset(x: 0, y: -geometry.size.height * 0.35)
                
                // Back
                Rectangle()
                    .fill(Color.green.opacity(0.4))
                    .frame(width: geometry.size.width * 0.4, height: geometry.size.height * 0.1)
                    .offset(x: 0, y: -geometry.size.height * 0.25)
                
                // Ball position (bottom)
                Circle()
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .offset(x: 0, y: geometry.size.height * 0.4)
                
                // Yardage lines
                // 150 yard marker
                yardageLine(yards: 150, yOffset: geometry.size.height * 0.2, geometry: geometry)
                // 100 yard marker
                yardageLine(yards: 100, yOffset: -geometry.size.height * 0.05, geometry: geometry)
                
                // Yardage labels
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            YardageLabel(yards: 160, label: "To Center")
                            YardageLabel(yards: 145, label: "To Front")
                            YardageLabel(yards: 175, label: "To Back")
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    private func yardageLine(yards: Int, yOffset: CGFloat, geometry: GeometryProxy) -> some View {
        Rectangle()
            .fill(Color.yellow.opacity(0.5))
            .frame(width: geometry.size.width, height: 2)
            .offset(x: 0, y: yOffset)
            .overlay(
                Text("\(yards) yds")
                    .font(.caption)
                    .padding(4)
                    .background(Color.yellow)
                    .cornerRadius(4),
                alignment: .leading
            )
    }
    
    // MARK: - Yardage Info
    
    private var yardageInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distances to Green")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                YardageRow(label: "Front:", yards: 145)
                YardageRow(label: "Center:", yards: 160)
                YardageRow(label: "Back:", yards: 175)
            }
        }
    }
}

struct YardageLabel: View {
    let yards: Int
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(yards)")
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.8))
        .cornerRadius(4)
    }
}

struct YardageRow: View {
    let label: String
    let yards: Int
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(yards) yds")
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Preview

#Preview {
    ApproachCaddieView()
}



