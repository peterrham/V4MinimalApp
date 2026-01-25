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
        guard !isRecording else { 
            appBootLog.warningWithContext("⚠️ Already recording, ignoring request")
            return 
        }
        guard session.isRunning else {
            appBootLog.errorWithContext("❌ Cannot start recording: Camera session not running")
            error = .captureError("Camera session not running")
            return
        }
        
        appBootLog.infoWithContext("🎬 Starting recording with streaming upload...")
        
        // Create temporary file URL
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "streaming_\(Date().timeIntervalSince1970).mov"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        // Remove any existing file
        try? FileManager.default.removeItem(at: fileURL)
        appBootLog.debugWithContext("📁 Recording file: \(fileURL.lastPathComponent)")
        
        currentVideoURL = fileURL
        
        // Start upload session FIRST
        do {
            let sessionURL = try await uploader.startUploadSession(fileName: "inventory_scan")
            appBootLog.infoWithContext("✅ Streaming upload session created")
            appBootLog.debugWithContext("   Session URL: \(sessionURL)")
        } catch {
            appBootLog.errorWithContext("❌ Failed to start upload session: \(error.localizedDescription)")
            throw error
        }
        
        // Start recording
        appBootLog.infoWithContext("🎥 Starting AVFoundation recording...")
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        
        await MainActor.run {
            isRecording = true
            recordingStartTime = Date()
        }
        
        appBootLog.infoWithContext("✅ Recording started successfully")
        
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
        let chunkSize: UInt64 = 512 * 1024 // 512 KB chunks for better streaming performance
        let pollInterval: UInt64 = 1_000_000_000 // 1 second - gives AVFoundation time to write
        var consecutiveErrors = 0
        let maxConsecutiveErrors = 5
        
        appBootLog.infoWithContext("📡 Starting file monitoring and streaming...")
        appBootLog.debugWithContext("   Chunk size: \(chunkSize / 1024) KB")
        appBootLog.debugWithContext("   Poll interval: \(pollInterval / 1_000_000_000)s")
        
        // Wait for file to be created by AVFoundation
        var fileCreated = false
        for attempt in 1...10 {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                fileCreated = true
                appBootLog.infoWithContext("✅ Recording file created (attempt \(attempt))")
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        guard fileCreated else {
            appBootLog.errorWithContext("❌ Recording file was not created after 1 second")
            return
        }
        
        while await MainActor.run(body: { isRecording }) {
            do {
                // Wait before checking for new data
                try await Task.sleep(nanoseconds: pollInterval)
                
                // Check if file exists and get its size
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    appBootLog.warningWithContext("⚠️ Recording file disappeared")
                    continue
                }
                
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                guard let fileSize = attributes[.size] as? UInt64 else { 
                    appBootLog.warningWithContext("⚠️ Could not read file size")
                    continue 
                }
                
                // Check if there's new data
                if fileSize > lastPosition {
                    let newDataSize = fileSize - lastPosition
                    
                    appBootLog.debugWithContext("📊 File grew: +\(newDataSize) bytes (total: \(fileSize) bytes)")
                    
                    // Read new data in chunks to avoid memory issues
                    var currentChunkPosition = lastPosition
                    
                    while currentChunkPosition < fileSize {
                        let remainingBytes = fileSize - currentChunkPosition
                        let bytesToRead = min(chunkSize, remainingBytes)
                        
                        // Open file handle for this chunk
                        let fileHandle = try FileHandle(forReadingFrom: fileURL)
                        defer { try? fileHandle.close() }
                        
                        try fileHandle.seek(toOffset: currentChunkPosition)
                        
                        guard let data = try fileHandle.read(upToCount: Int(bytesToRead)), !data.isEmpty else {
                            appBootLog.warningWithContext("⚠️ No data read from offset \(currentChunkPosition)")
                            break
                        }
                        
                        // Upload chunk
                        appBootLog.infoWithContext("📤 Uploading chunk: \(data.count) bytes from offset \(currentChunkPosition)")
                        
                        try await uploader.uploadChunk(data)
                        currentChunkPosition += UInt64(data.count)
                        
                        appBootLog.infoWithContext("✅ Chunk uploaded. Progress: \(uploader.bytesUploaded) bytes total")
                        
                        // Reset error counter on success
                        consecutiveErrors = 0
                    }
                    
                    lastPosition = currentChunkPosition
                    
                } else if fileSize < lastPosition {
                    // File size decreased - this shouldn't happen
                    appBootLog.errorWithContext("❌ File size decreased! Was: \(lastPosition), now: \(fileSize)")
                    lastPosition = 0 // Reset position
                }
                
            } catch {
                consecutiveErrors += 1
                appBootLog.errorWithContext("❌ Error during streaming upload (\(consecutiveErrors)/\(maxConsecutiveErrors)): \(error.localizedDescription)")
                
                // If too many consecutive errors, stop monitoring
                if consecutiveErrors >= maxConsecutiveErrors {
                    appBootLog.errorWithContext("❌ Too many consecutive errors, stopping upload monitoring")
                    await MainActor.run {
                        self.error = .captureError("Streaming upload failed: \(error.localizedDescription)")
                    }
                    return
                }
                
                // Continue monitoring despite errors
                try? await Task.sleep(nanoseconds: pollInterval)
            }
        }
        
        // Recording stopped, finalize upload
        appBootLog.infoWithContext("🏁 Recording stopped, finalizing upload...")
        
        // Give AVFoundation time to finish writing
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        do {
            // Get final file size
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                appBootLog.errorWithContext("❌ Recording file disappeared before finalization")
                throw NSError(domain: "CameraManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Recording file not found"])
            }
            
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let fileSize = attributes[.size] as? UInt64 else {
                throw NSError(domain: "CameraManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not read final file size"])
            }
            
            appBootLog.infoWithContext("📊 Final file size: \(fileSize) bytes")
            appBootLog.infoWithContext("📊 Last uploaded position: \(lastPosition) bytes")
            
            // Upload any remaining data
            if fileSize > lastPosition {
                let remainingBytes = fileSize - lastPosition
                appBootLog.infoWithContext("📤 Uploading final \(remainingBytes) bytes...")
                
                let fileHandle = try FileHandle(forReadingFrom: fileURL)
                defer { try? fileHandle.close() }
                
                try fileHandle.seek(toOffset: lastPosition)
                
                if let data = try fileHandle.read(upToCount: Int(fileSize - lastPosition)), !data.isEmpty {
                    appBootLog.infoWithContext("📤 Final chunk size: \(data.count) bytes")
                    try await uploader.uploadChunk(data)
                    appBootLog.infoWithContext("✅ Final chunk uploaded")
                }
            }
            
            // Finalize upload
            appBootLog.infoWithContext("🏁 Finalizing upload with total size: \(fileSize) bytes")
            try await uploader.finalizeUpload(totalSize: Int64(fileSize))
            
            appBootLog.infoWithContext("✅✅✅ Streaming upload completed successfully! ✅✅✅")
            appBootLog.infoWithContext("   Total size: \(fileSize) bytes")
            appBootLog.infoWithContext("   Total uploaded: \(uploader.bytesUploaded) bytes")
            
            // Delete local file since it's been uploaded
            do {
                try FileManager.default.removeItem(at: fileURL)
                appBootLog.infoWithContext("🗑️ Local recording file deleted (uploaded to Drive)")
                
                await MainActor.run {
                    currentVideoURL = nil
                }
            } catch {
                appBootLog.warningWithContext("⚠️ Could not delete local file: \(error.localizedDescription)")
            }
            
            // Post notification
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("StreamingUploadComplete"),
                    object: nil,
                    userInfo: [
                        "fileURL": fileURL,
                        "bytesUploaded": uploader.bytesUploaded,
                        "success": true
                    ]
                )
            }
            
        } catch {
            appBootLog.errorWithContext("❌❌❌ Failed to finalize upload: \(error.localizedDescription)")
            await MainActor.run {
                self.error = .captureError("Upload finalization failed: \(error.localizedDescription)")
                
                NotificationCenter.default.post(
                    name: NSNotification.Name("StreamingUploadComplete"),
                    object: nil,
                    userInfo: [
                        "fileURL": fileURL,
                        "bytesUploaded": uploader.bytesUploaded,
                        "success": false,
                        "error": error.localizedDescription
                    ]
                )
            }
        }
    }
}
