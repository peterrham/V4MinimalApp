//
//  GeminiVisionService.swift
//  V4MinimalApp
//
//  Service for identifying objects using Gemini Vision API
//

import Foundation
import UIKit
import Vision

/// Append a diagnostic line to Documents/debug_log.txt for debugging
nonisolated func geminiDebugLog(_ msg: String) {
    print(msg)
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
        let logURL = dir.appendingPathComponent("debug_log.txt")
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) { handle.write(data) }
            handle.closeFile()
        } else {
            try? line.data(using: .utf8)?.write(to: logURL, options: .atomic)
        }
    }
}

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

    /// Expose API key for other services (e.g., normalization) to reuse
    var apiKeyValue: String { apiKey }
    
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

    // MARK: - Structured Inventory Identification

    /// Identify an image and return structured inventory data
    func identifyForInventory(_ image: UIImage) async -> PhotoIdentificationResult? {
        guard !apiKey.isEmpty else {
            error = "API key not configured"
            return nil
        }

        isProcessing = true
        error = nil

        let prompt = """
        Identify the main item in this photo for home inventory.
        Return JSON only: {"name":"...","brand":"...","color":"...","size":"...","category":"...","estimatedValue":...,"description":"..."}
        category: one of Electronics, Furniture, Appliance, Decor, Kitchen, Clothing, Books, Tools, Sports, Toys, Valuables, Other.
        estimatedValue: number in USD or null. description: 1-2 sentence detail about the item.
        Use null for unknown fields. JSON only, no markdown.
        """

        do {
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                throw GeminiError.imageConversionFailed
            }
            let base64Image = imageData.base64EncodedString()
            let request = try createRequest(base64Image: base64Image, prompt: prompt, maxOutputTokens: 300)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
                throw GeminiError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: errorBody)
            }

            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let candidate = geminiResponse.candidates.first,
                  let content = candidate.content.parts.first else {
                isProcessing = false
                return nil
            }

            let responseText = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📸 Photo identification response: \(responseText.prefix(400))")

            // Also update the display string for backward compat
            latestIdentification = responseText

            let result = PhotoIdentificationResult.parse(from: responseText)
            isProcessing = false
            return result

        } catch {
            self.error = error.localizedDescription
            print("📸 Photo identification error: \(error.localizedDescription)")
            isProcessing = false
            return nil
        }
    }

    // MARK: - Multi-Item Identification

    /// Identify ALL items in a photo, returning structured results with bounding boxes
    func identifyAllItems(_ image: UIImage) async -> [PhotoIdentificationResult] {
        geminiDebugLog("📸 identifyAllItems called, image: \(Int(image.size.width))x\(Int(image.size.height))")

        guard !apiKey.isEmpty else {
            error = "API key not configured"
            geminiDebugLog("📸 ERROR: API key not configured")
            return []
        }

        isProcessing = true
        error = nil

        let prompt = """
        List ALL individual items visible in this photo for home inventory.
        Include even partially visible or indistinct items with your best guess.
        Return JSON array only:
        [{"name":"...","brand":"...","color":"...","size":"...","category":"...","estimatedValue":...,"description":"...","box":[ymin,xmin,ymax,xmax]}]
        category: one of Electronics, Furniture, Appliance, Decor, Kitchen, Clothing, Books, Tools, Sports, Toys, Valuables, Other.
        estimatedValue: number in USD or null. box: bounding box coords 0-1000.
        description: 1-2 sentence detail. Use null for unknown fields.
        Each item must have a UNIQUE descriptive name. Do NOT repeat the same name.
        If multiple similar items exist, number them (e.g. "white bottle 1", "white bottle 2").
        Include every distinct item, even small ones. JSON only, no markdown fences.
        """

        do {
            // Resize large images to max 2048px on longest side for API efficiency
            let maxDim: CGFloat = 2048
            let sendImage: UIImage
            if max(image.size.width, image.size.height) > maxDim {
                let scale = maxDim / max(image.size.width, image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.0  // 1:1 pixels, not screen scale
                let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                sendImage = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
                geminiDebugLog("📸 Resized \(Int(image.size.width))x\(Int(image.size.height)) → \(Int(newSize.width))x\(Int(newSize.height))")
            } else {
                sendImage = image
            }

            guard let imageData = sendImage.jpegData(compressionQuality: 0.85) else {
                throw GeminiError.imageConversionFailed
            }
            let base64Image = imageData.base64EncodedString()
            geminiDebugLog("📸 Image base64: \(base64Image.count) chars, \(imageData.count / 1024)KB")
            let request = try createRequest(base64Image: base64Image, prompt: prompt, maxOutputTokens: 4096)

            geminiDebugLog("📸 Sending request to Gemini...")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                geminiDebugLog("📸 ERROR: Not an HTTP response")
                throw GeminiError.invalidResponse
            }

            geminiDebugLog("📸 HTTP \(httpResponse.statusCode), response: \(data.count) bytes")

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
                geminiDebugLog("📸 API ERROR \(httpResponse.statusCode): \(errorBody.prefix(500))")
                throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }

            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let candidate = geminiResponse.candidates.first,
                  let content = candidate.content.parts.first else {
                geminiDebugLog("📸 ERROR: No candidates in response")
                isProcessing = false
                return []
            }

            let responseText = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            geminiDebugLog("📸 Response text (\(responseText.count) chars):\n\(responseText)")

            if let finishReason = candidate.finishReason {
                geminiDebugLog("📸 Finish reason: \(finishReason)")
            }

            var results = PhotoIdentificationResult.parseMultiple(from: responseText)
            geminiDebugLog("📸 Parsed \(results.count) items (pre-OCR)")
            for (i, r) in results.enumerated() {
                geminiDebugLog("📸   [\(i)] '\(r.name)' cat=\(r.category ?? "-") val=\(r.estimatedValue.map { String(format: "%.0f", $0) } ?? "-") box=\(r.boundingBox != nil)")
            }

            // Enrich with on-device OCR (run off main thread)
            let originalImage = image
            let preOCR = results
            results = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var mutable = preOCR
                    PhotoIdentificationResult.enrichWithOCR(&mutable, originalImage: originalImage)
                    continuation.resume(returning: mutable)
                }
            }

            geminiDebugLog("📸 Final results after OCR: \(results.count) items")
            for (i, r) in results.enumerated() {
                geminiDebugLog("📸   [\(i)] '\(r.name)' brand=\(r.brand ?? "-") size=\(r.size ?? "-") ocr=\(r.ocrText?.count ?? 0) lines")
            }

            isProcessing = false
            return results

        } catch {
            self.error = error.localizedDescription
            geminiDebugLog("📸 CATCH error: \(error)")
            isProcessing = false
            return []
        }
    }

    // MARK: - Private Methods

    private func createRequest(base64Image: String, prompt: String, maxOutputTokens: Int = 100) throws -> URLRequest {
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
                "maxOutputTokens": maxOutputTokens
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
}

// MARK: - Photo Identification Result

struct PhotoIdentificationResult: Identifiable {
    let id = UUID()
    var name: String
    var brand: String?
    var color: String?
    var size: String?
    var category: String?
    var estimatedValue: Double?
    var description: String?
    var boundingBox: (yMin: CGFloat, xMin: CGFloat, yMax: CGFloat, xMax: CGFloat)?
    var ocrText: [String]?

    /// Parse from Gemini JSON response text, with fallback for plain text
    static func parse(from text: String) -> PhotoIdentificationResult {
        // Strip markdown fences if present
        var cleaned = text
        if let range = cleaned.range(of: "```json") {
            cleaned = String(cleaned[range.upperBound...])
        } else if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[range.upperBound...])
        }
        if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try JSON parse
        if let startIdx = cleaned.firstIndex(of: "{"),
           let endIdx = cleaned.lastIndex(of: "}") {
            let jsonStr = String(cleaned[startIdx...endIdx])
            if let data = jsonStr.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                let name = dict["name"] as? String ?? "Unknown Item"
                // Filter out refusal/garbage names
                if name.contains("cannot") || name.contains("unable") || name.count > 80 {
                    return PhotoIdentificationResult(name: "Unknown Item", description: text)
                }

                return PhotoIdentificationResult(
                    name: name,
                    brand: Self.nullableString(dict["brand"]),
                    color: Self.nullableString(dict["color"]),
                    size: Self.nullableString(dict["size"]),
                    category: Self.nullableString(dict["category"]),
                    estimatedValue: Self.nullableDouble(dict["estimatedValue"]),
                    description: Self.nullableString(dict["description"])
                )
            }
        }

        // Fallback: use raw text as description, try to extract a name from first line
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let name = firstLine.count <= 60 ? firstLine : "Unknown Item"
        return PhotoIdentificationResult(name: name, description: text)
    }

    /// Parse a JSON array response into multiple PhotoIdentificationResult items.
    /// Handles truncated JSON (MAX_TOKENS) by recovering complete objects before the break.
    static func parseMultiple(from text: String) -> [PhotoIdentificationResult] {
        geminiDebugLog("🔍 parseMultiple input (\(text.count) chars)")

        // Strip markdown fences if present
        var cleaned = text
        if let range = cleaned.range(of: "```json") {
            cleaned = String(cleaned[range.upperBound...])
            geminiDebugLog("🔍 Stripped ```json fence")
        } else if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[range.upperBound...])
            geminiDebugLog("🔍 Stripped ``` fence")
        }
        if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to find JSON array start
        guard let startIdx = cleaned.firstIndex(of: "[") else {
            geminiDebugLog("🔍 No [ found in text")
            return []
        }

        // Extract from [ to end (may or may not have closing ])
        var jsonStr = String(cleaned[startIdx...])

        // Attempt 1: parse as-is (complete JSON)
        if let results = parseJSONArray(jsonStr) {
            geminiDebugLog("🔍 Clean parse: \(results.count) items")
            return results
        }

        // Attempt 2: truncated JSON — find last complete object and close the array
        // Look backwards for the last "}," or "}" that ends a complete object
        geminiDebugLog("🔍 JSON parse failed, attempting truncation recovery...")
        var recovered = false
        var searchStr = jsonStr
        // Try progressively shorter substrings ending at the last complete "}"
        while let lastBrace = searchStr.lastIndex(of: "}") {
            let candidate = String(searchStr[...lastBrace]) + "]"
            if let results = parseJSONArray(candidate) {
                geminiDebugLog("🔍 Truncation recovery: \(results.count) items from \(candidate.count) chars")
                return results
            }
            // Move search window back before this brace
            searchStr = String(searchStr[..<lastBrace])
        }

        if !recovered {
            geminiDebugLog("🔍 All recovery attempts failed")
        }
        return []
    }

    /// Parse a JSON string as an array of item dictionaries, returning nil on failure
    private static func parseJSONArray(_ jsonStr: String) -> [PhotoIdentificationResult]? {
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let array = obj as? [[String: Any]] else {
            return nil
        }

        var results: [PhotoIdentificationResult] = []
        var nameCounts: [String: Int] = [:]  // Track duplicate names to cap hallucinations
        for (i, dict) in array.enumerated() {
            let name = dict["name"] as? String ?? ""
            if name.isEmpty { continue }
            // Filter refusal/garbage names
            if name.contains("cannot") || name.contains("unable") || name.count > 80 { continue }
            if name.contains("{") || name.contains("[") || name.contains("\"") { continue }
            if name.hasPrefix("```") { continue }
            // Cap duplicate names at 3 to prevent hallucination spam
            let nameKey = name.lowercased()
            let count = nameCounts[nameKey, default: 0]
            if count >= 3 { continue }
            nameCounts[nameKey] = count + 1

            var box: (yMin: CGFloat, xMin: CGFloat, yMax: CGFloat, xMax: CGFloat)?
            if let boxArr = dict["box"] as? [NSNumber], boxArr.count == 4 {
                box = (
                    yMin: CGFloat(boxArr[0].doubleValue) / 1000.0,
                    xMin: CGFloat(boxArr[1].doubleValue) / 1000.0,
                    yMax: CGFloat(boxArr[2].doubleValue) / 1000.0,
                    xMax: CGFloat(boxArr[3].doubleValue) / 1000.0
                )
            }

            let result = PhotoIdentificationResult(
                name: name,
                brand: nullableString(dict["brand"]),
                color: nullableString(dict["color"]),
                size: nullableString(dict["size"]),
                category: nullableString(dict["category"]),
                estimatedValue: nullableDouble(dict["estimatedValue"]),
                description: nullableString(dict["description"]),
                boundingBox: box
            )
            results.append(result)
            geminiDebugLog("🔍 [\(i)] ✅ '\(name)' box=\(box != nil)")
        }
        geminiDebugLog("🔍 Array: \(results.count)/\(array.count) valid")
        return results.isEmpty ? nil : results
    }

    private static func nullableString(_ value: Any?) -> String? {
        guard let str = value as? String, str != "null", !str.isEmpty else { return nil }
        return str
    }

    private static func nullableDouble(_ value: Any?) -> Double? {
        if let num = value as? Double { return num }
        if let num = value as? Int { return Double(num) }
        if let str = value as? String, let num = Double(str) { return num }
        return nil
    }

    // MARK: - OCR Enrichment

    /// Run Vision OCR on a UIImage and return recognized text lines
    static func recognizeText(in image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        var results: [String] = []
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            for observation in observations {
                if let candidate = observation.topCandidates(1).first, candidate.confidence > 0.3 {
                    results.append(candidate.string)
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        return results
    }

    /// Crop an image to a normalized bounding box (0-1 coords) with padding for OCR
    private static func cropForOCR(_ image: UIImage, box: (yMin: CGFloat, xMin: CGFloat, yMax: CGFloat, xMax: CGFloat)) -> UIImage {
        let imgW = image.size.width
        let imgH = image.size.height

        let bx = box.xMin * imgW
        let by = box.yMin * imgH
        let bw = (box.xMax - box.xMin) * imgW
        let bh = (box.yMax - box.yMin) * imgH
        let pad: CGFloat = 0.05
        let padX = bw * pad
        let padY = bh * pad

        let cropRect = CGRect(
            x: max(bx - padX, 0),
            y: max(by - padY, 0),
            width: min(bw + padX * 2, imgW - max(bx - padX, 0)),
            height: min(bh + padY * 2, imgH - max(by - padY, 0))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
        return renderer.image { _ in
            image.draw(at: CGPoint(x: -cropRect.origin.x, y: -cropRect.origin.y))
        }
    }

    /// Enrich results with on-device OCR from cropped bounding boxes
    static func enrichWithOCR(_ results: inout [PhotoIdentificationResult], originalImage: UIImage) {
        geminiDebugLog("🔤 OCR enrichment starting for \(results.count) items")

        for i in results.indices {
            guard let box = results[i].boundingBox else { continue }

            let cropped = cropForOCR(originalImage, box: box)
            let ocrLines = recognizeText(in: cropped)

            if ocrLines.isEmpty {
                geminiDebugLog("🔤 [\(i)] '\(results[i].name)' — no OCR text")
                continue
            }

            results[i].ocrText = ocrLines
            let allText = ocrLines.joined(separator: " ")
            geminiDebugLog("🔤 [\(i)] '\(results[i].name)' — OCR(\(ocrLines.count) lines): \(ocrLines.prefix(3).joined(separator: " | "))")

            // 1. Extract brand from OCR if missing
            if results[i].brand == nil || results[i].brand == "Unknown" {
                if let brand = extractBrand(from: ocrLines) {
                    geminiDebugLog("🔤   Brand: '\(results[i].brand ?? "nil")' → '\(brand)'")
                    results[i].brand = brand
                }
            }

            // 2. Extract size from OCR if missing
            if results[i].size == nil {
                if let size = extractSize(from: allText) {
                    geminiDebugLog("🔤   Size: nil → '\(size)'")
                    results[i].size = size
                }
            }

            // 3. Improve generic names using OCR
            let improvedName = improveNameWithOCR(
                currentName: results[i].name,
                brand: results[i].brand,
                ocrLines: ocrLines
            )
            if improvedName != results[i].name {
                geminiDebugLog("🔤   Name: '\(results[i].name)' → '\(improvedName)'")
                results[i].name = improvedName
            }

            // 4. Append key OCR text to description
            let ocrSummary = ocrLines.prefix(5).joined(separator: "; ")
            if !ocrSummary.isEmpty {
                let existing = results[i].description ?? ""
                results[i].description = existing.isEmpty ? "OCR: \(ocrSummary)" : "\(existing) | OCR: \(ocrSummary)"
            }
        }

        geminiDebugLog("🔤 OCR enrichment complete")
    }

    // Common words to skip when looking for brands
    private static let commonWords: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "your", "not",
        "all", "new", "use", "see", "may", "can", "get", "how", "our",
        "drug", "facts", "active", "ingredient", "purpose", "uses", "warnings",
        "directions", "other", "information", "questions", "keep", "out",
        "reach", "children", "stop", "ask", "doctor", "apply", "skin",
        "net", "contents", "made", "usa", "distributed", "do", "not",
        "danger", "caution", "warning", "maximum", "strength", "fast",
        "acting", "relief", "daily", "twice", "once"
    ]

    /// Extract a brand name from OCR lines
    private static func extractBrand(from ocrLines: [String]) -> String? {
        // Priority 1: Lines with ® or ™
        for line in ocrLines {
            if line.contains("®") || line.contains("™") {
                let brand = line
                    .replacingOccurrences(of: "®", with: "")
                    .replacingOccurrences(of: "™", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if brand.count >= 2 && brand.count <= 40 {
                    return brand
                }
            }
        }

        // Priority 2: ALL-CAPS phrases (3-30 chars, not common/instruction words)
        for line in ocrLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3, trimmed.count <= 30,
                  trimmed == trimmed.uppercased(),
                  trimmed.rangeOfCharacter(from: .letters) != nil else { continue }

            let lower = trimmed.lowercased()
            let words = lower.split(separator: " ").map(String.init)
            // Skip if ALL words are common
            if words.allSatisfy({ commonWords.contains($0) }) { continue }
            // Skip pure numbers
            if lower.allSatisfy({ $0.isNumber || $0 == " " }) { continue }
            // Skip sizes
            if lower.contains(" oz") || lower.contains(" ml") || lower.contains(" mg") { continue }
            // Skip instructions
            if lower.hasPrefix("do ") || lower.hasPrefix("use ") || lower.hasPrefix("apply ") { continue }
            return trimmed
        }

        // Priority 3: Title-cased multi-word phrases in first few lines
        for line in ocrLines.prefix(5) {
            let words = line.split(separator: " ").map(String.init)
            guard words.count >= 1, words.count <= 4,
                  line.count >= 3, line.count <= 40 else { continue }

            let hasProperNoun = words.contains { word in
                guard let first = word.first else { return false }
                return first.isUppercase && !commonWords.contains(word.lowercased())
            }
            guard hasProperNoun else { continue }

            let lower = line.lowercased()
            if lower.contains("drug facts") || lower.contains("active ingredient") { continue }
            if lower.hasPrefix("do ") || lower.hasPrefix("use ") || lower.hasPrefix("apply ") { continue }
            // Skip if it looks like a sentence fragment (contains common verbs)
            if lower.contains(" is ") || lower.contains(" are ") || lower.contains(" the ") { continue }
            return line.trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

    /// Extract size/weight info from OCR text
    private static func extractSize(from text: String) -> String? {
        let patterns = [
            "\\b(\\d+\\.?\\d*)\\s*(fl\\.?\\s*oz|oz|ml|mg|g|lb|kg|gal)\\b",
            "\\b(\\d+\\.?\\d*)\\s*(fluid ounce|ounce|gram|liter|gallon)s?\\b"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                return String(text[range])
            }
        }
        return nil
    }

    /// Improve a generic name using OCR-detected text
    private static func improveNameWithOCR(currentName: String, brand: String?, ocrLines: [String]) -> String {
        let lowerName = currentName.lowercased()

        // Only improve names that look generic
        let genericPatterns = [
            "white bottle", "small bottle", "blue bottle", "red container",
            "white tube", "clear bottle", "black bottle", "purple bottle",
            "small black", "small white", "small green", "small brown",
            "white device", "white electronic", "clear plastic",
            "small item", "blue bottle 1", "blue bottle 2",
            "white bottle 1", "white bottle 2", "white label",
            "red pill", "tan bottle", "light brown bottle"
        ]

        let isGeneric = genericPatterns.contains(where: { lowerName.contains($0) })
            || (lowerName.hasPrefix("small ") && lowerName.count < 25)

        guard isGeneric else { return currentName }

        // Look for product-type keywords in OCR
        let productTypes: [(keyword: String, label: String)] = [
            ("shampoo", "Shampoo"),
            ("conditioner", "Conditioner"),
            ("deodorant", "Deodorant"),
            ("toothpaste", "Toothpaste"),
            ("tooth powder", "Tooth Powder"),
            ("mouthwash", "Mouthwash"),
            ("sunscreen", "Sunscreen"),
            ("lotion", "Lotion"),
            ("cream", "Cream"),
            ("serum", "Serum"),
            ("moisturizer", "Moisturizer"),
            ("cleanser", "Cleanser"),
            ("body wash", "Body Wash"),
            ("face wash", "Face Wash"),
            ("hand sanitizer", "Hand Sanitizer"),
            ("itch relief", "Itch Relief"),
            ("anti-itch", "Anti-Itch Treatment"),
            ("pain relief", "Pain Relief"),
            ("antibiotic", "Antibiotic"),
            ("hydrocortisone", "Hydrocortisone Cream"),
            ("fluoride", "Fluoride Toothpaste"),
            ("sharps container", "Sharps Container"),
            ("supplement", "Supplement"),
            ("vitamin", "Vitamin"),
            ("spray", "Spray"),
            ("ointment", "Ointment"),
            ("powder", "Powder"),
            ("soap", "Soap"),
            ("floss", "Dental Floss"),
            ("bandage", "Bandage"),
        ]

        let allText = ocrLines.joined(separator: " ").lowercased()

        for (keyword, label) in productTypes {
            if allText.contains(keyword) {
                if let brand = brand, !brand.isEmpty {
                    return "\(brand) \(label)"
                } else {
                    return label
                }
            }
        }

        // If no product type found but we have a brand, prefix it
        if let brand = brand, !brand.isEmpty,
           !currentName.lowercased().contains(brand.lowercased()) {
            return "\(brand) \(currentName)"
        }

        return currentName
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
