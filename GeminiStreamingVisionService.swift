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
    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
    
    // Frame analysis throttling
    private var lastAnalysisTime: Date = .distantPast
    private let analysisInterval: TimeInterval = 2.0 // Analyze every 2 seconds
    private var isCurrentlyAnalyzing = false

    /// Last analyzed frame — stored so we can grab a thumbnail when the user saves
    private(set) var lastAnalyzedFrame: UIImage?
    
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
    
    /// Analyze a video frame — detects items with bounding boxes in one call
    func analyzeFrame(_ image: UIImage) async {
        // Skip if not analyzing or throttled
        guard isAnalyzing else { return }
        guard !isCurrentlyAnalyzing else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= analysisInterval else { return }

        lastAnalysisTime = now
        isCurrentlyAnalyzing = true

        // Store frame for thumbnail creation later (on save)
        lastAnalyzedFrame = image

        do {
            // Convert image to base64
            guard let imageData = image.jpegData(compressionQuality: 0.5) else {
                throw GeminiStreamingError.imageConversionFailed
            }

            let base64Image = imageData.base64EncodedString()

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

                let responseText = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("📦 Response: \(responseText.prefix(400))")

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
            // Filter out garbage names
            if name.contains("{") || name.contains("[") || name.contains("\"") { continue }

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
            .filter { !$0.isEmpty && !$0.contains("\"") }
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
    let name: String
    let timestamp: Date
    var color: String?
    var brand: String?
    var size: String?
    var categoryHint: String?
    var sourceFrame: UIImage?  // Reference to the camera frame (thumbnail created on save)
    var boundingBoxes: [BoundingBox]?

    /// Create JPEG thumbnail on demand (called when saving to inventory).
    /// If bounding box available: crops to the box with padding + draws green outline.
    /// Otherwise: returns scaled full frame.
    func createThumbnailData() -> Data? {
        guard let image = sourceFrame else { return nil }
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

            // Draw green bounding box outline on the cropped thumbnail
            if let ctx = UIGraphicsGetCurrentContext() {
                // Box position relative to crop
                let relX = (bx - cropRect.origin.x) * scale
                let relY = (by - cropRect.origin.y) * scale
                let relW = bw * scale
                let relH = bh * scale
                let boxRect = CGRect(x: relX, y: relY, width: relW, height: relH)

                ctx.setStrokeColor(UIColor.green.cgColor)
                ctx.setLineWidth(3.0)
                ctx.stroke(boxRect)

                // Label — large font
                let label = box.label
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.white
                ]
                let textSize = (label as NSString).size(withAttributes: attrs)
                let labelBg = CGRect(
                    x: relX,
                    y: max(relY - textSize.height - 6, 0),
                    width: textSize.width + 10,
                    height: textSize.height + 6
                )
                ctx.setFillColor(UIColor(red: 0, green: 0.5, blue: 0, alpha: 0.8).cgColor)
                ctx.fill(labelBg)
                (label as NSString).draw(
                    at: CGPoint(x: labelBg.origin.x + 5, y: labelBg.origin.y + 3),
                    withAttributes: attrs
                )
            }

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

            // Stamp "BOUNDING BOX MISSING" on the image
            if let ctx = UIGraphicsGetCurrentContext() {
                let msg = "BOUNDING BOX MISSING"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: UIColor.white
                ]
                let textSize = (msg as NSString).size(withAttributes: attrs)
                let bgRect = CGRect(
                    x: (newSize.width - textSize.width - 16) / 2,
                    y: newSize.height - textSize.height - 20,
                    width: textSize.width + 16,
                    height: textSize.height + 10
                )
                ctx.setFillColor(UIColor.red.withAlphaComponent(0.7).cgColor)
                ctx.fill(bgRect)
                (msg as NSString).draw(
                    at: CGPoint(x: bgRect.origin.x + 8, y: bgRect.origin.y + 5),
                    withAttributes: attrs
                )
            }

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
