//
//  GeminiStreamingVisionService.swift
//  V4MinimalApp
//
//  Real-time video frame analysis with Gemini Vision API
//

import Foundation
import UIKit
import AVFoundation
import os.log

/// Service for real-time object detection from video frames using Gemini
@MainActor
class GeminiStreamingVisionService: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published var detectedObjects: [DetectedObject] = []
    @Published var isAnalyzing = false
    @Published var error: String?

    // MARK: - Timing Metrics

    @Published var lastResponseTimeMs: Int = 0
    @Published var averageResponseTimeMs: Int = 0
    @Published var totalAnalyses: Int = 0
    @Published var successfulAnalyses: Int = 0
    private var recentResponseTimes: [Double] = []  // rolling window of last 50

    // MARK: - Configuration

    private let apiKey: String
    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"

    // Frame analysis throttling
    private var lastAnalysisTime: Date = .distantPast
    private var analysisInterval: TimeInterval {
        DetectionSettings.shared.analysisInterval
    }
    private var isCurrentlyAnalyzing = false

    /// Last analyzed frame — stored so we can grab a thumbnail when the user saves
    var lastAnalyzedFrame: UIImage?
    
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
    /// Timestamp when startAnalyzing() was called — used to measure time-to-first-detection
    var analysisStartTime: CFAbsoluteTime = 0
    var hasLoggedFirstDetection = false

    func startAnalyzing() {
        guard !apiKey.isEmpty else {
            error = "API key not configured"
            return
        }

        isAnalyzing = true
        error = nil
        detectedObjects.removeAll()
        analysisStartTime = CFAbsoluteTimeGetCurrent()
        hasLoggedFirstDetection = false
        NetworkLogger.shared.info("TIMING: detection started (t=0ms)", category: "Detection")
        os_log("TIMING: detection started (t=0ms)")
        print("🎥 Started real-time object detection (t=0ms)")
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
    
    /// Analyze a video frame — detects items with bounding boxes in one call
    func analyzeFrame(_ image: UIImage) async {
        // Skip if not analyzing or throttled
        guard isAnalyzing else { return }
        guard !isCurrentlyAnalyzing else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= analysisInterval else { return }

        lastAnalysisTime = now
        isCurrentlyAnalyzing = true

        let sinceStart = Int((CFAbsoluteTimeGetCurrent() - analysisStartTime) * 1000)
        if totalAnalyses == 0 {
            NetworkLogger.shared.info("TIMING: first frame to Gemini at t=\(sinceStart)ms", category: "Detection")
            os_log("TIMING: first frame to Gemini at t=%dms", sinceStart)
            print("⏱️ First frame sent to Gemini at t=\(sinceStart)ms")
        }

        // Store frame for thumbnail creation later (on save)
        lastAnalyzedFrame = image

        do {
            // Resize frame for faster analysis (default 640px wide)
            let resized = Self.resizeForAnalysis(image)

            // Convert image to base64 with configurable quality
            let quality = DetectionSettings.shared.jpegQuality
            guard let imageData = resized.jpegData(compressionQuality: quality) else {
                throw GeminiStreamingError.imageConversionFailed
            }

            let base64Image = imageData.base64EncodedString()
            let payloadKB = imageData.count / 1024
            print("📦 Frame: \(Int(resized.size.width))x\(Int(resized.size.height)), \(payloadKB)KB, q=\(String(format: "%.0f%%", quality * 100))")

            // Combined prompt: item names + bounding boxes in one call
            let prompt = """
            List physical items suitable for home inventory with bounding boxes.
            Be specific with brand/type when visible (e.g., "DirecTV remote", "Samsung TV").

            INCLUDE: furniture, electronics, appliances, decor, tools, clothing, books, kitchenware, valuables.
            EXCLUDE: shadows, light, reflections, textures, floors, walls, ceilings.

            Return JSON array only: [{"name":"Item Name","box":[ymin,xmin,ymax,xmax]}]
            Coordinates 0-1000. 2-4 words per item name. JSON only, no markdown.
            """

            let request = try createRequest(base64Image: base64Image, prompt: prompt, maxOutputTokens: 400)

            // Make API call with timing
            let startTime = CFAbsoluteTimeGetCurrent()
            totalAnalyses += 1

            let (data, response) = try await URLSession.shared.data(for: request)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let elapsedMs = Int(elapsed * 1000)
            lastResponseTimeMs = elapsedMs

            // Update rolling average (keep last 50)
            recentResponseTimes.append(elapsed * 1000)
            if recentResponseTimes.count > 50 {
                recentResponseTimes.removeFirst()
            }
            averageResponseTimeMs = Int(recentResponseTimes.reduce(0, +) / Double(recentResponseTimes.count))

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiStreamingError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GeminiStreamingError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }

            successfulAnalyses += 1
            print("📦 Response: \(elapsedMs)ms (avg \(averageResponseTimeMs)ms, \(successfulAnalyses)/\(totalAnalyses) ok)")

            // Parse response
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

            if let candidate = geminiResponse.candidates.first,
               let content = candidate.content.parts.first {

                let responseText = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("📦 Response: \(responseText.prefix(400))")

                // Reject refusal/error responses entirely
                if Self.isRefusalResponse(responseText) {
                    NetworkLogger.shared.warning("Gemini returned refusal text, skipping: \(responseText.prefix(100))", category: "Detection")
                    print("⚠️ Gemini refusal detected, skipping response")
                    isCurrentlyAnalyzing = false
                    return
                }

                // Try JSON parse (with bounding boxes)
                let parsedWithBoxes = Self.parseDetectionsWithBoxes(from: responseText, timestamp: Date())

                // Fall back to comma-separated if JSON parse fails
                let parsedDetections: [DetectedObject]
                if !parsedWithBoxes.isEmpty {
                    parsedDetections = parsedWithBoxes
                    print("📦 Parsed \(parsedWithBoxes.count) items with bounding boxes")
                } else {
                    parsedDetections = Self.parseDetections(from: responseText, timestamp: Date())
                    print("📦 Fallback: parsed \(parsedDetections.count) items without boxes")
                }

                // Add new detected objects
                for var detection in parsedDetections {
                    // Avoid duplicates from recent detections (last 10 seconds)
                    let isDuplicate = detectedObjects.contains { existing in
                        existing.name.lowercased() == detection.name.lowercased() &&
                        now.timeIntervalSince(existing.timestamp) < 10
                    }

                    if !isDuplicate {
                        // Lazily attach a thumbnail reference — actual JPEG created on save
                        detection.sourceFrame = image
                        detectedObjects.append(detection)
                        print("✅ Detected: \(detection.name)\(detection.boundingBoxes != nil ? " [bbox]" : "")")

                        // Log time-to-first-detection
                        if !hasLoggedFirstDetection {
                            let totalMs = Int((CFAbsoluteTimeGetCurrent() - analysisStartTime) * 1000)
                            NetworkLogger.shared.info("TIMING: FIRST DETECTION at t=\(totalMs)ms — \(detection.name) (API: \(elapsedMs)ms)", category: "Detection")
                            os_log("TIMING: FIRST DETECTION at t=%dms — %{public}@ (API: %dms)", totalMs, detection.name, elapsedMs)
                            print("⏱️ FIRST DETECTION at t=\(totalMs)ms: \(detection.name) (API call: \(elapsedMs)ms)")
                            hasLoggedFirstDetection = true
                        }
                    }
                }

                // Keep only last 200 objects (reduced from 500 to save memory with frame refs)
                if detectedObjects.count > 200 {
                    // Nil out frame references on old items before removing
                    for i in 0..<(detectedObjects.count - 200) {
                        detectedObjects[i].sourceFrame = nil
                    }
                    detectedObjects.removeFirst(detectedObjects.count - 200)
                }
            }

        } catch {
            self.error = error.localizedDescription
            print("❌ Frame analysis error: \(error.localizedDescription)")
        }

        isCurrentlyAnalyzing = false
    }
    
    // MARK: - Frame Resizing

    /// Resize image to target width for faster API analysis
    static func resizeForAnalysis(_ image: UIImage) -> UIImage {
        let targetWidth = CGFloat(DetectionSettings.shared.frameResizeWidth)
        guard image.size.width > targetWidth else { return image }

        let scale = targetWidth / image.size.width
        let newSize = CGSize(width: targetWidth, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Response Validation

    /// Check if the entire response looks like a refusal or error rather than detection results
    static func isRefusalResponse(_ text: String) -> Bool {
        let lower = text.lowercased()
        let refusalPhrases = [
            "i cannot", "i can't", "i'm sorry", "i am sorry", "i'm unable",
            "i am unable", "unable to", "cannot provide", "cannot detect",
            "no physical items", "no items detected", "i don't see",
            "i do not see", "not able to", "there are no items",
            "i apologize", "as an ai", "as a language model"
        ]
        return refusalPhrases.contains { lower.contains($0) }
    }

    /// Check if a detection name looks valid (not an error message or sentence)
    static func isValidDetectionName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Too long — likely a sentence, not an item name
        if trimmed.count > 60 { return false }
        // Too many words — item names are typically 1-5 words
        let wordCount = trimmed.split(separator: " ").count
        if wordCount > 7 { return false }
        // Contains JSON artifacts
        if trimmed.contains("{") || trimmed.contains("[") || trimmed.contains("\"") { return false }
        // Contains refusal/error phrases
        let lower = trimmed.lowercased()
        let badPhrases = [
            "cannot", "can't", "sorry", "unable", "i don't", "i do not",
            "no items", "not able", "apologize", "as an ai", "detect any",
            "provide a list", "language model"
        ]
        if badPhrases.contains(where: { lower.contains($0) }) { return false }
        return true
    }

    // MARK: - Response Parsing

    /// Parse JSON response with bounding boxes into DetectedObjects
    static func parseDetectionsWithBoxes(from text: String, timestamp: Date) -> [DetectedObject] {
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

        guard let startIdx = cleaned.firstIndex(of: "["),
              let endIdx = cleaned.lastIndex(of: "]") else { return [] }

        let jsonStr = String(cleaned[startIdx...endIdx])
        guard let jsonData = jsonStr.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return []
        }

        var results: [DetectedObject] = []
        for entry in array {
            guard let name = entry["name"] as? String, !name.isEmpty else { continue }
            guard isValidDetectionName(name) else { continue }

            var detection = DetectedObject(name: name, timestamp: timestamp)

            if let box = entry["box"] as? [NSNumber], box.count == 4 {
                let bb = BoundingBox(
                    label: name,
                    yMin: CGFloat(box[0].doubleValue) / 1000.0,
                    xMin: CGFloat(box[1].doubleValue) / 1000.0,
                    yMax: CGFloat(box[2].doubleValue) / 1000.0,
                    xMax: CGFloat(box[3].doubleValue) / 1000.0
                )
                detection.boundingBoxes = [bb]
            }
            results.append(detection)
        }
        return results
    }

    /// Fallback: parse comma-separated item names from Gemini response
    static func parseDetections(from text: String, timestamp: Date) -> [DetectedObject] {
        // Don't comma-split JSON
        if text.contains("{") || text.contains("[") { return [] }
        return text
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isValidDetectionName($0) }
            .map { DetectedObject(name: $0, timestamp: timestamp) }
    }

    // MARK: - Request Building

    private func createRequest(base64Image: String, prompt: String, maxOutputTokens: Int = 150, timeout: TimeInterval = 10) throws -> URLRequest {
        guard let url = URL(string: "\(apiEndpoint)?key=\(apiKey)") else {
            throw GeminiStreamingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

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
                "temperature": 0.2,
                "topK": 20,
                "topP": 0.8,
                "maxOutputTokens": maxOutputTokens
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        return request
    }

    // MARK: - YOLO Crop Enrichment

    /// Enrichment result from Gemini for a cropped YOLO detection
    struct CropEnrichmentResult {
        let name: String
        let brand: String?
        let color: String?
        let size: String?
        let category: String?
        let estimatedValue: String?
    }

    /// Send a cropped image (from YOLO bounding box) to Gemini for specific identification.
    /// Returns enriched name + details, or nil on failure.
    func enrichCrop(_ croppedImage: UIImage, yoloClassName: String) async -> CropEnrichmentResult? {
        guard !apiKey.isEmpty else { return nil }

        let resized = Self.resizeForAnalysis(croppedImage)
        let quality = DetectionSettings.shared.jpegQuality
        guard let imageData = resized.jpegData(compressionQuality: quality) else { return nil }
        let base64Image = imageData.base64EncodedString()

        let prompt = """
        Identify this specific item (detected as "\(yoloClassName)" by object detection).
        Be specific: brand, model, color, size when visible.
        Return JSON only: {"name":"Specific Item Name","brand":"...","color":"...","size":"...","category":"...","estimatedValue":"..."}
        Use null for unknown fields. category: Electronics, Furniture, Appliance, Decor, Kitchen, Clothing, Books, Tools, Sports, Toys, Valuables, Other.
        2-4 words for name. JSON only, no markdown.
        """

        do {
            let request = try createRequest(base64Image: base64Image, prompt: prompt, maxOutputTokens: 200, timeout: 10)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let candidate = geminiResponse.candidates.first,
                  let content = candidate.content.parts.first else { return nil }

            let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Parse JSON
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

            guard let startIdx = cleaned.firstIndex(of: "{"),
                  let endIdx = cleaned.lastIndex(of: "}") else { return nil }

            let jsonStr = String(cleaned[startIdx...endIdx])
            guard let jsonData = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }

            guard let name = dict["name"] as? String, !name.isEmpty,
                  !name.contains("{"), !name.contains("[") else { return nil }

            return CropEnrichmentResult(
                name: name,
                brand: (dict["brand"] as? String).flatMap { $0 == "null" ? nil : $0 },
                color: (dict["color"] as? String).flatMap { $0 == "null" ? nil : $0 },
                size: (dict["size"] as? String).flatMap { $0 == "null" ? nil : $0 },
                category: (dict["category"] as? String).flatMap { $0 == "null" ? nil : $0 },
                estimatedValue: (dict["estimatedValue"] as? String).flatMap { $0 == "null" ? nil : $0 }
            )
        } catch {
            print("🔬 Crop enrichment error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Bounding Box Enrichment

    /// Background request to get bounding box coordinates for detected items
    func requestBoundingBoxes(for names: [String], base64Image: String) async {
        guard !names.isEmpty else { return }

        let itemList = names.joined(separator: ", ")
        let prompt = """
        For each item in this image, return bounding box coordinates.
        Items: \(itemList)
        Return JSON array only: [{"name":"...","box":[ymin,xmin,ymax,xmax]}]
        Coordinates 0-1000. JSON only, no markdown, no explanation.
        """

        print("📦 Requesting bounding boxes for: \(itemList)")

        do {
            let request = try createRequest(base64Image: base64Image, prompt: prompt, maxOutputTokens: 400, timeout: 15)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("📦 Bounding box: not an HTTP response")
                return
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "?"
                print("📦 Bounding box HTTP \(httpResponse.statusCode): \(body.prefix(200))")
                return
            }

            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let candidate = geminiResponse.candidates.first,
                  let content = candidate.content.parts.first else {
                print("📦 Bounding box: no candidates in response")
                return
            }

            let responseText = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📦 Bounding box raw response: \(responseText.prefix(300))")
            let boxes = Self.parseBoundingBoxes(from: responseText)

            guard !boxes.isEmpty else {
                print("📦 No bounding boxes parsed from response")
                return
            }

            print("📦 Parsed \(boxes.count) box groups: \(boxes.keys.joined(separator: ", "))")

            // Match boxes to existing detected objects by name
            var matched = 0
            for (name, boxList) in boxes {
                let nameLower = name.lowercased()
                if let idx = detectedObjects.lastIndex(where: {
                    $0.name.lowercased() == nameLower ||
                    $0.name.lowercased().contains(nameLower) ||
                    nameLower.contains($0.name.lowercased())
                }) {
                    detectedObjects[idx].boundingBoxes = boxList
                    matched += 1
                    print("📦 Matched box '\(name)' -> '\(detectedObjects[idx].name)' [\(boxList.count) boxes]")
                } else {
                    print("📦 No match for box name: '\(name)'")
                }
            }
            print("📦 Bounding boxes done: \(matched)/\(boxes.count) matched")
        } catch {
            print("📦 Bounding box error: \(error.localizedDescription)")
        }
    }

    /// Parse bounding box JSON from Gemini response
    static func parseBoundingBoxes(from text: String) -> [String: [BoundingBox]] {
        var result: [String: [BoundingBox]] = [:]

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

        // Try to find JSON array
        guard let startIdx = cleaned.firstIndex(of: "["),
              let endIdx = cleaned.lastIndex(of: "]") else { return result }

        let jsonStr = String(cleaned[startIdx...endIdx])
        guard let jsonData = jsonStr.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return result
        }

        for entry in array {
            guard let name = entry["name"] as? String,
                  let box = entry["box"] as? [NSNumber], box.count == 4 else { continue }

            let bb = BoundingBox(
                label: name,
                yMin: CGFloat(box[0].doubleValue) / 1000.0,
                xMin: CGFloat(box[1].doubleValue) / 1000.0,
                yMax: CGFloat(box[2].doubleValue) / 1000.0,
                xMax: CGFloat(box[3].doubleValue) / 1000.0
            )

            result[name, default: []].append(bb)
        }

        return result
    }
}

// MARK: - Models

struct BoundingBox {
    let label: String
    let yMin: CGFloat  // 0.0 - 1.0 normalized
    let xMin: CGFloat
    let yMax: CGFloat
    let xMax: CGFloat
}

struct DetectedObject: Identifiable, Equatable {
    let id = UUID()
    var name: String
    let timestamp: Date
    var color: String?
    var brand: String?
    var size: String?
    var categoryHint: String?
    var sourceFrame: UIImage?  // Reference to the camera frame (thumbnail created on save)
    var boundingBoxes: [BoundingBox]?

    // YOLO hybrid pipeline fields
    var yoloClassName: String?    // Original COCO class (e.g., "laptop")
    var isEnriched: Bool = false  // True after Gemini enrichment

    /// Create JPEG thumbnail on demand (called when saving to inventory).
    /// If bounding box available: crops to the box with padding + draws green outline.
    /// Otherwise: returns scaled full frame.
    func createThumbnailData() -> Data? {
        guard let image = sourceFrame else {
            NetworkLogger.shared.error("createThumbnailData: sourceFrame is nil for '\(name)' (yolo=\(yoloClassName ?? "none"), enriched=\(isEnriched))", category: "Thumbnail")
            return nil
        }
        NetworkLogger.shared.info("createThumbnailData: sourceFrame OK for '\(name)' — \(Int(image.size.width))x\(Int(image.size.height)), boxes=\(boundingBoxes?.count ?? 0)", category: "Thumbnail")
        let imgW = image.size.width
        let imgH = image.size.height

        if let box = boundingBoxes?.first {
            // Crop to bounding box with 15% padding
            let pad: CGFloat = 0.15
            let bx = box.xMin * imgW
            let by = box.yMin * imgH
            let bw = (box.xMax - box.xMin) * imgW
            let bh = (box.yMax - box.yMin) * imgH
            let padX = bw * pad
            let padY = bh * pad

            let cropRect = CGRect(
                x: max(bx - padX, 0),
                y: max(by - padY, 0),
                width: min(bw + padX * 2, imgW - max(bx - padX, 0)),
                height: min(bh + padY * 2, imgH - max(by - padY, 0))
            )

            // Crop using CGImage (must handle orientation)
            guard let cgImage = image.cgImage else { return nil }
            // Convert from UIKit coords (origin top-left) to CGImage coords based on orientation
            let cropInCG = convertRectToCGImageCoords(cropRect, imageSize: image.size, orientation: image.imageOrientation)
            guard let cropped = cgImage.cropping(to: cropInCG) else { return nil }
            let croppedImage = UIImage(cgImage: cropped, scale: 1.0, orientation: image.imageOrientation)

            // Scale cropped image to max 480px wide
            let maxWidth: CGFloat = 480
            let scale = min(maxWidth / croppedImage.size.width, 1.0)
            let outSize = CGSize(width: croppedImage.size.width * scale, height: croppedImage.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(outSize, true, 1.0)
            croppedImage.draw(in: CGRect(origin: .zero, size: outSize))

            let result = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return result?.jpegData(compressionQuality: 0.5)
        } else {
            // No bounding box — return scaled full frame with "missing" stamp
            let maxWidth: CGFloat = 480
            let scale = min(maxWidth / imgW, 1.0)
            let newSize = CGSize(width: imgW * scale, height: imgH * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))

            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resized?.jpegData(compressionQuality: 0.4)
        }
    }

    /// Convert a rect from UIKit coordinates to CGImage coordinates accounting for orientation
    private func convertRectToCGImageCoords(_ rect: CGRect, imageSize: CGSize, orientation: UIImage.Orientation) -> CGRect {
        let w = imageSize.width
        let h = imageSize.height
        switch orientation {
        case .right: // 90° CW — most common for rear camera
            return CGRect(
                x: rect.origin.y,
                y: w - rect.origin.x - rect.width,
                width: rect.height,
                height: rect.width
            )
        case .left: // 90° CCW
            return CGRect(
                x: h - rect.origin.y - rect.height,
                y: rect.origin.x,
                width: rect.height,
                height: rect.width
            )
        case .down: // 180°
            return CGRect(
                x: w - rect.origin.x - rect.width,
                y: h - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
        default: // .up or others — no transform needed
            return rect
        }
    }

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
