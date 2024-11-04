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
    
    func debugPrint(_ str: String) {
    }
    
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
        
        debugPrint("handleAudioSessionInterruption")
        guard let userInfo = notification.userInfo,
              let interruptionTypeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue) else {
            return
        }
        
        if interruptionType == .began {
            debugPrint("Audio session interruption began. Pausing recognition.")
            recognitionTask?.cancel() // Cancel the task if an interruption begins
        } else if interruptionType == .ended {
            debugPrint("Audio session interruption ended.")
        }
    }
    
    func logWithTimestamp(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        debugPrint("[\(timestamp)] \(message)")
    }
    
    let index = 0;
    
    func printTranscriptionSegments(transcription: SFTranscription) {
        for (index, segment) in transcription.segments.enumerated() {
            debugPrint("index: \(index)")
            debugPrint("Text: \(segment.substring)")
            debugPrint("Range: \(segment.substringRange)")
            debugPrint("Timestamp: \(segment.timestamp) seconds")
            debugPrint("Duration: \(segment.duration) seconds")
            debugPrint("Confidence: \(segment.confidence)")
            debugPrint("-----------------------")
            
            if (index == 0) {
                if segment.timestamp == 0 {
                    debugPrint("ignore this one")
                } else {
                    debugPrint("keep this one")
                }
            }
        }
    }
    
    
    func processRecognitionResult(recognitionResult: SFSpeechRecognitionResult?, error: Error?)
    {
        self.logWithTimestamp("got recognition result")
        
        
        debugPrint("recognitionTask: \(self.recognitionTask)")
        debugPrint("recognitionTask.state: \(self.recognitionTask!.state)")
        
        // debugPrint(recognitionTask!)
        
        debugPrint("Recognition Task Properties:")
        debugPrint("----------------------------")
        debugPrint("State: \(recognitionTask!.state)")
        debugPrint("Is Finishing: \(recognitionTask!.isFinishing)")
        debugPrint("Is Cancelled: \(recognitionTask!.isCancelled)")
        
        // Print the current state of the task
        debugPrint("Recognition Task State:")
        switch recognitionTask!.state {
        case .starting:
            debugPrint("The task is starting.")
        case .running:
            debugPrint("The task is running.")
        case .finishing:
            debugPrint("The task is finishing.")
        case .canceling:
            debugPrint("The task is canceling.")
        case .completed:
            debugPrint("The task is completed.")
        @unknown default:
            debugPrint("Unknown state.")
        }
        
        
        
        
        // debugPrint(result)
        if let result = recognitionResult {
            
            // if this one starts at timestamp 0, then I know the the previous segments have been trimmed
            // then accumlate the previous one
            
            /* This one does not seem to quite work ...
             if (result.bestTranscription.segments[0].timestamp == 0) {
             accumulatedText = accumulatedText + " " + previousText
             print("got a restart")
             // return
             }
             */
            
            var isReset:Bool = false
            
            if (result.bestTranscription.segments.first?.confidence ?? 0.0) > 0.0 {
                accumulatedText = accumulatedText + " " + previousText
                print("got zero confidence")
                isReset = true
            }
            
            
            
            
            debugPrint("result.isFinal: \(result.isFinal)")
            
            
            /*
             for segment in result.bestTranscription.segments {
             // debugPrint("Recognized word: \(segment.substring), Confidence: \(segment.confidence)")
             debugPrint("Recognized word: \(segment.substring)")
             }
             for transcription in result.transcriptions {
             debugPrint("Alternative transcription: \(transcription.formattedString)")
             }
             */
            
            // printTranscriptionSegments(transcription: result.bestTranscription)
            
        
            // let stopWord = "new line"
            var stopWord = "\n"
            stopWord = "go"
            
            
            let recognizedText = result.bestTranscription.formattedString
            debugPrint(recognizedText)
            
            if (result.bestTranscription.segments.first?.confidence ?? 0.0) > 0.0 {
                accumulatedText = accumulatedText + " " + previousText
                print("got zero confidence")
                isReset = true
            } else {
                accumulatedText = recognizedText
            }
            
            self.incrementalText = recognizedText
            previousText = recognizedText
            self.finalText = accumulatedText
            
            if recognizedText.contains(stopWord) {
                print("got the stop word")
                
               // exportDatabase()
                
                if true || isReset {
                    let strippedText = accumulatedText.replacingOccurrences(of: stopWord, with: "")
                    self.saveRecognizedText(strippedText)  // Save text when final result is received'
                    accumulatedText = ""
                    debugPrint(strippedText)
                    // self?.stopListening()                     // Stop and clear audio processing
                    // self?.startListening()
                }                    // Restart listening after detecting "stop"
            } else if result.isFinal {
                debugPrint("got isFinal")
                
                self.startListening()
            }
        } else if let error = error {
            debugPrint("Recognition error: \(error.localizedDescription)")
            self.stopListening()
            self.startListening()
        }
        
    }
    
    // Starts listening and sets up the speech recognition task
    func startListening() {
        // Ensure permissions are granted
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            debugPrint("Permissions not granted.")
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
            debugPrint("Audio session setup error: \(error)")
            return
        }
        
        setupAudioSessionObserver()
        
        // Reset and create a new recognition task
        clearRecognitionTask()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        // speechRecognizer?.defaultTaskHint = .dictation
        
        
        // Start the recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            
            self?.processRecognitionResult(recognitionResult: result!, error: error)
            
        }
        
        // Attach audio input node
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        
        inputNode.installTap(onBus: 0, bufferSize: 1024 * 1024, format: recordingFormat) { [weak self] buffer, when in
            // debugPrint("got buffer")
            self?.recognitionRequest?.append(buffer)
        }
        
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            debugPrint("Audio engine could not start: \(error)")
        }
        
        // startSilenceTimer()  // Start silence detection timer
    }
    
    private func clearRecognitionTask() {
        // recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    func stopListening() {
        debugPrint("inside stopListening")
        recognitionRequest?.endAudio()  // Signal end of audio to finalize recognition
        audioEngine.stop()              // Stop the audio engine to free resources
        //audioEngine.inputNode.removeTap(onBus: 0)  // Remove the tap to stop capturing audio
        
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
            debugPrint("Text saved successfully: \(text)")
        } catch {
            debugPrint("Failed to save text: \(error.localizedDescription)")
        }
    }
    
    // Silence detection methods
    private func startSilenceTimer() {
        resetSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            self?.debugPrint("timer fired")
            self?.stopListening()  // Stop if no audio is detected within threshold
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
