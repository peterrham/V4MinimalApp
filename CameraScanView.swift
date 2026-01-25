//
//  CameraScanView.swift
//  V4MinimalApp
//
//  Home Inventory - Camera Scanning View (Phase 3)
//

import SwiftUI

struct CameraScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false
    @State private var detectedItems: [String] = []
    @State private var isFlashOn = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera Preview (will be replaced with actual camera)
                Rectangle()
                    .fill(.black)
                    .overlay {
                        VStack {
                            Image(systemName: "camera.metering.unknown")
                                .font(.system(size: 100))
                                .foregroundStyle(.white.opacity(0.3))
                            
                            Text("Camera Preview")
                                .foregroundStyle(.white.opacity(0.5))
                                .font(.title3)
                            
                            Text("Connect CameraManager in Phase 3")
                                .foregroundStyle(.white.opacity(0.3))
                                .font(.caption)
                                .padding(.top, 4)
                        }
                    }
                    .ignoresSafeArea()
                
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
                            isFlashOn.toggle()
                        } label: {
                            Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(isFlashOn ? .yellow : .white)
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
                                // Capture photo
                                withAnimation {
                                    // Simulate detection
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
        }
    }
}

#Preview {
    CameraScanView()
}
