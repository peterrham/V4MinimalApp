//
//  CameraScanView.swift
//  V4MinimalApp
//
//  Home Inventory - Camera Scanning View (Phase 3)
//

import SwiftUI
import os
import AVFoundation

struct CameraScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager()
    
    @State private var isRecording = false
    @State private var detectedItems: [String] = []
    
    private let logger = Logger(subsystem: "com.yourcompany.yourapp", category: "CameraScanView")
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera Preview
                if cameraManager.isAuthorized && cameraManager.isSessionRunning {
                    CameraPreview(session: cameraManager.session)
                        .ignoresSafeArea()
                } else if !cameraManager.isAuthorized {
                    // Permission denied view
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
                                
                                Text("Please enable camera access in Settings to scan items")
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
                                .padding(.top, 8)
                            }
                        }
                        .ignoresSafeArea()
                } else {
                    // Loading view
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
                
                // Top Controls
                VStack {
                    HStack {
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
                        
                        // Item counter badge
                        if !detectedItems.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "cube.box.fill")
                                    .font(.caption)
                                Text("\(detectedItems.count)")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(AppTheme.Colors.success))
                        }
                        
                        Spacer()
                        
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
                    .padding(AppTheme.Spacing.l)
                    
                    Spacer()
                    
                    // Bottom Controls
                    VStack(spacing: AppTheme.Spacing.l) {
                        // Detected items overlay
                        if !detectedItems.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: AppTheme.Spacing.s) {
                                    ForEach(detectedItems, id: \.self) { item in
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                            
                                            Text(item)
                                                .font(.callout)
                                                .fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(.ultraThickMaterial))
                                    }
                                }
                                .padding(.horizontal, AppTheme.Spacing.l)
                            }
                        }
                        
                        // Control buttons
                        HStack(spacing: AppTheme.Spacing.xl) {
                            // Gallery
                            Button {
                                // Show photo library
                            } label: {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                            
                            Spacer()
                            
                            // Capture button
                            Button {
                                logger.info("Capture button tapped")
                                cameraManager.capturePhoto()
                                
                                // Simulate detection for now
                                withAnimation {
                                    detectedItems.append("Sample Item \(detectedItems.count + 1)")
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(.white, lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                    
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 70, height: 70)
                                }
                            }
                            .disabled(!cameraManager.isSessionRunning)
                            
                            Spacer()
                            
                            // Voice button
                            Button {
                                isRecording.toggle()
                            } label: {
                                Image(systemName: isRecording ? "mic.fill" : "mic")
                                    .font(.title2)
                                    .foregroundColor(isRecording ? .red : .white)
                                    .frame(width: 60, height: 60)
                                    .background {
                                        if isRecording {
                                            Circle().fill(Color.white)
                                        } else {
                                            Circle().fill(.ultraThinMaterial)
                                        }
                                    }
                            }
                            .symbolEffect(.pulse, isActive: isRecording)
                        }
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.bottom, AppTheme.Spacing.xl)
                    }
                }
                
                // Instructions overlay
                if detectedItems.isEmpty {
                    VStack {
                        Spacer()
                        
                        VStack(spacing: AppTheme.Spacing.m) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 50))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            Text("Point camera at items")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("AI will identify and catalog them automatically")
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .padding(AppTheme.Spacing.xl)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(AppTheme.Spacing.l)
                        
                        Spacer()
                        Spacer()
                        Spacer()
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                logger.info("CameraScanView appeared")
                // Camera manager will auto-start session after configuration
            }
            .onDisappear {
                logger.info("CameraScanView disappeared - stopping session")
                cameraManager.stopSession()
            }
            .alert(item: $cameraManager.error) { error in
                Alert(
                    title: Text("Camera Error"),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

#Preview {
    CameraScanView()
}
