//
//  YOLOLiveDetectionView.swift
//  V4MinimalApp
//
//  Real-time YOLO object detection with bounding box overlays
//

import SwiftUI
import AVFoundation

struct YOLOLiveDetectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var detector = YOLODetector()
    @StateObject private var cameraManager = CameraManager()
    @State private var viewSize: CGSize = .zero

    var body: some View {
        ZStack {
            // Camera preview
            if cameraManager.isAuthorized && cameraManager.isSessionRunning {
                CameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { viewSize = geo.size }
                                .onChange(of: geo.size) { _, newSize in viewSize = newSize }
                        }
                    )
            } else {
                Color.black.ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                    }
            }

            // Bounding box overlays
            ForEach(Array(detector.detections.enumerated()), id: \.offset) { _, detection in
                let rect = scaledRect(detection.boundingBox, in: viewSize)
                BoundingBoxView(detection: detection)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            // Top bar
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                    }

                    Spacer()

                    // Stats badge
                    HStack(spacing: 8) {
                        Text("\(detector.detections.count) objects")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text(String(format: "%.0fms", detector.inferenceTime))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.ultraThinMaterial))

                    Spacer()

                    // Model status
                    Circle()
                        .fill(detector.isReady ? .green : .red)
                        .frame(width: 12, height: 12)
                        .padding(.trailing, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // Bottom detection list
                if !detector.detections.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(detector.detections.enumerated()), id: \.offset) { _, det in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(colorForClass(det.classIndex))
                                        .frame(width: 8, height: 8)
                                    Text(det.className)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(String(format: "%.0f%%", det.confidence * 100))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(.ultraThickMaterial))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            cameraManager.enablePixelBufferCapture { [weak detector] buffer in
                detector?.detect(in: buffer)
            }
        }
        .onDisappear {
            cameraManager.disableFrameCapture()
            cameraManager.stopSession()
        }
    }

    /// Scale a normalized rect to the view's coordinate space
    private func scaledRect(_ normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: normalized.origin.y * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    private func colorForClass(_ index: Int) -> Color {
        let colors: [Color] = [.red, .green, .blue, .orange, .purple, .yellow, .cyan, .pink, .mint, .teal]
        return colors[abs(index) % colors.count]
    }
}

struct BoundingBoxView: View {
    let detection: YOLODetection

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bounding box rectangle
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(boxColor, lineWidth: 2)

            // Label
            Text("\(detection.className) \(Int(detection.confidence * 100))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(boxColor.opacity(0.8))
                .cornerRadius(4)
                .offset(x: 2, y: -20)
        }
    }

    private var boxColor: Color {
        let colors: [Color] = [.red, .green, .blue, .orange, .purple, .yellow, .cyan, .pink, .mint, .teal]
        return colors[abs(detection.classIndex) % colors.count]
    }
}
