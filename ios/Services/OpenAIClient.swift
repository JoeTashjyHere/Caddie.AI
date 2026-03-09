//
//  OpenAIClient.swift
//  Caddie.ai
//

import Foundation
import UIKit

struct OpenAIResponse: Codable {
    var resultJSON: String?
    var error: String?
}

enum OpenAIError: LocalizedError {
    case serverError(String)
    case invalidResponse
    case missingResultJSON
    case apiKeyMissing
    case networkError(Error)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            if message.contains("OPENAI_API_KEY missing") {
                return "Caddie AI isn't configured yet. Please check your server settings."
            }
            return "Server error: \(message)"
        case .invalidResponse:
            return "Invalid response from server. Please try again."
        case .missingResultJSON:
            return "Server response was incomplete. Please try again."
        case .apiKeyMissing:
            return "Caddie AI isn't configured yet. Please check your server settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse server response: \(error.localizedDescription)"
        }
    }
}

@MainActor
class OpenAIClient {
    static let shared = OpenAIClient()
    
    private let baseURL: URL
    private let requestTimeout: TimeInterval = 20
    private let maxRetryCount = 2
    
    private init() {
        // Use APIService as single source of truth for base URL
        self.baseURL = APIService.getBaseURL().appendingPathComponent("api")
    }
    
    /// Generation settings for controlled creativity (backend may use these if supported)
    struct GenerationSettings {
        static let temperature: Double = 0.7
        static let maxTokens: Int = 1024
    }
    
    func complete(system: String, user: String, correlationId: String = UUID().uuidString) async throws -> String {
        let url = baseURL.appendingPathComponent("openai/complete")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(correlationId, forHTTPHeaderField: "X-Correlation-ID")
        
        // Use safe formatters to ensure no empty strings
        let safeSystem = SafeFormatter.safeString(system)
        let safeUser = SafeFormatter.safeString(user)
        
        var body: [String: Any] = [
            "system": safeSystem,
            "user": safeUser
        ]
        body["temperature"] = GenerationSettings.temperature
        body["max_tokens"] = GenerationSettings.maxTokens
        
        let payload: [String: Any] = [
            "correlationId": correlationId,
            "temperature": GenerationSettings.temperature,
            "max_tokens": GenerationSettings.maxTokens,
            "hasPhoto": false
        ]
        body["correlationId"] = correlationId
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Log which keys are present
        DebugLogging.log("📤 Text request context keys: \(payload.keys.joined(separator: ", "))", category: "OpenAIClient")
        
        DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: payload)
        
        do {
            let (data, httpResponse) = try await performRequest(
                request: request,
                endpoint: "openai/complete",
                correlationId: correlationId
            )
            
            // Handle non-200 status codes
            guard (200...299).contains(httpResponse.statusCode) else {
                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
                   let errorMessage = errorResponse.error {
                    let error: OpenAIError
                    if errorMessage.contains("OPENAI_API_KEY missing") {
                        error = .apiKeyMissing
                    } else {
                        error = .serverError(errorMessage)
                    }
                    DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
                    throw error
                }
                
                let error = OpenAIError.serverError("HTTP \(httpResponse.statusCode)")
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
                throw error
            }
            
            // Decode response
            let openAIResponse: OpenAIResponse
            do {
                openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            } catch {
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
                throw OpenAIError.decodingError(error)
            }
            
            // Check for error in response
            if let errorMessage = openAIResponse.error {
                let error: OpenAIError
                if errorMessage.contains("OPENAI_API_KEY missing") {
                    error = .apiKeyMissing
                } else {
                    error = .serverError(errorMessage)
                }
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, parsedModel: openAIResponse, error: error)
                throw error
            }
            
            guard let resultJSON = openAIResponse.resultJSON else {
                let error = OpenAIError.missingResultJSON
                DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, parsedModel: openAIResponse, error: error)
                throw error
            }
            
            DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, parsedModel: openAIResponse)
            return resultJSON
            
        } catch let error as OpenAIError {
            throw error
        } catch {
            let networkError = OpenAIError.networkError(error)
            DebugLogging.logAPI(endpoint: "openai/complete", url: url, method: "POST", payload: payload, error: networkError)
            throw networkError
        }
    }
    
    func completeWithVision(
        system: String,
        user: String,
        image: UIImage,
        correlationId: String = UUID().uuidString
    ) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "OpenAIClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])
        }
        
        let imageBase64 = imageData.base64EncodedString()
        
        // Ensure image base64 is not empty
        guard !imageBase64.isEmpty else {
            throw NSError(domain: "OpenAIClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image data is empty"])
        }
        
        // Build safe context dictionary
        var contextDict: [String: Any] = [:]
        contextDict["system"] = SafeFormatter.safeString(system)
        contextDict["temperature"] = GenerationSettings.temperature
        contextDict["max_tokens"] = GenerationSettings.maxTokens
        
        // Try to parse user as JSON, otherwise use as string
        if let userData = user.data(using: .utf8),
           let userJSON = try? JSONSerialization.jsonObject(with: userData) as? [String: Any] {
            contextDict["user"] = userJSON
        } else {
            contextDict["user"] = SafeFormatter.safeString(user)
        }
        
        // Build safe inputs context (for debugging and backend)
        var inputs: [String: Any] = [:]
        inputs["hasPhoto"] = true
        inputs["imageSize"] = imageData.count
        contextDict["inputs"] = inputs
        
        guard let contextJSONData = try? JSONSerialization.data(withJSONObject: contextDict),
              let contextJSONString = String(data: contextJSONData, encoding: .utf8) else {
            throw NSError(domain: "OpenAIClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize context JSON"])
        }
        
        // Log which keys are present (without base64)
        var logDict = contextDict
        logDict["image"] = "<base64 image data (\(imageBase64.count) chars)>"
        DebugLogging.log("📤 Vision request context keys: \(logDict.keys.joined(separator: ", "))", category: "OpenAIClient")
        
        return try await vision(imageBase64: imageBase64, contextJSON: contextJSONString, correlationId: correlationId)
    }
    
    func vision(imageBase64: String, contextJSON: String, correlationId: String = UUID().uuidString) async throws -> String {
        let url = baseURL.appendingPathComponent("openai/vision")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(correlationId, forHTTPHeaderField: "X-Correlation-ID")
        
        var body: [String: Any] = [
            "image": imageBase64,
            "context": contextJSON
        ]
        
        let payload: [String: Any] = [
            "correlationId": correlationId,
            "hasPhoto": true
        ]
        body["correlationId"] = correlationId
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        DebugLogging.logAPI(endpoint: "openai/vision", url: url, method: "POST", payload: payload)
        
        do {
            let (data, httpResponse) = try await performRequest(
                request: request,
                endpoint: "openai/vision",
                correlationId: correlationId
            )
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if let errorResponse = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
                   let errorMessage = errorResponse.error {
                    let error: OpenAIError
                    if errorMessage.contains("OPENAI_API_KEY missing") {
                        error = .apiKeyMissing
                    } else {
                        error = .serverError(errorMessage)
                    }
                    DebugLogging.logAPI(endpoint: "openai/vision", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
                    throw error
                }
                
                let error = OpenAIError.serverError("HTTP \(httpResponse.statusCode)")
                DebugLogging.logAPI(endpoint: "openai/vision", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
                throw error
            }
            
            let openAIResponse: OpenAIResponse
            do {
                openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            } catch {
                DebugLogging.logAPI(endpoint: "openai/vision", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, error: error)
                throw OpenAIError.decodingError(error)
            }
            
            if let errorMessage = openAIResponse.error {
                let error: OpenAIError
                if errorMessage.contains("OPENAI_API_KEY missing") {
                    error = .apiKeyMissing
                } else {
                    error = .serverError(errorMessage)
                }
                DebugLogging.logAPI(endpoint: "openai/vision", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, parsedModel: openAIResponse, error: error)
                throw error
            }
            
            guard let resultJSON = openAIResponse.resultJSON else {
                let error = OpenAIError.missingResultJSON
                DebugLogging.logAPI(endpoint: "openai/vision", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, responseData: data, parsedModel: openAIResponse, error: error)
                throw error
            }
            
            DebugLogging.logAPI(endpoint: "openai/vision", url: url, method: "POST", payload: payload, responseStatus: httpResponse.statusCode, parsedModel: openAIResponse)
            return resultJSON
            
        } catch let error as OpenAIError {
            throw error
        } catch {
            let networkError = OpenAIError.networkError(error)
            DebugLogging.logAPI(endpoint: "openai/vision", url: url, method: "POST", payload: payload, error: networkError)
            throw networkError
        }
    }
    
    private func performRequest(
        request: URLRequest,
        endpoint: String,
        correlationId: String
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0

        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAIError.invalidResponse
                }

                if shouldRetry(statusCode: httpResponse.statusCode), attempt < maxRetryCount {
                    attempt += 1
                    DebugLogging.log("Retrying \(endpoint) correlationId=\(correlationId) attempt=\(attempt)", category: "OpenAIClient")
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt - 1)) * 300_000_000))
                    continue
                }

                return (data, httpResponse)
            } catch {
                if shouldRetry(error: error), attempt < maxRetryCount {
                    attempt += 1
                    DebugLogging.log(
                        "Retrying \(endpoint) correlationId=\(correlationId) attempt=\(attempt) due to \(error.localizedDescription)",
                        category: "OpenAIClient"
                    )
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt - 1)) * 300_000_000))
                    continue
                }

                if let urlError = error as? URLError, urlError.code == .timedOut {
                    throw OpenAIError.networkError(APIError.timeout)
                }
                throw error
            }
        }
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        [502, 503, 504].contains(statusCode)
    }

    private func shouldRetry(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            URLError.timedOut,
            URLError.networkConnectionLost,
            URLError.notConnectedToInternet,
            URLError.cannotFindHost,
            URLError.cannotConnectToHost
        ].contains(urlError.code)
    }
}
