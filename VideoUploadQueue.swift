//
//  VideoUploadQueue.swift
//  V4MinimalApp
//
//  Manages continuous upload of multiple videos one at a time
//

import Foundation
import AVFoundation

/// Manages a queue of videos to upload to Google Drive sequentially
@MainActor
class VideoUploadQueue: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isUploading = false
    @Published var currentUploadProgress: Double = 0
    @Published var queuedVideos: [QueuedVideo] = []
    @Published var currentUpload: QueuedVideo?
    @Published var completedUploads: [CompletedUpload] = []
    @Published var failedUploads: [FailedUpload] = []
    
    // MARK: - Types
    
    enum UploadError: Error {
        case cancelled
        case fileNotFound
        case maxRetriesExceeded(attempts: Int)
        case uploadFailed(String)
        
        var localizedDescription: String {
            switch self {
            case .cancelled:
                return "Upload cancelled"
            case .fileNotFound:
                return "File not found"
            case .maxRetriesExceeded(let attempts):
                return "Upload failed after \(attempts) attempts"
            case .uploadFailed(let message):
                return message
            }
        }
    }
    
    struct QueuedVideo: Identifiable, Equatable {
        let id = UUID()
        let fileURL: URL
        let fileName: String
        let fileSize: Int64
        let queuedAt: Date
        
        var fileSizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }
    }
    
    struct CompletedUpload: Identifiable {
        let id = UUID()
        let fileName: String
        let fileSize: Int64
        let uploadedAt: Date
        let duration: TimeInterval
        let driveFileId: String?
        
        var speedFormatted: String {
            let bytesPerSecond = Double(fileSize) / duration
            let mbPerSecond = bytesPerSecond / 1_048_576.0 // Convert to MB/s
            return String(format: "%.2f MB/s", mbPerSecond)
        }
    }
    
    struct FailedUpload: Identifiable {
        let id = UUID()
        let fileName: String
        let fileURL: URL
        let error: String
        let failedAt: Date
        let retryCount: Int
    }
    
    // MARK: - Configuration
    
    var maxRetries = 3
    var retryDelay: TimeInterval = 5.0 // seconds
    var autoUpload = true // Automatically start uploading when videos are added
    var deleteAfterUpload = true // Delete local file after successful upload
    
    // MARK: - Private State
    
    private var uploadTask: Task<Void, Never>?
    private let uploader = StreamingVideoUploader()
    
    // MARK: - Singleton (Optional)
    
    static let shared = VideoUploadQueue()
    
    // MARK: - Queue Management
    
    /// Add a video to the upload queue
    func addVideo(_ fileURL: URL) {
        appBootLog.infoWithContext("📋 Adding video to upload queue: \(fileURL.lastPathComponent)")
        
        // Check if already in queue
        if queuedVideos.contains(where: { $0.fileURL == fileURL }) {
            appBootLog.warningWithContext("⚠️ Video already in queue: \(fileURL.lastPathComponent)")
            return
        }
        
        // Get file size
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int64 else {
            appBootLog.errorWithContext("❌ Could not get file size: \(fileURL.lastPathComponent)")
            return
        }
        
        let video = QueuedVideo(
            fileURL: fileURL,
            fileName: fileURL.lastPathComponent,
            fileSize: fileSize,
            queuedAt: Date()
        )
        
        queuedVideos.append(video)
        
        appBootLog.infoWithContext("✅ Video added to queue. Queue size: \(queuedVideos.count)")
        appBootLog.debugWithContext("   File: \(video.fileName)")
        appBootLog.debugWithContext("   Size: \(video.fileSizeFormatted)")
        
        // Auto-start upload if enabled
        if autoUpload && !isUploading {
            startUploading()
        }
    }
    
    /// Add multiple videos at once
    func addVideos(_ fileURLs: [URL]) {
        for url in fileURLs {
            addVideo(url)
        }
    }
    
    /// Remove a video from the queue
    func removeVideo(_ video: QueuedVideo) {
        queuedVideos.removeAll { $0.id == video.id }
        appBootLog.infoWithContext("🗑️ Removed video from queue: \(video.fileName)")
    }
    
    /// Clear all queued videos
    func clearQueue() {
        queuedVideos.removeAll()
        appBootLog.infoWithContext("🗑️ Upload queue cleared")
    }
    
    /// Clear completed uploads history
    func clearCompleted() {
        completedUploads.removeAll()
        appBootLog.infoWithContext("🗑️ Completed uploads cleared")
    }
    
    /// Clear failed uploads history
    func clearFailed() {
        failedUploads.removeAll()
        appBootLog.infoWithContext("🗑️ Failed uploads cleared")
    }
    
    // MARK: - Upload Control
    
    /// Start uploading videos from the queue
    func startUploading() {
        guard !isUploading else {
            appBootLog.warningWithContext("⚠️ Upload already in progress")
            return
        }
        
        guard !queuedVideos.isEmpty else {
            appBootLog.infoWithContext("ℹ️ No videos in queue to upload")
            return
        }
        
        appBootLog.infoWithContext("🚀 Starting upload queue processing...")
        appBootLog.infoWithContext("   Videos in queue: \(queuedVideos.count)")
        
        isUploading = true
        
        uploadTask = Task {
            await processQueue()
        }
    }
    
    /// Pause/stop uploading
    func stopUploading() {
        appBootLog.infoWithContext("⏸️ Stopping upload queue...")
        
        uploadTask?.cancel()
        uploadTask = nil
        
        isUploading = false
        currentUpload = nil
        currentUploadProgress = 0
        
        // Cancel current streaming upload
        uploader.cancelUpload()
        
        appBootLog.infoWithContext("✅ Upload queue stopped")
    }
    
    /// Retry a failed upload
    func retryFailedUpload(_ failed: FailedUpload) {
        appBootLog.infoWithContext("🔄 Retrying failed upload: \(failed.fileName)")
        
        // Remove from failed list
        failedUploads.removeAll { $0.id == failed.id }
        
        // Add back to queue
        addVideo(failed.fileURL)
    }
    
    /// Retry all failed uploads
    func retryAllFailed() {
        appBootLog.infoWithContext("🔄 Retrying all failed uploads (\(failedUploads.count))...")
        
        let failedCopy = failedUploads
        failedUploads.removeAll()
        
        for failed in failedCopy {
            addVideo(failed.fileURL)
        }
    }
    
    // MARK: - Queue Processing
    
    private func processQueue() async {
        appBootLog.infoWithContext("⚙️ Processing upload queue...")
        
        while !queuedVideos.isEmpty && !Task.isCancelled {
            // Get next video
            guard let video = queuedVideos.first else { break }
            
            currentUpload = video
            currentUploadProgress = 0
            
            appBootLog.infoWithContext("📤 Uploading \(queuedVideos.count) of \(queuedVideos.count + completedUploads.count): \(video.fileName)")
            
            // Upload with retry logic
            let result = await uploadVideoWithRetry(video)
            
            // Remove from queue
            queuedVideos.removeFirst()
            currentUpload = nil
            
            // Handle result
            switch result {
            case .success(let uploadInfo):
                appBootLog.infoWithContext("✅ Upload completed: \(video.fileName)")
                
                completedUploads.append(uploadInfo)
                
                // Delete local file if enabled
                if deleteAfterUpload {
                    try? FileManager.default.removeItem(at: video.fileURL)
                    appBootLog.infoWithContext("🗑️ Deleted local file: \(video.fileName)")
                }
                
                // Post notification
                NotificationCenter.default.post(
                    name: NSNotification.Name("VideoUploadCompleted"),
                    object: nil,
                    userInfo: [
                        "fileName": video.fileName,
                        "fileSize": video.fileSize,
                        "driveFileId": uploadInfo.driveFileId as Any
                    ]
                )
                
            case .failure(let error):
                appBootLog.errorWithContext("❌ Upload failed: \(video.fileName) - \(error.localizedDescription)")
                
                failedUploads.append(FailedUpload(
                    fileName: video.fileName,
                    fileURL: video.fileURL,
                    error: error.localizedDescription,
                    failedAt: Date(),
                    retryCount: maxRetries
                ))
                
                // Post notification
                NotificationCenter.default.post(
                    name: NSNotification.Name("VideoUploadFailed"),
                    object: nil,
                    userInfo: [
                        "fileName": video.fileName,
                        "error": error.localizedDescription
                    ]
                )
            }
            
            // Small delay between uploads
            if !queuedVideos.isEmpty {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        // Queue processing complete
        isUploading = false
        currentUploadProgress = 0
        
        appBootLog.infoWithContext("🏁 Upload queue processing complete")
        appBootLog.infoWithContext("   ✅ Completed: \(completedUploads.count)")
        appBootLog.infoWithContext("   ❌ Failed: \(failedUploads.count)")
        
        // Post completion notification
        NotificationCenter.default.post(
            name: NSNotification.Name("VideoUploadQueueComplete"),
            object: nil,
            userInfo: [
                "completed": completedUploads.count,
                "failed": failedUploads.count
            ]
        )
    }
    
    private func uploadVideoWithRetry(_ video: QueuedVideo) async -> Result<CompletedUpload, UploadError> {
        let startTime = Date()
        
        for attempt in 1...maxRetries {
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            
            appBootLog.infoWithContext("🔄 Upload attempt \(attempt)/\(maxRetries): \(video.fileName)")
            
            do {
                // Upload the video
                let driveFileId = try await uploadVideo(video)
                
                let duration = Date().timeIntervalSince(startTime)
                
                let uploadInfo = CompletedUpload(
                    fileName: video.fileName,
                    fileSize: video.fileSize,
                    uploadedAt: Date(),
                    duration: duration,
                    driveFileId: driveFileId
                )
                
                return .success(uploadInfo)
                
            } catch {
                appBootLog.errorWithContext("❌ Attempt \(attempt) failed: \(error.localizedDescription)")
                
                // If this wasn't the last attempt, wait before retrying
                if attempt < maxRetries {
                    let delay = retryDelay * Double(attempt) // Exponential backoff
                    appBootLog.infoWithContext("⏳ Waiting \(delay)s before retry...")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        return .failure(.maxRetriesExceeded(attempts: maxRetries))
    }
    
    private func uploadVideo(_ video: QueuedVideo) async throws -> String? {
        // Use simple upload for now (not streaming since file is already complete)
        // You can implement a resumable upload here similar to streaming
        
        appBootLog.infoWithContext("📤 Starting upload: \(video.fileName)")
        appBootLog.debugWithContext("   Size: \(video.fileSizeFormatted)")
        
        // Read file data
        guard FileManager.default.fileExists(atPath: video.fileURL.path) else {
            throw NSError(domain: "VideoUploadQueue", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        
        let fileData = try Data(contentsOf: video.fileURL)
        
        // Create upload session
        let sessionURL = try await uploader.startUploadSession(
            fileName: video.fileName.replacingOccurrences(of: ".mov", with: ""),
            mimeType: "video/quicktime"
        )
        
        appBootLog.infoWithContext("✅ Upload session created")
        
        // Upload in chunks
        let chunkSize = 512 * 1024 // 512 KB
        var offset = 0
        
        while offset < fileData.count {
            if Task.isCancelled {
                throw NSError(domain: "VideoUploadQueue", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Upload cancelled"])
            }
            
            let remainingBytes = fileData.count - offset
            let bytesToUpload = min(chunkSize, remainingBytes)
            let endIndex = offset + bytesToUpload
            let chunk = fileData[offset..<endIndex]
            
            try await uploader.uploadChunk(Data(chunk))
            
            offset += bytesToUpload
            
            // Update progress
            await MainActor.run {
                currentUploadProgress = Double(offset) / Double(fileData.count)
            }
            
            appBootLog.debugWithContext("📊 Progress: \(Int(currentUploadProgress * 100))%")
        }
        
        // Finalize upload
        appBootLog.infoWithContext("🏁 Finalizing upload...")
        try await uploader.finalizeUpload(totalSize: Int64(fileData.count))
        
        appBootLog.infoWithContext("✅ Upload complete: \(video.fileName)")
        
        // Return file ID if available (you'd need to capture this from the uploader)
        return nil
    }
    
    // MARK: - Computed Properties
    
    var totalQueueSize: Int64 {
        queuedVideos.reduce(0) { $0 + $1.fileSize }
    }
    
    var totalQueueSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalQueueSize, countStyle: .file)
    }
    
    var hasQueuedVideos: Bool {
        !queuedVideos.isEmpty
    }
    
    var hasCompletedUploads: Bool {
        !completedUploads.isEmpty
    }
    
    var hasFailedUploads: Bool {
        !failedUploads.isEmpty
    }
}

// MARK: - Notification Names

extension NSNotification.Name {
    static let videoUploadCompleted = NSNotification.Name("VideoUploadCompleted")
    static let videoUploadFailed = NSNotification.Name("VideoUploadFailed")
    static let videoUploadQueueComplete = NSNotification.Name("VideoUploadQueueComplete")
}
