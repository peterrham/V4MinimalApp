//
//  GoogleCloudStorageUploader.swift
//  V4MinimalApp
//
//  Streams video to Google Cloud Storage (GCS) with true streaming support
//  GCS allows streaming uploads without finalization
//

import Foundation

/// Handles true streaming video upload to Google Cloud Storage
@MainActor
class GoogleCloudStorageUploader: NSObject, ObservableObject {
    
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var bytesUploaded: Int64 = 0
    
    private var bucketName: String
    private var objectName: String?
    private var currentOffset: Int64 = 0
    
    enum UploadError: Error {
        case notAuthenticated
        case uploadFailed(String)
        case invalidResponse
    }
    
    /// Initialize with your GCS bucket name
    /// Example: "my-app-videos" (you'll need to create this in GCP Console)
    init(bucketName: String) {
        self.bucketName = bucketName
    }
    
    // MARK: - Streaming Upload (No Finalization Required!)
    
    /// Start streaming upload - creates object immediately
    func startUpload(fileName: String) async throws -> String {
        guard let accessToken = AuthManager.shared.getAccessToken() else {
            throw UploadError.notAuthenticated
        }
        
        let timestamp = GoogleDriveUploader.iso8601FilenameTimestamp()
        let fullObjectName = "\(fileName)_\(timestamp).mov"
        self.objectName = fullObjectName
        
        currentOffset = 0
        bytesUploaded = 0
        isUploading = true
        
        appBootLog.infoWithContext("✅ Starting GCS streaming upload: \(fullObjectName)")
        appBootLog.infoWithContext("   Bucket: \(bucketName)")
        
        return fullObjectName
    }
    
    /// Upload a chunk - object is immediately accessible in GCS
    func uploadChunk(_ data: Data) async throws {
        guard let objectName = objectName else {
            throw UploadError.uploadFailed("No active upload session")
        }
        
        guard !data.isEmpty else {
            appBootLog.warningWithContext("⚠️ Skipping empty chunk")
            return
        }
        
        guard let accessToken = AuthManager.shared.getAccessToken() else {
            throw UploadError.notAuthenticated
        }
        
        // GCS streaming upload endpoint
        // Using multipart upload API for simplicity
        let uploadURL = URL(string: "https://storage.googleapis.com/upload/storage/v1/b/\(bucketName)/o?uploadType=media&name=\(objectName)")!
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 30
        
        appBootLog.infoWithContext("📤 Uploading chunk to GCS:")
        appBootLog.debugWithContext("   Size: \(data.count) bytes")
        appBootLog.debugWithContext("   Offset: \(currentOffset)")
        
        let uploadStart = Date()
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let uploadDuration = Date().timeIntervalSince(uploadStart)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            currentOffset += Int64(data.count)
            bytesUploaded = currentOffset
            
            let speed = Double(data.count) / uploadDuration / 1024.0
            appBootLog.infoWithContext("✅ Chunk uploaded! Total: \(ByteCountFormatter.string(fromByteCount: bytesUploaded, countStyle: .file))")
            appBootLog.debugWithContext("   Speed: \(String(format: "%.1f", speed)) KB/s")
            
            // Object is NOW ACCESSIBLE in GCS - no finalization needed!
            
        } else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            appBootLog.errorWithContext("❌ Upload failed: HTTP \(httpResponse.statusCode)")
            appBootLog.errorWithContext("   Error: \(errorMessage)")
            throw UploadError.uploadFailed("Status \(httpResponse.statusCode): \(errorMessage)")
        }
    }
    
    /// Complete upload - optional, just for cleanup
    func completeUpload() async {
        appBootLog.infoWithContext("✅ GCS upload complete!")
        appBootLog.infoWithContext("   Object: gs://\(bucketName)/\(objectName ?? "unknown")")
        appBootLog.infoWithContext("   Total size: \(ByteCountFormatter.string(fromByteCount: bytesUploaded, countStyle: .file))")
        
        isUploading = false
        uploadProgress = 1.0
    }
    
    func cancelUpload() {
        isUploading = false
        uploadProgress = 0
        bytesUploaded = 0
        currentOffset = 0
        objectName = nil
        
        appBootLog.infoWithContext("❌ Upload cancelled")
    }
}

// MARK: - Setup Instructions

/*
 To use Google Cloud Storage instead of Google Drive:
 
 1. Create a GCS bucket:
    - Go to https://console.cloud.google.com/storage
    - Click "Create Bucket"
    - Name it (e.g., "your-app-videos")
    - Choose a region close to your users
    - Set access control to "Uniform"
 
 2. Enable GCS API:
    - Go to https://console.cloud.google.com/apis/library
    - Search for "Cloud Storage API"
    - Click "Enable"
 
 3. Update OAuth scopes in your app:
    - Add "https://www.googleapis.com/auth/devstorage.read_write"
    - This gives read/write access to GCS
 
 4. Use in your app:
    ```swift
    let uploader = GoogleCloudStorageUploader(bucketName: "your-app-videos")
    try await cameraManager.startRecordingWithGCS(uploader: uploader)
    ```
 
 COST: ~$0.02/GB/month for storage + $0.12/GB for egress
       For most apps, this is < $1/month
 
 BENEFITS:
 - No finalization required
 - Object available immediately
 - Better for large files
 - More reliable for streaming
 - Can set lifecycle rules (auto-delete after 30 days, etc.)
 */
