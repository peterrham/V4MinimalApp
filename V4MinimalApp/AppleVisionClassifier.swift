//
//  AppleVisionClassifier.swift
//  V4MinimalApp
//
//  On-device image classification using Apple's Vision framework.
//  Uses VNClassifyImageRequest which has ~1000+ categories (much richer than YOLO's 80 COCO classes).
//  Runs entirely on-device, no API key, no network.
//

import Foundation
import UIKit
import Vision

struct VisionClassification {
    let identifier: String   // e.g., "laptop_computer", "coffee_mug", "desk"
    let confidence: Float
    /// Human-readable display name (underscores → spaces, capitalized)
    var displayName: String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

@MainActor
class AppleVisionClassifier: ObservableObject {
    @Published var classifications: [VisionClassification] = []
    @Published var inferenceTime: Double = 0  // milliseconds
    @Published var classificationCycle: Int = 0

    private var lastInferenceTime = Date.distantPast
    private let throttleInterval: TimeInterval = 0.2  // 5 FPS max (classification is heavier than detection)
    private let confidenceThreshold: Float = 0.1
    private let maxResults = 10

    /// Classify objects in a pixel buffer (from camera feed)
    func classify(pixelBuffer: CVPixelBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastInferenceTime) >= throttleInterval else { return }
        lastInferenceTime = now

        let startTime = CACurrentMediaTime()

        let request = VNClassifyImageRequest { [weak self] request, error in
            guard let self else { return }
            let elapsed = (CACurrentMediaTime() - startTime) * 1000

            guard let results = request.results as? [VNClassificationObservation] else {
                Task { @MainActor in
                    self.classifications = []
                    self.inferenceTime = elapsed
                    self.classificationCycle += 1
                }
                return
            }

            let filtered = results
                .filter { $0.confidence >= self.confidenceThreshold }
                .prefix(self.maxResults)
                .map { VisionClassification(identifier: $0.identifier, confidence: $0.confidence) }

            Task { @MainActor in
                self.classifications = Array(filtered)
                self.inferenceTime = elapsed
                self.classificationCycle += 1
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        DispatchQueue.global(qos: .userInteractive).async {
            try? handler.perform([request])
        }
    }

    /// Classify objects in a UIImage
    func classify(image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        let startTime = CACurrentMediaTime()

        let request = VNClassifyImageRequest { [weak self] request, error in
            guard let self else { return }
            let elapsed = (CACurrentMediaTime() - startTime) * 1000

            guard let results = request.results as? [VNClassificationObservation] else {
                Task { @MainActor in
                    self.classifications = []
                    self.inferenceTime = elapsed
                    self.classificationCycle += 1
                }
                return
            }

            let filtered = results
                .filter { $0.confidence >= self.confidenceThreshold }
                .prefix(self.maxResults)
                .map { VisionClassification(identifier: $0.identifier, confidence: $0.confidence) }

            Task { @MainActor in
                self.classifications = Array(filtered)
                self.inferenceTime = elapsed
                self.classificationCycle += 1
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        DispatchQueue.global(qos: .userInteractive).async {
            try? handler.perform([request])
        }
    }
}
