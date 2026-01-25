//
//  CameraManager+StreamingUpload.swift
//  V4MinimalApp
//
//  Extension to CameraManager for streaming uploads during recording
//

import Foundation
import AVFoundation

extension CameraManager {
    
    /// Start recording with streaming upload to Google Drive
    func startRecordingWithStreaming(uploader: StreamingVideoUploader) async throws {
        guard !isRecording else { return }
        guard session.isRunning else {
            error = .captureError("Camera session not running")
            return
        }
        
        // Create temporary file URL
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "streaming_\(Date().timeIntervalSince1970).mov"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        // Remove any existing file
        try? FileManager.default.removeItem(at: fileURL)
        
        currentVideoURL = fileURL
        
        // Start upload session
        do {
            _ = try await uploader.startUploadSession(fileName: "inventory_scan")
            appBootLog.infoWithContext("✅ Streaming upload session started")
        } catch {
            appBootLog.errorWithContext("Failed to start upload session: \(error.localizedDescription)")
            throw error
        }
        
        // Start recording
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        
        await MainActor.run {
            isRecording = true
            recordingStartTime = Date()
        }
        
        // Start monitoring file and uploading chunks
        Task {
            await monitorRecordingAndUpload(fileURL: fileURL, uploader: uploader)
        }
        
        // Start timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    /// Monitor the recording file and upload chunks as they're written
    private func monitorRecordingAndUpload(fileURL: URL, uploader: StreamingVideoUploader) async {
        var lastPosition: UInt64 = 0
        let chunkSize: UInt64 = 256 * 1024 // 256 KB chunks
        
        while await MainActor.run(body: { isRecording }) {
            do {
                // Wait a bit before checking
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Check if file exists and get its size
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    continue
                }
                
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                guard let fileSize = attributes[.size] as? UInt64 else { continue }
                
                // Check if there's new data
                if fileSize > lastPosition {
                    let newDataSize = fileSize - lastPosition
                    
                    // Read new data
                    let fileHandle = try FileHandle(forReadingFrom: fileURL)
                    defer { try? fileHandle.close() }
                    
                    try fileHandle.seek(toOffset: lastPosition)
                    
                    if let data = try fileHandle.read(upToCount: Int(newDataSize)) {
                        // Upload chunk
                        appBootLog.infoWithContext("📤 Uploading \(data.count) bytes from offset \(lastPosition)")
                        
                        try await uploader.uploadChunk(data)
                        lastPosition = fileSize
                        
                        appBootLog.infoWithContext("✅ Chunk uploaded. Total uploaded: \(uploader.bytesUploaded) bytes")
                    }
                }
                
            } catch {
                appBootLog.errorWithContext("Error during streaming upload: \(error.localizedDescription)")
                // Continue monitoring despite errors
            }
        }
        
        // Recording stopped, finalize upload
        appBootLog.infoWithContext("🏁 Recording stopped, finalizing upload...")
        
        do {
            // Get final file size
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? UInt64 {
                
                // Upload any remaining data
                if fileSize > lastPosition {
                    let fileHandle = try FileHandle(forReadingFrom: fileURL)
                    defer { try? fileHandle.close() }
                    
                    try fileHandle.seek(toOffset: lastPosition)
                    
                    if let data = try fileHandle.read(upToCount: Int(fileSize - lastPosition)) {
                        appBootLog.infoWithContext("📤 Uploading final chunk: \(data.count) bytes")
                        try await uploader.uploadChunk(data)
                    }
                }
                
                // Finalize upload
                try await uploader.finalizeUpload(totalSize: Int64(fileSize))
                
                appBootLog.infoWithContext("✅ Streaming upload completed! Total size: \(fileSize) bytes")
                
                // Post notification
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("StreamingUploadComplete"),
                        object: nil,
                        userInfo: [
                            "fileURL": fileURL,
                            "bytesUploaded": uploader.bytesUploaded
                        ]
                    )
                }
            }
        } catch {
            appBootLog.errorWithContext("Failed to finalize upload: \(error.localizedDescription)")
            await MainActor.run {
                self.error = .captureError("Upload finalization failed: \(error.localizedDescription)")
            }
        }
    }
}
