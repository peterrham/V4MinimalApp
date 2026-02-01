//
//  YOLODetector.swift
//  V4MinimalApp
//
//  On-device YOLO object detection via CoreML + Vision framework
//

import Foundation
import UIKit
import Vision
import CoreML

struct YOLODetection {
    let classIndex: Int
    let className: String
    let confidence: Float
    let boundingBox: CGRect  // Normalized 0-1 (origin = top-left)
}

@MainActor
class YOLODetector: ObservableObject {
    @Published var detections: [YOLODetection] = []
    @Published var inferenceTime: Double = 0  // milliseconds
    @Published var isReady = false

    private var visionModel: VNCoreMLModel?
    private var lastInferenceTime = Date.distantPast
    private let throttleInterval: TimeInterval = 0.1  // 10 FPS max

    static let cocoClasses: [String] = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
        "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
        "toothbrush"
    ]

    init() {
        loadModel()
    }

    private func loadModel() {
        guard let modelURL = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "yolo11n", withExtension: "mlpackage") else {
            print("⚠️ YOLO model not found in bundle")
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Use Neural Engine + GPU + CPU
            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            visionModel = try VNCoreMLModel(for: mlModel)
            isReady = true
            print("✅ YOLO model loaded successfully")
        } catch {
            print("❌ Failed to load YOLO model: \(error)")
        }
    }

    func detect(in pixelBuffer: CVPixelBuffer) {
        guard isReady, let visionModel else { return }

        // Throttle
        let now = Date()
        guard now.timeIntervalSince(lastInferenceTime) >= throttleInterval else { return }
        lastInferenceTime = now

        let startTime = CACurrentMediaTime()

        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard let self, let results = request.results else { return }
            let elapsed = (CACurrentMediaTime() - startTime) * 1000

            let detections = self.parseDetections(results)

            Task { @MainActor in
                self.detections = detections
                self.inferenceTime = elapsed
            }
        }
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        DispatchQueue.global(qos: .userInteractive).async {
            try? handler.perform([request])
        }
    }

    func detect(in image: UIImage) {
        guard isReady, let visionModel, let cgImage = image.cgImage else { return }

        let startTime = CACurrentMediaTime()

        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard let self, let results = request.results else { return }
            let elapsed = (CACurrentMediaTime() - startTime) * 1000

            let detections = self.parseDetections(results)

            Task { @MainActor in
                self.detections = detections
                self.inferenceTime = elapsed
            }
        }
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        DispatchQueue.global(qos: .userInteractive).async {
            try? handler.perform([request])
        }
    }

    private func parseDetections(_ results: [VNObservation]) -> [YOLODetection] {
        // VNCoreMLRequest with a detection model returns VNRecognizedObjectObservation
        if let recognized = results as? [VNRecognizedObjectObservation] {
            return recognized.compactMap { obs in
                guard let topLabel = obs.labels.first,
                      topLabel.confidence >= 0.3 else { return nil }

                // Vision framework uses bottom-left origin, flip to top-left
                let box = obs.boundingBox
                let flipped = CGRect(
                    x: box.origin.x,
                    y: 1 - box.origin.y - box.height,
                    width: box.width,
                    height: box.height
                )

                return YOLODetection(
                    classIndex: Self.cocoClasses.firstIndex(of: topLabel.identifier) ?? -1,
                    className: topLabel.identifier,
                    confidence: topLabel.confidence,
                    boundingBox: flipped
                )
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(20)
            .map { $0 }
        }

        // Fallback: raw MultiArray output (if model doesn't have NMS baked in)
        if let coreMLObservation = results.first as? VNCoreMLFeatureValueObservation,
           let multiArray = coreMLObservation.featureValue.multiArrayValue {
            return parseRawYOLOOutput(multiArray)
        }

        return []
    }

    /// Parse raw [1, 84, 8400] YOLO output with manual NMS
    private func parseRawYOLOOutput(_ output: MLMultiArray) -> [YOLODetection] {
        let numClasses = 80
        let numDetections = 8400
        let confidenceThreshold: Float = 0.3
        let iouThreshold: Float = 0.45

        var candidates: [YOLODetection] = []

        let ptr = UnsafeMutablePointer<Float>(OpaquePointer(output.dataPointer))
        let stride84 = numDetections  // [1, 84, 8400] → row i has stride numDetections

        for d in 0..<numDetections {
            // Extract bbox: [cx, cy, w, h] (rows 0-3)
            let cx = ptr[0 * stride84 + d]
            let cy = ptr[1 * stride84 + d]
            let w  = ptr[2 * stride84 + d]
            let h  = ptr[3 * stride84 + d]

            // Find best class (rows 4-83)
            var bestClass = 0
            var bestScore: Float = 0
            for c in 0..<numClasses {
                let score = ptr[(4 + c) * stride84 + d]
                if score > bestScore {
                    bestScore = score
                    bestClass = c
                }
            }

            guard bestScore >= confidenceThreshold else { continue }

            // Convert from model coords (0-640) to normalized (0-1)
            let x1 = (cx - w / 2) / 640.0
            let y1 = (cy - h / 2) / 640.0
            let bw = w / 640.0
            let bh = h / 640.0

            candidates.append(YOLODetection(
                classIndex: bestClass,
                className: bestClass < Self.cocoClasses.count ? Self.cocoClasses[bestClass] : "unknown",
                confidence: bestScore,
                boundingBox: CGRect(x: CGFloat(x1), y: CGFloat(y1), width: CGFloat(bw), height: CGFloat(bh))
            ))
        }

        // Sort by confidence
        candidates.sort { $0.confidence > $1.confidence }

        // Apply NMS
        var kept: [YOLODetection] = []
        var suppressed = Set<Int>()

        for i in 0..<candidates.count {
            guard !suppressed.contains(i) else { continue }
            kept.append(candidates[i])
            if kept.count >= 20 { break }

            for j in (i + 1)..<candidates.count {
                if !suppressed.contains(j) &&
                    candidates[i].classIndex == candidates[j].classIndex &&
                    iou(candidates[i].boundingBox, candidates[j].boundingBox) > iouThreshold {
                    suppressed.insert(j)
                }
            }
        }

        return kept
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        return Float(intersectionArea / unionArea)
    }
}
