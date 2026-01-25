//
//  CameraScanView.swift
//  V4MinimalApp
//
//  Home Inventory - Camera Scanning View (Phase 3)
//

import SwiftUI
import os
import AVFoundation
import PhotosUI

struct CameraScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager()
    
    @State private var isRecording = false
    @State private var detectedItems: [String] = []
    @State private var showUploadOptions = false
    @State private var recordedVideoURL: URL?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var enableStreamingUpload = false
    
    private let logger = Logger(subsystem: "com.yourcompany.yourapp", category: "CameraScanView")
    private let driveUploader = GoogleDriveUploader()
    @StateObject private var streamingUploader = StreamingVideoUploader()
    
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
                        
                        // Recording indicator
                        if cameraManager.isRecording {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                
                                Text(formatDuration(cameraManager.recordingDuration))
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.black.opacity(0.6)))
                        }
                        
                        // Item counter badge
                        else if !detectedItems.isEmpty {
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
                        
                        // Streaming upload toggle
                        Button {
                            enableStreamingUpload.toggle()
                        } label: {
                            Image(systemName: enableStreamingUpload ? "icloud.fill" : "icloud.slash.fill")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(enableStreamingUpload ? .green : .white)
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
                            // Gallery - Open Photo Library
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                            .onChange(of: selectedPhotoItem) { oldValue, newValue in
                                Task {
                                    await loadSelectedPhoto()
                                }
                            }
                            
                            Spacer()
                            
                            // Capture/Record button
                            Button {
                                if cameraManager.isRecording {
                                    // Stop recording
                                    cameraManager.stopRecording()
                                } else {
                                    logger.info("Capture button tapped")
                                    cameraManager.capturePhoto()
                                    
                                    // Simulate detection for now
                                    withAnimation {
                                        detectedItems.append("Sample Item \(detectedItems.count + 1)")
                                    }
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .stroke(.white, lineWidth: 4)
                                        .frame(width: 80, height: 80)
                                    
                                    if cameraManager.isRecording {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(.red)
                                            .frame(width: 40, height: 40)
                                    } else {
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 70, height: 70)
                                    }
                                }
                            }
                            .disabled(!cameraManager.isSessionRunning)
                            
                            Spacer()
                            
                            // Record/Voice button
                            Button {
                                if cameraManager.isRecording {
                                    cameraManager.stopRecording()
                                } else {
                                    if enableStreamingUpload {
                                        // Start recording with streaming upload
                                        Task {
                                            do {
                                                try await cameraManager.startRecordingWithStreaming(uploader: streamingUploader)
                                            } catch {
                                                logger.error("Failed to start streaming upload: \(error.localizedDescription)")
                                                cameraManager.error = .captureError("Streaming upload failed: \(error.localizedDescription)")
                                            }
                                        }
                                    } else {
                                        // Regular recording
                                        cameraManager.startRecording()
                                    }
                                }
                            } label: {
                                ZStack {
                                    if cameraManager.isRecording {
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 60, height: 60)
                                    } else {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .frame(width: 60, height: 60)
                                    }
                                    
                                    Image(systemName: cameraManager.isRecording ? "stop.circle.fill" : "video.fill")
                                        .font(.title2)
                                        .foregroundColor(cameraManager.isRecording ? .red : .white)
                                    
                                    // Show cloud icon overlay when streaming
                                    if enableStreamingUpload && cameraManager.isRecording {
                                        Image(systemName: "icloud.fill")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                            .offset(x: 15, y: -15)
                                    }
                                }
                            }
                            .symbolEffect(.pulse, isActive: cameraManager.isRecording)
                            .disabled(!cameraManager.isSessionRunning)
                        }
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.bottom, AppTheme.Spacing.xl)
                    }
                }
                
                // Instructions overlay
                if detectedItems.isEmpty && !cameraManager.isRecording {
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
                
                // Streaming upload indicator - Enhanced with more details
                if streamingUploader.isUploading && cameraManager.isRecording {
                    VStack {
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                // Animated upload icon
                                ZStack {
                                    Circle()
                                        .fill(.white.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: "icloud.and.arrow.up")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .symbolEffect(.bounce, options: .repeating)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text("Live Upload")
                                            .font(.callout)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        
                                        Circle()
                                            .fill(.white)
                                            .frame(width: 6, height: 6)
                                            .opacity(0.8)
                                    }
                                    
                                    Text("\(formatBytes(streamingUploader.bytesUploaded)) → Google Drive")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                
                                Spacer()
                            }
                            
                            // Upload speed indicator (optional - shows activity)
                            HStack(spacing: 4) {
                                ForEach(0..<10, id: \.self) { index in
                                    Capsule()
                                        .fill(.white.opacity(0.4))
                                        .frame(width: 20, height: 3)
                                        .overlay(
                                            Capsule()
                                                .fill(.white)
                                                .frame(width: streamingUploader.bytesUploaded > 0 ? 20 : 0, height: 3)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.green.gradient.opacity(0.95))
                                .shadow(color: .green.opacity(0.3), radius: 8, y: 4)
                        )
                        .padding(.top, 120)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        
                        Spacer()
                    }
                }
                
                // Upload completion indicator
                if !streamingUploader.isUploading && streamingUploader.bytesUploaded > 0 && !cameraManager.isRecording {
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Upload Complete!")
                                    .font(.callout)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text("\(formatBytes(streamingUploader.bytesUploaded)) saved to Drive")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.blue.gradient.opacity(0.95))
                        )
                        .padding(.top, 120)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            // Auto-dismiss after 3 seconds
                            Task {
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                await MainActor.run {
                                    withAnimation {
                                        // Reset uploader state
                                        streamingUploader.bytesUploaded = 0
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                logger.info("CameraScanView appeared")
                // Camera manager will auto-start session after configuration
                
                // Listen for video recording completion
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("VideoRecordingComplete"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let url = notification.userInfo?["url"] as? URL {
                        recordedVideoURL = url
                        showUploadOptions = true
                    }
                }
                
                // Listen for photo capture completion
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("PhotoCaptureComplete"),
                    object: nil,
                    queue: .main
                ) { notification in
                    // Photo saved - camera shutter sound provides feedback
                    // No alert needed
                }
                
                // Listen for streaming upload completion
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("StreamingUploadComplete"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let success = notification.userInfo?["success"] as? Bool {
                        if success {
                            if let bytesUploaded = notification.userInfo?["bytesUploaded"] as? Int64 {
                                logger.info("✅✅✅ Streaming upload completed successfully!")
                                logger.info("   Total uploaded: \(bytesUploaded) bytes")
                                logger.info("   File automatically saved to Google Drive")
                                
                                // Show success haptic
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                            }
                        } else {
                            if let errorMessage = notification.userInfo?["error"] as? String {
                                logger.error("❌ Streaming upload failed: \(errorMessage)")
                                
                                // Show error haptic
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.error)
                            }
                        }
                    }
                }
            }
            .onDisappear {
                logger.info("CameraScanView disappeared - stopping session")
                cameraManager.stopSession()
                NotificationCenter.default.removeObserver(self)
            }
            .alert(item: $cameraManager.error) { error in
                Alert(
                    title: Text("Camera Error"),
                    message: Text(error.localizedDescription),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(isPresented: $showUploadOptions) {
                uploadOptionsSheet
            }
            .overlay {
                if isUploading {
                    uploadProgressOverlay
                }
            }
            .videoSavedToast() // Add toast notification for video saves
        }
    }
    
    // MARK: - Helper Views
    
    private var uploadOptionsSheet: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.l) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                    .padding(.top, AppTheme.Spacing.xl)
                
                Text("Video Recorded!")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Your video has been saved successfully")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Divider()
                    .padding(.vertical)
                
                VStack(spacing: AppTheme.Spacing.m) {
                    Button {
                        Task {
                            await uploadToGoogleDrive()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "cloud.fill")
                            Text("Upload to Google Drive")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .fill(Color.blue)
                        )
                        .foregroundColor(.white)
                    }
                    
                    Button {
                        Task {
                            await saveToPhotos()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Save to Photos")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .fill(Color.green)
                        )
                        .foregroundColor(.white)
                    }
                    
                    Button {
                        if let url = recordedVideoURL {
                            shareVideo(url: url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Video")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .fill(Color.gray.opacity(0.2))
                        )
                        .foregroundColor(.primary)
                    }
                    
                    Button {
                        showUploadOptions = false
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Recording Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var uploadProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: AppTheme.Spacing.l) {
                ProgressView(value: uploadProgress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 200)
                
                Text("Uploading to Google Drive...")
                    .foregroundColor(.white)
                    .font(.callout)
                
                Text("\(Int(uploadProgress * 100))%")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(AppTheme.Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(.ultraThickMaterial)
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadSelectedPhoto() async {
        guard let item = selectedPhotoItem else { return }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                logger.info("Photo selected from library")
                
                // Process the selected photo (could add to detected items, etc.)
                await MainActor.run {
                    withAnimation {
                        detectedItems.append("Item from Photo \(detectedItems.count + 1)")
                    }
                }
                
                // Optionally, you could analyze this photo with AI/ML here
            }
        } catch {
            logger.error("Failed to load photo: \(error.localizedDescription)")
        }
        
        // Reset selection
        selectedPhotoItem = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func uploadToGoogleDrive() async {
        guard let videoURL = recordedVideoURL else { return }
        
        showUploadOptions = false
        
        // Read video data
        guard let videoData = try? Data(contentsOf: videoURL) else {
            logger.error("Failed to read video file")
            return
        }
        
        await MainActor.run {
            isUploading = true
            uploadProgress = 0.1
        }
        
        // Generate filename
        let timestamp = GoogleDriveUploader.iso8601FilenameTimestamp()
        let filename = "inventory_scan_\(timestamp).mov"
        
        // Use existing GoogleDriveUploader with completion handler
        await withCheckedContinuation { continuation in
            driveUploader.uploadDataChunk(
                data: videoData,
                mimeType: "video/quicktime",
                baseFilename: filename
            ) { result in
                Task { @MainActor in
                    isUploading = false
                    
                    switch result {
                    case .success(let fileName):
                        self.logger.info("✅ Video uploaded to Google Drive successfully: \(fileName)")
                        
                        // Clean up local file
                        try? FileManager.default.removeItem(at: videoURL)
                        self.recordedVideoURL = nil
                        
                    case .failure(let error):
                        self.logger.error("Failed to upload video: \(error.localizedDescription)")
                        
                        // Show error in camera manager
                        self.cameraManager.error = .captureError(error.localizedDescription)
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    private func saveToPhotos() async {
        guard let videoURL = recordedVideoURL else { return }
        
        showUploadOptions = false
        
        do {
            try await LocalVideoStorage.saveToPhotos(videoURL)
            logger.info("✅ Video saved to Photos successfully")
            recordedVideoURL = nil
        } catch {
            logger.error("Failed to save to Photos: \(error.localizedDescription)")
            
            // Show error alert
            if let cameraError = error as? LocalVideoStorage.StorageError {
                cameraManager.error = .captureError(cameraError.localizedDescription)
            }
        }
    }
    
    private func shareVideo(url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
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
    CameraScanView()
}

