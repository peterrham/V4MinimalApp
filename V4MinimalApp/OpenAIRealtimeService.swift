//
//  OpenAIRealtimeService.swift
//  V4MinimalApp
//
//  WebSocket service for OpenAI Realtime API (GPT-4o voice conversations)
//

import Foundation
import AVFoundation

// MARK: - Supporting Types

enum RealtimeConnectionState: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case error = "Error"

    var color: String {
        switch self {
        case .disconnected: return "secondary"
        case .connecting: return "orange"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}

struct RealtimeTimingMetrics {
    var wsConnectStartTime: Date?
    var wsConnectedTime: Date?
    var wsConnectDurationMs: Int? {
        guard let start = wsConnectStartTime, let end = wsConnectedTime else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }

    var firstAudioSentTime: Date?
    var firstResponseDeltaTime: Date?
    var ttfbMs: Int? {
        guard let sent = firstAudioSentTime, let delta = firstResponseDeltaTime else { return nil }
        return Int(delta.timeIntervalSince(sent) * 1000)
    }

    var totalAudioBytesSent: Int = 0
    var totalAudioChunksSent: Int = 0
    var totalResponseDeltasReceived: Int = 0
    var totalResponseBytesReceived: Int = 0

    var responseStartTime: Date?
    var responseCompleteTime: Date?
    var totalResponseTimeMs: Int? {
        guard let start = responseStartTime, let end = responseCompleteTime else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }

    var lastEventTime: Date?
}

struct RealtimeLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let direction: Direction
    let eventType: String
    let detail: String

    enum Direction: String {
        case sent = "sent"
        case received = "received"
        case system = "system"

        var arrow: String {
            switch self {
            case .sent: return "\u{2191}" // up arrow
            case .received: return "\u{2193}" // down arrow
            case .system: return "\u{25CF}" // bullet
            }
        }
    }
}

// MARK: - OpenAI Realtime Service

@MainActor
class OpenAIRealtimeService: ObservableObject {

    // MARK: - Published State

    @Published var connectionState: RealtimeConnectionState = .disconnected
    @Published var userTranscript: String = ""
    @Published var assistantTranscript: String = ""
    @Published var isRecording: Bool = false
    @Published var error: String?
    @Published var timingMetrics = RealtimeTimingMetrics()
    @Published var eventLog: [RealtimeLogEntry] = []

    // MARK: - Private

    private let apiKey: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Recording engine (created on-demand in startRecording, torn down in stopRecording)
    private var recordingEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    // Playback engine (created when first audio delta arrives, torn down on next recording)
    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playbackFormat: AVAudioFormat?  // Set to mixer's native rate

    // MARK: - Initialization

    init() {
        if let key = Self.loadFromInfoPlist(), !key.isEmpty {
            self.apiKey = key
            NetworkLogger.shared.info("OpenAI Realtime API key loaded from Info.plist (length: \(key.count))", category: "OpenAI-Realtime")
        } else if let key = Self.loadFromConfig(), !key.isEmpty {
            self.apiKey = key
            NetworkLogger.shared.info("OpenAI Realtime API key loaded from Config.plist (length: \(key.count))", category: "OpenAI-Realtime")
        } else if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            self.apiKey = key
            NetworkLogger.shared.info("OpenAI Realtime API key loaded from environment (length: \(key.count))", category: "OpenAI-Realtime")
        } else {
            self.apiKey = ""
            NetworkLogger.shared.error("OpenAI Realtime API key not found in any source", category: "OpenAI-Realtime")
        }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - API Key Loading

    private static func loadFromInfoPlist() -> String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else {
            return nil
        }
        return key
    }

    private static func loadFromConfig() -> String? {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let config = NSDictionary(contentsOfFile: path),
              let key = config["OpenAIAPIKey"] as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }

    // MARK: - Connection

    func connect() {
        guard !apiKey.isEmpty else {
            error = "OpenAI API key not configured"
            connectionState = .error
            NetworkLogger.shared.error("Cannot connect: API key not configured", category: "OpenAI-Realtime")
            return
        }

        guard connectionState == .disconnected || connectionState == .error else { return }

        connectionState = .connecting
        timingMetrics = RealtimeTimingMetrics()
        timingMetrics.wsConnectStartTime = Date()
        userTranscript = ""
        assistantTranscript = ""
        error = nil

        addLog(.system, "session.connecting", "Opening WebSocket...")
        NetworkLogger.shared.info("WebSocket connecting...", category: "OpenAI-Realtime")

        // Configure audio session FIRST, before creating any AVAudioEngine
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
            NetworkLogger.shared.info("Audio session configured: playAndRecord, speaker output, volume=\(audioSession.outputVolume)", category: "OpenAI-Realtime")
        } catch {
            self.error = "Audio session setup failed: \(error.localizedDescription)"
            connectionState = .error
            NetworkLogger.shared.error("Audio session setup failed: \(error.localizedDescription)", category: "OpenAI-Realtime")
            return
        }

        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview") else {
            error = "Invalid WebSocket URL"
            connectionState = .error
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        request.timeoutInterval = 30

        let session = URLSession(configuration: .default)
        self.urlSession = session
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        receiveMessages()

        // Connection timeout
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if connectionState == .connecting {
                error = "Connection timeout"
                connectionState = .error
                addLog(.system, "session.timeout", "WebSocket connection timed out")
                NetworkLogger.shared.error("WebSocket connection timed out", category: "OpenAI-Realtime")
                webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
            }
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        stopRecording()
        teardownPlaybackEngine()

        connectionState = .disconnected
        addLog(.system, "session.disconnected", "WebSocket closed")
        NetworkLogger.shared.info("WebSocket disconnected", category: "OpenAI-Realtime")
    }

    // MARK: - Session Configuration

    private func sendSessionConfig() {
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": "You are a helpful, enthusiastic assistant. Speak quickly and energetically with natural inflection, like a lively conversation. Keep responses short and punchy. Always respond in English.",
                "voice": "shimmer",
                "temperature": 1,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "whisper-1",
                    "language": "en"
                ],
                "turn_detection": NSNull()
            ]
        ]

        sendJSON(config, eventType: "session.update")
    }

    // MARK: - Audio Recording (Own Mic)

    func startRecording() {
        guard connectionState == .connected else { return }
        guard !isRecording else { return }

        NetworkLogger.shared.info("startRecording: begin", category: "OpenAI-Realtime")

        // Tear down any playback engine from previous response
        teardownPlaybackEngine()

        // Create a fresh engine for this recording session
        let engine = AVAudioEngine()
        self.recordingEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        NetworkLogger.shared.info("startRecording: inputFormat = \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch", category: "OpenAI-Realtime")

        // Validate input format
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            NetworkLogger.shared.error("startRecording: invalid input format, aborting", category: "OpenAI-Realtime")
            return
        }

        // Use a known-safe format for the tap: mono Float32 at the device sample rate
        guard let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false) else {
            NetworkLogger.shared.error("startRecording: failed to create tap format", category: "OpenAI-Realtime")
            return
        }

        // Setup converter: tap format -> PCM16 24kHz mono
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
        audioConverter = AVAudioConverter(from: tapFormat, to: outputFormat)
        audioConverter?.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converterInputFormat = tapFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            // Copy buffer data immediately on the audio thread
            guard let copy = Self.copyBuffer(buffer) else { return }
            Task { @MainActor [weak self] in
                self?.processAndSendAudioBuffer(copy)
            }
        }

        // Start engine with the tap installed
        do {
            try engine.start()
            isRecording = true
            userTranscript = ""
            assistantTranscript = ""
            timingMetrics.firstAudioSentTime = nil
            timingMetrics.firstResponseDeltaTime = nil
            timingMetrics.totalAudioBytesSent = 0
            timingMetrics.totalAudioChunksSent = 0
            timingMetrics.totalResponseDeltasReceived = 0
            timingMetrics.totalResponseBytesReceived = 0
            addLog(.system, "recording.started", "Microphone active")
            NetworkLogger.shared.info("Recording started (tap format: \(tapFormat.sampleRate)Hz)", category: "OpenAI-Realtime")
        } catch {
            NetworkLogger.shared.error("Failed to restart engine with tap: \(error.localizedDescription)", category: "OpenAI-Realtime")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        if let engine = recordingEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        recordingEngine = nil

        isRecording = false
        addLog(.system, "recording.stopped", "Microphone off")
        NetworkLogger.shared.info("Recording stopped", category: "OpenAI-Realtime")

        // Commit audio and request response
        if connectionState == .connected {
            commitAndRequestResponse()
        }
    }

    // MARK: - External Audio Buffer (from SpeechRecognition pipe)

    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard connectionState == .connected else { return }
        processAndSendAudioBuffer(buffer)
    }

    // MARK: - Audio Conversion & Sending

    private func processAndSendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let inputFormat = buffer.format
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!

        // Create or reuse converter
        if audioConverter == nil || converterInputFormat != inputFormat {
            audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
            audioConverter?.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            converterInputFormat = inputFormat
        }

        guard let converter = audioConverter else { return }

        // Calculate output frame count
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return }

        var conversionError: NSError?
        var consumed = false
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil else {
            NetworkLogger.shared.error("Audio conversion error: \(conversionError?.localizedDescription ?? "unknown")", category: "OpenAI-Realtime")
            return
        }

        // Extract PCM16 bytes
        guard let int16Data = outputBuffer.int16ChannelData else { return }
        let byteCount = Int(outputBuffer.frameLength) * 2 // 2 bytes per Int16 sample
        let data = Data(bytes: int16Data[0], count: byteCount)
        let base64Audio = data.base64EncodedString()

        // Track timing
        if timingMetrics.firstAudioSentTime == nil {
            timingMetrics.firstAudioSentTime = Date()
        }
        timingMetrics.totalAudioBytesSent += byteCount
        timingMetrics.totalAudioChunksSent += 1

        // Send to WebSocket
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio
        ]
        sendJSON(event, eventType: "input_audio_buffer.append", logDetail: "\(byteCount)B chunk #\(timingMetrics.totalAudioChunksSent)")
    }

    // MARK: - Commit & Response

    func commitAndRequestResponse() {
        sendJSON(["type": "input_audio_buffer.commit"], eventType: "input_audio_buffer.commit")
        sendJSON(["type": "response.create"], eventType: "response.create")
        timingMetrics.responseStartTime = Date()
        NetworkLogger.shared.info("Audio committed, response requested", category: "OpenAI-Realtime")
    }

    // MARK: - WebSocket Sending

    private func sendJSON(_ dict: [String: Any], eventType: String, logDetail: String? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        // Only log non-audio events or summary for audio
        if eventType != "input_audio_buffer.append" {
            addLog(.sent, eventType, logDetail ?? "")
        }

        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                Task { @MainActor [weak self] in
                    self?.addLog(.system, "send.error", error.localizedDescription)
                    NetworkLogger.shared.error("WebSocket send error: \(error.localizedDescription)", category: "OpenAI-Realtime")
                }
            }
        }
    }

    // MARK: - WebSocket Receiving

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleServerEvent(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleServerEvent(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue receiving
                    self.receiveMessages()

                case .failure(let error):
                    if self.connectionState == .connected || self.connectionState == .connecting {
                        self.error = "WebSocket error: \(error.localizedDescription)"
                        self.connectionState = .error
                        self.addLog(.system, "ws.error", error.localizedDescription)
                        NetworkLogger.shared.error("WebSocket receive error: \(error.localizedDescription)", category: "OpenAI-Realtime")
                    }
                }
            }
        }
    }

    // MARK: - Server Event Handling

    private func handleServerEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        timingMetrics.lastEventTime = Date()

        switch type {
        case "session.created":
            let connectMs = timingMetrics.wsConnectDurationMs ?? 0
            timingMetrics.wsConnectedTime = Date()
            connectionState = .connected
            addLog(.received, type, "Connected in \(timingMetrics.wsConnectDurationMs ?? 0)ms")
            NetworkLogger.shared.info("WebSocket connected in \(timingMetrics.wsConnectDurationMs ?? 0)ms", category: "OpenAI-Realtime")
            sendSessionConfig()

        case "session.updated":
            addLog(.received, type, "Session configured")
            NetworkLogger.shared.info("Session configuration applied", category: "OpenAI-Realtime")

        case "response.audio.delta":
            if let delta = json["delta"] as? String {
                // Track TTFB on first audio delta
                if timingMetrics.firstResponseDeltaTime == nil {
                    timingMetrics.firstResponseDeltaTime = Date()
                    let ttfb = timingMetrics.ttfbMs ?? 0
                    NetworkLogger.shared.info("TTFB: \(ttfb)ms (first audio delta received)", category: "OpenAI-Realtime")
                }
                timingMetrics.totalResponseDeltasReceived += 1
                let decodedBytes = Data(base64Encoded: delta)?.count ?? 0
                timingMetrics.totalResponseBytesReceived += decodedBytes

                // Play audio
                playAudioDelta(delta)
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                assistantTranscript += delta
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                userTranscript = transcript
                addLog(.received, type, "User: \(transcript.prefix(80))")
                NetworkLogger.shared.info("User transcript: \(transcript.prefix(100))", category: "OpenAI-Realtime")
            }

        case "response.audio_transcript.done":
            if let transcript = json["transcript"] as? String {
                addLog(.received, type, "Assistant: \(transcript.prefix(80))")
            }

        case "response.done":
            timingMetrics.responseCompleteTime = Date()
            let totalMs = timingMetrics.totalResponseTimeMs ?? 0
            let deltas = timingMetrics.totalResponseDeltasReceived
            let bytes = timingMetrics.totalResponseBytesReceived
            addLog(.received, type, "\(totalMs)ms, \(deltas) deltas, \(bytes)B")
            NetworkLogger.shared.info("Response complete: \(totalMs)ms total, \(deltas) deltas, \(bytes)B received", category: "OpenAI-Realtime")

            // Log usage if present
            if let usage = json["usage"] as? [String: Any] {
                let inputTokens = usage["input_tokens"] as? Int ?? 0
                let outputTokens = usage["output_tokens"] as? Int ?? 0
                NetworkLogger.shared.info("Usage: \(inputTokens) input, \(outputTokens) output tokens", category: "OpenAI-Realtime")
            }

        case "error":
            let errorObj = json["error"] as? [String: Any]
            let message = errorObj?["message"] as? String ?? "Unknown error"
            self.error = message
            addLog(.received, type, message)
            NetworkLogger.shared.error("Server error: \(message)", category: "OpenAI-Realtime")

        case "input_audio_buffer.speech_started":
            addLog(.received, type, "Speech detected")

        case "input_audio_buffer.speech_stopped":
            addLog(.received, type, "Speech ended")

        case "input_audio_buffer.committed":
            addLog(.received, type, "Audio buffer committed")

        case "response.created":
            addLog(.received, type, "Response generation started")
            timingMetrics.responseStartTime = Date()

        case "response.output_item.added",
             "conversation.item.created",
             "response.content_part.added",
             "response.content_part.done",
             "response.output_item.done":
            // Minor lifecycle events — log but don't surface
            break

        default:
            addLog(.received, type, "")
        }
    }

    // MARK: - Playback Engine

    /// Start a dedicated playback engine on first audio delta
    private func ensurePlaybackEngine() {
        guard playbackEngine == nil else { return }

        // Re-apply speaker override
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        // Connect player at mixer's native rate to avoid AVAudioEngine resampling issues
        let mixerRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: mixerRate, channels: 1, interleaved: false)!
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        self.playbackFormat = fmt

        do {
            try engine.start()
            player.play()
            self.playbackEngine = engine
            self.playerNode = player
            NetworkLogger.shared.info("Playback engine started (Float32 \(mixerRate)Hz, streaming)", category: "OpenAI-Realtime")
        } catch {
            NetworkLogger.shared.error("Failed to start playback engine: \(error.localizedDescription)", category: "OpenAI-Realtime")
        }
    }

    private func teardownPlaybackEngine() {
        playerNode?.stop()
        playbackEngine?.stop()
        playerNode = nil
        playbackEngine = nil
        playbackFormat = nil
    }

    private func playAudioDelta(_ base64String: String) {
        guard let data = Data(base64Encoded: base64String) else {
            NetworkLogger.shared.error("playAudioDelta: base64 decode failed", category: "OpenAI-Realtime")
            return
        }

        // Create playback engine on first delta (recording engine is already torn down)
        ensurePlaybackEngine()

        guard let player = playerNode, let engine = playbackEngine, engine.isRunning,
              let outFmt = playbackFormat else {
            NetworkLogger.shared.error("playAudioDelta: playback engine not ready", category: "OpenAI-Realtime")
            return
        }

        if !player.isPlaying {
            player.play()
        }

        // Decode PCM16 Int16 samples from 24kHz source
        let srcFrameCount = data.count / 2
        guard srcFrameCount > 0 else { return }

        // Upsample 24kHz → output rate (e.g. 44100Hz) via linear interpolation
        let outputRate = outFmt.sampleRate
        let srcRate = 24000.0
        let ratio = outputRate / srcRate
        let dstFrameCount = Int(Double(srcFrameCount) * ratio)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: AVAudioFrameCount(dstFrameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(dstFrameCount)

        guard let floatData = buffer.floatChannelData else { return }
        let gain: Float = 1.8  // Boost to match ChatGPT native app loudness
        data.withUnsafeBytes { rawBuf in
            let int16Ptr = rawBuf.bindMemory(to: Int16.self)
            let srcCount = int16Ptr.count
            for i in 0..<dstFrameCount {
                let srcPos = Double(i) / ratio
                let idx = Int(srcPos)
                let frac = Float(srcPos - Double(idx))
                let s0 = Float(int16Ptr[min(idx, srcCount - 1)]) / 32768.0
                let s1 = Float(int16Ptr[min(idx + 1, srcCount - 1)]) / 32768.0
                let sample = (s0 + (s1 - s0) * frac) * gain
                floatData[0][i] = min(max(sample, -1.0), 1.0) // Clamp to prevent clipping
            }
        }

        player.scheduleBuffer(buffer)

        let deltaNum = timingMetrics.totalResponseDeltasReceived
        if deltaNum <= 3 || deltaNum % 50 == 0 {
            NetworkLogger.shared.debug("playAudioDelta #\(deltaNum): \(srcFrameCount)→\(dstFrameCount) frames (\(srcRate)→\(outputRate)Hz)", category: "OpenAI-Realtime")
        }
    }

    // MARK: - Buffer Copy (audio thread safe)

    /// Copies an AVAudioPCMBuffer so it can be safely sent across threads.
    /// The original buffer from an audio tap is reused by the system.
    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        let channelCount = Int(buffer.format.channelCount)
        if let srcFloat = buffer.floatChannelData, let dstFloat = copy.floatChannelData {
            let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
            for ch in 0..<channelCount {
                memcpy(dstFloat[ch], srcFloat[ch], bytes)
            }
        } else if let srcInt16 = buffer.int16ChannelData, let dstInt16 = copy.int16ChannelData {
            let bytes = Int(buffer.frameLength) * MemoryLayout<Int16>.size
            for ch in 0..<channelCount {
                memcpy(dstInt16[ch], srcInt16[ch], bytes)
            }
        } else if let srcInt32 = buffer.int32ChannelData, let dstInt32 = copy.int32ChannelData {
            let bytes = Int(buffer.frameLength) * MemoryLayout<Int32>.size
            for ch in 0..<channelCount {
                memcpy(dstInt32[ch], srcInt32[ch], bytes)
            }
        } else {
            return nil
        }

        return copy
    }

    // MARK: - Event Log

    private func addLog(_ direction: RealtimeLogEntry.Direction, _ eventType: String, _ detail: String) {
        let entry = RealtimeLogEntry(timestamp: Date(), direction: direction, eventType: eventType, detail: detail)
        eventLog.append(entry)
        // Keep last 200 entries
        if eventLog.count > 200 {
            eventLog.removeFirst(eventLog.count - 200)
        }
    }

    func clearLog() {
        eventLog.removeAll()
    }
}
