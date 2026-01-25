//
//  GeminiStreamingVisionService.swift
//  V4MinimalApp
//
//  Real-time video frame analysis with Gemini Vision API
//

import Foundation
import UIKit
import AVFoundation

/// Service for real-time object detection from video frames using Gemini
@MainActor
class GeminiStreamingVisionService: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published var detectedObjects: [DetectedObject] = []
    @Published var isAnalyzing = false
    @Published var error: String?
    
    // MARK: - Configuration
    
    private let apiKey: String
    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent"
    
    // Frame analysis throttling
    private var lastAnalysisTime: Date = .distantPast
    private let analysisInterval: TimeInterval = 2.0 // Analyze every 2 seconds
    private var isCurrentlyAnalyzing = false
    
    // MARK: - Initialization
    
    init(apiKey: String = "") {
        // Load API key from multiple sources (same as GeminiVisionService)
        if !apiKey.isEmpty {
            self.apiKey = apiKey
        } else if let configKey = Self.loadFromConfig() {
            self.apiKey = configKey
        } else if let infoPlistKey = Self.loadFromInfoPlist() {
            self.apiKey = infoPlistKey
        } else if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            self.apiKey = envKey
        } else {
            self.apiKey = ""
        }
        
        super.init()
    }
    
    // MARK: - Configuration Loading
    
    private static func loadFromConfig() -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let apiKey = config["GeminiAPIKey"] as? String,
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }
    
    private static func loadFromInfoPlist() -> String? {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String,
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }
    
    // MARK: - Public Methods
    
    /// Start analyzing video frames
    func startAnalyzing() {
        guard !apiKey.isEmpty else {
            error = "API key not configured"
            return
        }
        
        isAnalyzing = true
        error = nil
        detectedObjects.removeAll()
        print("🎥 Started real-time object detection")
    }
    
    /// Stop analyzing video frames
    func stopAnalyzing() {
        isAnalyzing = false
        print("⏹️ Stopped real-time object detection")
    }
    
    /// Clear detected objects
    func clearDetections() {
        detectedObjects.removeAll()
    }
    
    /// Analyze a video frame
    func analyzeFrame(_ image: UIImage) async {
        // Skip if not analyzing or throttled
        guard isAnalyzing else { return }
        guard !isCurrentlyAnalyzing else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= analysisInterval else { return }
        
        lastAnalysisTime = now
        isCurrentlyAnalyzing = true
        
        do {
            // Convert image to base64
            guard let imageData = image.jpegData(compressionQuality: 0.5) else {
                throw GeminiStreamingError.imageConversionFailed
            }
            
            let base64Image = imageData.base64EncodedString()
            
            // Create request with optimized prompt for object detection
            let prompt = "List all distinct objects you see in this image. Give ONE brief phrase per object (3-5 words max). Format as a simple list separated by commas. Focus on physical items, not descriptions."
            
            let request = try createRequest(base64Image: base64Image, prompt: prompt)
            
            // Make API call
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiStreamingError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiStreamingError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            
            // Parse response
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            
            if let candidate = geminiResponse.candidates.first,
               let content = candidate.content.parts.first {
                
                // Parse the comma-separated list
                let objectNames = content.text
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                // Add new detected objects
                for name in objectNames {
                    let detection = DetectedObject(name: name, timestamp: Date())
                    
                    // Avoid duplicates from recent detections (last 10 seconds)
                    let isDuplicate = detectedObjects.contains { existing in
                        existing.name.lowercased() == name.lowercased() &&
                        now.timeIntervalSince(existing.timestamp) < 10
                    }
                    
                    if !isDuplicate {
                        detectedObjects.append(detection)
                        print("✅ Detected: \(name)")
                    }
                }
                
                // Keep only last 500 objects
                if detectedObjects.count > 500 {
                    detectedObjects.removeFirst(detectedObjects.count - 500)
                }
            }
            
        } catch {
            self.error = error.localizedDescription
            print("❌ Frame analysis error: \(error.localizedDescription)")
        }
        
        isCurrentlyAnalyzing = false
    }
    
    // MARK: - Private Methods
    
    private func createRequest(base64Image: String, prompt: String) throws -> URLRequest {
        guard let url = URL(string: "\(apiEndpoint)?key=\(apiKey)") else {
            throw GeminiStreamingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10 // Faster timeout for real-time
        
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
                "temperature": 0.2, // Lower temperature for more consistent detection
                "topK": 20,
                "topP": 0.8,
                "maxOutputTokens": 150
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }
}

// MARK: - Models

struct DetectedObject: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let timestamp: Date
    
    static func == (lhs: DetectedObject, rhs: DetectedObject) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Errors

enum GeminiStreamingError: Error {
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
