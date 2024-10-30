//
//  ContentView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 10/30/24.
//
/*
import SwiftUI

import AVFoundation

class AudioRecorder: ObservableObject {
    private var audioEngine = AVAudioEngine()

    func startListening() {
        // Access the microphone input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, time in
            // Process the audio buffer here (e.g., send to a speech recognition API)
           //  print("Audio buffer received: \(buffer)")
            
            // Analyze buffer for amplitude to detect voice input
                        let level = self.averagePower(for: buffer)
                        if level > -30 { // Adjust threshold as needed
                            print("Voice detected with amplitude: \(level)")
                        } else {
                            // print("Silence or background noise detected.")
                        }
        }

        // Start the audio engine
        do {
            try audioEngine.start()
            print("Audio engine started and listening...")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func averagePower(for buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else {
            return -160 // Very low dB for silence if there's no data
        }
        let frameLength = Int(buffer.frameLength)
        
        // Step 1: Calculate the sum of squares
        var sum: Float = 0.0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        
        // Step 2: Calculate the mean
        let mean = sum / Float(frameLength)
        
        // Step 3: Calculate the RMS (root mean square)
        let rms = sqrt(mean)
        
        // Step 4: Convert to decibels
        let decibels = 20 * log10(rms)
        return decibels
    }


    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        print("Audio engine stopped.")
    }
}




struct ContentView: View {
    
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var speechManager = SpeechRecognitionManager()
    var body: some View {
        VStack {
            Text(speechManager.recognizedText)
                           .padding()
                       
                       Button("Start Transcribing") {
                           speechManager.startTranscribing()
                       }
                       .padding()
                       
                       Button("Stop Transcribing") {
                           speechManager.stopTranscribing()
                       }
                       .padding()
            Button("Start Listening") {
                          audioRecorder.startListening()
                      }
                      .padding()
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            
            Button("Stop Listening") {
                           audioRecorder.stopListening()
                       }
                       .padding()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
*/
