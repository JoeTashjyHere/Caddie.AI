//
//  PuttingResultView.swift
//  Caddie.ai
//
//  View displaying putting analysis results
//

import SwiftUI

struct PuttingResultView: View {
    let result: PuttingRead
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Putting Read")
                .font(.title)
                .fontWeight(.bold)
            
            // Aim direction
            VStack(alignment: .leading, spacing: 8) {
                Text("Aim")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack {
                    if result.aimInchesRight > 0 {
                        Image(systemName: "arrow.right")
                            .foregroundColor(.blue)
                        Text("\(result.aimInchesRight, specifier: "%.1f") inches right")
                            .font(.title2)
                            .fontWeight(.semibold)
                    } else if result.aimInchesRight < 0 {
                        Image(systemName: "arrow.left")
                            .foregroundColor(.blue)
                        Text("\(abs(result.aimInchesRight), specifier: "%.1f") inches left")
                            .font(.title2)
                            .fontWeight(.semibold)
                    } else {
                        Text("Straight")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
            }
            
            Divider()
            
            // Pace hint
            VStack(alignment: .leading, spacing: 8) {
                Text("Pace")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(result.paceHint)
                    .font(.body)
            }
            
            Divider()
            
            // Break description
            VStack(alignment: .leading, spacing: 8) {
                Text("Break")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(result.breakDescription)
                    .font(.body)
            }
            
            // Notes
            if let notes = result.notes {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            // Confidence
            HStack {
                Text("Confidence:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(Int(result.confidence * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.top)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    PuttingResultView(
        result: PuttingRead(
            aimInchesRight: 3.5,
            paceHint: "Firm pace - the green is running fast",
            breakDescription: "The putt breaks left to right, about 3-4 inches. Start it on the left edge.",
            confidence: 0.88,
            notes: "Watch for grain affecting the last 2 feet"
        )
    )
    .padding()
}

