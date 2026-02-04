//
//  LiveObjectDetectionView.swift
//  V4MinimalApp
//
//  Real-time object detection with streaming Gemini Vision analysis
//

import SwiftUI
import AVFoundation
import os.log

struct LiveObjectDetectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var inventoryStore: InventoryStore
    @EnvironmentObject var sessionStore: DetectionSessionStore
    @StateObject private var cameraManager = CameraManager(detectionOnly: !DetectionSettings.shared.useHDDetection)
    @StateObject private var visionService = GeminiStreamingVisionService()
    @StateObject private var enrichmentService = BackgroundEnrichmentService()
    @StateObject private var yoloDetector = YOLODetector()
    @StateObject private var visionClassifier = AppleVisionClassifier()
    @StateObject private var motionMonitor = RecordingMotionMonitor()

    @State private var isDetectionActive = false
    @State private var useMotionCoaching = false
    @State private var currentSessionId: UUID?
    @State private var sessionItemCount: Int = 0
    /// Tracks which detection IDs have been added to the session already
    @State private var addedDetectionIds: Set<UUID> = []

    /// Tracks YOLO object IDs → DetectedObject IDs for reconciliation
    @State private var yoloTrackedObjects: [String: TrackedYOLOObject] = [:]
    /// Latest camera frame for cropping YOLO bounding boxes
    @State private var latestFrame: UIImage?
    /// Pipeline mode read once on appear
    @State private var activePipeline: LiveDetectionPipeline = .yoloThenGemini
    /// For bootstrap mode: true once first Gemini response has been received
    @State private var geminiHasResponded = false
    /// For bootstrap mode: set of YOLO class names already added (class-level dedup)
    @State private var yoloSeenClasses: Set<String> = []
    /// For Apple Vision bootstrap: set of identifiers already added
    @State private var visionSeenIdentifiers: Set<String> = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera Preview
                if cameraManager.isAuthorized && cameraManager.isSessionRunning {
                    CameraPreview(session: cameraManager.session)
                        .ignoresSafeArea()
                } else if !cameraManager.isAuthorized {
                    // Permission denied view
                    cameraPermissionView
                } else {
                    // Loading view
                    cameraLoadingView
                }
                
                // Motion coaching overlays (pitch guide + coverage ring)
                if useMotionCoaching {
                    motionPitchGuide
                        .allowsHitTesting(false)

                    // Coverage ring — positioned in upper third so detection list doesn't obscure it
                    if isDetectionActive {
                        VStack {
                            Spacer()
                                .frame(height: 140)
                            motionCoverageRing
                                .frame(width: 120, height: 120)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }
                }

                // Overlay UI
                VStack(spacing: 0) {
                    // Top controls
                    topControls

                    // Motion coaching hint + speed
                    if useMotionCoaching && isDetectionActive {
                        motionHintBar
                    }

                    Spacer()

                    // Detection display box
                    if isDetectionActive || !visionService.detectedObjects.isEmpty {
                        StreamingObjectDetectionView(
                            detectedObjects: visionService.detectedObjects,
                            isAnalyzing: isDetectionActive,
                            sessionItemCount: sessionItemCount
                        )
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Speed gauge (motion coaching)
                    if useMotionCoaching && isDetectionActive {
                        motionSpeedGauge
                    }

                    // Bottom controls
                    bottomControls
                        .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                setupStreamingDetection()
            }
            .onDisappear {
                cleanup()
            }
            .onChange(of: yoloDetector.detectionCycle) { _, _ in
                if activePipeline == .yoloThenGemini || activePipeline == .yoloBootstrapThenGemini {
                    reconcileYOLODetections(yoloDetector.detections)
                }
            }
            .onChange(of: visionClassifier.classificationCycle) { _, _ in
                if activePipeline == .appleVisionBootstrap {
                    reconcileVisionClassifications(visionClassifier.classifications)
                }
            }
            .onChange(of: visionService.detectedObjects.count) { _, _ in
                addNewDetectionsToSession()
            }
        }
    }
    
    // MARK: - UI Components
    
    private var topControls: some View {
        HStack {
            // Close button
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
            
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(isDetectionActive ? .green : .gray)
                    .frame(width: 8, height: 8)
                
                Text(isDetectionActive ? "LIVE" : "PAUSED")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.6)))
            
            Spacer()
            
            // Flash toggle
            Button {
                cameraManager.toggleFlash()
            } label: {
                Image(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(cameraManager.isFlashOn ? .yellow : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
            }
        }
        .padding()
    }
    
    private var bottomControls: some View {
        HStack(spacing: 30) {
            // Clear detections
            Button {
                withAnimation {
                    visionService.clearDetections()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                        .foregroundColor(.white)

                    Text("Clear")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .background(Circle().fill(.ultraThinMaterial))
            }
            .disabled(visionService.detectedObjects.isEmpty)

            // Start/Stop detection button
            Button {
                toggleDetection()
            } label: {
                ZStack {
                    Circle()
                        .fill((isDetectionActive ? Color.red : Color.green).gradient)
                        .frame(width: 80, height: 80)
                        .shadow(color: (isDetectionActive ? Color.red : Color.green).opacity(0.5), radius: 10)

                    Image(systemName: isDetectionActive ? "stop.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .symbolEffect(.pulse, isActive: isDetectionActive)

            // Session counter badge
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "tray.full.fill")
                        .font(.title3)
                        .foregroundColor(.white)

                    if sessionItemCount > 0 {
                        Text("\(sessionItemCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Circle().fill(.blue))
                            .offset(x: 10, y: -10)
                    }
                }

                Text("Collected")
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            .frame(width: 60, height: 60)
            .background(Circle().fill(.ultraThinMaterial))
        }
        .padding(.horizontal)
    }
    
    private var cameraPermissionView: some View {
        Rectangle()
            .fill(.black)
            .overlay {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill.badge.ellipsis")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    Text("Camera Access Required")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("Please enable camera access in Settings for live object detection")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    } label: {
                        Text("Open Settings")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.blue))
                    }
                }
            }
            .ignoresSafeArea()
    }
    
    private var cameraLoadingView: some View {
        Rectangle()
            .fill(.black)
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    
                    Text("Initializing Camera...")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.callout)
                }
            }
            .ignoresSafeArea()
    }
    
    // MARK: - Motion Coaching UI

    private var motionPitchGuide: some View {
        GeometryReader { geo in
            let centerY = geo.size.height / 2
            let indicatorY = centerY + motionMonitor.pitchOffset * 300
            let guideColor: Color = motionMonitor.pitchAligned ? .green : (abs(motionMonitor.pitchOffset) < 0.3 ? .yellow : .red)

            ZStack {
                // Target line
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 1)
                    .position(x: geo.size.width / 2, y: centerY)

                // Tick marks
                HStack {
                    Rectangle().fill(.white.opacity(0.5)).frame(width: 1, height: 12)
                    Spacer()
                    Rectangle().fill(.white.opacity(0.5)).frame(width: 1, height: 12)
                }
                .padding(.horizontal, 40)
                .position(x: geo.size.width / 2, y: centerY)

                // Moving indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(guideColor)
                    .frame(width: geo.size.width - 80, height: 3)
                    .position(x: geo.size.width / 2, y: indicatorY)
                    .animation(.easeOut(duration: 0.1), value: motionMonitor.pitchOffset)

                if abs(motionMonitor.pitchOffset) >= 0.15 {
                    Image(systemName: motionMonitor.pitchOffset < 0 ? "arrow.down" : "arrow.up")
                        .font(.caption.bold())
                        .foregroundColor(guideColor)
                        .position(x: geo.size.width / 2, y: centerY + (motionMonitor.pitchOffset < 0 ? 20 : -20))
                }
            }
        }
    }

    private var motionCoverageRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 5)

            ForEach(0..<RecordingMotionMonitor.segmentCount, id: \.self) { i in
                let startAngle = Angle(degrees: Double(i) * (360.0 / Double(RecordingMotionMonitor.segmentCount)) - 90)
                let endAngle = Angle(degrees: Double(i + 1) * (360.0 / Double(RecordingMotionMonitor.segmentCount)) - 90)

                if motionMonitor.coveredSegments.contains(i) {
                    ArcSegment(startAngle: startAngle, endAngle: endAngle)
                        .stroke(motionMonitor.completedFullCircle ? .green : .cyan, lineWidth: 5)
                }
            }

            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", motionMonitor.coveragePercent))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundColor(.white)
                if motionMonitor.completedFullCircle {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
    }

    private var motionHintBar: some View {
        HStack(spacing: 12) {
            Text(motionMonitor.hint)
                .font(.caption.bold())
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            Text(String(format: "%.0f°/s", motionMonitor.rotationRate))
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.black.opacity(0.4))
        .animation(.easeInOut(duration: 0.3), value: motionMonitor.hint)
    }

    private var motionSpeedGauge: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(motionMonitor.speedLevel.color)
                        .frame(width: max(geo.size.width * min(motionMonitor.rotationRate / 90.0, 1.0), 4))
                        .animation(.easeOut(duration: 0.15), value: motionMonitor.rotationRate)
                }
            }
            .frame(height: 6)

            HStack {
                Text("still")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(motionMonitor.speedLevel.rawValue)
                    .font(.caption2.bold())
                    .foregroundColor(motionMonitor.speedLevel.color)
                Spacer()
                Text("fast")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 4)
    }

    // MARK: - Methods

    private func setupStreamingDetection() {
        // Create a new detection session
        currentSessionId = sessionStore.createSession()
        addedDetectionIds.removeAll()
        sessionItemCount = 0

        // Wire enrichment service to vision service
        enrichmentService.visionService = visionService

        // Motion coaching
        useMotionCoaching = DetectionSettings.shared.useGuidedMotionCoaching
        if useMotionCoaching {
            motionMonitor.startMonitoring()
            motionMonitor.startRecording()
        }

        // Read pipeline setting
        activePipeline = DetectionSettings.shared.detectionPipeline

        switch activePipeline {
        case .yoloThenGemini:
            setupYOLOThenGemini()
        case .yoloBootstrapThenGemini:
            setupYOLOBootstrapThenGemini()
        case .appleVisionBootstrap:
            setupAppleVisionBootstrap()
        case .geminiOnly:
            setupGeminiOnly()
        }

        // Auto-start detection immediately
        visionService.startAnalyzing()
        isDetectionActive = true
        NetworkLogger.shared.info("TIMING: detection armed (\(activePipeline.rawValue)), waiting for camera frames", category: "Detection")
        os_log("TIMING: detection armed, waiting for camera frames")
        print("⏱️ Detection armed (\(activePipeline.displayName)), waiting for camera frames...")
    }

    private func setupGeminiOnly() {
        // Original pipeline: full frame → Gemini every 2s
        cameraManager.enableFrameCapture { image in
            Task {
                let countBefore = visionService.detectedObjects.count
                await visionService.analyzeFrame(image)
                let countAfter = visionService.detectedObjects.count

                // Enqueue new detections for background enrichment
                if countAfter > countBefore {
                    for i in countBefore..<countAfter {
                        enrichmentService.enqueue(visionService.detectedObjects[i])
                    }
                }
            }
        }
    }

    private func setupYOLOThenGemini() {
        // Frame capture for UIImage (needed to crop YOLO bounding boxes)
        cameraManager.enableFrameCapture { image in
            Task { @MainActor in
                latestFrame = image
                visionService.lastAnalyzedFrame = image
            }
        }

        // Pixel buffer capture for YOLO
        cameraManager.enablePixelBufferCapture { pixelBuffer in
            yoloDetector.detect(in: pixelBuffer)
        }
    }

    /// Bootstrap mode: YOLO runs until first Gemini response, then Gemini takes over
    private func setupYOLOBootstrapThenGemini() {
        geminiHasResponded = false
        yoloSeenClasses = []

        // Frame capture for UIImage
        cameraManager.enableFrameCapture { image in
            Task { @MainActor in
                latestFrame = image
                visionService.lastAnalyzedFrame = image

                // Once Gemini has responded, run Gemini analysis on every frame
                if geminiHasResponded {
                    let countBefore = visionService.detectedObjects.count
                    await visionService.analyzeFrame(image)
                    let countAfter = visionService.detectedObjects.count
                    if countAfter > countBefore {
                        for i in countBefore..<countAfter {
                            enrichmentService.enqueue(visionService.detectedObjects[i])
                        }
                    }
                }
            }
        }

        // Pixel buffer capture for YOLO (runs until Gemini takes over)
        cameraManager.enablePixelBufferCapture { pixelBuffer in
            yoloDetector.detect(in: pixelBuffer)
        }

        // Fire off the first Gemini call immediately in parallel
        Task {
            // Wait for a frame to be available
            while latestFrame == nil {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let frame = latestFrame else { return }
            await visionService.analyzeFrame(frame)
            // Once we get here, Gemini has responded — switch over
            await MainActor.run {
                geminiHasResponded = true
                // Stop YOLO pixel buffer capture
                cameraManager.onPixelBufferCaptured = nil
                let count = visionService.detectedObjects.count
                NetworkLogger.shared.info("TIMING: Gemini responded, YOLO bootstrap done. \(count) objects total.", category: "Detection")
                print("🔄 Bootstrap: Gemini responded, YOLO stopped. \(count) objects.")
            }
        }
    }

    /// Apple Vision bootstrap: classifies frames on-device until first Gemini response
    private func setupAppleVisionBootstrap() {
        geminiHasResponded = false
        visionSeenIdentifiers = []

        // Pixel buffer for Apple Vision classification
        cameraManager.enablePixelBufferCapture { pixelBuffer in
            visionClassifier.classify(pixelBuffer: pixelBuffer)
        }

        // Frame capture for UIImage (Gemini + thumbnail storage)
        cameraManager.enableFrameCapture { image in
            Task { @MainActor in
                latestFrame = image
                visionService.lastAnalyzedFrame = image

                // Backfill sourceFrame on detections that were created before the first frame arrived
                var backfilled = 0
                for i in visionService.detectedObjects.indices {
                    if visionService.detectedObjects[i].sourceFrame == nil {
                        visionService.detectedObjects[i].sourceFrame = image
                        backfilled += 1
                    }
                }
                if backfilled > 0 {
                    NetworkLogger.shared.info("BACKFILL: set sourceFrame on \(backfilled) detections", category: "Thumbnail")
                }

                if geminiHasResponded {
                    let countBefore = visionService.detectedObjects.count
                    await visionService.analyzeFrame(image)
                    let countAfter = visionService.detectedObjects.count
                    if countAfter > countBefore {
                        for i in countBefore..<countAfter {
                            enrichmentService.enqueue(visionService.detectedObjects[i])
                        }
                    }
                }
            }
        }

        // Fire first Gemini call in parallel
        Task {
            while latestFrame == nil {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let frame = latestFrame else { return }
            await visionService.analyzeFrame(frame)
            await MainActor.run {
                geminiHasResponded = true
                cameraManager.onPixelBufferCaptured = nil
                let count = visionService.detectedObjects.count
                NetworkLogger.shared.info("TIMING: Gemini responded, Apple Vision bootstrap done. \(count) objects.", category: "Detection")
                print("🔄 Apple Vision bootstrap: Gemini responded, classifier stopped. \(count) objects.")
            }
        }
    }

    /// Reconcile Apple Vision classifications into detectedObjects.
    private func reconcileVisionClassifications(_ classifications: [VisionClassification]) {
        guard isDetectionActive else { return }
        guard !geminiHasResponded else { return }
        guard let frame = latestFrame else { return }

        let now = Date()

        // Expanded skip list filters generic scene/category labels that aren't useful inventory items
        let minimalSkipLabels: Set<String> = ["room", "scene", "indoor", "outdoor", "floor", "wall", "ceiling"]
        let strictSkipLabels: Set<String> = minimalSkipLabels.union([
            "structure", "conveyance", "portal", "material", "people", "adult",
            "housewares", "tool", "interior room", "art", "wood processed",
            "textile", "bedding", "animal", "decoration", "sign", "furniture",
            "building", "plant", "sky", "ground", "person", "nature",
            "food", "drink", "clothing", "fabric", "surface", "container"
        ])
        let skipLabels = DetectionSettings.shared.strictVisionDedup ? strictSkipLabels : minimalSkipLabels

        for cls in classifications {
            guard !visionSeenIdentifiers.contains(cls.identifier) else { continue }
            // Skip generic labels
            guard !skipLabels.contains(cls.identifier.lowercased()) else { continue }

            let newNameLower = cls.displayName.lowercased()

            // Also check existing detectedObjects by name
            let nameExists = visionService.detectedObjects.contains { obj in
                obj.name.lowercased() == newNameLower
            }
            guard !nameExists else {
                visionSeenIdentifiers.insert(cls.identifier)
                continue
            }

            // Substring dedup: skip if new label is a substring of existing or vice versa
            if DetectionSettings.shared.strictVisionDedup {
                let substringDuplicate = visionService.detectedObjects.contains { obj in
                    let existingLower = obj.name.lowercased()
                    return existingLower.contains(newNameLower) || newNameLower.contains(existingLower)
                }
                if substringDuplicate {
                    visionSeenIdentifiers.insert(cls.identifier)
                    continue
                }
            }

            var detection = DetectedObject(name: cls.displayName, timestamp: now)
            detection.yoloClassName = cls.identifier  // reuse field for tracking
            detection.sourceFrame = frame
            NetworkLogger.shared.info("Vision detection '\(cls.displayName)' created with sourceFrame \(Int(frame.size.width))x\(Int(frame.size.height))", category: "Thumbnail")
            // No bounding box — VNClassifyImageRequest doesn't provide boxes

            if visionService.detectedObjects.isEmpty && !visionService.hasLoggedFirstDetection {
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - visionService.analysisStartTime) * 1000)
                NetworkLogger.shared.info("TIMING: FIRST DETECTION (Apple Vision) at t=\(totalMs)ms — \(cls.displayName)", category: "Detection")
                print("⏱️ FIRST DETECTION (Apple Vision) at t=\(totalMs)ms: \(cls.displayName)")
                visionService.hasLoggedFirstDetection = true
            }

            visionService.detectedObjects.append(detection)
            visionSeenIdentifiers.insert(cls.identifier)
            print("🍎 Vision new: \(cls.displayName) [\(String(format: "%.0f%%", cls.confidence * 100))]")
        }
    }

    /// Reconcile YOLO detections with existing tracked objects.
    /// Uses class-name dedup + IOU tracking to prevent duplicates.
    private func reconcileYOLODetections(_ yoloDetections: [YOLODetection]) {
        guard isDetectionActive else { return }
        guard let frame = latestFrame else { return }

        // In bootstrap mode, stop adding YOLO objects once Gemini has responded
        if activePipeline == .yoloBootstrapThenGemini && geminiHasResponded {
            return
        }

        let now = Date()

        for yolo in yoloDetections {
            // --- Class-level dedup: skip if this COCO class already exists ---
            // Check both tracked objects AND existing detectedObjects
            let classAlreadyExists = yoloSeenClasses.contains(yolo.className) ||
                visionService.detectedObjects.contains { obj in
                    obj.yoloClassName == yolo.className ||
                    obj.name.lowercased() == yolo.className.lowercased()
                }

            // --- IOU dedup: find best matching tracked object ---
            var bestKey: String?
            var bestIOU: Float = 0
            for (key, tracked) in yoloTrackedObjects {
                guard tracked.className == yolo.className else { continue }
                let overlap = iou(yolo.boundingBox, tracked.lastBBox)
                if overlap > bestIOU {
                    bestIOU = overlap
                    bestKey = key
                }
            }

            if let key = bestKey, bestIOU > 0.3 {
                // Existing tracked object — just update position
                yoloTrackedObjects[key]?.lastSeen = now
                yoloTrackedObjects[key]?.lastBBox = yolo.boundingBox
            } else if classAlreadyExists {
                // Same class but different position — still a duplicate, just track the bbox
                let trackKey = UUID().uuidString
                yoloTrackedObjects[trackKey] = TrackedYOLOObject(
                    className: yolo.className,
                    lastBBox: yolo.boundingBox,
                    lastSeen: now,
                    detectedObjectID: UUID() // placeholder, no DetectedObject created
                )
            } else {
                // Genuinely new class — create DetectedObject
                let bb = BoundingBox(
                    label: yolo.className,
                    yMin: yolo.boundingBox.origin.y,
                    xMin: yolo.boundingBox.origin.x,
                    yMax: yolo.boundingBox.origin.y + yolo.boundingBox.height,
                    xMax: yolo.boundingBox.origin.x + yolo.boundingBox.width
                )

                let displayName = yolo.className.capitalized
                var detection = DetectedObject(name: displayName, timestamp: now)
                detection.yoloClassName = yolo.className
                detection.boundingBoxes = [bb]
                detection.sourceFrame = frame

                // Log first detection timing
                if visionService.detectedObjects.isEmpty && !visionService.hasLoggedFirstDetection {
                    let totalMs = Int((CFAbsoluteTimeGetCurrent() - visionService.analysisStartTime) * 1000)
                    NetworkLogger.shared.info("TIMING: FIRST DETECTION (YOLO) at t=\(totalMs)ms — \(displayName)", category: "Detection")
                    os_log("TIMING: FIRST DETECTION (YOLO) at t=%dms — %{public}@", totalMs, displayName)
                    print("⏱️ FIRST DETECTION (YOLO) at t=\(totalMs)ms: \(displayName)")
                    visionService.hasLoggedFirstDetection = true
                }

                visionService.detectedObjects.append(detection)
                yoloSeenClasses.insert(yolo.className)

                let trackKey = UUID().uuidString
                yoloTrackedObjects[trackKey] = TrackedYOLOObject(
                    className: yolo.className,
                    lastBBox: yolo.boundingBox,
                    lastSeen: now,
                    detectedObjectID: detection.id
                )

                // Crop and enqueue for Gemini enrichment (hybrid mode only)
                if activePipeline == .yoloThenGemini {
                    if let cropped = cropFrame(frame, bbox: yolo.boundingBox) {
                        enrichmentService.enqueueCrop(detection, croppedImage: cropped)
                    }
                }

                print("✅ YOLO new: \(displayName) [\(String(format: "%.0f%%", yolo.confidence * 100))]")
            }
        }

        // Clean stale tracking entries (>10s not seen)
        let staleKeys = yoloTrackedObjects.keys.filter { key in
            guard let tracked = yoloTrackedObjects[key] else { return true }
            return now.timeIntervalSince(tracked.lastSeen) > 10
        }
        for key in staleKeys {
            yoloTrackedObjects.removeValue(forKey: key)
        }

        // Cap total detections
        if visionService.detectedObjects.count > 200 {
            for i in 0..<(visionService.detectedObjects.count - 200) {
                visionService.detectedObjects[i].sourceFrame = nil
            }
            visionService.detectedObjects.removeFirst(visionService.detectedObjects.count - 200)
        }
    }

    /// Crop a UIImage using a normalized bounding box (0-1) with 15% padding
    private func cropFrame(_ image: UIImage, bbox: CGRect) -> UIImage? {
        let imgW = image.size.width
        let imgH = image.size.height
        let pad: CGFloat = 0.15

        let bx = bbox.origin.x * imgW
        let by = bbox.origin.y * imgH
        let bw = bbox.width * imgW
        let bh = bbox.height * imgH
        let padX = bw * pad
        let padY = bh * pad

        let cropRect = CGRect(
            x: max(bx - padX, 0),
            y: max(by - padY, 0),
            width: min(bw + padX * 2, imgW - max(bx - padX, 0)),
            height: min(bh + padY * 2, imgH - max(by - padY, 0))
        )

        guard let cgImage = image.cgImage else { return nil }

        // Convert UIKit coords to CGImage coords based on orientation
        let cropInCG: CGRect
        let w = image.size.width
        let h = image.size.height
        switch image.imageOrientation {
        case .right:
            cropInCG = CGRect(
                x: cropRect.origin.y,
                y: w - cropRect.origin.x - cropRect.width,
                width: cropRect.height,
                height: cropRect.width
            )
        case .left:
            cropInCG = CGRect(
                x: h - cropRect.origin.y - cropRect.height,
                y: cropRect.origin.x,
                width: cropRect.height,
                height: cropRect.width
            )
        case .down:
            cropInCG = CGRect(
                x: w - cropRect.origin.x - cropRect.width,
                y: h - cropRect.origin.y - cropRect.height,
                width: cropRect.width,
                height: cropRect.height
            )
        default:
            cropInCG = cropRect
        }

        guard let cropped = cgImage.cropping(to: cropInCG) else { return nil }
        return UIImage(cgImage: cropped, scale: 1.0, orientation: image.imageOrientation)
    }

    /// Intersection over Union for two CGRects
    private func iou(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        return Float(intersectionArea / unionArea)
    }

    /// Add any new detections (not yet tracked) to the active session.
    private func addNewDetectionsToSession() {
        guard currentSessionId != nil else { return }
        for detection in visionService.detectedObjects {
            guard !addedDetectionIds.contains(detection.id) else { continue }
            addedDetectionIds.insert(detection.id)
            sessionStore.addItem(from: detection)
            sessionItemCount = sessionStore.activeSessionItemCount
        }
    }

    private func cleanup() {
        // End the detection session
        if currentSessionId != nil {
            // Final sweep to capture any stragglers
            addNewDetectionsToSession()
            sessionStore.endSession()
            currentSessionId = nil
        }

        visionService.stopAnalyzing()
        enrichmentService.cancelAll()
        cameraManager.disableFrameCapture()
        cameraManager.stopSession()
        yoloTrackedObjects.removeAll()
        yoloSeenClasses.removeAll()
        visionSeenIdentifiers.removeAll()
        geminiHasResponded = false
        if useMotionCoaching {
            motionMonitor.stopRecording()
            motionMonitor.stopMonitoring()
        }
    }

    private func toggleDetection() {
        withAnimation {
            isDetectionActive.toggle()

            if isDetectionActive {
                visionService.startAnalyzing()

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } else {
                visionService.stopAnalyzing()

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
    }
    
}

// MARK: - YOLO Tracking Helper

struct TrackedYOLOObject {
    let className: String
    var lastBBox: CGRect
    var lastSeen: Date
    let detectedObjectID: UUID
}

// MARK: - Preview

#Preview {
    LiveObjectDetectionView()
        .environmentObject(InventoryStore())
        .environmentObject(DetectionSessionStore())
}
