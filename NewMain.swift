import SwiftUI
import AVFoundation
import Speech

@main
struct VoiceRecognitionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// testing

class SpeechRecognitionManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var recognizedText: String = ""
    private var interimText: String = ""
    
    init() {
        requestMicrophonePermission()
    }
    
    func startListening() {
        // Ensure permissions are granted
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            print("Permissions not granted.")
            return
        }
        
        // Reset any previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        // Create a new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request.")
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        
        // Start the recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            
            print("got a recognition event")
            if let result = result {
                let newText = result.bestTranscription.formattedString.lowercased()
                
                // Check for the "stop" keyword
                if newText.contains("stop") {
                    print("got a STOP")
                    let segments = newText.components(separatedBy: "stop")
                    if let firstSegment = segments.first {
                        self.recognizedText = firstSegment.trimmingCharacters(in: .whitespacesAndNewlines)
                        print("self.recognizedText")
                        print(self.recognizedText)
                    }
                    self.stopListening()
                } else {
                    print("NO stop")
                    self.interimText = newText
                    self.recognizedText = newText
                    print("new text ....")
                    print(newText)
                }
            }
            
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        // Configure the audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        // Start the audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Audio engine could not start: \(error)")
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionRequest = nil
    }
    
    private func requestMicrophonePermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Speech recognition authorized.")
            case .denied, .restricted, .notDetermined:
                print("Speech recognition not authorized.")
            @unknown default:
                break
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("Microphone access granted.")
            } else {
                print("Microphone access denied.")
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var isListening = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Recognized Text:")
                .font(.headline)
            
            Text(speechManager.recognizedText)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            
            Button(action: {
                if isListening {
                    speechManager.stopListening()
                } else {
                    speechManager.startListening()
                }
                isListening.toggle()
            }) {
                Text(isListening ? "Stop Listening" : "Start Listening")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isListening ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
