//
//  SpeechRecognitionExtension.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/1/24.
//

import AVFoundation
import Speech

extension SpeechRecognitionManager {
    internal func requestMicrophonePermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    appBootLog.infoWithContext("Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    appBootLog.infoWithContext("Speech recognition not authorized")
                @unknown default:
                    appBootLog.infoWithContext("Unknown authorization status")
                }
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    appBootLog.infoWithContext("Microphone access granted")
                } else {
                    appBootLog.infoWithContext("Microphone access denied")
                }
            }
        }
    }
    
    
}
