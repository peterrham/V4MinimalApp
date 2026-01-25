import Speech
import AVFoundation

class SpeechRecognizerManager: NSObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let appBootLog = AppBootLog()

    override init() {
        super.init()
        speechRecognizer.delegate = self
        SFSpeechRecognizer.requestAuthorization { authStatus in
            switch authStatus {
            case .authorized:
                self.appBootLog.infoWithContext("Speech recognition authorized.")
            case .denied:
                self.appBootLog.infoWithContext("Speech recognition permission denied.")
            case .restricted:
                self.appBootLog.infoWithContext("Speech recognition restricted on this device.")
            case .notDetermined:
                self.appBootLog.infoWithContext("Speech recognition not yet determined.")
            @unknown default:
                self.appBootLog.infoWithContext("Unknown authorization status.")
            }
        }
    }

    func startRecording() throws {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            appBootLog.errorWithContext("Failed to set up audio session: \(error.localizedDescription)")
            throw error
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            appBootLog.errorWithContext("Unable to create recognition request.")
            throw NSError(domain: "SpeechRecognizer", code: 1, userInfo: nil)
        }

        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.appBootLog.debugWithContext(result.bestTranscription.formattedString)
            }

            if error != nil || (result?.isFinal ?? false) {
                self.audioEngine.stop()
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }

        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            appBootLog.errorWithContext("Audio engine could not start: \(error.localizedDescription)")
            throw error
        }
    }

    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
    }
}

class AppBootLog {
    func infoWithContext(_ message: String) {
        // Implementation for info logging
    }

    func errorWithContext(_ message: String) {
        // Implementation for error logging
    }
    
    func debugWithContext(_ message: String) {
        // Implementation for debug logging
    }
}
