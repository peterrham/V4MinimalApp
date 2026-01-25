//
//  StreamingVideoUploader.swift
//  V4MinimalApp
//
//  Streams video to Google Drive as it's being recorded
//

import Foundation
import AVFoundation

/// Handles streaming video upload to Google Drive during recording
@MainActor
class StreamingVideoUploader: NSObject, ObservableObject {
    
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var bytesUploaded: Int64 = 0
    
    private var uploadSessionURL: String?
    private var totalBytesExpected: Int64 = 0
    private var currentOffset: Int64 = 0
    
    private let chunkSize: Int = 256 * 1024 // 256 KB chunks
    private var pendingChunks: [Data] = []
    private var isProcessingChunks = false
    
    enum UploadError: Error {
        case notAuthenticated
        case sessionCreationFailed(String)
        case uploadFailed(String)
        case invalidResponse
    }
    
    // MARK: - Resumable Upload Session
    
    /// Start a new resumable upload session
    func startUploadSession(fileName: String, mimeType: String = "video/quicktime") async throws -> String {
        guard let accessToken = AuthManager.shared.getAccessToken() else {
            throw UploadError.notAuthenticated
        }
        
        // Create metadata for the file
        let timestamp = GoogleDriveUploader.iso8601FilenameTimestamp()
        let fullFileName = "\(fileName)_\(timestamp).mov"
        
        let metadata: [String: Any] = [
            "name": fullFileName,
            "mimeType": mimeType
        ]
        
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadata) else {
            throw UploadError.sessionCreationFailed("Failed to create metadata")
        }
        
        // Initiate resumable upload
        let initiateURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!
        var request = URLRequest(url: initiateURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = metadataData
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let location = httpResponse.value(forHTTPHeaderField: "Location") else {
            throw UploadError.sessionCreationFailed("Failed to get upload location")
        }
        
        uploadSessionURL = location
        isUploading = true
        currentOffset = 0
        bytesUploaded = 0
        
        appBootLog.infoWithContext("✅ Upload session created: \(fullFileName)")
        appBootLog.infoWithContext("   Session URL: \(location)")
        
        return location
    }
    
    // MARK: - Chunk Upload
    
    /// Upload a chunk of video data
    func uploadChunk(_ data: Data) async throws {
        guard let sessionURL = uploadSessionURL,
              let url = URL(string: sessionURL) else {
            appBootLog.errorWithContext("❌ No active upload session")
            throw UploadError.uploadFailed("No active upload session")
        }
        
        guard !data.isEmpty else { 
            appBootLog.warningWithContext("⚠️ Attempted to upload empty chunk, skipping")
            return 
        }
        
        let startByte = currentOffset
        let endByte = startByte + Int64(data.count) - 1
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // 30 second timeout for uploads
        
        // Content-Range header: "bytes START-END/*" 
        // Use * for total size since we don't know final size during recording
        let rangeHeader = "bytes \(startByte)-\(endByte)/*"
        request.setValue(rangeHeader, forHTTPHeaderField: "Content-Range")
        request.httpBody = data
        
        appBootLog.infoWithContext("📤 Uploading chunk:")
        appBootLog.debugWithContext("   Range: \(rangeHeader)")
        appBootLog.debugWithContext("   Size: \(data.count) bytes (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))")
        
        let uploadStart = Date()
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let uploadDuration = Date().timeIntervalSince(uploadStart)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            appBootLog.errorWithContext("❌ Invalid HTTP response")
            throw UploadError.invalidResponse
        }
        
        appBootLog.debugWithContext("   Response: HTTP \(httpResponse.statusCode)")
        appBootLog.debugWithContext("   Duration: \(String(format: "%.2f", uploadDuration))s")
        
        // 308 = Resume Incomplete (chunk uploaded, continue)
        // 200/201 = Upload complete
        if httpResponse.statusCode == 308 {
            // Chunk uploaded successfully, continue
            currentOffset = endByte + 1
            bytesUploaded = currentOffset
            
            let speed = Double(data.count) / uploadDuration / 1024.0 // KB/s
            appBootLog.infoWithContext("✅ Chunk uploaded! Total: \(ByteCountFormatter.string(fromByteCount: bytesUploaded, countStyle: .file))")
            appBootLog.debugWithContext("   Speed: \(String(format: "%.1f", speed)) KB/s")
            
        } else if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            // Upload complete (shouldn't happen during streaming, but handle it)
            currentOffset = endByte + 1
            bytesUploaded = currentOffset
            
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let fileId = json["id"] as? String,
               let fileName = json["name"] as? String {
                appBootLog.infoWithContext("✅ Upload complete! File ID: \(fileId), Name: \(fileName)")
            }
            
            isUploading = false
            uploadProgress = 1.0
            
        } else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            appBootLog.errorWithContext("❌ Upload failed: HTTP \(httpResponse.statusCode)")
            appBootLog.errorWithContext("   Error: \(errorMessage)")
            throw UploadError.uploadFailed("Status \(httpResponse.statusCode): \(errorMessage)")
        }
        
        // Update progress (if we know expected size)
        if totalBytesExpected > 0 {
            uploadProgress = Double(bytesUploaded) / Double(totalBytesExpected)
        }
    }
    
    /// Finalize the upload with known file size
    func finalizeUpload(totalSize: Int64) async throws {
        guard let sessionURL = uploadSessionURL,
              let url = URL(string: sessionURL) else {
            throw UploadError.uploadFailed("No active upload session")
        }
        
        appBootLog.infoWithContext("🏁 Finalizing upload...")
        appBootLog.infoWithContext("   Total file size: \(totalSize) bytes")
        appBootLog.infoWithContext("   Bytes uploaded so far: \(bytesUploaded) bytes")
        appBootLog.infoWithContext("   Current offset: \(currentOffset)")
        
        // Check if we've uploaded everything
        if currentOffset < totalSize {
            let missing = totalSize - currentOffset
            appBootLog.warningWithContext("⚠️ WARNING: Not all bytes uploaded! Missing \(missing) bytes")
        }
        
        // Create a custom URLSession with longer timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // 2 minutes for request
        config.timeoutIntervalForResource = 300 // 5 minutes total
        let session = URLSession(configuration: config)
        
        // Retry logic for finalization
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                appBootLog.infoWithContext("🔄 Finalization attempt \(attempt)/\(maxRetries)...")
                
                // Send final empty PUT with complete Content-Range
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
                request.setValue("bytes */\(totalSize)", forHTTPHeaderField: "Content-Range")
                request.httpBody = Data() // Empty body
                
                appBootLog.debugWithContext("   Sending finalization request with Content-Range: bytes */\(totalSize)")
                
                let startTime = Date()
                let (responseData, response) = try await session.data(for: request)
                let duration = Date().timeIntervalSince(startTime)
                
                appBootLog.debugWithContext("   Request took \(String(format: "%.2f", duration))s")
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    appBootLog.errorWithContext("❌ Invalid HTTP response during finalization")
                    throw UploadError.invalidResponse
                }
                
                appBootLog.infoWithContext("📥 Finalization response: HTTP \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                       let fileId = json["id"] as? String,
                       let fileName = json["name"] as? String {
                        appBootLog.infoWithContext("✅ Upload finalized! File ID: \(fileId), Name: \(fileName)")
                        appBootLog.infoWithContext("   🔗 View in Drive: https://drive.google.com/file/d/\(fileId)/view")
                    } else {
                        appBootLog.infoWithContext("✅ Upload finalized! (No file metadata in response)")
                    }
                    
                    isUploading = false
                    uploadProgress = 1.0
                    uploadSessionURL = nil
                    
                    return // Success!
                    
                } else if httpResponse.statusCode == 308 {
                    // Still expecting more data - this shouldn't happen during finalization
                    appBootLog.errorWithContext("❌ Got HTTP 308 during finalization - server still expects more data")
                    if let rangeHeader = httpResponse.value(forHTTPHeaderField: "Range") {
                        appBootLog.errorWithContext("   Server received: \(rangeHeader)")
                    }
                    throw UploadError.uploadFailed("Server still expects more data. Received: \(currentOffset), Expected: \(totalSize)")
                } else {
                    let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
                    appBootLog.errorWithContext("❌ Finalization failed: HTTP \(httpResponse.statusCode)")
                    appBootLog.errorWithContext("   Error response: \(errorMessage)")
                    throw UploadError.uploadFailed("Finalization failed: \(httpResponse.statusCode) - \(errorMessage)")
                }
                
            } catch {
                lastError = error
                appBootLog.errorWithContext("❌ Finalization attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    let delay = UInt64(attempt * 2) * 1_000_000_000 // Exponential backoff: 2s, 4s
                    appBootLog.infoWithContext("⏳ Waiting \(attempt * 2)s before retry...")
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        // All retries failed
        appBootLog.errorWithContext("❌ All finalization attempts failed")
        throw lastError ?? UploadError.uploadFailed("Finalization failed after \(maxRetries) attempts")
    }
    
    // MARK: - Queue-based Chunk Processing
    
    /// Add data to upload queue (for async processing)
    func queueChunk(_ data: Data) {
        pendingChunks.append(data)
        
        if !isProcessingChunks {
            Task {
                await processChunkQueue()
            }
        }
    }
    
    private func processChunkQueue() async {
        guard !isProcessingChunks else { return }
        isProcessingChunks = true
        
        while !pendingChunks.isEmpty {
            let chunk = pendingChunks.removeFirst()
            
            do {
                try await uploadChunk(chunk)
            } catch {
                appBootLog.errorWithContext("Failed to upload queued chunk: \(error.localizedDescription)")
                // Could implement retry logic here
            }
        }
        
        isProcessingChunks = false
    }
    
    // MARK: - Cancel Upload
    
    func cancelUpload() {
        uploadSessionURL = nil
        isUploading = false
        uploadProgress = 0
        bytesUploaded = 0
        currentOffset = 0
        pendingChunks.removeAll()
        
        appBootLog.infoWithContext("❌ Upload cancelled")
    }
}

// MARK: - Integration with CameraManager

extension StreamingVideoUploader {
    
    /// Monitor a file and upload chunks as they're written
    func monitorAndUploadFile(at fileURL: URL, fileName: String) async throws {
        // Start upload session
        _ = try await startUploadSession(fileName: fileName)
        
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        
        var lastPosition: UInt64 = 0
        
        // Poll file for new data every 0.5 seconds
        while isUploading {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check file size
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let fileSize = attributes[.size] as? UInt64 else { continue }
            
            if fileSize > lastPosition {
                // New data available
                let bytesToRead = fileSize - lastPosition
                
                try fileHandle.seek(toOffset: lastPosition)
                
                if let data = try fileHandle.read(upToCount: Int(bytesToRead)) {
                    try await uploadChunk(data)
                    lastPosition = fileSize
                }
            }
            
            // Check if recording has stopped (you'd need to set a flag)
            // For now, you'll need to call finalizeUpload() manually
        }
    }
}
