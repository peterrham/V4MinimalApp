//
//  VideoUploadQueueView.swift
//  V4MinimalApp
//
//  UI for managing video upload queue
//

import SwiftUI

struct VideoUploadQueueView: View {
    @ObservedObject var queue: VideoUploadQueue
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Current Upload Section
                if let current = queue.currentUpload {
                    Section {
                        CurrentUploadRow(
                            video: current,
                            progress: queue.currentUploadProgress
                        )
                    } header: {
                        Text("Uploading Now")
                    }
                }
                
                // Queued Videos Section
                if !queue.queuedVideos.isEmpty {
                    Section {
                        ForEach(queue.queuedVideos) { video in
                            QueuedVideoRow(video: video)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        queue.removeVideo(video)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text("Queue (\(queue.queuedVideos.count))")
                            Spacer()
                            Text(queue.totalQueueSizeFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        if !queue.isUploading && queue.autoUpload {
                            Text("Videos will upload automatically")
                        }
                    }
                }
                
                // Completed Uploads Section
                if !queue.completedUploads.isEmpty {
                    Section {
                        ForEach(queue.completedUploads) { upload in
                            CompletedUploadRow(upload: upload)
                        }
                    } header: {
                        HStack {
                            Text("Completed (\(queue.completedUploads.count))")
                            Spacer()
                            Button("Clear") {
                                queue.clearCompleted()
                            }
                            .font(.caption)
                            .foregroundStyle(.blue)
                        }
                    }
                }
                
                // Failed Uploads Section
                if !queue.failedUploads.isEmpty {
                    Section {
                        ForEach(queue.failedUploads) { failed in
                            FailedUploadRow(failed: failed) {
                                queue.retryFailedUpload(failed)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Failed (\(queue.failedUploads.count))")
                            Spacer()
                            Button("Retry All") {
                                queue.retryAllFailed()
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
                
                // Empty State
                if queue.queuedVideos.isEmpty && 
                   queue.completedUploads.isEmpty && 
                   queue.failedUploads.isEmpty &&
                   queue.currentUpload == nil {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            
                            Text("No Videos in Queue")
                                .font(.headline)
                            
                            Text("Record videos and they'll automatically be added to the upload queue")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                
                // Settings Section
                Section {
                    Toggle("Auto Upload", isOn: $queue.autoUpload)
                    Toggle("Delete After Upload", isOn: $queue.deleteAfterUpload)
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Auto upload starts uploading immediately when videos are added. Delete after upload removes local files after successful upload to save space.")
                }
            }
            .navigationTitle("Upload Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if queue.isUploading {
                        Button("Pause") {
                            queue.stopUploading()
                        }
                        .foregroundStyle(.orange)
                    } else if queue.hasQueuedVideos {
                        Button("Start") {
                            queue.startUploading()
                        }
                        .foregroundStyle(.blue)
                    }
                }
            }
        }
    }
}

// MARK: - Row Components

struct CurrentUploadRow: View {
    let video: VideoUploadQueue.QueuedVideo
    let progress: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.fileName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(video.fileSizeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }
            
            ProgressView(value: progress)
                .tint(.blue)
        }
        .padding(.vertical, 4)
    }
}

struct QueuedVideoRow: View {
    let video: VideoUploadQueue.QueuedVideo
    
    var body: some View {
        HStack {
            Image(systemName: "film")
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(video.fileName)
                    .font(.subheadline)
                
                HStack(spacing: 12) {
                    Text(video.fileSizeFormatted)
                    Text("•")
                    Text(video.queuedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CompletedUploadRow: View {
    let upload: VideoUploadQueue.CompletedUpload
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(upload.fileName)
                    .font(.subheadline)
                
                HStack(spacing: 12) {
                    Text(ByteCountFormatter.string(fromByteCount: upload.fileSize, countStyle: .file))
                    Text("•")
                    Text(upload.speedFormatted)
                    Text("•")
                    Text(upload.uploadedAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct FailedUploadRow: View {
    let failed: VideoUploadQueue.FailedUpload
    let onRetry: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(failed.fileName)
                    .font(.subheadline)
                
                Text(failed.error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button {
                onRetry()
            } label: {
                Text("Retry")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.orange))
            }
        }
    }
}

// MARK: - Upload Queue Badge

struct UploadQueueBadge: View {
    @ObservedObject var queue: VideoUploadQueue
    @State private var showQueue = false
    
    var body: some View {
        Button {
            showQueue = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: queue.isUploading ? "arrow.up.circle.fill" : "arrow.up.circle")
                    .font(.title2)
                    .foregroundStyle(queue.isUploading ? .blue : .white)
                    .symbolEffect(.pulse, isActive: queue.isUploading)
                
                if queue.queuedVideos.count > 0 {
                    Text("\(queue.queuedVideos.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(.red))
                        .offset(x: 8, y: -8)
                }
            }
        }
        .sheet(isPresented: $showQueue) {
            VideoUploadQueueView(queue: queue)
        }
    }
}

// MARK: - Preview

#Preview {
    VideoUploadQueueView(queue: {
        let queue = VideoUploadQueue()
        // Add some test data
        return queue
    }())
}
