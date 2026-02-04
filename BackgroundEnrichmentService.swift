//
//  BackgroundEnrichmentService.swift
//  V4MinimalApp
//
//  Background Gemini calls to enrich detected objects with details
//

import Foundation
import UIKit

@MainActor
class BackgroundEnrichmentService: ObservableObject {

    @Published var enrichedCount: Int = 0
    @Published var queueCount: Int = 0

    private var queue: [(objectID: UUID, name: String, frame: UIImage, isCrop: Bool)] = []
    private var isProcessing = false
    private var processingTask: Task<Void, Never>?

    private let apiKey: String
    private let apiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"

    // Reference to vision service for updating detected objects
    weak var visionService: GeminiStreamingVisionService?

    init() {
        // Load API key (same sources as GeminiStreamingVisionService)
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: path),
           let key = config["GeminiAPIKey"] as? String, !key.isEmpty {
            self.apiKey = key
        } else if let key = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String, !key.isEmpty {
            self.apiKey = key
        } else if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            self.apiKey = key
        } else {
            self.apiKey = ""
        }
    }

    /// Enqueue a detected object for background enrichment. Returns immediately.
    func enqueue(_ object: DetectedObject) {
        guard DetectionSettings.shared.enableBackgroundEnrichment else { return }
        guard let frame = object.sourceFrame else { return }
        guard !apiKey.isEmpty else { return }

        queue.append((objectID: object.id, name: object.name, frame: frame, isCrop: false))
        queueCount = queue.count
        print("🔬 Enrichment queued: \(object.name) (queue: \(queue.count))")

        startProcessingIfNeeded()
    }

    /// Enqueue a pre-cropped image for YOLO→Gemini enrichment. Updates name + details.
    func enqueueCrop(_ object: DetectedObject, croppedImage: UIImage) {
        guard DetectionSettings.shared.enableBackgroundEnrichment else { return }
        guard !apiKey.isEmpty else { return }

        queue.append((objectID: object.id, name: object.name, frame: croppedImage, isCrop: true))
        queueCount = queue.count
        print("🔬 Crop enrichment queued: \(object.name) (queue: \(queue.count))")

        startProcessingIfNeeded()
    }

    private func startProcessingIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true

        processingTask = Task {
            while !queue.isEmpty {
                let item = queue.removeFirst()
                queueCount = queue.count
                await processItem(item)

                // 1-second delay between calls to avoid rate limiting
                if !queue.isEmpty {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            isProcessing = false
        }
    }

    private func processItem(_ item: (objectID: UUID, name: String, frame: UIImage, isCrop: Bool)) async {
        if item.isCrop {
            await processCropItem(item)
        } else {
            await processFullFrameItem(item)
        }
    }

    /// Crop-based enrichment: identify the specific item from a YOLO bbox crop, update name + details
    private func processCropItem(_ item: (objectID: UUID, name: String, frame: UIImage, isCrop: Bool)) async {
        guard let service = visionService else { return }

        let result = await service.enrichCrop(item.frame, yoloClassName: item.name)

        guard let result else {
            print("🔬 Crop enrichment returned nil for \(item.name)")
            return
        }

        if let idx = service.detectedObjects.firstIndex(where: { $0.id == item.objectID }) {
            service.detectedObjects[idx].name = result.name
            service.detectedObjects[idx].isEnriched = true
            if let brand = result.brand { service.detectedObjects[idx].brand = brand }
            if let color = result.color { service.detectedObjects[idx].color = color }
            if let size = result.size { service.detectedObjects[idx].size = size }
            if let category = result.category { service.detectedObjects[idx].categoryHint = category }
            enrichedCount += 1
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - service.analysisStartTime) * 1000)
            NetworkLogger.shared.info("TIMING: ENRICHED \(item.name) → \(result.name) at t=\(totalMs)ms", category: "Detection")
            print("🔬 Crop enriched: \(item.name) → \(result.name), brand=\(result.brand ?? "nil")")
        }
    }

    /// Full-frame enrichment: add details to an existing Gemini-detected object
    private func processFullFrameItem(_ item: (objectID: UUID, name: String, frame: UIImage, isCrop: Bool)) async {
        // Resize frame to small size for enrichment
        let resized = GeminiStreamingVisionService.resizeForAnalysis(item.frame)
        let quality = DetectionSettings.shared.jpegQuality
        guard let imageData = resized.jpegData(compressionQuality: quality) else { return }
        let base64Image = imageData.base64EncodedString()

        let prompt = """
        For the item "\(item.name)" visible in this image, provide details.
        Return JSON only: {"brand":"...","color":"...","size":"...","category":"...","estimatedValue":"..."}
        Use null for unknown fields. category should be one of: Electronics, Furniture, Appliance, Decor, Kitchen, Clothing, Books, Tools, Sports, Toys, Valuables, Other.
        JSON only, no markdown.
        """

        do {
            guard let url = URL(string: "\(apiEndpoint)?key=\(apiKey)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            let requestBody: [String: Any] = [
                "contents": [[
                    "parts": [
                        ["text": prompt],
                        ["inline_data": ["mime_type": "image/jpeg", "data": base64Image]]
                    ]
                ]],
                "generationConfig": [
                    "temperature": 0.2,
                    "maxOutputTokens": 200
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("🔬 Enrichment failed for \(item.name): HTTP error")
                return
            }

            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let candidate = geminiResponse.candidates.first,
                  let content = candidate.content.parts.first else { return }

            let responseText = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("🔬 Enrichment response for \(item.name): \(responseText.prefix(200))")

            // Parse JSON response
            let details = parseEnrichment(from: responseText)

            // Update the corresponding DetectedObject in vision service
            guard let service = visionService else { return }
            if let idx = service.detectedObjects.firstIndex(where: { $0.id == item.objectID }) {
                if let brand = details["brand"] as? String, brand != "null" {
                    service.detectedObjects[idx].brand = brand
                }
                if let color = details["color"] as? String, color != "null" {
                    service.detectedObjects[idx].color = color
                }
                if let size = details["size"] as? String, size != "null" {
                    service.detectedObjects[idx].size = size
                }
                if let category = details["category"] as? String, category != "null" {
                    service.detectedObjects[idx].categoryHint = category
                }
                enrichedCount += 1
                print("🔬 Enriched \(item.name): brand=\(details["brand"] ?? "nil"), color=\(details["color"] ?? "nil")")
            }
        } catch {
            print("🔬 Enrichment error for \(item.name): \(error.localizedDescription)")
        }
    }

    private func parseEnrichment(from text: String) -> [String: Any] {
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
              let endIdx = cleaned.lastIndex(of: "}") else { return [:] }

        let jsonStr = String(cleaned[startIdx...endIdx])
        guard let jsonData = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    func cancelAll() {
        processingTask?.cancel()
        processingTask = nil
        queue.removeAll()
        queueCount = 0
        isProcessing = false
    }
}
