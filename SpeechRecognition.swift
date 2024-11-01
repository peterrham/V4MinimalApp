//
//  SpeechRecognition.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 10/31/24.
//

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
    
    init(context: NSManagedObjectContext) {
        self.context = context
        requestMicrophonePermission()
        
        startListening()
    }
    
    func createRecognitionTask() {
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Start a new recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { result, error in
            
            
            print(result)
            print(error)
            
            if let result = result {
                let newText = result.bestTranscription.formattedString.lowercased()
                
                print("newText: \(newText)")
                
                print("before testing STOP")
                print("result.final: \(result.isFinal)")
                
                if newText.contains("stop") {
                    let segments = newText.components(separatedBy: "stop")
                    if let firstSegment = segments.last {
                        let moreText = firstSegment.trimmingCharacters(in: .whitespacesAndNewlines)
                        print("moreText: \(moreText)")
                        
                        if moreText.isEmpty {
                        } else {
                            self.saveRecognizedText(moreText)
                            
                            self.finalText = moreText// "final text" // moreText  // Reset recognized text for new segment
                        }
                        self.startListening()
                    }
                } else {
                    self.incrementalText = newText // "new text"
                }
                
                if error != nil || result.isFinal == true {
                    print("FINAL")
                    self.audioEngine.stop()
                    self.audioEngine.inputNode.removeTap(onBus: 0)
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                }
            }
        }
    }
    
    func startRecognition() {
        // Cancel any ongoing task before starting a new one
        clearRecognitionTask()
        
        // Set up a new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true  // Set as needed
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        // Start capturing audio
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            self.recognitionRequest?.append(buffer)
        }
        
       let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request.")
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        
        createRecognitionTask()
    }
    
    func clearRecognitionTask() {
        // Cancel and reset the recognition task and request
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
    
    func stopRecognition() {
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        clearRecognitionTask()
    }
    
    func startListening() {
        
        print("inside startListening")
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            print("Permissions not granted.")
            return
        }
        
        print("before starting audio engine")
        
        do {
            self.audioEngine.prepare()
            try self.audioEngine.start()
        } catch {
            print("Audio engine could not start: \(error)")
        }
        
        let inputNode = self.audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        startRecognition()
        
        print(recognitionTask)
        print("after recognition task")
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
