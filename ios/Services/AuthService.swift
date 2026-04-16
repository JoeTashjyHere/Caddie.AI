//
//  AuthService.swift
//  Caddie.ai
//
//  Handles Apple, Google, and Email authentication with Keychain persistence.
//

import Foundation
import AuthenticationServices
import UIKit

// MARK: - Auth Models

enum AuthProvider: String, Codable {
    case apple
    case google
    case email
    case anonymous
}

struct AuthUser: Codable, Equatable {
    let id: String
    var email: String?
    var firstName: String?
    var lastName: String?
    let provider: AuthProvider
    let createdAt: Date
    var lastActiveAt: Date
}

// MARK: - AuthService

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    enum AuthState: Equatable {
        case unknown, unauthenticated, authenticated
    }

    @Published private(set) var state: AuthState = .unknown
    @Published private(set) var currentUser: AuthUser?

    private let keychain = KeychainService.shared
    private let userKey = "caddie_auth_user"
    private let tokenKey = "caddie_auth_token"
    private var appleCoordinator: AppleSignInCoordinator?

    private init() {
        restoreSession()
    }

    // MARK: - Apple Sign-In

    func signInWithApple(completion: @escaping (Bool) -> Void) {
        let coordinator = AppleSignInCoordinator()
        self.appleCoordinator = coordinator

        coordinator.onComplete = { [weak self] result in
            guard let self else { return }
            self.appleCoordinator = nil

            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    completion(false)
                    return
                }
                self.handleAppleCredential(credential)
                AnalyticsService.shared.track("auth_completed", properties: ["provider": "apple"])
                completion(true)

            case .failure(let error):
                let nsError = error as NSError
                if nsError.domain == ASAuthorizationError.errorDomain,
                   nsError.code == ASAuthorizationError.canceled.rawValue {
                    completion(false)
                    return
                }
                AnalyticsService.shared.track("auth_failed", properties: [
                    "provider": "apple",
                    "error": error.localizedDescription
                ])
                completion(false)
            }
        }

        coordinator.startSignIn()
    }

    private func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) {
        let userId = credential.user
        let email = credential.email
        let firstName = credential.fullName?.givenName
        let lastName = credential.fullName?.familyName

        let user = AuthUser(
            id: userId,
            email: email ?? currentUser?.email,
            firstName: firstName ?? currentUser?.firstName,
            lastName: lastName ?? currentUser?.lastName,
            provider: .apple,
            createdAt: currentUser?.createdAt ?? Date(),
            lastActiveAt: Date()
        )

        persistUser(user)

        if let tokenData = credential.identityToken,
           let token = String(data: tokenData, encoding: .utf8) {
            keychain.save(token, forKey: tokenKey)
        }

        currentUser = user
        state = .authenticated
    }

    // MARK: - Google Sign-In (requires GoogleSignIn SDK)

    func signInWithGoogle(completion: @escaping (Bool) -> Void) {
        // Full implementation requires:
        // 1. Add GoogleSignIn Swift Package: https://github.com/google/GoogleSignIn-iOS
        // 2. Configure OAuth client ID in Google Cloud Console
        // 3. Add URL scheme to Info.plist
        //
        // When SDK is configured, call:
        // GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in ... }

        AnalyticsService.shared.track("auth_attempted", properties: ["provider": "google"])

        // Falls through to email-based flow until SDK is configured
        completion(false)
    }

    // MARK: - Email Sign-In

    func signInWithEmail(email: String, name: String) -> Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let user = AuthUser(
            id: UUID().uuidString,
            email: email.isEmpty ? nil : email,
            firstName: name.isEmpty ? nil : name,
            lastName: nil,
            provider: .email,
            createdAt: Date(),
            lastActiveAt: Date()
        )

        persistUser(user)
        currentUser = user
        state = .authenticated

        AnalyticsService.shared.track("auth_completed", properties: ["provider": "email"])
        return true
    }

    // MARK: - Session Management

    func restoreSession() {
        guard let data = keychain.load(forKey: userKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else {
            state = .unauthenticated
            return
        }

        currentUser = user
        state = .authenticated

        if user.provider == .apple {
            verifyAppleCredential(userId: user.id)
        }

        var updated = user
        updated.lastActiveAt = Date()
        persistUser(updated)
        currentUser = updated
    }

    func signOut() {
        keychain.delete(forKey: userKey)
        keychain.delete(forKey: tokenKey)
        currentUser = nil
        state = .unauthenticated
        AnalyticsService.shared.track("auth_signout", properties: [:])
    }

    // MARK: - Helpers

    private func persistUser(_ user: AuthUser) {
        if let data = try? JSONEncoder().encode(user) {
            keychain.save(data, forKey: userKey)
        }
    }

    private func verifyAppleCredential(userId: String) {
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userId) { [weak self] credState, _ in
            Task { @MainActor in
                switch credState {
                case .revoked, .notFound:
                    self?.signOut()
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Apple Sign-In Coordinator

private class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    var onComplete: ((Result<ASAuthorization, Error>) -> Void)?

    func startSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        onComplete?(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        onComplete?(.failure(error))
    }
}
