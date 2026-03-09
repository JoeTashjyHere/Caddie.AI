//
//  ViewState.swift
//  Caddie.ai
//
//  Unified state management for API calls and data loading

import Foundation
import SwiftUI
import UIKit

/// Unified state enum for API calls and data loading
enum ViewState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
    case empty
    
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
    
    var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
    
    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
    
    var isEmpty: Bool {
        if case .empty = self {
            return true
        }
        return false
    }
}

enum RequestState: Equatable {
    case idle
    case ready
    case submitting
    case success
    case failure(errorMessage: String, debugId: String)

    var isSubmitting: Bool {
        if case .submitting = self { return true }
        return false
    }

    var failureMessage: String? {
        if case .failure(let errorMessage, _) = self { return errorMessage }
        return nil
    }

    var debugId: String? {
        if case .failure(_, let debugId) = self { return debugId }
        return nil
    }
}

// MARK: - Reusable View Components

struct LoadingView: View {
    let message: String
    
    init(message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(GolfTheme.grassGreen)
            Text(message)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: (() -> Void)?
    
    init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            
            Text(message)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let onRetry = onRetry {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onRetry()
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
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    init(icon: String = "tray", title: String = "No Data", message: String = "There's nothing here yet") {
        self.icon = icon
        self.title = title
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(GolfTheme.textSecondary)
            
            Text(title)
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            
            Text(message)
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - View Modifier for State-based Content

struct ViewStateModifier<Content: View>: View {
    let state: ViewState
    let content: () -> Content
    let loadingMessage: String
    let emptyState: EmptyStateView?
    let onRetry: (() -> Void)?
    
    init(
        state: ViewState,
        loadingMessage: String = "Loading...",
        emptyState: EmptyStateView? = nil,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.state = state
        self.content = content
        self.loadingMessage = loadingMessage
        self.emptyState = emptyState
        self.onRetry = onRetry
    }
    
    var body: some View {
        Group {
            switch state {
            case .idle:
                content()
            case .loading:
                LoadingView(message: loadingMessage)
            case .loaded:
                content()
            case .error(let message):
                ErrorView(message: message, onRetry: onRetry)
            case .empty:
                if let emptyState = emptyState {
                    emptyState
                } else {
                    EmptyStateView()
                }
            }
        }
    }
}

extension View {
    func viewState(
        _ state: ViewState,
        loadingMessage: String = "Loading...",
        emptyState: EmptyStateView? = nil,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Self
    ) -> some View {
        ViewStateModifier(
            state: state,
            loadingMessage: loadingMessage,
            emptyState: emptyState,
            onRetry: onRetry,
            content: { content() }
        )
    }
}
