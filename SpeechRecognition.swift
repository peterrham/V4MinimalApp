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
        
        print("before starting")
        // Reset and create a new recognition task
        clearRecognitionTask()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        // Start the recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            
            print("got a result")
            if let result = result {
                self?.incrementalText = result.bestTranscription.formattedString
                if result.isFinal {
                    print("it's final")
                    self?.finalText = result.bestTranscription.formattedString
                    self?.stopListening()
                    // saveRecognizedText(self?.finalText?)
                    
                    let textToSave = self?.finalText
                        self?.saveRecognizedText(textToSave!)
                    
                    self?.startListening()
                    
                } else {
                    self?.resetSilenceTimer()  // Reset timer when partial results are received
                    self?.startSilenceTimer()
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
            // print("got some audio")
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine could not start: \(error)")
        }
        
        startSilenceTimer()  // Start silence detection timer
    }
    
    private func clearRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    func stopListening() {
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        clearRecognitionTask()
        resetSilenceTimer()
    }
    
    private func requestMicrophonePermission() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Microphone permission granted.")
                case .denied, .restricted, .notDetermined:
                    print("Microphone permission not granted.")
                @unknown default:
                    print("Unknown authorization status.")
                }
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Recording permission granted.")
                } else {
                    print("Recording permission not granted.")
                }
            }
        }
    }
    
    // Silence detection methods
    private func startSilenceTimer() {
        print("starting silence timer")
        resetSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            print("silence timer fired")
            self?.stopListening()  // Stop if no audio is detected within threshold
            self?.startSilenceTimer()
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    
    private func saveRecognizedText(_ text: String) {
        let newEntry = RecognizedTextEntity(context: context)
        newEntry.content = text
        newEntry.timestamp = Date()
        
        do {
            try context.save()
        } catch {
            print("Failed to save recognized text: \(error)")
        }
    }
}
