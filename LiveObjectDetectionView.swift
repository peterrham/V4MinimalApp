//
//  LiveObjectDetectionView.swift
//  V4MinimalApp
//
//  Real-time object detection with streaming Gemini Vision analysis
//

import SwiftUI
import AVFoundation

struct LiveObjectDetectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionService = GeminiStreamingVisionService()
    
    @State private var isDetectionActive = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera Preview
                if cameraManager.isAuthorized && cameraManager.isSessionRunning {
                    CameraPreview(session: cameraManager.session)
                        .ignoresSafeArea()
                } else if !cameraManager.isAuthorized {
                    // Permission denied view
                    cameraPermissionView
                } else {
                    // Loading view
                    cameraLoadingView
                }
                
                // Overlay UI
                VStack(spacing: 0) {
                    // Top controls
                    topControls
                    
                    Spacer()
                    
                    // Detection display box
                    if isDetectionActive || !visionService.detectedObjects.isEmpty {
                        StreamingObjectDetectionView(
                            detectedObjects: visionService.detectedObjects,
                            isAnalyzing: isDetectionActive
                        )
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Bottom controls
                    bottomControls
                        .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                setupStreamingDetection()
            }
            .onDisappear {
                cleanup()
            }
        }
    }
    
    // MARK: - UI Components
    
    private var topControls: some View {
        HStack {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(isDetectionActive ? .green : .gray)
                    .frame(width: 8, height: 8)
                
                Text(isDetectionActive ? "LIVE" : "PAUSED")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.6)))
            
            Spacer()
            
            // Flash toggle
            Button {
                cameraManager.toggleFlash()
            } label: {
                Image(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(cameraManager.isFlashOn ? .yellow : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
            }
        }
        .padding()
    }
    
    private var bottomControls: some View {
        HStack(spacing: 30) {
            // Clear detections
            Button {
                withAnimation {
                    visionService.clearDetections()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                    
                    Text("Clear")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .background(Circle().fill(.ultraThinMaterial))
            }
            .disabled(visionService.detectedObjects.isEmpty)
            
            // Start/Stop detection button
            Button {
                toggleDetection()
            } label: {
                ZStack {
                    Circle()
                        .fill((isDetectionActive ? Color.red : Color.green).gradient)
                        .frame(width: 80, height: 80)
                        .shadow(color: (isDetectionActive ? Color.red : Color.green).opacity(0.5), radius: 10)
                    
                    Image(systemName: isDetectionActive ? "stop.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .symbolEffect(.pulse, isActive: isDetectionActive)
            
            // Export/Share button
            Button {
                shareDetections()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                    
                    Text("Share")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .frame(width: 60, height: 60)
                .background(Circle().fill(.ultraThinMaterial))
            }
            .disabled(visionService.detectedObjects.isEmpty)
        }
        .padding(.horizontal)
    }
    
    private var cameraPermissionView: some View {
        Rectangle()
            .fill(.black)
            .overlay {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill.badge.ellipsis")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.5))
                    
                    Text("Camera Access Required")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text("Please enable camera access in Settings for live object detection")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    } label: {
                        Text("Open Settings")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.blue))
                    }
                }
            }
            .ignoresSafeArea()
    }
    
    private var cameraLoadingView: some View {
        Rectangle()
            .fill(.black)
            .overlay {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    
                    Text("Initializing Camera...")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.callout)
                }
            }
            .ignoresSafeArea()
    }
    
    // MARK: - Methods
    
    private func setupStreamingDetection() {
        // Enable frame capture with vision analysis
        cameraManager.enableFrameCapture { image in
            Task {
                await visionService.analyzeFrame(image)
            }
        }
    }
    
    private func cleanup() {
        visionService.stopAnalyzing()
        cameraManager.disableFrameCapture()
        cameraManager.stopSession()
    }
    
    private func toggleDetection() {
        withAnimation {
            isDetectionActive.toggle()
            
            if isDetectionActive {
                visionService.startAnalyzing()
                
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } else {
                visionService.stopAnalyzing()
                
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
    }
    
    private func shareDetections() {
        let detectionList = visionService.detectedObjects
            .map { "• \($0.name)" }
            .joined(separator: "\n")
        
        let shareText = """
        Detected Objects (\(visionService.detectedObjects.count)):
        
        \(detectionList)
        
        Generated with Live Object Detection
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}

// MARK: - Preview

#Preview {
    LiveObjectDetectionView()
}
