//
//  PipelineRunner.swift
//  V4MinimalApp
//
//  Frame extraction from videos and pipeline execution for evaluation harness
//

import Foundation
import UIKit
import AVFoundation
import Vision

// MARK: - Extracted Frame

struct ExtractedFrame {
    let index: Int
    let image: UIImage
    let timestamp: Double
}

// MARK: - Pipeline Runner

@MainActor
class PipelineRunner: ObservableObject {

    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    @Published var isRunning = false

    private var cancelled = false

    // MARK: - Frame Extraction

    /// Extract frames from a video at the given interval
    nonisolated static func extractFrames(
        from videoURL: URL,
        intervalSeconds: Double = 2.0,
        maxSize: CGSize = CGSize(width: 1280, height: 720)
    ) async throws -> [ExtractedFrame] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        var frames: [ExtractedFrame] = []
        var time: Double = 0
        var index = 0

        while time < durationSeconds {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: cmTime)
                let image = UIImage(cgImage: cgImage)
                frames.append(ExtractedFrame(index: index, image: image, timestamp: time))
            } catch {
                print("Frame extraction failed at \(time)s: \(error)")
            }
            time += intervalSeconds
            index += 1
        }

        return frames
    }

    // MARK: - Cancel

    func cancel() {
        cancelled = true
    }

    // MARK: - Run Pipeline

    func runPipeline(
        _ pipeline: DetectionPipeline,
        videoURL: URL,
        sessionId: UUID,
        intervalSeconds: Double,
        groundTruth: GroundTruth?
    ) async -> PipelineRunResult? {
        isRunning = true
        cancelled = false
        progress = 0
        statusMessage = "Extracting frames..."

        let startTime = CFAbsoluteTimeGetCurrent()

        // Extract frames
        guard let frames = try? await Self.extractFrames(
            from: videoURL,
            intervalSeconds: intervalSeconds
        ), !frames.isEmpty else {
            statusMessage = "Failed to extract frames"
            isRunning = false
            return nil
        }

        guard !cancelled else {
            isRunning = false
            return nil
        }

        statusMessage = "Running \(pipeline.rawValue) on \(frames.count) frames..."

        var allDetections: [EvalDetectedItem] = []
        var apiCallCount = 0

        switch pipeline {
        case .yoloOnly:
            allDetections = await runYOLO(frames: frames)

        case .yoloPlusOCR:
            allDetections = await runYOLOPlusOCR(frames: frames)

        case .geminiStreaming:
            let (items, calls) = await runGeminiStreaming(frames: frames)
            allDetections = items
            apiCallCount = calls

        case .geminiMultiItem:
            let (items, calls) = await runGeminiMultiItem(frames: frames)
            allDetections = items
            apiCallCount = calls
        }

        guard !cancelled else {
            isRunning = false
            return nil
        }

        // Dedup across frames
        let dedupedItems = dedup(allDetections)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Compute scores if ground truth exists
        let scores: SessionScores?
        if let gt = groundTruth, !gt.items.isEmpty {
            scores = Self.computeScores(groundTruth: gt, detected: dedupedItems, pipeline: pipeline)
        } else {
            scores = nil
        }

        let result = PipelineRunResult(
            pipeline: pipeline,
            sessionId: sessionId,
            detectedItems: dedupedItems,
            durationSeconds: elapsed,
            framesProcessed: frames.count,
            apiCallCount: apiCallCount,
            scores: scores
        )

        statusMessage = "Done: \(dedupedItems.count) items in \(String(format: "%.1f", elapsed))s"
        progress = 1.0
        isRunning = false
        return result
    }

    // MARK: - YOLO Only

    private func runYOLO(frames: [ExtractedFrame]) async -> [EvalDetectedItem] {
        let detector = YOLODetector()

        // Wait for model to load
        var attempts = 0
        while !detector.isReady && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            attempts += 1
        }
        guard detector.isReady else {
            statusMessage = "YOLO model failed to load"
            return []
        }

        var items: [EvalDetectedItem] = []

        for (i, frame) in frames.enumerated() {
            guard !cancelled else { break }
            progress = Double(i) / Double(frames.count)
            statusMessage = "YOLO: frame \(i + 1)/\(frames.count)"

            detector.detect(in: frame.image)
            // Wait briefly for async detection to complete
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

            for detection in detector.detections {
                let item = EvalDetectedItem(
                    name: detection.className,
                    confidence: Double(detection.confidence),
                    boundingBox: CodableBoundingBox(cgRect: detection.boundingBox),
                    frameIndex: frame.index
                )
                items.append(item)
            }
        }

        return items
    }

    // MARK: - YOLO + OCR

    private func runYOLOPlusOCR(frames: [ExtractedFrame]) async -> [EvalDetectedItem] {
        let detector = YOLODetector()

        var attempts = 0
        while !detector.isReady && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        guard detector.isReady else {
            statusMessage = "YOLO model failed to load"
            return []
        }

        var items: [EvalDetectedItem] = []

        for (i, frame) in frames.enumerated() {
            guard !cancelled else { break }
            progress = Double(i) / Double(frames.count)
            statusMessage = "YOLO+OCR: frame \(i + 1)/\(frames.count)"

            detector.detect(in: frame.image)
            try? await Task.sleep(nanoseconds: 300_000_000)

            for detection in detector.detections {
                var ocrLines: [String]? = nil
                var enrichedName = detection.className

                // Crop bounding box region and run OCR
                let box = detection.boundingBox
                if box.width > 0 && box.height > 0, let cgImage = frame.image.cgImage {
                    let imgW = CGFloat(cgImage.width)
                    let imgH = CGFloat(cgImage.height)
                    let cropRect = CGRect(
                        x: max(box.origin.x * imgW, 0),
                        y: max(box.origin.y * imgH, 0),
                        width: min(box.width * imgW, imgW),
                        height: min(box.height * imgH, imgH)
                    )

                    if let cropped = cgImage.cropping(to: cropRect) {
                        let croppedImage = UIImage(cgImage: cropped)
                        let lines = await withCheckedContinuation { continuation in
                            DispatchQueue.global(qos: .userInitiated).async {
                                let result = PhotoIdentificationResult.recognizeText(in: croppedImage)
                                continuation.resume(returning: result)
                            }
                        }
                        if !lines.isEmpty {
                            ocrLines = lines
                            // Use OCR text to improve generic COCO class name
                            let joined = lines.prefix(3).joined(separator: " ")
                            if !joined.isEmpty {
                                enrichedName = "\(detection.className) (\(joined))"
                            }
                        }
                    }
                }

                let item = EvalDetectedItem(
                    name: enrichedName,
                    confidence: Double(detection.confidence),
                    boundingBox: CodableBoundingBox(cgRect: detection.boundingBox),
                    ocrText: ocrLines,
                    frameIndex: frame.index
                )
                items.append(item)
            }
        }

        return items
    }

    // MARK: - Gemini Streaming

    private func runGeminiStreaming(frames: [ExtractedFrame]) async -> ([EvalDetectedItem], Int) {
        var items: [EvalDetectedItem] = []
        var apiCalls = 0

        let apiKey = GeminiVisionService.shared.apiKeyValue
        guard !apiKey.isEmpty else {
            statusMessage = "No Gemini API key configured"
            return ([], 0)
        }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"

        let prompt = """
        List physical items suitable for home inventory with bounding boxes.
        Be specific with brand/type when visible (e.g., "DirecTV remote", "Samsung TV").

        INCLUDE: furniture, electronics, appliances, decor, tools, clothing, books, kitchenware, valuables.
        EXCLUDE: shadows, light, reflections, textures, floors, walls, ceilings.

        Return JSON array only: [{"name":"Item Name","box":[ymin,xmin,ymax,xmax]}]
        Coordinates 0-1000. 2-4 words per item name. JSON only, no markdown.
        """

        for (i, frame) in frames.enumerated() {
            guard !cancelled else { break }
            progress = Double(i) / Double(frames.count)
            statusMessage = "Gemini Streaming: frame \(i + 1)/\(frames.count)"

            // Resize frame
            let resized = resizeForAPI(frame.image, maxWidth: 800)
            guard let imageData = resized.jpegData(compressionQuality: 0.7) else { continue }
            let base64Image = imageData.base64EncodedString()

            // Build request (same as GeminiStreamingVisionService.createRequest)
            guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 10

            let requestBody: [String: Any] = [
                "contents": [[
                    "parts": [
                        ["text": prompt],
                        ["inline_data": ["mime_type": "image/jpeg", "data": base64Image]]
                    ]
                ]],
                "generationConfig": [
                    "temperature": 0.2,
                    "topK": 20,
                    "topP": 0.8,
                    "maxOutputTokens": 400
                ]
            ]

            guard let body = try? JSONSerialization.data(withJSONObject: requestBody) else { continue }
            request.httpBody = body

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                apiCalls += 1

                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }

                // Parse response — same structure as GeminiStreamingVisionService
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {

                    let detections = GeminiStreamingVisionService.parseDetectionsWithBoxes(
                        from: text,
                        timestamp: Date()
                    )

                    for det in detections {
                        var box: CodableBoundingBox? = nil
                        if let bb = det.boundingBoxes?.first {
                            box = CodableBoundingBox(
                                yMin: Double(bb.yMin),
                                xMin: Double(bb.xMin),
                                yMax: Double(bb.yMax),
                                xMax: Double(bb.xMax)
                            )
                        }

                        items.append(EvalDetectedItem(
                            name: det.name,
                            brand: det.brand,
                            color: det.color,
                            size: det.size,
                            category: det.categoryHint,
                            boundingBox: box,
                            frameIndex: frame.index
                        ))
                    }
                }
            } catch {
                print("Gemini streaming request failed: \(error)")
            }

            // Rate limit: 1s between API calls
            if i < frames.count - 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        return (items, apiCalls)
    }

    // MARK: - Gemini Multi-Item

    private func runGeminiMultiItem(frames: [ExtractedFrame]) async -> ([EvalDetectedItem], Int) {
        var items: [EvalDetectedItem] = []
        var apiCalls = 0

        let service = GeminiVisionService.shared

        for (i, frame) in frames.enumerated() {
            guard !cancelled else { break }
            progress = Double(i) / Double(frames.count)
            statusMessage = "Gemini Multi-Item: frame \(i + 1)/\(frames.count)"

            let results = await service.identifyAllItems(frame.image)
            apiCalls += 1

            for result in results {
                var box: CodableBoundingBox? = nil
                if let bb = result.boundingBox {
                    box = CodableBoundingBox(
                        yMin: Double(bb.yMin),
                        xMin: Double(bb.xMin),
                        yMax: Double(bb.yMax),
                        xMax: Double(bb.xMax)
                    )
                }

                items.append(EvalDetectedItem(
                    name: result.name,
                    brand: result.brand,
                    color: result.color,
                    size: result.size,
                    category: result.category,
                    boundingBox: box,
                    ocrText: result.ocrText,
                    frameIndex: frame.index
                ))
            }

            // Rate limit: 1s between API calls
            if i < frames.count - 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        return (items, apiCalls)
    }

    // MARK: - Deduplication

    private func dedup(_ items: [EvalDetectedItem]) -> [EvalDetectedItem] {
        var seen: [String: EvalDetectedItem] = [:]

        for item in items {
            let key = Self.normalizedName(item.name)
            if let existing = seen[key] {
                // Keep the one with the longer/more specific name
                if item.name.count > existing.name.count {
                    seen[key] = item
                }
            } else {
                seen[key] = item
            }
        }

        return Array(seen.values).sorted { $0.name < $1.name }
    }

    static func normalizedName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Scoring

    static func computeScores(
        groundTruth: GroundTruth,
        detected: [EvalDetectedItem],
        pipeline: DetectionPipeline
    ) -> SessionScores {
        let detectedNames = detected.map { normalizedName($0.name) }
        var matched = 0
        var details: [MatchDetail] = []
        var usedDetectedIndices = Set<Int>()

        for gtItem in groundTruth.items {
            let gtNorm = normalizedName(gtItem.name)
            var bestMatch: (index: Int, type: MatchType, name: String)? = nil

            for (di, dn) in detectedNames.enumerated() {
                guard !usedDetectedIndices.contains(di) else { continue }

                if dn == gtNorm {
                    bestMatch = (di, .exact, detected[di].name)
                    break // Exact match is best
                } else if dn.contains(gtNorm) || gtNorm.contains(dn) {
                    if bestMatch == nil || bestMatch!.type != .exact {
                        bestMatch = (di, .substring, detected[di].name)
                    }
                } else if fuzzyMatch(gtNorm, dn) {
                    if bestMatch == nil {
                        bestMatch = (di, .fuzzy, detected[di].name)
                    }
                }
            }

            if let match = bestMatch {
                usedDetectedIndices.insert(match.index)
                matched += 1
                details.append(MatchDetail(
                    groundTruthName: gtItem.name,
                    detectedName: match.name,
                    matchType: match.type,
                    pipeline: pipeline
                ))
            } else {
                details.append(MatchDetail(
                    groundTruthName: gtItem.name,
                    detectedName: nil,
                    matchType: .none,
                    pipeline: pipeline
                ))
            }
        }

        let totalGT = groundTruth.items.count
        let totalDet = detected.count
        let recall = totalGT > 0 ? Double(matched) / Double(totalGT) : 0
        let precision = totalDet > 0 ? Double(matched) / Double(totalDet) : 0

        // Name quality heuristic: 1 (generic) → 5 (brand + specific product)
        let avgQuality: Double
        if detected.isEmpty {
            avgQuality = 0
        } else {
            let total = detected.reduce(0.0) { sum, item in
                sum + nameQualityScore(item)
            }
            avgQuality = total / Double(detected.count)
        }

        return SessionScores(
            matchedCount: matched,
            totalGroundTruth: totalGT,
            totalDetected: totalDet,
            recall: recall,
            precision: precision,
            avgNameQuality: avgQuality,
            matchDetails: details
        )
    }

    /// Fuzzy match: word overlap > 50%
    private static func fuzzyMatch(_ a: String, _ b: String) -> Bool {
        let wordsA = Set(a.split(separator: " ").map(String.init))
        let wordsB = Set(b.split(separator: " ").map(String.init))
        guard !wordsA.isEmpty && !wordsB.isEmpty else { return false }
        let overlap = wordsA.intersection(wordsB).count
        let minSize = min(wordsA.count, wordsB.count)
        return Double(overlap) / Double(minSize) > 0.5
    }

    /// Name quality: 1 = generic single word, 5 = brand + specific product name
    private static func nameQualityScore(_ item: EvalDetectedItem) -> Double {
        var score = 1.0
        let words = item.name.split(separator: " ")

        // More words = more specific
        if words.count >= 2 { score += 1.0 }
        if words.count >= 3 { score += 0.5 }

        // Has brand
        if item.brand != nil && item.brand?.isEmpty == false { score += 1.0 }

        // Has category
        if item.category != nil && item.category?.isEmpty == false { score += 0.5 }

        // Has color or size
        if item.color != nil || item.size != nil { score += 0.5 }

        return min(score, 5.0)
    }

    // MARK: - Helpers

    private func resizeForAPI(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        guard image.size.width > maxWidth else { return image }
        let scale = maxWidth / image.size.width
        let newSize = CGSize(width: maxWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
