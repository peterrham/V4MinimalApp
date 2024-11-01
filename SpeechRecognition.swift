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
    
    @Published var incrementalText: String = ""  // Shows incremental speech as it's recognized
    @Published var finalText: String = ""        // Shows finalized speech after "stop" is detected
    
    // Silence detection timer
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.0  // Adjust as needed
    
    init(context: NSManagedObjectContext) {
        self.context = context
        requestMicrophonePermission()
        startListening()
    }
    
    // Starts listening and sets up the speech recognition task
    func startListening() {
        // Ensure permissions are granted
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            print("Permissions not granted.")
            return
        }
        
        // Configure and activate audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup error: \(error)")
            return
        }
        
        // Reset and create a new recognition task
        clearRecognitionTask()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        // Start the recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            print("got recognition result")
            if let result = result {
                let recognizedText = result.bestTranscription.formattedString.lowercased()
                self?.incrementalText = recognizedText
                if recognizedText.contains("stop") {
                    self?.finalText = recognizedText
                    self?.saveRecognizedText(recognizedText)  // Save text after detecting "stop"
                    self?.stopListening()                     // Stop and clear audio processing
                    // self?.startListening()                    // Restart listening after detecting "stop"
                } else if result.isFinal {
                    self?.finalText = recognizedText
                    self?.saveRecognizedText(recognizedText)  // Save text when final result is received
                    // self?.startListening()
                }
            } else if let error = error {
                print("Recognition error: \(error.localizedDescription)")
                self?.stopListening()
                self?.startListening()
            }
        }
        
        // Attach audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, when in
            // print("got buffer")
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine could not start: \(error)")
        }
        
       // startSilenceTimer()  // Start silence detection timer
    }
    
    private func clearRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    func stopListening() {
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
            print("Text saved successfully: \(text)")
        } catch {
            print("Failed to save text: \(error.localizedDescription)")
        }
    }
    
    // Silence detection methods
    private func startSilenceTimer() {
        resetSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            self?.stopListening()  // Stop if no audio is detected within threshold
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
