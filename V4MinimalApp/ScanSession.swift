//
//  ScanSession.swift
//  V4MinimalApp
//
//  Data models for the scan session evaluation harness
//

import Foundation

// MARK: - Detection Pipeline

enum DetectionPipeline: String, Codable, CaseIterable, Identifiable {
    case yoloOnly = "YOLO Only"
    case yoloPlusOCR = "YOLO + OCR"
    case geminiStreaming = "Gemini Streaming"
    case geminiMultiItem = "Gemini Multi-Item"
    case geminiVideo = "Gemini Video"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .yoloOnly: return "On-device YOLO detection (80 COCO classes)"
        case .yoloPlusOCR: return "YOLO detection + Vision OCR enrichment"
        case .geminiStreaming: return "Gemini API with streaming detection prompt"
        case .geminiMultiItem: return "Gemini API with full multi-item analysis + OCR"
        case .geminiVideo: return "Upload entire video to Gemini File API (single call)"
        }
    }

    var isOnDevice: Bool {
        switch self {
        case .yoloOnly, .yoloPlusOCR: return true
        case .geminiStreaming, .geminiMultiItem, .geminiVideo: return false
        }
    }
}

// MARK: - Bounding Box (Codable)

struct CodableBoundingBox: Codable, Equatable {
    let yMin: Double
    let xMin: Double
    let yMax: Double
    let xMax: Double

    init(yMin: Double, xMin: Double, yMax: Double, xMax: Double) {
        self.yMin = yMin
        self.xMin = xMin
        self.yMax = yMax
        self.xMax = xMax
    }

    init(cgRect: CGRect) {
        // CGRect is top-left origin, normalized 0-1
        self.xMin = Double(cgRect.origin.x)
        self.yMin = Double(cgRect.origin.y)
        self.xMax = Double(cgRect.origin.x + cgRect.width)
        self.yMax = Double(cgRect.origin.y + cgRect.height)
    }
}

// MARK: - Evaluation Detected Item

struct EvalDetectedItem: Codable, Identifiable {
    let id: UUID
    let name: String
    var brand: String?
    var color: String?
    var size: String?
    var category: String?
    var confidence: Double?
    var boundingBox: CodableBoundingBox?
    var ocrText: [String]?
    var frameIndex: Int

    init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        color: String? = nil,
        size: String? = nil,
        category: String? = nil,
        confidence: Double? = nil,
        boundingBox: CodableBoundingBox? = nil,
        ocrText: [String]? = nil,
        frameIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.color = color
        self.size = size
        self.category = category
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.ocrText = ocrText
        self.frameIndex = frameIndex
    }
}

// MARK: - Match Types

enum MatchType: String, Codable {
    case exact
    case substring
    case fuzzy
    case none
}

struct MatchDetail: Codable, Identifiable {
    let id: UUID
    let groundTruthName: String
    let detectedName: String?
    let matchType: MatchType
    let pipeline: DetectionPipeline

    init(
        id: UUID = UUID(),
        groundTruthName: String,
        detectedName: String? = nil,
        matchType: MatchType,
        pipeline: DetectionPipeline
    ) {
        self.id = id
        self.groundTruthName = groundTruthName
        self.detectedName = detectedName
        self.matchType = matchType
        self.pipeline = pipeline
    }
}

// MARK: - Session Scores

struct SessionScores: Codable {
    let matchedCount: Int
    let totalGroundTruth: Int
    let totalDetected: Int
    let recall: Double
    let precision: Double
    let avgNameQuality: Double
    let matchDetails: [MatchDetail]

    var recallPercent: String { String(format: "%.0f%%", recall * 100) }
    var precisionPercent: String { String(format: "%.0f%%", precision * 100) }
}

// MARK: - Pipeline Run Result

struct PipelineRunResult: Codable, Identifiable {
    let id: UUID
    let pipeline: DetectionPipeline
    let sessionId: UUID
    let detectedItems: [EvalDetectedItem]
    let durationSeconds: Double
    let framesProcessed: Int
    let apiCallCount: Int
    let scores: SessionScores?
    let runDate: Date
    let videoStartTime: Double
    let videoEndTime: Double?

    init(
        id: UUID = UUID(),
        pipeline: DetectionPipeline,
        sessionId: UUID,
        detectedItems: [EvalDetectedItem],
        durationSeconds: Double,
        framesProcessed: Int,
        apiCallCount: Int,
        scores: SessionScores? = nil,
        runDate: Date = Date(),
        videoStartTime: Double = 0,
        videoEndTime: Double? = nil
    ) {
        self.id = id
        self.pipeline = pipeline
        self.sessionId = sessionId
        self.detectedItems = detectedItems
        self.durationSeconds = durationSeconds
        self.framesProcessed = framesProcessed
        self.apiCallCount = apiCallCount
        self.scores = scores
        self.runDate = runDate
        self.videoStartTime = videoStartTime
        self.videoEndTime = videoEndTime
    }
}

// MARK: - Ground Truth

struct GroundTruthItem: Codable, Identifiable {
    let id: UUID
    var name: String
    var category: String?

    init(id: UUID = UUID(), name: String, category: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
    }
}

struct GroundTruth: Codable {
    var items: [GroundTruthItem]

    init(items: [GroundTruthItem] = []) {
        self.items = items
    }
}

// MARK: - Scan Session

struct ScanSession: Codable, Identifiable {
    let id: UUID
    var name: String
    let videoFileName: String
    let recordedAt: Date
    var groundTruth: GroundTruth
    var pipelineRuns: [PipelineRunResult]
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        videoFileName: String,
        recordedAt: Date = Date(),
        groundTruth: GroundTruth = GroundTruth(),
        pipelineRuns: [PipelineRunResult] = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.videoFileName = videoFileName
        self.recordedAt = recordedAt
        self.groundTruth = groundTruth
        self.pipelineRuns = pipelineRuns
        self.notes = notes
    }
}
