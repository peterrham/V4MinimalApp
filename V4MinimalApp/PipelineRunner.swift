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
        startTime: Double = 0,
        endTime: Double? = nil,
        maxSize: CGSize = CGSize(width: 1280, height: 720)
    ) async throws -> [ExtractedFrame] {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else { return [] }

        let effectiveStart = max(0, startTime)
        let effectiveEnd = min(endTime ?? durationSeconds, durationSeconds)
        guard effectiveStart < effectiveEnd else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        var frames: [ExtractedFrame] = []
        var time = effectiveStart
        var index = 0

        while time < effectiveEnd {
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
        startTime: Double = 0,
        endTime: Double? = nil,
        groundTruth: GroundTruth?
    ) async -> PipelineRunResult? {
        isRunning = true
        cancelled = false
        progress = 0

        let wallStart = CFAbsoluteTimeGetCurrent()

        // Gemini Video pipeline skips frame extraction entirely
        if pipeline == .geminiVideo {
            statusMessage = "Preparing video for Gemini..."
            let (items, calls) = await runGeminiVideo(videoURL: videoURL, startTime: startTime, endTime: endTime)

            guard !cancelled else { isRunning = false; return nil }

            let dedupedItems = dedup(items)
            let elapsed = CFAbsoluteTimeGetCurrent() - wallStart

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
                framesProcessed: 0,
                apiCallCount: calls,
                scores: scores,
                videoStartTime: startTime,
                videoEndTime: endTime
            )

            statusMessage = "Done: \(dedupedItems.count) items in \(String(format: "%.1f", elapsed))s"
            progress = 1.0
            isRunning = false
            return result
        }

        statusMessage = "Extracting frames..."

        // Extract frames
        guard let frames = try? await Self.extractFrames(
            from: videoURL,
            intervalSeconds: intervalSeconds,
            startTime: startTime,
            endTime: endTime
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

        case .geminiVideo:
            break // handled above
        }

        guard !cancelled else {
            isRunning = false
            return nil
        }

        // Dedup across frames
        let dedupedItems = dedup(allDetections)

        let elapsed = CFAbsoluteTimeGetCurrent() - wallStart

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
            scores: scores,
            videoStartTime: startTime,
            videoEndTime: endTime
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

    // MARK: - Video Trimming

    /// Trim a video to the given time range using AVAssetExportSession.
    /// Returns the URL of the trimmed file (caller must clean up), or nil on failure.
    nonisolated private static func trimVideo(
        at videoURL: URL,
        startTime: Double,
        endTime: Double?
    ) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else {
            print("🎬 [TRIM] Failed to load video duration")
            return nil
        }
        let durationSeconds = CMTimeGetSeconds(duration)
        let effectiveStart = max(0, startTime)
        let effectiveEnd = min(endTime ?? durationSeconds, durationSeconds)

        // Skip trim if it covers the whole video (within 0.5s tolerance)
        if effectiveStart < 0.5 && effectiveEnd >= durationSeconds - 0.5 {
            print("🎬 [TRIM] Range \(effectiveStart)–\(effectiveEnd) covers full video (\(durationSeconds)s), skipping trim")
            return nil
        }

        print("🎬 [TRIM] Trimming \(videoURL.lastPathComponent): \(effectiveStart)s–\(effectiveEnd)s of \(String(format: "%.1f", durationSeconds))s")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            print("🎬 [TRIM] Failed to create AVAssetExportSession")
            return nil
        }

        let trimmedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_\(UUID().uuidString)")
            .appendingPathExtension(videoURL.pathExtension)

        exportSession.outputURL = trimmedURL
        exportSession.outputFileType = videoURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: effectiveStart, preferredTimescale: 600),
            end: CMTime(seconds: effectiveEnd, preferredTimescale: 600)
        )

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            let trimmedSize = (try? FileManager.default.attributesOfItem(atPath: trimmedURL.path)[.size] as? Int) ?? 0
            print("🎬 [TRIM] Success: \(trimmedSize / 1024)KB trimmed file at \(trimmedURL.lastPathComponent)")
            return trimmedURL
        case .failed:
            print("🎬 [TRIM] Export failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            return nil
        case .cancelled:
            print("🎬 [TRIM] Export cancelled")
            return nil
        default:
            print("🎬 [TRIM] Unexpected export status: \(exportSession.status.rawValue)")
            return nil
        }
    }

    // MARK: - Gemini Video (File API)

    private func runGeminiVideo(videoURL: URL, startTime: Double = 0, endTime: Double? = nil) async -> ([EvalDetectedItem], Int) {
        let apiKey = GeminiVisionService.shared.apiKeyValue
        guard !apiKey.isEmpty else {
            statusMessage = "No Gemini API key configured"
            return ([], 0)
        }

        let uploadEndpoint = "https://generativelanguage.googleapis.com/upload/v1beta/files?key=\(apiKey)"
        let generateEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=\(apiKey)"

        // Step 0: Trim video to range if needed
        var effectiveURL = videoURL
        var trimmedTempURL: URL? = nil

        if startTime > 0 || endTime != nil {
            statusMessage = "Trimming video to \(String(format: "%.1f", startTime))s–\(endTime.map { String(format: "%.1f", $0) } ?? "end")..."
            progress = 0.05

            if let trimmed = await Self.trimVideo(at: videoURL, startTime: startTime, endTime: endTime) {
                effectiveURL = trimmed
                trimmedTempURL = trimmed
                print("🎬 [GEMINI-VIDEO] Using trimmed video: \(trimmed.lastPathComponent)")
            } else {
                print("🎬 [GEMINI-VIDEO] Trim returned nil (full video or error), uploading original")
            }
        }

        // Step 1: Upload video via File API
        statusMessage = "Reading video file..."
        progress = 0.1

        guard let videoData = try? Data(contentsOf: effectiveURL) else {
            statusMessage = "Failed to read video file"
            print("🎬 [GEMINI-VIDEO] ERROR: Cannot read video at \(effectiveURL.path)")
            cleanupTrimmed(trimmedTempURL)
            return ([], 0)
        }

        let sizeMB = Double(videoData.count) / 1_048_576.0
        print("🎬 [GEMINI-VIDEO] Video size: \(String(format: "%.1f", sizeMB))MB, path: \(effectiveURL.lastPathComponent)")

        let mimeType: String
        switch effectiveURL.pathExtension.lowercased() {
        case "mp4": mimeType = "video/mp4"
        case "mov": mimeType = "video/quicktime"
        case "avi": mimeType = "video/x-msvideo"
        default: mimeType = "video/mp4"
        }

        // Resumable upload: initiate
        print("🎬 [GEMINI-VIDEO] Step 1: Initiating resumable upload (\(mimeType), \(videoData.count) bytes)...")
        statusMessage = "Initiating upload (\(String(format: "%.1f", sizeMB))MB)..."

        guard let initURL = URL(string: uploadEndpoint) else {
            statusMessage = "Invalid upload URL"
            cleanupTrimmed(trimmedTempURL)
            return ([], 0)
        }

        var initRequest = URLRequest(url: initURL)
        initRequest.httpMethod = "POST"
        initRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        initRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        initRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        initRequest.setValue("\(videoData.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        initRequest.timeoutInterval = 30

        let metadata: [String: Any] = ["file": ["display_name": effectiveURL.lastPathComponent]]
        initRequest.httpBody = try? JSONSerialization.data(withJSONObject: metadata)

        let uploadURL: String
        do {
            let (initData, initResponse) = try await URLSession.shared.data(for: initRequest)
            guard let httpResp = initResponse as? HTTPURLResponse else {
                print("🎬 [GEMINI-VIDEO] ERROR: Upload init — no HTTP response")
                statusMessage = "Upload initiation failed (no response)"
                cleanupTrimmed(trimmedTempURL)
                return ([], 0)
            }
            print("🎬 [GEMINI-VIDEO] Upload init response: HTTP \(httpResp.statusCode)")
            guard httpResp.statusCode == 200,
                  let resumeURL = httpResp.value(forHTTPHeaderField: "X-Goog-Upload-URL") else {
                let body = String(data: initData, encoding: .utf8) ?? ""
                print("🎬 [GEMINI-VIDEO] ERROR: Upload init failed HTTP \(httpResp.statusCode): \(body.prefix(300))")
                statusMessage = "Upload initiation failed (HTTP \(httpResp.statusCode))"
                cleanupTrimmed(trimmedTempURL)
                return ([], 0)
            }
            uploadURL = resumeURL
            print("🎬 [GEMINI-VIDEO] Got resumable upload URL")
        } catch {
            print("🎬 [GEMINI-VIDEO] ERROR: Upload init exception: \(error)")
            statusMessage = "Upload initiation error: \(error.localizedDescription)"
            cleanupTrimmed(trimmedTempURL)
            return ([], 0)
        }

        guard !cancelled else { cleanupTrimmed(trimmedTempURL); return ([], 0) }

        // Resumable upload: send bytes
        statusMessage = "Uploading \(String(format: "%.1f", sizeMB))MB..."
        progress = 0.2
        print("🎬 [GEMINI-VIDEO] Step 2: Uploading \(videoData.count) bytes...")

        guard let resumeURL = URL(string: uploadURL) else { cleanupTrimmed(trimmedTempURL); return ([], 0) }
        var uploadRequest = URLRequest(url: resumeURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("\(videoData.count)", forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.httpBody = videoData
        uploadRequest.timeoutInterval = 300

        let fileURI: String
        do {
            let uploadStart = CFAbsoluteTimeGetCurrent()
            let (uploadData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
            let uploadDuration = CFAbsoluteTimeGetCurrent() - uploadStart
            guard let httpResp = uploadResponse as? HTTPURLResponse else {
                print("🎬 [GEMINI-VIDEO] ERROR: Upload — no HTTP response")
                statusMessage = "Upload failed (no response)"
                cleanupTrimmed(trimmedTempURL)
                return ([], 0)
            }
            print("🎬 [GEMINI-VIDEO] Upload response: HTTP \(httpResp.statusCode) in \(String(format: "%.1f", uploadDuration))s")
            guard httpResp.statusCode == 200 else {
                let body = String(data: uploadData, encoding: .utf8) ?? ""
                print("🎬 [GEMINI-VIDEO] ERROR: Upload failed HTTP \(httpResp.statusCode): \(body.prefix(300))")
                statusMessage = "Upload failed (HTTP \(httpResp.statusCode))"
                cleanupTrimmed(trimmedTempURL)
                return ([], 0)
            }
            guard let json = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
                  let file = json["file"] as? [String: Any],
                  let uri = file["uri"] as? String else {
                let body = String(data: uploadData, encoding: .utf8) ?? ""
                print("🎬 [GEMINI-VIDEO] ERROR: Upload response parse failed: \(body.prefix(500))")
                statusMessage = "Failed to parse upload response"
                cleanupTrimmed(trimmedTempURL)
                return ([], 0)
            }
            fileURI = uri
            let state = file["state"] as? String ?? "unknown"
            print("🎬 [GEMINI-VIDEO] Upload complete: URI=\(fileURI), state=\(state)")
        } catch {
            print("🎬 [GEMINI-VIDEO] ERROR: Upload exception: \(error)")
            statusMessage = "Upload error: \(error.localizedDescription)"
            cleanupTrimmed(trimmedTempURL)
            return ([], 0)
        }

        // Clean up trimmed file now that it's uploaded
        cleanupTrimmed(trimmedTempURL)

        guard !cancelled else { return ([], 0) }

        // Step 2: Poll until file is ACTIVE
        statusMessage = "Waiting for server to process video..."
        progress = 0.4
        print("🎬 [GEMINI-VIDEO] Step 3: Polling for ACTIVE state...")

        let fileName = fileURI.components(separatedBy: "/").last ?? ""
        let fileInfoEndpoint = "https://generativelanguage.googleapis.com/v1beta/files/\(fileName)?key=\(apiKey)"

        var fileActive = false
        for attempt in 0..<60 {
            guard !cancelled else { return ([], 0) }

            guard let infoURL = URL(string: fileInfoEndpoint) else { break }
            var infoReq = URLRequest(url: infoURL)
            infoReq.httpMethod = "GET"
            infoReq.timeoutInterval = 15

            do {
                let (data, response) = try await URLSession.shared.data(for: infoReq)
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let state = json["state"] as? String {
                    print("🎬 [GEMINI-VIDEO] Poll #\(attempt + 1): state=\(state), HTTP \(httpStatus)")
                    if state == "ACTIVE" {
                        fileActive = true
                        break
                    } else if state == "FAILED" {
                        let error = json["error"] as? [String: Any]
                        let errorMsg = error?["message"] as? String ?? "unknown reason"
                        print("🎬 [GEMINI-VIDEO] ERROR: Server processing FAILED: \(errorMsg)")
                        statusMessage = "Video processing failed: \(errorMsg)"
                        return ([], 0)
                    }
                    statusMessage = "Processing video (poll \(attempt + 1), state: \(state))..."
                } else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    print("🎬 [GEMINI-VIDEO] Poll #\(attempt + 1): HTTP \(httpStatus), unparseable: \(body.prefix(200))")
                    statusMessage = "Processing video (poll \(attempt + 1), HTTP \(httpStatus))..."
                }
            } catch {
                print("🎬 [GEMINI-VIDEO] Poll #\(attempt + 1) error: \(error)")
                statusMessage = "Processing video (poll \(attempt + 1), error)..."
            }

            progress = 0.4 + Double(attempt) * 0.005
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s between polls
        }

        guard fileActive else {
            print("🎬 [GEMINI-VIDEO] ERROR: Timed out after 60 polls")
            statusMessage = "Timed out waiting for video processing"
            return ([], 0)
        }

        // Step 3: generateContent referencing the video file
        statusMessage = "Analyzing video with Gemini..."
        progress = 0.7
        print("🎬 [GEMINI-VIDEO] Step 4: Calling generateContent...")

        let prompt = """
        List ALL individual physical items visible in this video for home inventory.
        Be specific with brand/type when visible (e.g., "DirecTV remote", "Samsung TV").

        INCLUDE: furniture, electronics, appliances, decor, tools, clothing, books, kitchenware, valuables.
        EXCLUDE: shadows, light, reflections, textures, floors, walls, ceilings, people.

        Return JSON array only:
        [{"name":"Item Name","brand":"...","color":"...","category":"...","estimatedValue":...}]
        Use null for unknown fields. Each item must have a UNIQUE descriptive name.
        2-5 words per item name. JSON only, no markdown fences.
        """

        guard let genURL = URL(string: generateEndpoint) else { return ([], 0) }
        var genRequest = URLRequest(url: genURL)
        genRequest.httpMethod = "POST"
        genRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        genRequest.timeoutInterval = 120

        let genBody: [String: Any] = [
            "contents": [[
                "parts": [
                    ["file_data": ["mime_type": mimeType, "file_uri": fileURI]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.3,
                "topK": 32,
                "topP": 1.0,
                "maxOutputTokens": 8192
            ]
        ]

        guard let genBodyData = try? JSONSerialization.data(withJSONObject: genBody) else { return ([], 0) }
        genRequest.httpBody = genBodyData

        var items: [EvalDetectedItem] = []
        do {
            let genStart = CFAbsoluteTimeGetCurrent()
            let (data, response) = try await URLSession.shared.data(for: genRequest)
            let genDuration = CFAbsoluteTimeGetCurrent() - genStart
            guard let httpResp = response as? HTTPURLResponse else {
                print("🎬 [GEMINI-VIDEO] ERROR: generateContent — no HTTP response")
                return ([], 1)
            }
            print("🎬 [GEMINI-VIDEO] generateContent: HTTP \(httpResp.statusCode) in \(String(format: "%.1f", genDuration))s, \(data.count) bytes")

            guard httpResp.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
                print("🎬 [GEMINI-VIDEO] ERROR: generateContent HTTP \(httpResp.statusCode): \(errorBody.prefix(500))")
                statusMessage = "Gemini API error (HTTP \(httpResp.statusCode))"
                return ([], 1)
            }

            progress = 0.9

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {

                print("🎬 [GEMINI-VIDEO] Response text (\(text.count) chars): \(text.prefix(500))")

                let results = PhotoIdentificationResult.parseMultiple(from: text)
                print("🎬 [GEMINI-VIDEO] parseMultiple returned \(results.count) items")
                for result in results {
                    items.append(EvalDetectedItem(
                        name: result.name,
                        brand: result.brand,
                        color: result.color,
                        size: result.size,
                        category: result.category,
                        frameIndex: 0
                    ))
                }

                if items.isEmpty {
                    print("🎬 [GEMINI-VIDEO] parseMultiple empty, trying streaming parser...")
                    let detections = GeminiStreamingVisionService.parseDetectionsWithBoxes(
                        from: text, timestamp: Date()
                    )
                    print("🎬 [GEMINI-VIDEO] parseDetectionsWithBoxes returned \(detections.count) items")
                    for det in detections {
                        items.append(EvalDetectedItem(
                            name: det.name,
                            brand: det.brand,
                            color: det.color,
                            size: det.size,
                            category: det.categoryHint,
                            frameIndex: 0
                        ))
                    }
                }
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("🎬 [GEMINI-VIDEO] WARNING: Could not parse candidates from response: \(body.prefix(500))")
            }
        } catch {
            print("🎬 [GEMINI-VIDEO] ERROR: generateContent exception: \(error)")
            statusMessage = "Gemini request error: \(error.localizedDescription)"
            return ([], 1)
        }

        // Step 4: Clean up uploaded file (best effort)
        print("🎬 [GEMINI-VIDEO] Step 5: Deleting uploaded file \(fileName)...")
        let deleteEndpoint = "https://generativelanguage.googleapis.com/v1beta/files/\(fileName)?key=\(apiKey)"
        if let deleteURL = URL(string: deleteEndpoint) {
            var deleteReq = URLRequest(url: deleteURL)
            deleteReq.httpMethod = "DELETE"
            if let (_, delResp) = try? await URLSession.shared.data(for: deleteReq) {
                let delStatus = (delResp as? HTTPURLResponse)?.statusCode ?? 0
                print("🎬 [GEMINI-VIDEO] Delete file: HTTP \(delStatus)")
            }
        }

        print("🎬 [GEMINI-VIDEO] Done: \(items.count) items detected")
        return (items, 1)
    }

    private func cleanupTrimmed(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
        print("🎬 [TRIM] Cleaned up temp file: \(url.lastPathComponent)")
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
