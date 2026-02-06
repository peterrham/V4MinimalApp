//
//  QueuedPhotoScanView.swift
//  V4MinimalApp
//
//  Photo Queue capture mode - rapid-fire photo capture with background processing
//

import SwiftUI

struct QueuedPhotoScanView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var inventoryStore: InventoryStore
    @EnvironmentObject var sessionStore: DetectionSessionStore
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var queueManager = PhotoQueueManager()

    @State private var showResultsSheet = false
    @State private var showDebugInfo = false
    @State private var photoCaptureObserver: NSObjectProtocol?
    @State private var didQueueInitialPhotos = false

    /// Optional photos to queue immediately on appear (from library picker)
    var initialPhotos: [UIImage] = []

    var body: some View {
        ZStack {
            // Camera Preview
            cameraPreviewLayer

            // Overlay UI
            VStack(spacing: 0) {
                // Top bar
                topBar
                    .padding(.horizontal, AppTheme.Spacing.l)
                    .padding(.top, AppTheme.Spacing.l)

                Spacer()

                // Queue status strip
                if !queueManager.queue.isEmpty {
                    queueStatusStrip
                        .padding(.horizontal, AppTheme.Spacing.m)
                        .padding(.bottom, AppTheme.Spacing.m)
                }

                // Bottom controls
                bottomControls
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Set up auto-save to session
            queueManager.inventoryStore = inventoryStore
            queueManager.sessionStore = sessionStore

            if cameraManager.isAuthorized && !cameraManager.isSessionRunning {
                cameraManager.startSession()
            }
            // Queue any initial photos from library picker (only once)
            if !initialPhotos.isEmpty && !didQueueInitialPhotos {
                didQueueInitialPhotos = true
                for photo in initialPhotos {
                    queueManager.queuePhoto(photo)
                }
                // Show results sheet after a short delay to let processing start
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showResultsSheet = true
                }
            }
            // Add observer once on appear
            photoCaptureObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PhotoCaptureComplete"),
                object: nil,
                queue: .main
            ) { [weak queueManager] notification in
                guard let image = notification.userInfo?["image"] as? UIImage else { return }
                queueManager?.queuePhoto(image)

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
        .onDisappear {
            // Remove observer on disappear
            if let observer = photoCaptureObserver {
                NotificationCenter.default.removeObserver(observer)
                photoCaptureObserver = nil
            }
            cameraManager.stopSession()
            if queueManager.totalPhotosProcessed > 0 {
                queueManager.endSession()
            }
        }
        .sheet(isPresented: $showResultsSheet) {
            PhotoQueueResultsSheet(
                queueManager: queueManager,
                inventoryStore: inventoryStore,
                sessionStore: sessionStore
            )
        }
        .debugScreenName("QueuedPhotoScanView")
    }

    // MARK: - Camera Preview

    @ViewBuilder
    private var cameraPreviewLayer: some View {
        if cameraManager.isAuthorized && cameraManager.isSessionRunning {
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()
        } else if !cameraManager.isAuthorized {
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
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
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
        } else {
            Rectangle()
                .fill(.black)
                .overlay {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
                .ignoresSafeArea()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
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

                // Progress indicator showing completed/total
                if queueManager.totalPhotosQueued > 0 {
                    let total = queueManager.totalPhotosQueued
                    let completed = queueManager.totalPhotosProcessed
                    let remaining = queueManager.queue.filter { $0.status == .queued }.count
                    let processing = queueManager.currentlyProcessing.count

                    HStack(spacing: 8) {
                        // Main progress badge
                        HStack(spacing: 6) {
                            Image(systemName: "photo.stack.fill")
                                .font(.caption)
                            Text("\(completed)/\(total)")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(completed == total && total > 0 ? .green.opacity(0.8) : .purple.opacity(0.8)))

                        // Processing indicator (shown while processing)
                        if processing > 0 {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.6)
                                Text("\(processing)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.orange.opacity(0.8)))
                        }

                        // Waiting count (if any)
                        if remaining > 0 && !queueManager.isProcessing {
                            Text("\(remaining) waiting")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }

                Spacer()

                // Debug toggle
                Button {
                    showDebugInfo.toggle()
                } label: {
                    Image(systemName: showDebugInfo ? "info.circle.fill" : "info.circle")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(showDebugInfo ? .yellow : .white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.ultraThinMaterial))
                }
            }

            // Mode picker
            HStack(spacing: 8) {
                ForEach(PhotoQueueProcessingMode.allCases) { mode in
                    Button {
                        queueManager.processingMode = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.caption2)
                            Text(mode.rawValue)
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(queueManager.processingMode == mode ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(queueManager.processingMode == mode ? .blue : .white.opacity(0.2))
                        )
                    }
                }
            }
        }
    }

    // MARK: - Queue Status Strip

    private var queueStatusStrip: some View {
        VStack(spacing: 8) {
            // Debug metrics (when enabled)
            if showDebugInfo {
                HStack(spacing: 16) {
                    metricPill("Queued", value: "\(queueManager.totalPhotosQueued)")
                    metricPill("Processed", value: "\(queueManager.totalPhotosProcessed)")
                    metricPill("Items", value: "\(queueManager.totalItemsDetected)")
                    metricPill("Avg", value: "\(queueManager.averageProcessingTimeMs)ms")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
            }

            // Thumbnail strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(queueManager.queue.suffix(10)) { photo in
                        queueThumbnail(photo)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
    }

    private func metricPill(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func queueThumbnail(_ photo: QueuedPhoto) -> some View {
        ZStack {
            Image(uiImage: photo.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Status overlay
            RoundedRectangle(cornerRadius: 6)
                .fill(statusColor(photo.status).opacity(0.3))
                .frame(width: 50, height: 50)

            // Status icon
            statusIcon(photo.status)
                .font(.caption)
                .foregroundColor(.white)
                .shadow(radius: 2)
        }
    }

    private func statusColor(_ status: PhotoQueueStatus) -> Color {
        switch status {
        case .queued: return .gray
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: PhotoQueueStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "clock.fill")
        case .processing:
            ProgressView()
                .tint(.white)
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "xmark.circle.fill")
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            // Batch process button (only in batch mode with queued photos)
            if queueManager.processingMode == .batch && !queueManager.queue.isEmpty {
                Button {
                    queueManager.startProcessing()
                } label: {
                    ZStack {
                        Circle()
                            .fill(queueManager.isProcessing ? .gray : .green)
                            .frame(width: 60, height: 60)
                        if queueManager.isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(queueManager.isProcessing)
            } else {
                // Placeholder for balance
                Circle()
                    .fill(.clear)
                    .frame(width: 60, height: 60)
            }

            Spacer()

            // Shutter button
            Button {
                capturePhoto()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(.purple)
                        .frame(width: 70, height: 70)
                    Image(systemName: "photo.stack.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .disabled(!cameraManager.isSessionRunning)

            Spacer()

            // Results button
            Button {
                showResultsSheet = true
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 60, height: 60)
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title2)
                        .foregroundColor(.white)

                    // Count badge
                    if queueManager.totalItemsDetected > 0 {
                        Text("\(queueManager.totalItemsDetected)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.green))
                            .offset(x: 20, y: -20)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func capturePhoto() {
        // Just trigger the capture - observer registered in onAppear handles the result
        cameraManager.capturePhoto()
    }
}

// MARK: - Preview

#Preview {
    QueuedPhotoScanView()
        .environmentObject(InventoryStore())
        .environmentObject(DetectionSessionStore())
}
