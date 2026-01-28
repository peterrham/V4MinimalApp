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
    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
    
    // MARK: - Singleton
    
    static let shared = GeminiVisionService()
    
    // MARK: - Initialization
    
    init(apiKey: String = "") {
        appBootLog.infoWithContext("🔧 Initializing GeminiVisionService...")
        
        // Load API key from multiple sources (in order of priority)
        if !apiKey.isEmpty {
            // 1. Explicitly provided
            self.apiKey = apiKey
            appBootLog.infoWithContext("✅ API key loaded from explicit parameter (length: \(apiKey.count) chars)")
        } else if let configKey = Self.loadFromConfig() {
            // 2. From Config.plist
            self.apiKey = configKey
            appBootLog.infoWithContext("✅ API key loaded from Config.plist (length: \(configKey.count) chars)")
        } else if let infoPlistKey = Self.loadFromInfoPlist() {
            // 3. From Info.plist
            self.apiKey = infoPlistKey
            appBootLog.infoWithContext("✅ API key loaded from Info.plist (length: \(infoPlistKey.count) chars)")
        } else if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            // 4. From environment variable
            self.apiKey = envKey
            appBootLog.infoWithContext("✅ API key loaded from environment variable (length: \(envKey.count) chars)")
        } else {
            // No API key found
            self.apiKey = ""
            appBootLog.errorWithContext("❌ API key not found in any configuration source")
        }
        
        // Detailed logging for debugging
        if self.apiKey.isEmpty {
            appBootLog.errorWithContext("❌❌❌ GEMINI API KEY NOT CONFIGURED ❌❌❌")
            appBootLog.errorWithContext("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            appBootLog.errorWithContext("📋 Troubleshooting Checklist:")
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("1️⃣ Config.plist:")
            if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist") {
                appBootLog.errorWithContext("   ✅ File exists at: \(configPath)")
                if let config = NSDictionary(contentsOfFile: configPath) {
                    appBootLog.errorWithContext("   📄 File is readable")
                    if let key = config["GeminiAPIKey"] as? String {
                        if key.isEmpty {
                            appBootLog.errorWithContext("   ⚠️ GeminiAPIKey key exists but is EMPTY")
                        } else {
                            appBootLog.errorWithContext("   ⚠️ GeminiAPIKey exists with value (this shouldn't happen)")
                        }
                    } else {
                        appBootLog.errorWithContext("   ❌ No 'GeminiAPIKey' key found in dictionary")
                        appBootLog.errorWithContext("   📋 Available keys: \(config.allKeys)")
                    }
                } else {
                    appBootLog.errorWithContext("   ❌ File exists but cannot be read as NSDictionary")
                }
            } else {
                appBootLog.errorWithContext("   ❌ Config.plist not found in bundle")
            }
            
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("2️⃣ Info.plist:")
            if let infoPlistKey = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") {
                if let keyString = infoPlistKey as? String {
                    if keyString.isEmpty {
                        appBootLog.errorWithContext("   ⚠️ GeminiAPIKey exists but is EMPTY")
                    } else {
                        appBootLog.errorWithContext("   ⚠️ GeminiAPIKey exists (this shouldn't happen)")
                    }
                } else {
                    appBootLog.errorWithContext("   ❌ GeminiAPIKey exists but is not a String (type: \(type(of: infoPlistKey)))")
                }
            } else {
                appBootLog.errorWithContext("   ❌ No 'GeminiAPIKey' in Info.plist")
            }
            
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("3️⃣ Environment Variable:")
            if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
                if envKey.isEmpty {
                    appBootLog.errorWithContext("   ⚠️ GEMINI_API_KEY exists but is EMPTY")
                } else {
                    appBootLog.errorWithContext("   ⚠️ GEMINI_API_KEY exists (this shouldn't happen)")
                }
            } else {
                appBootLog.errorWithContext("   ❌ GEMINI_API_KEY environment variable not set")
            }
            
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("🔧 How to Fix:")
            appBootLog.errorWithContext("   • Quick Start: Add to Info.plist with key 'GeminiAPIKey'")
            appBootLog.errorWithContext("   • Recommended: Create Config.plist (see GEMINI_SETUP.md)")
            appBootLog.errorWithContext("   • Development: Set GEMINI_API_KEY in scheme environment")
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("📖 See GEMINI_SETUP.md for detailed instructions")
            appBootLog.errorWithContext("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        } else {
            appBootLog.infoWithContext("✅ Gemini API key configured successfully")
            // Validate key format (Gemini keys start with "AIza")
            if self.apiKey.hasPrefix("AIza") {
                appBootLog.infoWithContext("   ✓ Key format looks valid (starts with 'AIza')")
            } else {
                appBootLog.warningWithContext("   ⚠️ Key format may be invalid (should start with 'AIza')")
                appBootLog.warningWithContext("   Key prefix: '\(String(self.apiKey.prefix(4)))...'")
            }
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
            appBootLog.errorWithContext("❌❌❌ CANNOT IDENTIFY IMAGE: API KEY NOT CONFIGURED ❌❌❌")
            appBootLog.errorWithContext("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            appBootLog.errorWithContext("🔍 Attempted photo identification without API key")
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("⚠️ This error occurs when:")
            appBootLog.errorWithContext("   • No API key is configured in Info.plist, Config.plist, or environment")
            appBootLog.errorWithContext("   • API key is empty or whitespace only")
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("📋 Configuration Status:")
            appBootLog.errorWithContext("   API Key Length: \(apiKey.count) characters")
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("🔧 To Fix:")
            appBootLog.errorWithContext("   1. Get API key from: https://makersuite.google.com/app/apikey")
            appBootLog.errorWithContext("   2. Add to Info.plist with key 'GeminiAPIKey' (quick start)")
            appBootLog.errorWithContext("      OR create Config.plist (recommended)")
            appBootLog.errorWithContext("   3. Rebuild and run the app")
            appBootLog.errorWithContext("")
            appBootLog.errorWithContext("📖 See GEMINI_SETUP.md for complete setup instructions")
            appBootLog.errorWithContext("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return
        }
        
        isProcessing = true
        error = nil
        
        let prompt = customPrompt ?? "What is in this image? Provide a brief, clear identification of the main object or scene. Keep the response concise (1-2 sentences)."
        
        appBootLog.infoWithContext("🔍 Identifying image with Gemini Vision API...")
        appBootLog.debugWithContext("   Image size: \(image.size.width)×\(image.size.height)")
        appBootLog.debugWithContext("   Prompt: \(prompt)")
        
        do {
            // Convert image to base64
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                appBootLog.errorWithContext("❌ Failed to convert UIImage to JPEG data")
                throw GeminiError.imageConversionFailed
            }
            
            let imageSizeKB = Double(imageData.count) / 1024.0
            appBootLog.debugWithContext("   Image data: \(String(format: "%.1f", imageSizeKB)) KB")
            
            let base64Image = imageData.base64EncodedString()
            appBootLog.debugWithContext("   Base64 encoded: \(base64Image.count) characters")
            
            // Create request
            let request = try createRequest(base64Image: base64Image, prompt: prompt)
            appBootLog.debugWithContext("   Request URL: \(request.url?.absoluteString ?? "nil")")
            appBootLog.debugWithContext("   Request method: \(request.httpMethod ?? "nil")")
            
            // Make API call
            appBootLog.infoWithContext("📡 Sending request to Gemini API...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check response
            guard let httpResponse = response as? HTTPURLResponse else {
                appBootLog.errorWithContext("❌ Invalid HTTP response (not HTTPURLResponse)")
                throw GeminiError.invalidResponse
            }
            
            appBootLog.infoWithContext("📥 API Response received")
            appBootLog.debugWithContext("   Status Code: \(httpResponse.statusCode)")
            appBootLog.debugWithContext("   Response size: \(data.count) bytes")
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                appBootLog.errorWithContext("❌ API Error Response:")
                appBootLog.errorWithContext("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                appBootLog.errorWithContext("   Status Code: \(httpResponse.statusCode)")
                appBootLog.errorWithContext("   Error Body: \(errorBody)")
                appBootLog.errorWithContext("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                
                // Provide specific guidance based on status code
                switch httpResponse.statusCode {
                case 400:
                    appBootLog.errorWithContext("💡 400 Bad Request - Check request format or API parameters")
                case 401:
                    appBootLog.errorWithContext("💡 401 Unauthorized - API key may be invalid")
                case 403:
                    appBootLog.errorWithContext("💡 403 Forbidden - API key may be invalid or expired")
                    appBootLog.errorWithContext("   → Verify your key at: https://makersuite.google.com/app/apikey")
                case 429:
                    appBootLog.errorWithContext("💡 429 Rate Limited - Too many requests")
                    appBootLog.errorWithContext("   → Free tier: 15 requests/minute")
                    appBootLog.errorWithContext("   → Wait and try again")
                case 500...599:
                    appBootLog.errorWithContext("💡 \(httpResponse.statusCode) Server Error - Gemini service issue")
                    appBootLog.errorWithContext("   → Try again in a few moments")
                default:
                    appBootLog.errorWithContext("💡 Unknown error code: \(httpResponse.statusCode)")
                }
                
                throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            
            // Parse response
            appBootLog.debugWithContext("🔍 Parsing response...")
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            
            // Extract text from response
            if let candidate = geminiResponse.candidates.first,
               let content = candidate.content.parts.first {
                latestIdentification = content.text
                appBootLog.infoWithContext("✅ Image identified successfully!")
                appBootLog.debugWithContext("   Result: \(content.text)")
                
                // Log safety ratings if present
                if let safetyRatings = candidate.safetyRatings {
                    appBootLog.debugWithContext("   Safety ratings: \(safetyRatings.count) categories checked")
                }
            } else {
                latestIdentification = "No identification available"
                appBootLog.warningWithContext("⚠️ Response received but no identification text found")
                appBootLog.debugWithContext("   Candidates count: \(geminiResponse.candidates.count)")
            }
            
        } catch let error as GeminiError {
            self.error = error.localizedDescription
            appBootLog.errorWithContext("❌ Gemini error: \(error.localizedDescription)")
        } catch let decodingError as DecodingError {
            self.error = "Failed to parse API response"
            appBootLog.errorWithContext("❌ JSON Decoding error: \(decodingError)")
            switch decodingError {
            case .keyNotFound(let key, let context):
                appBootLog.errorWithContext("   Missing key: \(key.stringValue)")
                appBootLog.errorWithContext("   Context: \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                appBootLog.errorWithContext("   Type mismatch: expected \(type)")
                appBootLog.errorWithContext("   Context: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                appBootLog.errorWithContext("   Value not found: \(type)")
                appBootLog.errorWithContext("   Context: \(context.debugDescription)")
            case .dataCorrupted(let context):
                appBootLog.errorWithContext("   Data corrupted")
                appBootLog.errorWithContext("   Context: \(context.debugDescription)")
            @unknown default:
                appBootLog.errorWithContext("   Unknown decoding error")
            }
        } catch {
            self.error = error.localizedDescription
            appBootLog.errorWithContext("❌ Unexpected error: \(error.localizedDescription)")
            appBootLog.errorWithContext("   Error type: \(type(of: error))")
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
