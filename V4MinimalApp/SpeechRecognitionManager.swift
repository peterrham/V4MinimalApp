//
//  SpeechRecognitionManager.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 10/30/24.
//

/*
import SwiftUI
import AVFoundation
import Speech



class SpeechRecognitionManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var recognizedText = ""
    
    func startTranscribing() {
        

        // Request Speech Authorization
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Speech recognition authorized.")
                case .denied:
                    print("Speech recognition permission denied.")
                case .restricted:
                    print("Speech recognition restricted on this device.")
                case .notDetermined:
                    print("Speech recognition not yet determined.")
                @unknown default:
                    print("Unknown authorization status.")
                }
            }
        }

    
        // Reset if there's an ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Set up audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        // Create a new recognition request
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else {
            print("Unable to create recognition request.")
            return
        }
        request.shouldReportPartialResults = true
        
        // Begin recognizing speech
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    print(result.bestTranscription.formattedString)
                    self.recognizedText = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.request = nil
                self.recognitionTask = nil
            }
        }
        
        // Configure the audio engine to receive audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        // Start the audio engine
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Audio engine could not start: \(error)")
        }
    }
    
    func stopTranscribing() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        request = nil
        recognitionTask = nil
    }
}

*/
