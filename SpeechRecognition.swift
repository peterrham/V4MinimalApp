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
        
        logWithTimestamp("App launched: SpeechRecognitionManager initialized")
        
        print("inside init()")
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
            detailedLog(string: "<<<<<<<<<<<<<<<<<<<<<<<<")
            detailedLog(string: "index: \(index)")
            detailedLog(string: "Text: \(segment.substring)")
            detailedLog(string: "Range: \(segment.substringRange)")
            detailedLog(string: "Timestamp: \(segment.timestamp) seconds")
            detailedLog(string: "Duration: \(segment.duration) seconds")
            detailedLog(string: "Confidence: \(segment.confidence)")
            detailedLog(string: "-----------------------")
            
            if (index == 0) {
                if segment.timestamp == 0 {
                    detailedLog(string: "ignore this one")
                } else {
                    detailedLog(string: "keep this one")
                }
            }
        }
    }
    
    func detailedLog(string: String) {
        if false {
            logWithTimestamp (string)
        }
    }
    
    func processRecognitionResult(recognitionResult: SFSpeechRecognitionResult?, error: Error?)
    {
        detailedLog(string: "got recognition result")
        
        
        if false {
            
            detailedLog(string: "recognitionTask: \(self.recognitionTask)")
            detailedLog(string: "recognitionTask.state: \(self.recognitionTask!.state)")
            
            // detailedLog(string: recognitionTask!)
            
            detailedLog(string: "Recognition Task Properties:")
            detailedLog(string: "----------------------------")
            detailedLog(string: "State: \(recognitionTask!.state)")
            detailedLog(string: "Is Finishing: \(recognitionTask!.isFinishing)")
            detailedLog(string: "Is Cancelled: \(recognitionTask!.isCancelled)")
            
            // Print the current state of the task
            detailedLog(string: "Recognition Task State:")
            switch recognitionTask!.state {
            case .starting:
                detailedLog(string: "The task is starting.")
            case .running:
                detailedLog(string: "The task is running.")
            case .finishing:
                detailedLog(string: "The task is finishing.")
            case .canceling:
                detailedLog(string: "The task is canceling.")
            case .completed:
                detailedLog(string: "The task is completed.")
            @unknown default:
                detailedLog(string: "Unknown state.")
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
                detailedLog(string: "got zero confidence")
                isReset = true
            }
            
            
            
            
            detailedLog(string: "result.isFinal: \(result.isFinal)")
            
            
            if false {
                for segment in result.bestTranscription.segments {
                    // detailedLog(string: "Recognized word: \(segment.substring), Confidence: \(segment.confidence)")
                    detailedLog(string: "Recognized word: \(segment.substring)")
                }
                for transcription in result.transcriptions {
                    detailedLog(string: "Alternative transcription: \(transcription.formattedString)")
                }
            }
            
            
            // printTranscriptionSegments(transcription: result.bestTranscription)
            
            
            // let stopWord = "new line"
            var stopWord = "\n"
            stopWord = "go"
            
            
            let recognizedText = result.bestTranscription.formattedString
            detailedLog(string: "recognizedText: \(recognizedText)")
            
            if (result.bestTranscription.segments.first?.confidence ?? 0.0) > 0.0 {
                accumulatedText = accumulatedText + " " + previousText
                detailedLog(string: "got zero confidence")
                isReset = true
            } else {
                accumulatedText = recognizedText
            }
            
            self.incrementalText = recognizedText
            previousText = recognizedText
            self.finalText = accumulatedText
            
            if recognizedText.contains(stopWord) {
                detailedLog(string: "got the stop word")
                
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
                detailedLog(string: "got isFinal")
                
                // self.startListening()
            }
        } else if let error = error {
            detailedLog(string: "Recognition error: \(error.localizedDescription)")
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
            logWithTimestamp("Speech permission: not determined")
        case .denied:
            logWithTimestamp("Speech permission: denied")
        case .restricted:
            logWithTimestamp("Speech permission: restricted")
        case .authorized:
            logWithTimestamp("Speech permission: authorized")
        @unknown default:
            logWithTimestamp("Speech permission: unknown")
        }
        
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined:
            logWithTimestamp("Microphone permission: undetermined")
        case .denied:
            logWithTimestamp("Microphone permission: denied")
        case .granted:
            logWithTimestamp("Microphone permission: granted")
        @unknown default:
            logWithTimestamp("Microphone permission: unknown")
        }
        
        // Ensure permissions are granted
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            detailedLog(string: "Permissions not granted.")
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
            detailedLog(string: "Audio session setup error: \(error)")
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
            self?.detailedLog(string: "about to handle the recognitionRequest")
            
            if let result = result {
                self?.processRecognitionResult(recognitionResult: result, error: error)
            } else {
                self?.detailedLog(string: "result is NULL")
            }
        }
        
        // Attach audio input node
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        
        inputNode.installTap(onBus: 0, bufferSize: 1024 * 1024, format: recordingFormat) { [weak self] buffer, when in
       
            self?.recognitionRequest?.append(buffer)
            
            let timestamp = ISO8601DateFormatter().string(from: Date())
            
            print("[\(timestamp)] Buffer format:", buffer.format)
            print("[\(timestamp)] Common format:", buffer.format.commonFormat.rawValue)
            
            // Print number of bytes in the buffer
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            let bytesPerSample = 4 // Float32 is 4 bytes
            let totalBytes = frameLength * channelCount * bytesPerSample
            print("[\(timestamp)] Number of bytes in buffer:", totalBytes)
            
            // Print first sample if format is Float32
            if let floatChannelData = buffer.floatChannelData {
                let firstSample = floatChannelData.pointee[0]
                print("[\(timestamp)] First float sample:", firstSample)
            }
            
            // Print the first 16 bytes as hex
            if let floatChannelData = buffer.floatChannelData {
                // Assume non-interleaved, print from the first channel
                let bytePtr = UnsafeRawPointer(floatChannelData.pointee).assumingMemoryBound(to: UInt8.self)
                let hexString = (0..<16).map { String(format: "%02X", bytePtr[$0]) }.joined(separator: " ")
                print("[\(timestamp)] First 16 bytes as hex:", hexString)
            }
            
            /*
            // Print the first 16 bits (first Int16 sample) of the buffer
            if let channelData = buffer.int16ChannelData {
                let firstSample = channelData.pointee[0]
                print("First 16 bits of buffer (as Int16): \(firstSample)")
            }
            */
            
            print("got buffer afterwards")
        }
        
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            detailedLog(string: "Audio engine could not start: \(error)")
        }
        
        // startSilenceTimer()  // Start silence detection timer
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
        detailedLog(string: "inside stopListening")
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
            detailedLog(string: "Text saved successfully: \(text)")
        } catch {
            detailedLog(string: "Failed to save text: \(error.localizedDescription)")
        }
        
        saveToSheet(timestamp: newEntry.timestamp!.formatted(), text: newEntry.content)
        
    }
    
    // Silence detection methods
    private func startSilenceTimer() {
        resetSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            self?.detailedLog(string: "timer fired")
            self?.stopListening()  // Stop if no audio is detected within threshold
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}

