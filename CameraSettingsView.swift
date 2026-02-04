//
//  CameraSettingsView.swift
//  V4MinimalApp
//
//  Camera & Detection settings with live metrics
//

import SwiftUI

struct CameraSettingsView: View {
    @ObservedObject private var settings = DetectionSettings.shared

    // Optional: pass a vision service to show live metrics
    var visionService: GeminiStreamingVisionService?

    var body: some View {
        Form {
            // Section A: Live Metrics
            if let service = visionService {
                Section {
                    MetricRow(label: "Last Response", value: "\(service.lastResponseTimeMs)ms",
                              color: service.lastResponseTimeMs < 1500 ? .green : .orange)
                    MetricRow(label: "Avg Response", value: "\(service.averageResponseTimeMs)ms",
                              color: service.averageResponseTimeMs < 1500 ? .green : .orange)
                    MetricRow(label: "Success Rate",
                              value: service.totalAnalyses > 0
                                ? "\(Int(Double(service.successfulAnalyses) / Double(service.totalAnalyses) * 100))%"
                                : "--",
                              color: .primary)
                    MetricRow(label: "Total Analyses", value: "\(service.totalAnalyses)", color: .primary)
                    MetricRow(label: "Items Detected", value: "\(service.detectedObjects.count)", color: .primary)
                } header: {
                    Text("Live Metrics")
                } footer: {
                    Text("Metrics update in real-time during live detection")
                }
            }

            // Section B: Configuration
            Section {
                // Detection Pipeline
                Picker("Detection Pipeline", selection: $settings.detectionPipeline) {
                    ForEach(LiveDetectionPipeline.allCases) { pipeline in
                        VStack(alignment: .leading) {
                            Text(pipeline.displayName)
                        }
                        .tag(pipeline)
                    }
                }

                // Session Preset
                Picker("Camera Resolution", selection: $settings.sessionPreset) {
                    Text("VGA (640x480)").tag("vga640x480")
                    Text("720p (1280x720)").tag("hd1280x720")
                    Text("1080p (1920x1080)").tag("hd1920x1080")
                    Text("Photo (Full Res)").tag("photo")
                }

                // Analysis Interval
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Analysis Interval")
                        Spacer()
                        Text(String(format: "%.1fs", settings.analysisInterval))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.analysisInterval, in: 0.5...5.0, step: 0.5)
                        .tint(AppTheme.Colors.primary)
                }

                // JPEG Quality
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("JPEG Quality")
                        Spacer()
                        Text("\(Int(settings.jpegQuality * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.jpegQuality, in: 0.3...0.9, step: 0.1)
                        .tint(AppTheme.Colors.primary)
                }

                // Analysis Width
                Picker("Analysis Width", selection: $settings.frameResizeWidth) {
                    Text("480px").tag(480)
                    Text("640px").tag(640)
                    Text("800px").tag(800)
                    Text("Full").tag(9999)
                }

                // Background Enrichment
                Toggle(isOn: $settings.enableBackgroundEnrichment) {
                    Label("Background Enrichment", systemImage: "sparkles")
                }

                // Autofocus
                Toggle(isOn: $settings.enableAutoFocus) {
                    Label("Continuous Autofocus", systemImage: "camera.metering.center.weighted")
                }

                // Auto Exposure
                Toggle(isOn: $settings.enableAutoExposure) {
                    Label("Continuous Auto-Exposure", systemImage: "sun.max")
                }
            } header: {
                Text("Detection Configuration")
            } footer: {
                Text("Lower analysis interval = faster detection but more API calls. Smaller width = faster uploads. Camera changes take effect on next session start.")
            }

            // Section C: UI Settings
            Section {
                Picker("Tab Bar Icon Size", selection: $settings.tabIconSize) {
                    Text("Default (26pt)").tag(0)
                    Text("Large (34pt)").tag(1)
                    Text("Extra Large (42pt)").tag(2)
                }
            } header: {
                Text("UI")
            } footer: {
                Text("Larger icons and labels are easier to tap. Changes apply immediately.")
            }

            // Section D: Physical Upgrades
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Clip-on Wide-Angle Lens", systemImage: "camera.aperture")
                        .font(.headline)

                    Text("A clip-on wide-angle lens (e.g. Sandmarc, Moment) is the best physical upgrade for scanning rooms. It captures more items per frame without any code changes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Label("External Cameras", systemImage: "video.badge.ellipsis")
                        .font(.headline)

                    Text("UVC/USB cameras are only supported on iPadOS, not iPhone. WiFi cameras (e.g. RTSP streams) are possible but require significant development work.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Physical Upgrades")
            }
        }
        .navigationTitle("Camera & Detection")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .font(.system(.body, design: .monospaced))
        }
    }
}

#Preview {
    NavigationStack {
        CameraSettingsView()
    }
}
