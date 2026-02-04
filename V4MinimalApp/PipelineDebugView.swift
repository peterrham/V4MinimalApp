//
//  PipelineDebugView.swift
//  V4MinimalApp
//
//  Debug screen for comparing detection pipeline approaches
//

import SwiftUI

struct PipelineDebugView: View {
    @ObservedObject private var settings = DetectionSettings.shared

    var body: some View {
        Form {
            // Current pipeline selection
            Section {
                Picker("Active Pipeline", selection: $settings.detectionPipeline) {
                    ForEach(LiveDetectionPipeline.allCases) { pipeline in
                        Text(pipeline.displayName).tag(pipeline)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Pipeline Selection")
            } footer: {
                Text(settings.detectionPipeline.description)
                    .font(.caption)
            }

            // Pipeline descriptions
            Section {
                PipelineCard(
                    pipeline: .geminiOnly,
                    isActive: settings.detectionPipeline == .geminiOnly,
                    speed: "~1750ms",
                    accuracy: "High",
                    details: "Sends full camera frame to Gemini every 2s. Returns specific item names with bounding boxes. Original behavior."
                )

                PipelineCard(
                    pipeline: .yoloThenGemini,
                    isActive: settings.detectionPipeline == .yoloThenGemini,
                    speed: "~100ms",
                    accuracy: "High",
                    details: "YOLO detects objects instantly with COCO labels. Each crop is sent to Gemini for specific identification. One Gemini call per new object."
                )

                PipelineCard(
                    pipeline: .yoloBootstrapThenGemini,
                    isActive: settings.detectionPipeline == .yoloBootstrapThenGemini,
                    speed: "~100ms initial",
                    accuracy: "High",
                    details: "YOLO fills the list instantly while first Gemini call runs in parallel. Once Gemini responds, YOLO stops and Gemini takes over completely. Best of both worlds."
                )

                PipelineCard(
                    pipeline: .appleVisionBootstrap,
                    isActive: settings.detectionPipeline == .appleVisionBootstrap,
                    speed: "~200ms initial",
                    accuracy: "Medium-High",
                    details: "Apple Vision classifies the scene on-device (~1000 categories, richer than YOLO's 80). No bounding boxes. Gemini takes over after first response. Fully local bootstrap."
                )
            } header: {
                Text("Pipeline Comparison")
            }

            // Gemini Frame Rate
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Min Interval")
                        Spacer()
                        Text(String(format: "%.2fs", settings.analysisInterval))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Target FPS")
                        Spacer()
                        Text(String(format: "%.1f", 1.0 / settings.analysisInterval))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.analysisInterval, in: 0.25...5.0, step: 0.25)
                }

                // Presets
                HStack(spacing: 8) {
                    FrameRatePreset(label: "0.5s", value: 0.5, current: $settings.analysisInterval)
                    FrameRatePreset(label: "1.0s", value: 1.0, current: $settings.analysisInterval)
                    FrameRatePreset(label: "1.5s", value: 1.5, current: $settings.analysisInterval)
                    FrameRatePreset(label: "2.0s", value: 2.0, current: $settings.analysisInterval)
                    FrameRatePreset(label: "3.0s", value: 3.0, current: $settings.analysisInterval)
                }

                // Recommendation
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("Recommendation")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Text(frameRateRecommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Gemini Frame Rate")
            } footer: {
                Text("Gemini responds in ~1.5-2s. Setting interval below response time means no idle gap between calls. Overlapping requests are skipped automatically.")
            }

            // Other tuning
            Section {
                Toggle(isOn: $settings.enableBackgroundEnrichment) {
                    Label("Background Enrichment", systemImage: "sparkles")
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("JPEG Quality")
                        Spacer()
                        Text("\(Int(settings.jpegQuality * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.jpegQuality, in: 0.3...0.9, step: 0.1)
                }
            } header: {
                Text("Tuning")
            } footer: {
                Text("Changes take effect on next scan session start.")
            }

            // Camera & Dedup
            Section {
                Toggle(isOn: $settings.useHDDetection) {
                    Label("HD Detection Camera", systemImage: "camera.aperture")
                }

                Toggle(isOn: $settings.useVideoStabilization) {
                    Label("Video Stabilization", systemImage: "hand.raised.slash")
                }

                Toggle(isOn: $settings.strictVisionDedup) {
                    Label("Strict Vision Dedup", systemImage: "line.3.horizontal.decrease.circle")
                }

                Toggle(isOn: $settings.useGuidedMotionCoaching) {
                    Label("Guided Motion Coaching", systemImage: "gyroscope")
                }
            } header: {
                Text("Camera & Dedup")
            } footer: {
                Text("HD Detection uses 1280x720 instead of 640x480 for sharper thumbnails and better Gemini identification.\n\nVideo Stabilization applies cinematic stabilization to the camera feed, reducing motion blur for cleaner frames. May add slight latency.\n\nStrict Dedup filters generic Apple Vision scene labels (Structure, Furniture, Conveyance, etc.) and skips substring-duplicate detections.\n\nGuided Motion Coaching overlays the pitch guide, speed gauge, and 360° coverage ring from the guided recording view onto the live detection screen. Helps you pan steadily while items are detected and saved to inventory.\n\nAll settings require restarting the scan session.")
            }

            // Quick reference
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Indicator Dots", systemImage: "circle.fill")
                        .font(.subheadline.bold())

                    HStack(spacing: 8) {
                        Circle().fill(.yellow).frame(width: 8, height: 8)
                        Text("YOLO / Apple Vision detected (awaiting Gemini)")
                            .font(.caption)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Gemini enriched (specific name)")
                            .font(.caption)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(.orange).frame(width: 8, height: 8)
                        Text("Gemini-only with bounding box")
                            .font(.caption)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(.blue).frame(width: 8, height: 8)
                        Text("Saved to inventory")
                            .font(.caption)
                    }
                }
            } header: {
                Text("Legend")
            }
        }
        .navigationTitle("Pipeline Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var frameRateRecommendation: String {
        let interval = settings.analysisInterval
        if interval <= 0.5 {
            return "Aggressive — fires as fast as Gemini can respond (~0.5-0.7 effective FPS). Best for quick panning. Uses more API quota."
        } else if interval <= 1.0 {
            return "Fast — good balance for scanning rooms. Catches items while panning at moderate speed."
        } else if interval <= 1.5 {
            return "Default sweet spot — one call finishes before the next fires. Minimal wasted requests."
        } else if interval <= 2.5 {
            return "Conservative — saves API calls. Good for stationary scenes or slow panning."
        } else {
            return "Slow — significant gaps between detections. Best for saving API quota on long sessions."
        }
    }
}

// MARK: - Frame Rate Preset Button

private struct FrameRatePreset: View {
    let label: String
    let value: Double
    @Binding var current: Double

    var isSelected: Bool { abs(current - value) < 0.01 }

    var body: some View {
        Button {
            current = value
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pipeline Card

private struct PipelineCard: View {
    let pipeline: LiveDetectionPipeline
    let isActive: Bool
    let speed: String
    let accuracy: String
    let details: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pipeline.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if isActive {
                    Text("ACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.green))
                }
            }

            HStack(spacing: 16) {
                Label(speed, systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Label(accuracy, systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        PipelineDebugView()
    }
}
