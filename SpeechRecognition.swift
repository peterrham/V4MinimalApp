import SwiftUI
import CoreData
import AVFoundation
import Speech
import Foundation

/*
func logWithTimestamp(_ string: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("[\(timestamp)] \(string)")
}
 */

// MARK: - Speech Recognition Manager

@MainActor
class SpeechRecognitionManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let context: NSManagedObjectContext
    
    // Persistent audio file storage
    private var audioFileURL: URL?
    private var audioFileHandle: FileHandle?

    private var wavFileURL: URL?
    private var wavAudioFile: AVAudioFile?
    
    // Google Drive incremental upload support
    private var driveUploader = GoogleDriveUploader()
    private var driveChunkBuffer = Data()
    // Increased to produce much longer Google Drive audio file uploads (streaming style)
    private let driveChunkSizeBytes: Int = 5 * 1024 * 1024 // 5 MB for longer audio chunks
    // Increased to produce much longer Google Drive audio file uploads (streaming style)
    private let driveFlushInterval: TimeInterval = 30.0 // seconds (longer duration per upload)
    private var driveBaseFilename: String = "rawAudio-\(Int(Date().timeIntervalSince1970))"
    private var lastDriveFlushTime: Date = Date()
    
    // Verbose logging control for audio tap
    private let enableAudioTapVerboseLogging: Bool = false

    private func makeAudioFileURL() -> URL? {
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let filename = "rawAudio-\(Int(Date().timeIntervalSince1970)).pcm"
            return docs.appendingPathComponent(filename)
        } catch {
            appBootLog.errorWithContext("Failed to get Documents directory: \(error.localizedDescription)")
            return nil
        }
    }
    
    // this is the text that we add together until we get a stop word
    
    private var  accumulatedText: String = ""
    
    // this is the text from the last good recognition result
    private var  previousText: String = ""
    
    
    
    @Published var incrementalText: String = ""  // Shows incremental speech as it's recognized
    @Published var finalText: String = ""        // Shows finalized speech after "stop" is detected
    
    // Silence detection timer
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 12.0  // Adjust as needed
    
    
    
    /**
     Initializes SpeechRecognitionManager.
     
     - Parameters:
       - context: Core Data managed object context.
     
     Note: Removed scenePhase observer from initializer. To flush audio on app background/inactive,
     call `flushPendingAudioToDrive(sampleRate:)` from your view's `.onChange(of: scenePhase)` closure,
     passing the appropriate sample rate.
     */
    init(context: NSManagedObjectContext) {
        
        appBootLog.infoWithContext("App launched: SpeechRecognitionManager initialized")
        
        appBootLog.infoWithContext("inside init()")
        self.context = context
        requestMicrophonePermission()
        startListening()
    }
    
    func setupAudioSessionObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption(_:)), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
    }
    
    @objc func handleAudioSessionInterruption(_ notification: Notification) {
        
        detailedLog(string: "handleAudioSessionInterruption")
        guard let userInfo = notification.userInfo,
              let interruptionTypeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue) else {
            return
        }
        
        if interruptionType == .began {
            detailedLog(string: "Audio session interruption began. Pausing recognition.")
            recognitionTask?.cancel() // Cancel the task if an interruption begins
        } else if interruptionType == .ended {
            detailedLog(string: "Audio session interruption ended.")
        }
    }
    
    
    
    let index = 0;
    
    func printTranscriptionSegments(transcription: SFTranscription) {
        for (index, segment) in transcription.segments.enumerated() {
            appBootLog.infoWithContext("<<<<<<<<<<<<<<<<<<<<<<<<")
            appBootLog.infoWithContext("index: \(index)")
            appBootLog.infoWithContext("Text: \(segment.substring)")
            appBootLog.infoWithContext("Range: \(segment.substringRange)")
            appBootLog.infoWithContext("Timestamp: \(segment.timestamp) seconds")
            appBootLog.infoWithContext("Duration: \(segment.duration) seconds")
            appBootLog.infoWithContext("Confidence: \(segment.confidence)")
            appBootLog.infoWithContext("-----------------------")
            
            if (index == 0) {
                if segment.timestamp == 0 {
                    appBootLog.infoWithContext("ignore this one")
                } else {
                    appBootLog.infoWithContext("keep this one")
                }
            }
        }
    }
    
    func detailedLog(string: String) {
        appBootLog.debugWithContext(string)
    }
    
    func processRecognitionResult(recognitionResult: SFSpeechRecognitionResult?, error: Error?)
    {
        appBootLog.debugWithContext("got recognition result")
        
        
        if false {
            
            appBootLog.debugWithContext("recognitionTask: \(self.recognitionTask)")
            appBootLog.debugWithContext("recognitionTask.state: \(self.recognitionTask!.state)")
            
            // detailedLog(string: recognitionTask!)
            
            appBootLog.debugWithContext("Recognition Task Properties:")
            appBootLog.debugWithContext("----------------------------")
            appBootLog.debugWithContext("State: \(recognitionTask!.state)")
            appBootLog.debugWithContext("Is Finishing: \(recognitionTask!.isFinishing)")
            appBootLog.debugWithContext("Is Cancelled: \(recognitionTask!.isCancelled)")
            
            // Print the current state of the task
            appBootLog.debugWithContext("Recognition Task State:")
            switch recognitionTask!.state {
            case .starting:
                appBootLog.debugWithContext("The task is starting.")
            case .running:
                appBootLog.debugWithContext("The task is running.")
            case .finishing:
                appBootLog.debugWithContext("The task is finishing.")
            case .canceling:
                appBootLog.debugWithContext("The task is canceling.")
            case .completed:
                appBootLog.debugWithContext("The task is completed.")
            @unknown default:
                appBootLog.debugWithContext("Unknown state.")
            }
            
            
        }
        
        // detailedLog(string: result)
        if let result = recognitionResult {
            
            // if this one starts at timestamp 0, then I know the the previous segments have been trimmed
            // then accumlate the previous one
            
            /* This one does not seem to quite work ...
             if (result.bestTranscription.segments[0].timestamp == 0) {
             accumulatedText = accumulatedText + " " + previousText
             detailedLog(string: "got a restart")
             // return
             }
             */
            
            var isReset:Bool = false
            
            if (result.bestTranscription.segments.first?.confidence ?? 0.0) > 0.0 {
                accumulatedText = accumulatedText + " " + previousText
                appBootLog.debugWithContext("got zero confidence")
                isReset = true
            }
            
            
            
            
            appBootLog.debugWithContext("result.isFinal: \(result.isFinal)")
            
            
            if false {
                for segment in result.bestTranscription.segments {
                    // detailedLog(string: "Recognized word: \(segment.substring), Confidence: \(segment.confidence)")
                    appBootLog.debugWithContext("Recognized word: \(segment.substring)")
                }
                for transcription in result.transcriptions {
                    appBootLog.debugWithContext("Alternative transcription: \(transcription.formattedString)")
                }
            }
            
            
            // printTranscriptionSegments(transcription: result.bestTranscription)
            
            
            // let stopWord = "new line"
            var stopWord = "\n"
            stopWord = "go"
            
            
            let recognizedText = result.bestTranscription.formattedString
            appBootLog.debugWithContext("recognizedText: \(recognizedText)")
            
            if (result.bestTranscription.segments.first?.confidence ?? 0.0) > 0.0 {
                accumulatedText = accumulatedText + " " + previousText
                appBootLog.debugWithContext("got zero confidence")
                isReset = true
            } else {
                accumulatedText = recognizedText
            }
            
            self.incrementalText = recognizedText
            previousText = recognizedText
            self.finalText = accumulatedText
            
            if recognizedText.contains(stopWord) {
                appBootLog.debugWithContext("got the stop word")
                
                // exportDatabase()
                
                if true || isReset {
                    let strippedText = accumulatedText.replacingOccurrences(of: stopWord, with: "")
                    self.saveRecognizedText(strippedText)  // Save text when final result is received'
                    accumulatedText = ""
                    // detailedLog(string: strippedText)
                    self.stopListening()                     // Stop and clear audio processing
                    self.startListening()
                }                    // Restart listening after detecting "stop"
            } else if result.isFinal {
                appBootLog.debugWithContext("got isFinal")
                
                // self.startListening()
            }
        } else if let error = error {
            appBootLog.debugWithContext("Recognition error: \(error.localizedDescription)")
            self.stopListening()
            self.startListening()
        }
        
    }
    
    // Starts listening and sets up the speech recognition task
    func startListening() {
        // Log current authorization statuses with timestamps
        
        // Commented out old logs
        // logWithTimestamp("SFSpeechRecognizer.authorizationStatus() = \(SFSpeechRecognizer.authorizationStatus())")
        // logWithTimestamp("AVAudioSession.sharedInstance().recordPermission = \(AVAudioSession.sharedInstance().recordPermission)")
        
        // New detailed authorization status logs:
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            appBootLog.infoWithContext("Speech permission: not determined")
        case .denied:
            appBootLog.infoWithContext("Speech permission: denied")
        case .restricted:
            appBootLog.infoWithContext("Speech permission: restricted")
        case .authorized:
            appBootLog.infoWithContext("Speech permission: authorized")
        @unknown default:
            appBootLog.infoWithContext("Speech permission: unknown")
        }
        
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            appBootLog.infoWithContext("Microphone permission: undetermined")
        case .denied:
            appBootLog.infoWithContext("Microphone permission: denied")
        case .granted:
            appBootLog.infoWithContext("Microphone permission: granted")
        @unknown default:
            appBootLog.infoWithContext("Microphone permission: unknown")
        }
        
        // Ensure permissions are granted
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            appBootLog.debugWithContext("Permissions not granted.")
            return
        }
        
        
        
        
        // Configure and activate audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            // try audioSession.setPreferredIOBufferDuration(0.01)  // Set a lower buffer duration for real-time processing
            try audioSession.setPreferredIOBufferDuration(100)
        } catch {
            appBootLog.debugWithContext("Audio session setup error: \(error)")
            return
        }
        
        setupAudioSessionObserver()
        
        // Reset and create a new recognition task
        clearRecognitionTask()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        // speechRecognizer?.defaultTaskHint = .dictation
        
        
        // Start the recognition task
        // how can result be null "what does weak self" mean
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            
            let one = 1 // adding a test line of code to see where the exception is raised
            appBootLog.infoWithContext("about to handle the recognitionRequest")
            
            if let result = result {
                self?.processRecognitionResult(recognitionResult: result, error: error)
            } else {
                appBootLog.debugWithContext("result is NULL")
            }
        }
        
        // Attach audio input node
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, when in
            self?.handleAudioTap(buffer: buffer, when: when)
            if let wavFile = self?.wavAudioFile {
                // Downmix to mono by using channel 0 only if needed
                let inputBuffer = buffer
                do {
                    try wavFile.write(from: inputBuffer)
                } catch {
                    appBootLog.errorWithContext("Failed to write to WAV file: \(error.localizedDescription)")
                }
            }
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            // Open/create audio file for appending raw PCM
            if audioFileHandle == nil {
                audioFileURL = makeAudioFileURL()
                if let url = audioFileURL {
                    FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
                    do {
                        audioFileHandle = try FileHandle(forWritingTo: url)
                        appBootLog.infoWithContext("Opened audio file for writing at: \(url.path)")
                        
                        // Create/open WAV file for iOS-friendly playback
                        do {
                            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                            let wavURL = docs.appendingPathComponent("rawAudio-\(Int(Date().timeIntervalSince1970)).wav")
                            self.wavFileURL = wavURL
                            // Build WAV (Linear PCM Float32) settings matching the input sample rate, mono
                            let sampleRate = recordingFormat.sampleRate
                            let wavSettings: [String: Any] = [
                                AVFormatIDKey: kAudioFormatLinearPCM,
                                AVSampleRateKey: sampleRate,
                                AVNumberOfChannelsKey: 1, // mono; we're writing channel 0
                                AVLinearPCMBitDepthKey: 32,
                                AVLinearPCMIsFloatKey: true,
                                AVLinearPCMIsBigEndianKey: false,
                                AVLinearPCMIsNonInterleaved: false
                            ]
                            self.wavAudioFile = try AVAudioFile(forWriting: wavURL, settings: wavSettings, commonFormat: .pcmFormatFloat32, interleaved: true)
                            appBootLog.infoWithContext("Opened WAV file for writing at: \(wavURL.path)")
                        } catch {
                            appBootLog.errorWithContext("Failed to open WAV file: \(error.localizedDescription)")
                        }
                        
                    } catch {
                        appBootLog.errorWithContext("Failed to open audio file handle: \(error.localizedDescription)")
                    }
                } else {
                    appBootLog.errorWithContext("Could not create audio file URL")
                }
            }
            // Reset Drive chunking state
            self.driveChunkBuffer.removeAll(keepingCapacity: true)
            self.driveBaseFilename = "rawAudio-\(Int(Date().timeIntervalSince1970))"
            self.lastDriveFlushTime = Date()
            appBootLog.infoWithContext("[Drive] Initialized chunking: base=\(self.driveBaseFilename)")
            
            self.driveUploader.ensureDrivePathReady { result in
                switch result {
                case .success(let folderId):
                    appBootLog.infoWithContext("[Drive] Ready: using session folder id=\(folderId)")
                case .failure(let err):
                    appBootLog.errorWithContext("[Drive] ensureDrivePathReady failed: \(err.localizedDescription)")
                }
            }
        } catch {
            appBootLog.debugWithContext("Audio engine could not start: \(error)")
        }
        
        // startSilenceTimer()  // Start silence detection timer
    }
    
    private func handleAudioTap(buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        self.recognitionRequest?.append(buffer)

        if let fileHandle = self.audioFileHandle, let channelData = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
            let bytesPerSample = MemoryLayout<Float>.size // 4 bytes for Float32
            let ptr = channelData[0]
            let data = Data(bytes: ptr, count: frames * bytesPerSample)
            do {
                try fileHandle.write(contentsOf: data)
            } catch {
                appBootLog.errorWithContext("Failed writing PCM buffer: \(error.localizedDescription)")
            }
        } else {
            appBootLog.errorWithContext("No fileHandle or channelData available for writing")
        }

        // this logging is too frequent
        if (false) {
            appBootLog.info("INFO_BOOT_MARKER_123_AUDIO —  audio buffer")
        }

        if enableAudioTapVerboseLogging {
            appBootLog.infoWithContext("Buffer format: \(buffer.format)")
            appBootLog.infoWithContext("Common format: \(buffer.format.commonFormat.rawValue)")

            // Print number of bytes in the buffer
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            let bytesPerSample = 4 // Float32 is 4 bytes
            let totalBytes = frameLength * channelCount * bytesPerSample
            appBootLog.infoWithContext("Number of bytes in buffer: \(totalBytes)")

            // Print first sample if format is Float32
            if let floatChannelData = buffer.floatChannelData {
                let firstSample = floatChannelData.pointee[0]
                appBootLog.infoWithContext("First float sample: \(firstSample)")
            }

            // Print the first 16 bytes as hex
            if let floatChannelData = buffer.floatChannelData {
                // Assume non-interleaved, print from the first channel
                let bytePtr = UnsafeRawPointer(floatChannelData.pointee).assumingMemoryBound(to: UInt8.self)
                let hexString = (0..<16).map { String(format: "%02X", bytePtr[$0]) }.joined(separator: " ")
                appBootLog.infoWithContext("First 16 bytes as hex: \(hexString)")
            }

            /*
             // Print the first 16 bits (first Int16 sample) of the buffer
             if let channelData = buffer.int16ChannelData {
             let firstSample = channelData.pointee[0]
             print("First 16 bits of buffer (as Int16): \(firstSample)")
             }
             */

            appBootLog.infoWithContext("got buffer afterwards")
        }
        
        // Append to Drive chunk buffer (Float32 PCM from channel 0)
        if let floatChannelData = buffer.floatChannelData {
            let frames = Int(buffer.frameLength)
            let bytesPerSample = MemoryLayout<Float>.size
            let ptr = floatChannelData[0]
            let data = Data(bytes: ptr, count: frames * bytesPerSample)
            driveChunkBuffer.append(data)
            if enableAudioTapVerboseLogging {
                appBootLog.debugWithContext("[Drive] Buffered bytes: \(data.count), total in chunk: \(driveChunkBuffer.count)")
            }
        }

        // Time/size-based flush to Drive as WAV chunks for incremental testing
        let now = Date()
        if driveChunkBuffer.count >= driveChunkSizeBytes || now.timeIntervalSince(lastDriveFlushTime) >= driveFlushInterval {
            flushDriveChunkAsWAV(sampleRate: buffer.format.sampleRate)
            lastDriveFlushTime = now
        }
    }
    
    // Build a minimal WAV header for Float32 mono and upload current chunk to Google Drive
    private func flushDriveChunkAsWAV(sampleRate: Double) {
        guard !driveChunkBuffer.isEmpty else { return }
        let wavData = buildFloat32MonoWAV(sampleRate: sampleRate, pcmFloatData: driveChunkBuffer)
        let filenameBase = driveBaseFilename
        appBootLog.infoWithContext("[Drive] Flushing chunk to Drive: bytes=\(wavData.count)")
        driveUploader.uploadDataChunk(data: wavData, mimeType: "audio/wav", baseFilename: filenameBase) { result in
            switch result {
            case .success(let name):
                appBootLog.infoWithContext("[Drive] Uploaded chunk ok: name=\(name)")
            case .failure(let error):
                appBootLog.errorWithContext("[Drive] Upload failed: \(error.localizedDescription)")
            }
        }
        driveChunkBuffer.removeAll(keepingCapacity: true)
    }

    /**
     Public method to flush any pending audio chunks to Google Drive as WAV.
     
     Call this from your app's view or coordinator when the app transitions to background or inactive state,
     if you do not use the `scenePhase` binding initializer.

     // Example (in your View):
     // .onChange(of: scenePhase) { newPhase in
     //     if newPhase == .background || newPhase == .inactive {
     //         speechManager.flushPendingAudioToDrive(sampleRate: speechManager.audioEngine.inputNode.outputFormat(forBus: 0).sampleRate)
     //     }
     // }
     */
    public func flushPendingAudioToDrive(sampleRate: Double) {
        flushDriveChunkAsWAV(sampleRate: sampleRate)
    }

    // Construct a simple WAV header for Float32 mono, little-endian
    private func buildFloat32MonoWAV(sampleRate: Double, pcmFloatData: Data) -> Data {
        let bytesPerSample: UInt16 = 4
        let numChannels: UInt16 = 1
        let sampleRateUInt32: UInt32 = UInt32(sampleRate)
        let byteRate: UInt32 = UInt32(bytesPerSample) * UInt32(numChannels) * sampleRateUInt32
        let blockAlign: UInt16 = UInt16(bytesPerSample) * numChannels
        let subchunk2Size: UInt32 = UInt32(pcmFloatData.count)
        let chunkSize: UInt32 = 36 + subchunk2Size

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: chunkSize.littleEndian, { Data($0) }))
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian, { Data($0) })) // Subchunk1Size
        header.append(withUnsafeBytes(of: UInt16(3).littleEndian, { Data($0) }))  // AudioFormat = 3 (IEEE float)
        header.append(withUnsafeBytes(of: numChannels.littleEndian, { Data($0) }))
        header.append(withUnsafeBytes(of: sampleRateUInt32.littleEndian, { Data($0) }))
        header.append(withUnsafeBytes(of: byteRate.littleEndian, { Data($0) }))
        header.append(withUnsafeBytes(of: blockAlign.littleEndian, { Data($0) }))
        let bitsPerSample: UInt16 = 32
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian, { Data($0) }))
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: subchunk2Size.littleEndian, { Data($0) }))

        // Debug: dump first 44 bytes of the WAV header we just built
        Self.dumpWAVHeader(data: header)

        var wav = Data(capacity: header.count + pcmFloatData.count)
        wav.append(header)
        wav.append(pcmFloatData)
        return wav
    }
    
    private func clearRecognitionTask() {
        // recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    func saveToSheet(timestamp: String?, text: String?)
    {
        let appendLog = AppendLog()
        
        appendLog.appendRow(row: [timestamp!, text!])
    }
    
    func stopListening() {
        appBootLog.debugWithContext("inside stopListening")
        recognitionRequest?.endAudio()  // Signal end of audio to finalize recognition
        audioEngine.stop()              // Stop the audio engine to free resources
        audioEngine.inputNode.removeTap(onBus: 0)  // Remove the tap to stop capturing audio
        
        audioFileHandle?.synchronizeFile()
        audioFileHandle?.closeFile()
        audioFileHandle = nil
        
        // Close WAV file (AVAudioFile closes on deinit)
        wavAudioFile = nil
        wavFileURL = nil
        
        // Flush any remaining Drive data
        flushDriveChunkAsWAV(sampleRate: audioEngine.inputNode.outputFormat(forBus: 0).sampleRate)
        
        clearRecognitionTask()
        resetSilenceTimer()
    }
    
    // Saves the recognized text to Core Data
    private func saveRecognizedText(_ text: String) {
        let newEntry = RecognizedTextEntity(context: context) // Replace RecognizedTextEntity with your Core Data entity name
        newEntry.content = text
        newEntry.timestamp = Date()  // Add a timestamp if needed
        
        do {
            try context.save()
            appBootLog.debugWithContext("Text saved successfully: \(text)")
        } catch {
            appBootLog.debugWithContext("Failed to save text: \(error.localizedDescription)")
        }
        
        saveToSheet(timestamp: newEntry.timestamp!.formatted(), text: newEntry.content)
        
    }
    
    // Silence detection methods
    private func startSilenceTimer() {
        resetSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            appBootLog.debugWithContext("timer fired")
            self?.stopListening()  // Stop if no audio is detected within threshold
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    private static func dumpWAVHeader(data: Data) {
        guard data.count >= 44 else {
            appBootLog.errorWithContext("[WAV] Header too small: \(data.count) bytes")
            return
        }
        func str(_ range: Range<Int>) -> String { String(data: data[range], encoding: .ascii) ?? "" }
        func le16(_ range: Range<Int>) -> UInt16 { data[range].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian } }
        func le32(_ range: Range<Int>) -> UInt32 { data[range].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian } }

        let chunkID = str(0..<4)
        let chunkSize = le32(4..<8)
        let format = str(8..<12)
        let subchunk1ID = str(12..<16)
        let subchunk1Size = le32(16..<20)
        let audioFormat = le16(20..<22)
        let numChannels = le16(22..<24)
        let sampleRate = le32(24..<28)
        let byteRate = le32(28..<32)
        let blockAlign = le16(32..<34)
        let bitsPerSample = le16(34..<36)
        let subchunk2ID = str(36..<40)
        let subchunk2Size = le32(40..<44)

        appBootLog.infoWithContext("[WAV] Header dump:")
        appBootLog.infoWithContext("  chunkID=\(chunkID) chunkSize=\(chunkSize) format=\(format)")
        appBootLog.infoWithContext("  fmt subchunk1ID=\(subchunk1ID) size=\(subchunk1Size) audioFormat=\(audioFormat)")
        appBootLog.infoWithContext("  numChannels=\(numChannels) sampleRate=\(sampleRate) byteRate=\(byteRate)")
        appBootLog.infoWithContext("  blockAlign=\(blockAlign) bitsPerSample=\(bitsPerSample)")
        appBootLog.infoWithContext("  data subchunk2ID=\(subchunk2ID) size=\(subchunk2Size)")
    }
}

import Combine

