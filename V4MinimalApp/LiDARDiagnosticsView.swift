//
//  LiDARDiagnosticsView.swift
//  V4MinimalApp
//
//  LiDAR / Depth Sensor Diagnostics
//

import SwiftUI
import ARKit
import RealityKit
import Photos

struct LiDARDiagnosticsView: View {
    @State private var arSession: ARSession?
    @State private var isRunning = false
    @State private var logs: [DiagnosticLog] = []
    @State private var depthStats: DepthStats?
    @State private var confidenceStats: ConfidenceStats?
    @State private var frameCount = 0
    @State private var lastFrameTime: Date?
    @State private var sessionDelegate: LiDARSessionDelegate?
    @State private var gotFirstDepth = false

    // AR Preview state
    @State private var showARPreview = false
    @State private var showFeaturePoints = true
    @State private var showAnchorGeometry = true
    @State private var showWorldOrigin = false
    @State private var trackingState: String = "Not running"
    @State private var planeCount = 0
    @State private var meshAnchorCount = 0

    // Coverage tracking
    @State private var coverageSegments: [Bool] = Array(repeating: false, count: 36) // 10° each
    @State private var cameraPoseHistory: [simd_float3] = [] // XZ positions for minimap
    @State private var coveragePercent: Int = 0

    // Plane area stats
    @State private var floorArea: Float = 0   // sq meters
    @State private var wallArea: Float = 0    // sq meters

    // Auto-captured frames
    @State private var capturedFrames: [CapturedFrame] = []
    @State private var autoCapture = true
    @State private var lastCaptureTime: Date = .distantPast
    @State private var lastCaptureYaw: Float = 999 // radians, sentinel
    @State private var saveToPhotos = true
    @State private var photosSavedCount = 0

    private let hasLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    private let hasSmoothedDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    private let deviceModel = Self.getDeviceModel()

    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }

    /// LiDAR-equipped devices (Pro models only)
    private var hasLiDARHardware: Bool {
        // iPhone 12 Pro+, 13 Pro+, 14 Pro+, 15 Pro+, 16 Pro+, iPad Pro 2020+
        let model = deviceModel
        let lidarModels = [
            "iPhone13,3", "iPhone13,4",       // 12 Pro, 12 Pro Max
            "iPhone14,2", "iPhone14,3",       // 13 Pro, 13 Pro Max
            "iPhone15,2", "iPhone15,3",       // 14 Pro, 14 Pro Max
            "iPhone16,1", "iPhone16,2",       // 15 Pro, 15 Pro Max
            "iPhone17,1", "iPhone17,2",       // 16 Pro, 16 Pro Max
        ]
        // Also check iPad Pro models (various identifiers)
        if lidarModels.contains(model) { return true }
        if model.starts(with: "iPad13,") || model.starts(with: "iPad14,") || model.starts(with: "iPad16,") { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // AR Camera Preview (top ~40% when toggled on)
            if showARPreview && isRunning, let session = arSession {
                ZStack(alignment: .topLeading) {
                    ARViewContainer(session: session,
                                    showFeaturePoints: showFeaturePoints,
                                    showAnchorGeometry: showAnchorGeometry,
                                    showWorldOrigin: showWorldOrigin)
                        .frame(height: 300)
                        .clipped()

                    // Tracking state badge
                    trackingBadge
                        .padding(8)
                }
            }

            ScrollView {
                VStack(spacing: 20) {
                    // AR Preview controls
                    if isRunning {
                        arPreviewSection
                    }

                    // Detected anchors stats
                    if isRunning && (planeCount > 0 || meshAnchorCount > 0) {
                        anchorStatsSection
                    }

                    // Coverage minimap + stats
                    if isRunning {
                        coverageSection
                    }

                    // Plane area stats
                    if isRunning && (floorArea > 0 || wallArea > 0) {
                        planeAreaSection
                    }

                    // Auto-captured frames gallery
                    if !capturedFrames.isEmpty {
                        capturedFramesSection
                    }

                    // Device capability section
                    capabilitySection

                    // Depth stats section (shown when running)
                    if let stats = depthStats {
                        depthStatsSection(stats)
                    }

                    // Confidence map section
                    if let conf = confidenceStats {
                        confidenceSection(conf)
                    }

                    // Controls
                    controlsSection

                    // Log output
                    logSection
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("LiDAR Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            stopSession()
        }
    }

    // MARK: - Tracking Badge

    private var trackingBadge: some View {
        let (label, color) = trackingBadgeInfo
        return Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(12)
    }

    private var trackingBadgeInfo: (String, Color) {
        switch trackingState {
        case "Normal": return ("Tracking", .green)
        case "Limited": return ("Limited", .orange)
        case "Not Available": return ("No Tracking", .red)
        default: return (trackingState, .gray)
        }
    }

    // MARK: - AR Preview Section

    private var arPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("AR Camera Preview")

            Toggle("Show AR Camera Feed", isOn: $showARPreview)
                .font(.subheadline)

            if showARPreview {
                Toggle("Feature Points", isOn: $showFeaturePoints)
                    .font(.caption)
                Toggle("Anchor Geometry", isOn: $showAnchorGeometry)
                    .font(.caption)
                Toggle("World Origin", isOn: $showWorldOrigin)
                    .font(.caption)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Anchor Stats Section

    private var anchorStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Detected Anchors")

            HStack(spacing: 16) {
                statCard("Planes", value: "\(planeCount)", color: .blue)
                statCard("Mesh", value: "\(meshAnchorCount)", color: .cyan)
                statCard("Tracking", value: trackingState, color: trackingState == "Normal" ? .green : .orange)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Coverage Section

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Room Coverage — \(coveragePercent)%")

            HStack(spacing: 16) {
                // Coverage ring (36 segments around a circle)
                ZStack {
                    ForEach(0..<36, id: \.self) { i in
                        let startAngle = Angle(degrees: Double(i * 10) - 90)
                        let endAngle = Angle(degrees: Double((i + 1) * 10) - 90)
                        Path { path in
                            path.addArc(center: CGPoint(x: 60, y: 60),
                                        radius: 50,
                                        startAngle: startAngle,
                                        endAngle: endAngle,
                                        clockwise: false)
                        }
                        .stroke(coverageSegments[i] ? Color.green : Color.gray.opacity(0.3),
                                lineWidth: 8)
                    }

                    // Camera position dot trail (minimap)
                    if cameraPoseHistory.count > 1 {
                        Canvas { context, size in
                            let positions = cameraPoseHistory
                            let xs = positions.map { $0.x }
                            let zs = positions.map { $0.z }
                            let minX = (xs.min() ?? 0) - 0.5
                            let maxX = (xs.max() ?? 0) + 0.5
                            let minZ = (zs.min() ?? 0) - 0.5
                            let maxZ = (zs.max() ?? 0) + 0.5
                            let rangeX = max(maxX - minX, 0.1)
                            let rangeZ = max(maxZ - minZ, 0.1)
                            let scale = min(size.width / CGFloat(rangeX), size.height / CGFloat(rangeZ)) * 0.8
                            let cx = size.width / 2
                            let cy = size.height / 2
                            let midX = (minX + maxX) / 2
                            let midZ = (minZ + maxZ) / 2

                            for (idx, pos) in positions.enumerated() {
                                let x = cx + CGFloat(pos.x - midX) * scale
                                let y = cy + CGFloat(pos.z - midZ) * scale
                                let opacity = Double(idx) / Double(positions.count)
                                let rect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
                                context.fill(Path(ellipseIn: rect),
                                             with: .color(.cyan.opacity(0.3 + opacity * 0.7)))
                            }
                            // Current position
                            if let last = positions.last {
                                let x = cx + CGFloat(last.x - midX) * scale
                                let y = cy + CGFloat(last.z - midZ) * scale
                                let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                                context.fill(Path(ellipseIn: rect), with: .color(.white))
                            }
                        }
                        .frame(width: 80, height: 80)
                    }

                    VStack(spacing: 2) {
                        Text("\(coveragePercent)%")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                        Text("covered")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)

                // Stats column
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        statCard("Planes", value: "\(planeCount)", color: .blue)
                        statCard("Saved", value: "\(photosSavedCount)", color: .green)
                    }

                    Toggle("Auto-Capture", isOn: $autoCapture)
                        .font(.caption)
                    Toggle("Save to Photos", isOn: $saveToPhotos)
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Plane Area Section

    private var planeAreaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Detected Surface Area")

            HStack(spacing: 16) {
                let floorSqFt = floorArea * 10.764  // m² to ft²
                let wallSqFt = wallArea * 10.764
                statCard("Floor", value: String(format: "%.0f ft²", floorSqFt), color: .blue)
                statCard("Walls", value: String(format: "%.0f ft²", wallSqFt), color: .purple)
                statCard("Total", value: String(format: "%.0f ft²", floorSqFt + wallSqFt), color: .green)
            }

            // Visual bar
            let totalArea = floorArea + wallArea
            if totalArea > 0 {
                GeometryReader { geo in
                    let floorPct = CGFloat(floorArea / totalArea)
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(width: geo.size.width * floorPct)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.purple)
                    }
                }
                .frame(height: 8)

                HStack {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    Text("Floor").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Circle().fill(Color.purple).frame(width: 8, height: 8)
                    Text("Walls").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Captured Frames Section

    private var capturedFramesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Auto-Captured Frames (\(capturedFrames.count))")
                Spacer()
                if capturedFrames.count > 0 {
                    Button("Save All") {
                        for frame in capturedFrames {
                            saveImageToPhotoLibrary(frame.image)
                        }
                        addLog("Saving \(capturedFrames.count) frames to Photos", type: .info)
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)

                    Button("Clear") {
                        capturedFrames.removeAll()
                        lastCaptureTime = .distantPast
                        lastCaptureYaw = 999
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(capturedFrames) { frame in
                        VStack(spacing: 4) {
                            Image(uiImage: frame.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 140, height: 100)
                                .clipped()
                                .cornerRadius(8)

                            HStack(spacing: 4) {
                                Image(systemName: frame.reason == "New area" ? "scope" : "camera.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(frame.reason == "New area" ? .green : .blue)
                                Text("\(frame.reason) · \(frame.yawDegrees)°")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }

                            Text(frame.timestamp, style: .time)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Capability Section

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Device: \(deviceModel)")

            capabilityRow("LiDAR Hardware", supported: hasLiDARHardware, detail: "Pro/Pro Max model required")
            capabilityRow("Depth API Support", supported: hasLiDAR, detail: "ARWorldTrackingConfiguration.sceneDepth")
            capabilityRow("Smoothed Depth", supported: hasSmoothedDepth, detail: "smoothedSceneDepth frame semantic")
            capabilityRow("ARKit Supported", supported: ARWorldTrackingConfiguration.isSupported, detail: "ARWorldTrackingConfiguration")
            capabilityRow("Face Tracking", supported: ARFaceTrackingConfiguration.isSupported, detail: "TrueDepth front camera")
            capabilityRow("Scene Reconstruction", supported: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh), detail: "Mesh reconstruction")
            capabilityRow("Scene Classification", supported: ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification), detail: "Classified mesh")

            if hasLiDAR && !hasLiDARHardware {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("API reports depth support but device model may lack LiDAR hardware. Depth frames may not arrive.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func capabilityRow(_ name: String, supported: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(supported ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(supported ? "Yes" : "No")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(supported ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((supported ? Color.green : Color.secondary).opacity(0.12))
                .cornerRadius(6)
        }
    }

    // MARK: - Depth Stats Section

    private func depthStatsSection(_ stats: DepthStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Depth Map (\(stats.width) x \(stats.height))")

            HStack(spacing: 16) {
                statCard("Min", value: String(format: "%.2f m", stats.minDepth), color: .blue)
                statCard("Max", value: String(format: "%.2f m", stats.maxDepth), color: .orange)
                statCard("Mean", value: String(format: "%.2f m", stats.meanDepth), color: .green)
            }

            HStack(spacing: 16) {
                statCard("Frames", value: "\(frameCount)", color: .purple)
                statCard("Valid Px", value: "\(stats.validPixels)/\(stats.totalPixels)", color: .cyan)
                statCard("FPS", value: fpsString, color: .pink)
            }

            // Depth histogram
            if !stats.histogram.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Depth Distribution")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(stats.histogram.enumerated()), id: \.offset) { index, count in
                            let maxCount = stats.histogram.max() ?? 1
                            let height = maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) * 60 : 0
                            VStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(height: max(2, height))
                                Text(histogramLabel(index: index, total: stats.histogram.count, maxDepth: stats.maxDepth))
                                    .font(.system(size: 7))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 80)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Confidence Section

    private func confidenceSection(_ conf: ConfidenceStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Confidence Map (\(conf.width) x \(conf.height))")

            HStack(spacing: 12) {
                confidenceBar("High", count: conf.highCount, total: conf.totalPixels, color: .green)
                confidenceBar("Medium", count: conf.mediumCount, total: conf.totalPixels, color: .yellow)
                confidenceBar("Low", count: conf.lowCount, total: conf.totalPixels, color: .red)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func confidenceBar(_ label: String, count: Int, total: Int, color: Color) -> some View {
        let pct = total > 0 ? Double(count) / Double(total) * 100 : 0
        return VStack(spacing: 4) {
            Text(String(format: "%.0f%%", pct))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.3))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(pct / 100))
                    }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 12) {
            if hasLiDAR {
                Button {
                    if isRunning {
                        stopSession()
                    } else {
                        startSession()
                    }
                } label: {
                    HStack {
                        Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                        Text(isRunning ? "Stop LiDAR Session" : "Start LiDAR Session")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isRunning ? Color.red : Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }

                if isRunning {
                    Button {
                        captureSnapshot()
                    } label: {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                            Text("Capture Snapshot")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .cornerRadius(10)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("This device does not have a LiDAR scanner. Depth diagnostics are unavailable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }

            Button {
                logs.removeAll()
                depthStats = nil
                confidenceStats = nil
                frameCount = 0
                lastFrameTime = nil
                gotFirstDepth = false
                coverageSegments = Array(repeating: false, count: 36)
                cameraPoseHistory.removeAll()
                coveragePercent = 0
                floorArea = 0
                wallArea = 0
                capturedFrames.removeAll()
                lastCaptureTime = .distantPast
                lastCaptureYaw = 999
                photosSavedCount = 0
                addLog("Cleared all results", type: .info)
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear Results")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground))
                .foregroundStyle(.secondary)
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Log Section

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Diagnostic Log (\(logs.count))")

            if logs.isEmpty {
                Text("No log entries yet. Start a LiDAR session to begin diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logs) { log in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: log.type.icon)
                                .font(.caption2)
                                .foregroundStyle(log.type.color)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(log.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Text(log.timestamp, style: .time)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private func statCard(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }

    private var fpsString: String {
        guard let last = lastFrameTime else { return "—" }
        let elapsed = Date().timeIntervalSince(last)
        guard elapsed > 0 else { return "—" }
        return String(format: "%.1f", 1.0 / elapsed)
    }

    private func histogramLabel(index: Int, total: Int, maxDepth: Float) -> String {
        let step = maxDepth / Float(total)
        let start = step * Float(index)
        return String(format: "%.1f", start)
    }

    // MARK: - Session Management

    private func startSession() {
        addLog("Initializing ARSession...", type: .info)
        NetworkLogger.shared.info("LiDAR: Initializing ARSession, device=\(deviceModel), hasLiDARHardware=\(hasLiDARHardware)", category: "LiDAR")

        // Check world sensing authorization
        // Note: worldSensingAuthorizationStatus API may not exist on this SDK version

        let session = ARSession()
        let delegate = LiDARSessionDelegate { frame in
            self.processFrame(frame)
        } onError: { error in
            self.addLog("ARSession error: \(error.localizedDescription)", type: .error)
            NetworkLogger.shared.error("LiDAR ARSession error: \(error.localizedDescription)", category: "LiDAR")
        }

        session.delegate = delegate
        self.sessionDelegate = delegate

        let config = ARWorldTrackingConfiguration()

        // Log all available video formats and which support depth
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        NetworkLogger.shared.info("LiDAR: \(formats.count) video formats available", category: "LiDAR")
        for (i, fmt) in formats.enumerated() {
            NetworkLogger.shared.info("LiDAR format[\(i)]: \(fmt.imageResolution) @\(fmt.framesPerSecond)fps \(fmt.captureDeviceType.rawValue)", category: "LiDAR")
        }

        // Try just .sceneDepth (simplest request)
        config.frameSemantics = .sceneDepth
        addLog("Set frameSemantics = .sceneDepth only", type: .success)

        // Enable plane detection (works on ALL ARKit devices, no LiDAR needed)
        config.planeDetection = [.horizontal, .vertical]
        addLog("Plane detection enabled (horizontal + vertical)", type: .success)

        // Enable mesh reconstruction if supported (LiDAR devices)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            addLog("Mesh reconstruction enabled", type: .success)
        }

        NetworkLogger.shared.info("LiDAR config: frameSemantics=\(config.frameSemantics), videoFormat=\(config.videoFormat)", category: "LiDAR")

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        self.arSession = session
        isRunning = true
        addLog("ARSession started — waiting for depth frames...", type: .success)
        NetworkLogger.shared.info("LiDAR: ARSession running, delegate=\(session.delegate != nil)", category: "LiDAR")

        // Check currentFrame directly after delays to diagnose depth delivery
        for delay in [2.0, 5.0, 10.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak session] in
                guard let session = session, self.isRunning else { return }
                if let frame = session.currentFrame {
                    let hasScene = frame.sceneDepth != nil
                    let hasSmoothed = frame.smoothedSceneDepth != nil
                    NetworkLogger.shared.info("LiDAR poll @\(delay)s: sceneDepth=\(hasScene) smoothed=\(hasSmoothed) tracking=\(frame.camera.trackingState)", category: "LiDAR")
                    self.addLog("Poll @\(delay)s: depth=\(hasScene || hasSmoothed), tracking=\(frame.camera.trackingState)", type: hasScene || hasSmoothed ? .success : .warning)
                }
            }
        }
    }

    private func stopSession() {
        arSession?.pause()
        arSession = nil
        sessionDelegate = nil
        isRunning = false
        addLog("ARSession stopped", type: .info)
        NetworkLogger.shared.info("LiDAR diagnostics session stopped", category: "LiDAR")
    }

    private func captureSnapshot() {
        guard let frame = arSession?.currentFrame else {
            addLog("No current frame available", type: .warning)
            return
        }
        processFrame(frame)
        addLog("Manual snapshot captured", type: .success)
    }

    private func processFrame(_ frame: ARFrame) {
        frameCount += 1
        lastFrameTime = Date()

        // Process depth map
        if let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap {
            let stats = analyzeDepthMap(depthMap)
            DispatchQueue.main.async {
                self.depthStats = stats
            }

            if !gotFirstDepth {
                gotFirstDepth = true
                addLog("First depth at frame #\(frameCount): \(stats.width)x\(stats.height), range \(String(format: "%.2f", stats.minDepth))–\(String(format: "%.2f", stats.maxDepth))m", type: .success)
                NetworkLogger.shared.info("LiDAR depth arrived at frame #\(frameCount): \(stats.width)x\(stats.height), depth \(String(format: "%.2f-%.2f", stats.minDepth, stats.maxDepth))m", category: "LiDAR")
            }
        } else {
            if frameCount <= 3 {
                addLog("Frame #\(frameCount): no depth data yet (warming up)", type: .warning)
                NetworkLogger.shared.info("LiDAR frame #\(frameCount): no depth data yet", category: "LiDAR")
            }
        }

        // Process confidence map
        if let confidenceMap = frame.smoothedSceneDepth?.confidenceMap ?? frame.sceneDepth?.confidenceMap {
            let conf = analyzeConfidenceMap(confidenceMap)
            DispatchQueue.main.async {
                self.confidenceStats = conf
            }

            if frameCount <= 1 || !gotFirstDepth {
                addLog("Confidence map: \(conf.width)x\(conf.height), high=\(conf.highCount), med=\(conf.mediumCount), low=\(conf.lowCount)", type: .info)
            }
        }

        // Update tracking state
        let newTrackingState = formatTrackingState(frame.camera.trackingState)
        if newTrackingState != trackingState {
            DispatchQueue.main.async {
                self.trackingState = newTrackingState
            }
        }

        // Count anchors
        let planes = frame.anchors.compactMap { $0 as? ARPlaneAnchor }
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }

        let newPlaneCount = planes.count
        let newMeshCount = meshAnchors.count

        if newPlaneCount != planeCount || newMeshCount != meshAnchorCount {
            DispatchQueue.main.async {
                self.planeCount = newPlaneCount
                self.meshAnchorCount = newMeshCount
            }
        }

        // Log mesh anchors periodically
        if frameCount % 30 == 0 {
            if !meshAnchors.isEmpty {
                let totalVertices = meshAnchors.reduce(0) { $0 + $1.geometry.vertices.count }
                let totalFaces = meshAnchors.reduce(0) { $0 + $1.geometry.faces.count }
                addLog("Mesh: \(meshAnchors.count) anchors, \(totalVertices) vertices, \(totalFaces) faces", type: .info)
            }
            if !planes.isEmpty {
                addLog("Planes: \(planes.count) detected (\(planes.filter { $0.alignment == .horizontal }.count) horiz, \(planes.filter { $0.alignment == .vertical }.count) vert)", type: .info)
            }
        }

        // Coverage tracking: which compass directions have been viewed
        let transform = frame.camera.transform
        let camPos = simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

        // Camera forward vector in XZ plane → yaw angle
        let forward = simd_float3(-transform.columns.2.x, 0, -transform.columns.2.z)
        let yaw = atan2(forward.x, forward.z) // -pi..pi
        let yawDeg = (Int((yaw * 180 / .pi) + 360) % 360) // 0..359
        let segment = yawDeg / 10 // 0..35

        var segmentsChanged = false
        if segment >= 0 && segment < 36 && !coverageSegments[segment] {
            segmentsChanged = true
        }

        // Record camera position for minimap (every 6th frame to save memory)
        let shouldRecordPos = frameCount % 6 == 0

        DispatchQueue.main.async {
            if segmentsChanged {
                self.coverageSegments[segment] = true
                self.coveragePercent = Int(self.coverageSegments.filter { $0 }.count * 100 / 36)
            }
            if shouldRecordPos {
                self.cameraPoseHistory.append(camPos)
                if self.cameraPoseHistory.count > 500 { self.cameraPoseHistory.removeFirst() }
            }
        }

        // Plane area calculation (every 10th frame)
        if frameCount % 10 == 0 {
            var newFloor: Float = 0
            var newWall: Float = 0
            for plane in planes {
                let area = plane.extent.x * plane.extent.z // meters
                if plane.alignment == .horizontal {
                    newFloor += area
                } else {
                    newWall += area
                }
            }
            DispatchQueue.main.async {
                self.floorArea = newFloor
                self.wallArea = newWall
            }
        }

        // Auto-capture: grab a frame when conditions are right
        if autoCapture && capturedFrames.count < 20 {
            let now = Date()
            let timeSinceLastCapture = now.timeIntervalSince(lastCaptureTime)
            let isNormal = (newTrackingState == "Normal")
            let yawDiffFromLast = abs(yaw - lastCaptureYaw)
            let isNewDirection = lastCaptureYaw > 900 || yawDiffFromLast > 0.5 // ~30° difference
            let hasEnoughTime = timeSinceLastCapture > 2.0

            if isNormal && isNewDirection && hasEnoughTime {
                let pixelBuffer = frame.capturedImage
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    let fullImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
                    // Downscale for in-app thumbnail
                    let thumb = downsampleImage(fullImage, maxDimension: 480)
                    let reason = segmentsChanged ? "New area" : "Steady shot"
                    let captured = CapturedFrame(
                        image: thumb,
                        timestamp: now,
                        reason: reason,
                        yawDegrees: yawDeg,
                        planeCount: newPlaneCount
                    )
                    DispatchQueue.main.async {
                        self.capturedFrames.append(captured)
                        self.lastCaptureTime = now
                        self.lastCaptureYaw = yaw
                    }
                    addLog("Auto-captured at \(yawDeg)°: \(reason) (\(capturedFrames.count + 1) total)", type: .success)

                    // Save full-resolution to photo library
                    if saveToPhotos {
                        saveImageToPhotoLibrary(fullImage)
                    }
                }
            }
        }
    }

    private func downsampleImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func saveImageToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.addLog("Photo library access denied", type: .warning)
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    DispatchQueue.main.async {
                        self.photosSavedCount += 1
                    }
                } else if let error = error {
                    self.addLog("Photo save failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }

    private func formatTrackingState(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "Normal"
        case .limited(let reason):
            switch reason {
            case .initializing: return "Limited"
            case .excessiveMotion: return "Limited"
            case .insufficientFeatures: return "Limited"
            case .relocalizing: return "Limited"
            @unknown default: return "Limited"
            }
        case .notAvailable: return "Not Available"
        }
    }

    // MARK: - Analysis

    private func analyzeDepthMap(_ depthMap: CVPixelBuffer) -> DepthStats {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let totalPixels = width * height

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return DepthStats(width: width, height: height, minDepth: 0, maxDepth: 0, meanDepth: 0, validPixels: 0, totalPixels: totalPixels, histogram: [])
        }

        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)

        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = 0
        var sum: Float = 0
        var validCount = 0

        for i in 0..<totalPixels {
            let d = floatBuffer[i]
            if d.isFinite && d > 0 {
                minVal = min(minVal, d)
                maxVal = max(maxVal, d)
                sum += d
                validCount += 1
            }
        }

        let mean = validCount > 0 ? sum / Float(validCount) : 0
        if validCount == 0 { minVal = 0 }

        // Build histogram (10 buckets)
        let bucketCount = 10
        var histogram = [Int](repeating: 0, count: bucketCount)
        if maxVal > 0 && validCount > 0 {
            let step = maxVal / Float(bucketCount)
            for i in 0..<totalPixels {
                let d = floatBuffer[i]
                if d.isFinite && d > 0 {
                    let bucket = min(Int(d / step), bucketCount - 1)
                    histogram[bucket] += 1
                }
            }
        }

        return DepthStats(
            width: width, height: height,
            minDepth: minVal, maxDepth: maxVal, meanDepth: mean,
            validPixels: validCount, totalPixels: totalPixels,
            histogram: histogram
        )
    }

    private func analyzeConfidenceMap(_ confidenceMap: CVPixelBuffer) -> ConfidenceStats {
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        let totalPixels = width * height

        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return ConfidenceStats(width: width, height: height, highCount: 0, mediumCount: 0, lowCount: 0, totalPixels: totalPixels)
        }

        let uint8Buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var high = 0, medium = 0, low = 0

        for i in 0..<totalPixels {
            switch uint8Buffer[i] {
            case 2: high += 1      // ARConfidenceLevel.high
            case 1: medium += 1    // ARConfidenceLevel.medium
            default: low += 1      // ARConfidenceLevel.low
            }
        }

        return ConfidenceStats(width: width, height: height, highCount: high, mediumCount: medium, lowCount: low, totalPixels: totalPixels)
    }

    private func addLog(_ message: String, type: DiagnosticLog.LogType) {
        DispatchQueue.main.async {
            logs.insert(DiagnosticLog(message: message, type: type), at: 0)
            if logs.count > 100 { logs.removeLast() }
        }
    }
}

// MARK: - Data Models

private struct DepthStats {
    let width: Int
    let height: Int
    let minDepth: Float
    let maxDepth: Float
    let meanDepth: Float
    let validPixels: Int
    let totalPixels: Int
    let histogram: [Int]
}

private struct ConfidenceStats {
    let width: Int
    let height: Int
    let highCount: Int
    let mediumCount: Int
    let lowCount: Int
    let totalPixels: Int
}

private struct CapturedFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let timestamp: Date
    let reason: String // e.g. "New area", "Steady shot", "Manual"
    let yawDegrees: Int
    let planeCount: Int
}

private struct DiagnosticLog: Identifiable {
    let id = UUID()
    let message: String
    let type: LogType
    let timestamp = Date()

    enum LogType {
        case info, success, warning, error

        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}

// MARK: - ARSession Delegate

private class LiDARSessionDelegate: NSObject, ARSessionDelegate {
    let onFrame: (ARFrame) -> Void
    let onError: (Error) -> Void
    private var frameSkip = 0
    private var didLogFirstDepth = false

    init(onFrame: @escaping (ARFrame) -> Void, onError: @escaping (Error) -> Void) {
        self.onFrame = onFrame
        self.onError = onError
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameSkip += 1
        let hasDepth = frame.sceneDepth != nil || frame.smoothedSceneDepth != nil

        // Log first few frames, first depth frame, and periodic updates
        if frameSkip <= 5 || (hasDepth && !didLogFirstDepth) || frameSkip % 60 == 0 {
            let capturedDepth = frame.capturedDepthData != nil
            let estimation = frame.estimatedDepthData != nil
            NetworkLogger.shared.info("LiDAR frame #\(frameSkip): sceneDepth=\(frame.sceneDepth != nil) smoothed=\(frame.smoothedSceneDepth != nil) capturedDepth=\(capturedDepth) estimatedDepth=\(estimation) tracking=\(frame.camera.trackingState)", category: "LiDAR")
            if hasDepth && !didLogFirstDepth {
                didLogFirstDepth = true
                NetworkLogger.shared.info("LiDAR delegate: first depth frame at frame #\(frameSkip)", category: "LiDAR")
            }
        }

        // Process every frame that has depth, throttle non-depth frames
        if hasDepth || frameSkip % 6 == 0 {
            onFrame(frame)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        NetworkLogger.shared.error("LiDAR delegate: session failed: \(error.localizedDescription)", category: "LiDAR")
        onError(error)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        NetworkLogger.shared.warning("LiDAR delegate: session interrupted", category: "LiDAR")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        NetworkLogger.shared.info("LiDAR delegate: interruption ended", category: "LiDAR")
    }

}

// MARK: - AR View Container

private struct ARViewContainer: UIViewRepresentable {
    let session: ARSession
    let showFeaturePoints: Bool
    let showAnchorGeometry: Bool
    let showWorldOrigin: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.session = session
        arView.environment.background = .cameraFeed()
        updateDebugOptions(arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        updateDebugOptions(arView)
    }

    private func updateDebugOptions(_ arView: ARView) {
        var options: ARView.DebugOptions = []
        if showFeaturePoints { options.insert(.showFeaturePoints) }
        if showAnchorGeometry { options.insert(.showAnchorGeometry) }
        if showWorldOrigin { options.insert(.showWorldOrigin) }
        arView.debugOptions = options
    }
}
