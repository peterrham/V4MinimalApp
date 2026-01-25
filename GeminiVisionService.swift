//
//  GeminiVisionService.swift
//  V4MinimalApp
//
//  Service for identifying objects using Gemini Vision API
//

import Foundation
import UIKit

/// Service for identifying objects in photos using Google's Gemini Vision API
@MainActor
class GeminiVisionService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var latestIdentification: String = ""
    @Published var isProcessing = false
    @Published var error: String?
    
    // MARK: - Configuration
    
    private let apiKey: String
    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent"
    
    // MARK: - Singleton
    
    static let shared = GeminiVisionService()
    
    // MARK: - Initialization
    
    init(apiKey: String = "") {
        // Load API key from multiple sources (in order of priority)
        if !apiKey.isEmpty {
            // 1. Explicitly provided
            self.apiKey = apiKey
        } else if let configKey = Self.loadFromConfig() {
            // 2. From Config.plist
            self.apiKey = configKey
            appBootLog.debugWithContext("API key loaded from Config.plist")
        } else if let infoPlistKey = Self.loadFromInfoPlist() {
            // 3. From Info.plist
            self.apiKey = infoPlistKey
            appBootLog.debugWithContext("API key loaded from Info.plist")
        } else if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            // 4. From environment variable
            self.apiKey = envKey
            appBootLog.debugWithContext("API key loaded from environment variable")
        } else {
            // No API key found
            self.apiKey = ""
        }
        
        if self.apiKey.isEmpty {
            appBootLog.warningWithContext("⚠️ Gemini API key not configured")
            appBootLog.warningWithContext("   Options: Info.plist, Config.plist, or GEMINI_API_KEY environment variable")
        } else {
            appBootLog.infoWithContext("✅ Gemini API key loaded successfully")
        }
    }
    
    // MARK: - Configuration Loading
    
    /// Load API key from Config.plist
    private static func loadFromConfig() -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let apiKey = config["GeminiAPIKey"] as? String,
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }
    
    /// Load API key from Info.plist
    private static func loadFromInfoPlist() -> String? {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String,
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }
    
    // MARK: - Public Methods
    
    /// Identify objects in an image using Gemini Vision API
    func identifyImage(_ image: UIImage, customPrompt: String? = nil) async {
        guard !apiKey.isEmpty else {
            error = "API key not configured"
            appBootLog.errorWithContext("❌ Cannot identify image: API key not configured")
            return
        }
        
        isProcessing = true
        error = nil
        
        let prompt = customPrompt ?? "What is in this image? Provide a brief, clear identification of the main object or scene. Keep the response concise (1-2 sentences)."
        
        appBootLog.infoWithContext("🔍 Identifying image with Gemini Vision API...")
        appBootLog.debugWithContext("   Prompt: \(prompt)")
        
        do {
            // Convert image to base64
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw GeminiError.imageConversionFailed
            }
            
            let base64Image = imageData.base64EncodedString()
            
            // Create request
            let request = try createRequest(base64Image: base64Image, prompt: prompt)
            
            // Make API call
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.invalidResponse
            }
            
            appBootLog.debugWithContext("API Response Status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                appBootLog.errorWithContext("❌ API Error: \(errorBody)")
                throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            
            // Parse response
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            
            // Extract text from response
            if let candidate = geminiResponse.candidates.first,
               let content = candidate.content.parts.first {
                latestIdentification = content.text
                appBootLog.infoWithContext("✅ Image identified: \(content.text)")
            } else {
                latestIdentification = "No identification available"
                appBootLog.warningWithContext("⚠️ No identification in response")
            }
            
        } catch let error as GeminiError {
            self.error = error.localizedDescription
            appBootLog.errorWithContext("❌ Gemini error: \(error.localizedDescription)")
        } catch {
            self.error = error.localizedDescription
            appBootLog.errorWithContext("❌ Unexpected error: \(error.localizedDescription)")
        }
        
        isProcessing = false
    }
    
    /// Clear the latest identification
    func clearIdentification() {
        latestIdentification = ""
        error = nil
    }
    
    // MARK: - Private Methods
    
    private func createRequest(base64Image: String, prompt: String) throws -> URLRequest {
        guard let url = URL(string: "\(apiEndpoint)?key=\(apiKey)") else {
            throw GeminiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": prompt
                        ],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "topK": 32,
                "topP": 1,
                "maxOutputTokens": 100
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
}

// MARK: - Response Models

struct GeminiResponse: Codable {
    let candidates: [Candidate]
    
    struct Candidate: Codable {
        let content: Content
        let finishReason: String?
        let safetyRatings: [SafetyRating]?
        
        struct Content: Codable {
            let parts: [Part]
            let role: String
            
            struct Part: Codable {
                let text: String
            }
        }
        
        struct SafetyRating: Codable {
            let category: String
            let probability: String
        }
    }
}

// MARK: - Errors

enum GeminiError: Error {
    case invalidURL
    case imageConversionFailed
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .imageConversionFailed:
            return "Failed to convert image"
        case .invalidResponse:
            return "Invalid API response"
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        }
    }
}
