import SwiftUI
import CoreData
import AVFoundation
import Speech

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
        
        print("inside init()")
        self.context = context
        requestMicrophonePermission()
        startListening()
    }
    
    func setupAudioSessionObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption(_:)), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
    }
    
    @objc func handleAudioSessionInterruption(_ notification: Notification) {
        
        logWithTimestamp("handleAudioSessionInterruption")
        guard let userInfo = notification.userInfo,
              let interruptionTypeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue) else {
            return
        }
        
        if interruptionType == .began {
            logWithTimestamp("Audio session interruption began. Pausing recognition.")
            recognitionTask?.cancel() // Cancel the task if an interruption begins
        } else if interruptionType == .ended {
            logWithTimestamp("Audio session interruption ended.")
        }
    }
    
   
    
    let index = 0;
    
    func printTranscriptionSegments(transcription: SFTranscription) {
        for (index, segment) in transcription.segments.enumerated() {
            logWithTimestamp("<<<<<<<<<<<<<<<<<<<<<<<<")
            logWithTimestamp("index: \(index)")
            logWithTimestamp("Text: \(segment.substring)")
            logWithTimestamp("Range: \(segment.substringRange)")
            logWithTimestamp("Timestamp: \(segment.timestamp) seconds")
            logWithTimestamp("Duration: \(segment.duration) seconds")
            logWithTimestamp("Confidence: \(segment.confidence)")
            logWithTimestamp("-----------------------")
            
            if (index == 0) {
                if segment.timestamp == 0 {
                    logWithTimestamp("ignore this one")
                } else {
                    logWithTimestamp("keep this one")
                }
            }
        }
    }
    
    
    func processRecognitionResult(recognitionResult: SFSpeechRecognitionResult?, error: Error?)
    {
        logWithTimestamp("got recognition result")
        
        
        logWithTimestamp("recognitionTask: \(self.recognitionTask)")
        logWithTimestamp("recognitionTask.state: \(self.recognitionTask!.state)")
        
        // logWithTimestamp(recognitionTask!)
        
        logWithTimestamp("Recognition Task Properties:")
        logWithTimestamp("----------------------------")
        logWithTimestamp("State: \(recognitionTask!.state)")
        logWithTimestamp("Is Finishing: \(recognitionTask!.isFinishing)")
        logWithTimestamp("Is Cancelled: \(recognitionTask!.isCancelled)")
        
        // Print the current state of the task
        logWithTimestamp("Recognition Task State:")
        switch recognitionTask!.state {
        case .starting:
            logWithTimestamp("The task is starting.")
        case .running:
            logWithTimestamp("The task is running.")
        case .finishing:
            logWithTimestamp("The task is finishing.")
        case .canceling:
            logWithTimestamp("The task is canceling.")
        case .completed:
            logWithTimestamp("The task is completed.")
        @unknown default:
            logWithTimestamp("Unknown state.")
        }
        
        
        
        
        // logWithTimestamp(result)
        if let result = recognitionResult {
            
            // if this one starts at timestamp 0, then I know the the previous segments have been trimmed
            // then accumlate the previous one
            
            /* This one does not seem to quite work ...
             if (result.bestTranscription.segments[0].timestamp == 0) {
             accumulatedText = accumulatedText + " " + previousText
             logWithTimestamp("got a restart")
             // return
             }
             */
            
            var isReset:Bool = false
            
            if (result.bestTranscription.segments.first?.confidence ?? 0.0) > 0.0 {
                accumulatedText = accumulatedText + " " + previousText
                logWithTimestamp("got zero confidence")
                isReset = true
            }
            
            
            
            
            logWithTimestamp("result.isFinal: \(result.isFinal)")
            
            
           
             for segment in result.bestTranscription.segments {
             // logWithTimestamp("Recognized word: \(segment.substring), Confidence: \(segment.confidence)")
             logWithTimestamp("Recognized word: \(segment.substring)")
             }
             for transcription in result.transcriptions {
             logWithTimestamp("Alternative transcription: \(transcription.formattedString)")
             }
            
            
            printTranscriptionSegments(transcription: result.bestTranscription)
            
        
            // let stopWord = "new line"
            var stopWord = "\n"
            stopWord = "go"
            
            
            let recognizedText = result.bestTranscription.formattedString
            logWithTimestamp("recognizedText: \(recognizedText)")
            
            if (result.bestTranscription.segments.first?.confidence ?? 0.0) > 0.0 {
                accumulatedText = accumulatedText + " " + previousText
                logWithTimestamp("got zero confidence")
                isReset = true
            } else {
                accumulatedText = recognizedText
            }
            
            self.incrementalText = recognizedText
            previousText = recognizedText
            self.finalText = accumulatedText
            
            if recognizedText.contains(stopWord) {
                logWithTimestamp("got the stop word")
                
               // exportDatabase()
                
                if true || isReset {
                    let strippedText = accumulatedText.replacingOccurrences(of: stopWord, with: "")
                    self.saveRecognizedText(strippedText)  // Save text when final result is received'
                    accumulatedText = ""
                    logWithTimestamp(strippedText)
                    self.stopListening()                     // Stop and clear audio processing
                    self.startListening()
                }                    // Restart listening after detecting "stop"
            } else if result.isFinal {
                logWithTimestamp("got isFinal")
                
                // self.startListening()
            }
        } else if let error = error {
            logWithTimestamp("Recognition error: \(error.localizedDescription)")
            self.stopListening()
            self.startListening()
        }
        
    }
    
    // Starts listening and sets up the speech recognition task
    func startListening() {
        // Ensure permissions are granted
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            logWithTimestamp("Permissions not granted.")
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
            logWithTimestamp("Audio session setup error: \(error)")
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
            logWithTimestamp("about to handle the recognitionRequest")
            
            if let result = result {
                self?.processRecognitionResult(recognitionResult: result, error: error)
            } else {
                logWithTimestamp("result is NULL")
            }
        }
        
        // Attach audio input node
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        
        inputNode.installTap(onBus: 0, bufferSize: 1024 * 1024, format: recordingFormat) { [weak self] buffer, when in
            // logWithTimestamp("got buffer")
            self?.recognitionRequest?.append(buffer)
        }
        
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            logWithTimestamp("Audio engine could not start: \(error)")
        }
        
        // startSilenceTimer()  // Start silence detection timer
    }
    
    private func clearRecognitionTask() {
        // recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    func stopListening() {
        logWithTimestamp("inside stopListening")
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
            logWithTimestamp("Text saved successfully: \(text)")
        } catch {
            logWithTimestamp("Failed to save text: \(error.localizedDescription)")
        }
    }
    
    // Silence detection methods
    private func startSilenceTimer() {
        resetSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            logWithTimestamp("timer fired")
            self?.stopListening()  // Stop if no audio is detected within threshold
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
