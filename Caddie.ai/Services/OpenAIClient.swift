//
//  OpenAIClient.swift
//  Caddie.ai
//
//  Client that calls the backend proxy (not OpenAI directly)
//  Backend endpoints: /api/openai/complete and /api/openai/vision
//

import Foundation

struct OpenAIResponse: Codable {
    var resultJSON: String?
    var error: String?
}

enum OpenAIError: LocalizedError {
    case serverError(String)
    case invalidResponse
    case missingResultJSON
    
    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return "Server error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .missingResultJSON:
            return "Missing resultJSON in response"
        }
    }
}

class OpenAIClient {
    static let shared = OpenAIClient()
    
    // Backend running on localhost for iOS Simulator
    // When deploying to Render, change to: URL(string: "https://YOUR-RENDER-URL.onrender.com/api")!
    private let baseURL: URL
    
    private init() {
        // Safe URL creation - will crash at init if invalid, which is appropriate for a configuration error
        guard let url = URL(string: "http://localhost:8080/api") else {
            fatalError("Invalid baseURL configuration")
        }
        self.baseURL = url
    }
    
    func complete(system: String, user: String) async throws -> String {
        let url = baseURL.appendingPathComponent("openai/complete")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "system": system,
            "user": user
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error message from response
            if let errorResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
               let errorMessage = errorResponse.error {
                throw OpenAIError.serverError(errorMessage)
            }
            throw OpenAIError.invalidResponse
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        // Check for error field in successful response
        if let errorMessage = openAIResponse.error {
            throw OpenAIError.serverError(errorMessage)
        }
        
        guard let resultJSON = openAIResponse.resultJSON else {
            throw OpenAIError.missingResultJSON
        }
        
        return resultJSON
    }
    
    func vision(imageBase64: String, contextJSON: String) async throws -> String {
        let url = baseURL.appendingPathComponent("openai/vision")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "image": imageBase64,
            "context": contextJSON
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error message from response
            if let errorResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
               let errorMessage = errorResponse.error {
                throw OpenAIError.serverError(errorMessage)
            }
            throw OpenAIError.invalidResponse
        }
        
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        
        // Check for error field in successful response
        if let errorMessage = openAIResponse.error {
            throw OpenAIError.serverError(errorMessage)
        }
        
        guard let resultJSON = openAIResponse.resultJSON else {
            throw OpenAIError.missingResultJSON
        }
        
        return resultJSON
    }
}

