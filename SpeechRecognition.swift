import SwiftUI
import CoreData
import AVFoundation
import Speech

/*
func logWithTimestamp(_ string: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("[\(timestamp)] \(string)")
}
 */

// MARK: - Speech Recognition Manager

class SpeechRecognitionManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let context: NSManagedObjectContext
    
    // this is the text that we add together until we get a stop word
    
    private var  accumulatedText: String = ""
    
    // this is the text from the last good recognition result
    private var  previousText: String = ""
    
    
    
    @Published var incrementalText: String = ""  // Shows incremental speech as it's recognized
    @Published var finalText: String = ""        // Shows finalized speech after "stop" is detected
    
    // Silence detection timer
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 12.0  // Adjust as needed
    
    
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
        
        
        inputNode.installTap(onBus: 0, bufferSize: 1024 * 1024, format: recordingFormat) { [weak self] buffer, when in
            self?.handleAudioTap(buffer: buffer, when: when)
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            appBootLog.debugWithContext("Audio engine could not start: \(error)")
        }
        
        // startSilenceTimer()  // Start silence detection timer
    }
    
    private func handleAudioTap(buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        self.recognitionRequest?.append(buffer)

        // this logging is too frequent
        if (false) {
            appBootLog.info("INFO_BOOT_MARKER_123_AUDIO —  audio buffer")
        }

        if (true) {
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
}

