//
//  AudioDiagnosticsView.swift
//  V4MinimalApp
//
//  Simple diagnostic view to test audio listening capabilities.
//

import SwiftUI
import AVFoundation
import Speech

struct AudioDiagnosticsView: View {
    @State private var micPermission: String = "Checking..."
    @State private var speechPermission: String = "Checking..."
    @State private var audioSessionCategory: String = "Checking..."
    @State private var audioSessionActive: Bool = false
    @State private var isListening: Bool = false
    @State private var audioLevel: Float = 0.0
    @State private var errorMessage: String?
    @State private var statusLog: [String] = []

    // Simple audio engine for testing
    @State private var audioEngine: AVAudioEngine?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Permissions Section
                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Microphone:")
                            Spacer()
                            Text(micPermission)
                                .foregroundStyle(micPermission == "GRANTED" ? .green : .red)
                                .fontWeight(.medium)
                        }
                        HStack {
                            Text("Speech Recognition:")
                            Spacer()
                            Text(speechPermission)
                                .foregroundStyle(speechPermission == "AUTHORIZED" ? .green : .red)
                                .fontWeight(.medium)
                        }
                    }
                }

                // Audio Session Section
                GroupBox("Audio Session") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Category:")
                            Spacer()
                            Text(audioSessionCategory)
                                .font(.system(.body, design: .monospaced))
                        }
                        HStack {
                            Text("Active:")
                            Spacer()
                            Text(audioSessionActive ? "YES" : "NO")
                                .foregroundStyle(audioSessionActive ? .green : .orange)
                        }
                    }
                }

                // Audio Level Meter
                GroupBox("Microphone Test") {
                    VStack(spacing: 12) {
                        // Level meter
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                Rectangle()
                                    .fill(audioLevel > 0.5 ? Color.red : audioLevel > 0.2 ? Color.yellow : Color.green)
                                    .frame(width: geo.size.width * CGFloat(audioLevel))
                            }
                        }
                        .frame(height: 24)
                        .cornerRadius(4)

                        Text("Level: \(String(format: "%.2f", audioLevel))")
                            .font(.system(.caption, design: .monospaced))

                        // Start/Stop button
                        Button(action: toggleListening) {
                            HStack {
                                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                                Text(isListening ? "Stop Listening" : "Start Listening")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isListening ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                }

                // Error display
                if let error = errorMessage {
                    GroupBox("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                // Status log
                GroupBox("Log") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(statusLog.indices, id: \.self) { index in
                            Text(statusLog[index])
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if statusLog.isEmpty {
                            Text("No log entries yet")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Actions
                GroupBox("Actions") {
                    VStack(spacing: 8) {
                        Button("Request Permissions") {
                            Task { await requestPermissions() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Refresh Status") {
                            checkStatus()
                        }
                        .buttonStyle(.bordered)

                        Button("Clear Log") {
                            statusLog.removeAll()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle("Audio Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            log("View appeared")
            checkStatus()
        }
        .onDisappear {
            stopListening()
        }
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        statusLog.append("[\(timestamp)] \(message)")
        appBootLog.infoWithContext("[AudioDiag] \(message)")

        // Keep log from growing too large
        if statusLog.count > 50 {
            statusLog.removeFirst()
        }
    }

    private func checkStatus() {
        log("Checking status...")

        let session = AVAudioSession.sharedInstance()

        // Check mic permission
        switch session.recordPermission {
        case .granted: micPermission = "GRANTED"
        case .denied: micPermission = "DENIED"
        case .undetermined: micPermission = "NOT ASKED"
        @unknown default: micPermission = "UNKNOWN"
        }

        // Check speech permission
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechPermission = "AUTHORIZED"
        case .denied: speechPermission = "DENIED"
        case .restricted: speechPermission = "RESTRICTED"
        case .notDetermined: speechPermission = "NOT ASKED"
        @unknown default: speechPermission = "UNKNOWN"
        }

        // Check audio session
        audioSessionCategory = session.category.rawValue
            .replacingOccurrences(of: "AVAudioSessionCategory", with: "")
        audioSessionActive = session.isOtherAudioPlaying == false // rough proxy

        log("Mic: \(micPermission), Speech: \(speechPermission)")
    }

    private func requestPermissions() async {
        log("Requesting permissions...")

        let session = AVAudioSession.sharedInstance()

        // Request mic permission
        if session.recordPermission == .undetermined {
            log("Requesting microphone permission...")
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            log("Microphone permission: \(granted ? "GRANTED" : "DENIED")")
        }

        // Request speech permission
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            log("Requesting speech recognition permission...")
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            log("Speech permission: \(status == .authorized ? "AUTHORIZED" : "DENIED")")
        }

        checkStatus()
    }

    private func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func startListening() {
        log("Starting audio capture...")
        errorMessage = nil

        do {
            let session = AVAudioSession.sharedInstance()

            // Configure audio session
            log("Configuring audio session...")
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            log("Audio session activated")

            // Create audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            log("Input format: \(format.sampleRate)Hz, \(format.channelCount) channels")

            // Install tap to monitor audio levels
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
                // Calculate RMS level
                let channelData = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)

                var sum: Float = 0
                if let data = channelData {
                    for i in 0..<frameLength {
                        sum += data[i] * data[i]
                    }
                }
                let rms = sqrt(sum / Float(frameLength))
                let level = min(1.0, rms * 5) // Scale up for visibility

                DispatchQueue.main.async {
                    self.audioLevel = level
                }
            }

            // Start engine
            try engine.start()
            log("Audio engine started")

            self.audioEngine = engine
            isListening = true

        } catch {
            log("ERROR: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func stopListening() {
        guard isListening else { return }

        log("Stopping audio capture...")

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        isListening = false
        audioLevel = 0

        log("Audio engine stopped")
    }
}

#Preview {
    NavigationStack {
        AudioDiagnosticsView()
    }
}
