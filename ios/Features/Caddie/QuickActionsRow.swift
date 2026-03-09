//
//  QuickActionsRow.swift
//  Caddie.ai
//
//  Row of quick action buttons

import SwiftUI

struct QuickActionsRow: View {
    let onDistance: () -> Void
    let onGreenReader: () -> Void
    let onHistory: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                title: "Enter Distance",
                icon: "ruler.fill",
                color: GolfTheme.grassGreen,
                onTap: onDistance
            )
            
            QuickActionButton(
                title: "Green Reader",
                icon: "flag.2.crossed",
                color: GolfTheme.accentGold,
                onTap: onGreenReader
            )
            
            QuickActionButton(
                title: "History",
                icon: "clock.arrow.circlepath",
                color: .blue,
                onTap: onHistory
            )
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(GolfTheme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(GolfTheme.cream)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    QuickActionsRow(
        onDistance: {},
        onGreenReader: {},
        onHistory: {}
    )
    .padding()
}


