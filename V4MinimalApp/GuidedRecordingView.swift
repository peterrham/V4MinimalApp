//
//  GuidedRecordingView.swift
//  V4MinimalApp
//
//  Guided video recording with real-time motion feedback.
//  Uses accelerometer/gyroscope to coach the user on pan speed and steadiness.
//  Tracks yaw coverage to show a 360° completion ring.
//

import SwiftUI
import CoreMotion
import Combine

// MARK: - Motion Monitor

@MainActor
class RecordingMotionMonitor: ObservableObject {

    @Published var rotationRate: Double = 0       // degrees/sec
    @Published var speedLevel: SpeedLevel = .still
    @Published var hint: String = "Point at the room and tap Record"
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    // Coverage: 36 segments of 10° each = 360°
    static let segmentCount = 36
    @Published var coveredSegments: Set<Int> = []
    @Published var coveragePercent: Double = 0
    @Published var completedFullCircle = false

    enum SpeedLevel: String {
        case tooFast = "Slow down"
        case good = "Good speed"
        case tooSlow = "Keep moving"
        case still = "Start panning"

        var color: Color {
            switch self {
            case .tooFast: return .red
            case .good: return .green
            case .tooSlow: return .yellow
            case .still: return .secondary
            }
        }
    }

    private let motionManager = CMMotionManager()
    private var recordingStart: Date?
    private var durationTimer: Timer?
    private var initialYaw: Double?

    // Thresholds (degrees/sec)
    private let tooFastThreshold: Double = 60
    private let goodMinThreshold: Double = 8
    private let stillThreshold: Double = 3

    func startMonitoring() {
        guard motionManager.isDeviceMotionAvailable else {
            hint = "Motion sensors unavailable"
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        // Use xArbitraryZVertical so yaw is relative to starting orientation
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            Task { @MainActor in
                self.processMotion(motion)
            }
        }
    }

    func stopMonitoring() {
        motionManager.stopDeviceMotionUpdates()
        durationTimer?.invalidate()
        durationTimer = nil
    }

    func startRecording() {
        isRecording = true
        recordingStart = Date()
        initialYaw = nil
        coveredSegments.removeAll()
        coveragePercent = 0
        completedFullCircle = false
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStart else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    func stopRecording() {
        isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStart = nil
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        let rate = motion.rotationRate
        let totalRadPerSec = sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z)
        let degPerSec = totalRadPerSec * (180.0 / .pi)

        // Smooth with low-pass filter
        rotationRate = rotationRate * 0.7 + degPerSec * 0.3

        if !isRecording {
            speedLevel = .still
            hint = "Point at the room and tap Record"
            return
        }

        // Track yaw coverage
        let yawRad = motion.attitude.yaw  // -π to π
        if initialYaw == nil {
            initialYaw = yawRad
        }

        // Compute relative yaw from start (0-360)
        let relativeYaw = (yawRad - (initialYaw ?? 0)) * (180.0 / .pi)
        // Normalize to 0-360
        let normalized = ((relativeYaw.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let segment = Int(normalized / (360.0 / Double(Self.segmentCount)))
            % Self.segmentCount

        let wasComplete = completedFullCircle
        coveredSegments.insert(segment)
        coveragePercent = Double(coveredSegments.count) / Double(Self.segmentCount) * 100

        if coveredSegments.count == Self.segmentCount && !wasComplete {
            completedFullCircle = true
        }

        // Speed + coverage hints
        if rotationRate > tooFastThreshold {
            speedLevel = .tooFast
            hint = "Slow down — too fast for clear frames"
        } else if completedFullCircle && !wasComplete {
            speedLevel = .good
            hint = "Full circle! You can stop or keep going"
        } else if rotationRate >= goodMinThreshold {
            speedLevel = .good
            if coveragePercent < 50 {
                hint = "Good — keep panning around"
            } else if coveragePercent < 90 {
                hint = "Good — almost there"
            } else {
                hint = "Good — nearly full coverage"
            }
        } else if rotationRate >= stillThreshold {
            speedLevel = .tooSlow
            hint = "A bit slow — keep panning"
        } else {
            speedLevel = .still
            if completedFullCircle {
                hint = "Full circle complete — tap stop when done"
            } else {
                hint = "Pan the camera around the room"
            }
        }
    }
}

// MARK: - Guided Recording View

struct GuidedRecordingView: View {
    @StateObject private var monitor = RecordingMotionMonitor()
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var yoloDetector = YOLODetector()
    @State private var isRecording = false
    @State private var uniqueClassNames: Set<String> = []

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()

            // HUD overlay
            VStack {
                hudBar
                    .padding(.top, 8)

                Spacer()

                // Coverage ring + hint
                ZStack {
                    if monitor.isRecording {
                        coverageRing
                            .frame(width: 140, height: 140)
                    }

                    VStack(spacing: 6) {
                        Text(monitor.hint)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 4)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .animation(.easeInOut(duration: 0.3), value: monitor.hint)

                        if monitor.isRecording && !uniqueClassNames.isEmpty {
                            Text(uniqueClassNames.sorted().joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .offset(y: monitor.isRecording ? 100 : 0)
                }

                Spacer()

                speedGauge
                    .padding(.bottom, 8)

                recordButton
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            cameraManager.startSession()
            monitor.startMonitoring()
            cameraManager.enablePixelBufferCapture { [weak yoloDetector] buffer in
                yoloDetector?.detect(in: buffer)
            }
        }
        .onDisappear {
            if isRecording {
                cameraManager.stopRecording()
            }
            cameraManager.disableFrameCapture()
            monitor.stopMonitoring()
            cameraManager.stopSession()
        }
        .onReceive(yoloDetector.$detections) { newDetections in
            guard monitor.isRecording else { return }
            for det in newDetections {
                uniqueClassNames.insert(det.className)
            }
        }
        .navigationTitle("Guided Recording")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Coverage Ring

    private var coverageRing: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 6)

            // Covered segments
            ForEach(0..<RecordingMotionMonitor.segmentCount, id: \.self) { i in
                let startAngle = Angle(degrees: Double(i) * (360.0 / Double(RecordingMotionMonitor.segmentCount)) - 90)
                let endAngle = Angle(degrees: Double(i + 1) * (360.0 / Double(RecordingMotionMonitor.segmentCount)) - 90)

                if monitor.coveredSegments.contains(i) {
                    ArcSegment(startAngle: startAngle, endAngle: endAngle)
                        .stroke(
                            monitor.completedFullCircle ? .green : .cyan,
                            lineWidth: 6
                        )
                }
            }

            // Center text
            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", monitor.coveragePercent))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundColor(.white)
                if monitor.completedFullCircle {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
        }
    }

    // MARK: - HUD Bar

    private var hudBar: some View {
        HStack(spacing: 16) {
            if monitor.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("REC")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                    Text(formatDuration(monitor.recordingDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)
                }

                HStack(spacing: 4) {
                    Image(systemName: "cube.box.fill")
                        .font(.caption2)
                    Text("\(uniqueClassNames.count) items")
                        .font(.caption.bold().monospacedDigit())
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.5)))
            }

            Spacer()

            Text(String(format: "%.0f°/s", monitor.rotationRate))
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.black.opacity(0.4))
    }

    // MARK: - Speed Gauge

    private var speedGauge: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(monitor.speedLevel.color)
                        .frame(width: gaugeWidth(in: geo.size.width))
                        .animation(.easeOut(duration: 0.15), value: monitor.rotationRate)
                }
            }
            .frame(height: 8)

            HStack {
                Text("still")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(monitor.speedLevel.rawValue)
                    .font(.caption2.bold())
                    .foregroundColor(monitor.speedLevel.color)
                Spacer()
                Text("fast")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 40)
    }

    private func gaugeWidth(in totalWidth: CGFloat) -> CGFloat {
        let normalized = min(monitor.rotationRate / 90.0, 1.0)
        return max(totalWidth * normalized, 4)
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            if isRecording {
                isRecording = false
                monitor.stopRecording()
                cameraManager.stopRecording()
            } else {
                isRecording = true
                uniqueClassNames.removeAll()
                monitor.startRecording()
                cameraManager.startRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)

                if isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 60, height: 60)
                }
            }
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Arc Segment Shape

struct ArcSegment: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
