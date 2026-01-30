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
    @EnvironmentObject var inventoryStore: InventoryStore
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionService = GeminiStreamingVisionService()
    @StateObject private var enrichmentService = BackgroundEnrichmentService()

    @State private var isDetectionActive = false
    @State private var showingInventorySheet = false
    @State private var showingDuplicateReview = false
    @State private var saveAllConfirmation = false
    
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
                            isAnalyzing: isDetectionActive,
                            onSaveItem: { object in
                                inventoryStore.addItem(from: object)
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                            },
                            onSaveAll: {
                                saveAllConfirmation = true
                            }
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
            .sheet(isPresented: $showingInventorySheet) {
                SavedInventorySheet()
                    .environmentObject(inventoryStore)
            }
            .sheet(isPresented: $showingDuplicateReview) {
                DuplicateReviewSheet()
                    .environmentObject(inventoryStore)
            }
            .alert("Save All Objects", isPresented: $saveAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save \(visionService.detectedObjects.count) Items") {
                    inventoryStore.addItems(from: visionService.detectedObjects)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } message: {
                Text("Add all \(visionService.detectedObjects.count) detected objects to your inventory?")
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
            
            // Inventory & Merge buttons
            VStack(spacing: 8) {
                Button {
                    showingInventorySheet = true
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "archivebox.fill")
                                .font(.title3)
                                .foregroundColor(.white)

                            if inventoryStore.items.count > 0 {
                                Text("\(inventoryStore.items.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .background(Circle().fill(.red))
                                    .offset(x: 10, y: -10)
                            }
                        }

                        Text("Inventory")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(.ultraThinMaterial))
                }

                Button {
                    showingDuplicateReview = true
                } label: {
                    Text("Merge")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
            }
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
        // Wire enrichment service to vision service
        enrichmentService.visionService = visionService

        // Enable frame capture with vision analysis
        cameraManager.enableFrameCapture { image in
            Task {
                let countBefore = visionService.detectedObjects.count
                await visionService.analyzeFrame(image)
                let countAfter = visionService.detectedObjects.count

                // Enqueue new detections for background enrichment
                if countAfter > countBefore {
                    for i in countBefore..<countAfter {
                        enrichmentService.enqueue(visionService.detectedObjects[i])
                    }
                }
            }
        }
    }
    
    private func cleanup() {
        visionService.stopAnalyzing()
        enrichmentService.cancelAll()
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
    
}

// MARK: - Preview

#Preview {
    LiveObjectDetectionView()
        .environmentObject(InventoryStore())
}
