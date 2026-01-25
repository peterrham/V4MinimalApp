# Streaming Upload - Quick Reference

## Enable Streaming in UI
```swift
@State private var enableStreamingUpload = false
@StateObject private var streamingUploader = StreamingVideoUploader()

// Toggle button
Button {
    enableStreamingUpload.toggle()
} label: {
    Image(systemName: enableStreamingUpload ? "icloud.fill" : "icloud.slash.fill")
}
```

## Start Streaming Recording
```swift
if enableStreamingUpload {
    Task {
        try await cameraManager.startRecordingWithStreaming(
            uploader: streamingUploader
        )
    }
} else {
    cameraManager.startRecording() // Regular recording
}
```

## Stop Recording
```swift
// Same for both streaming and regular
cameraManager.stopRecording()
```

## Monitor Upload Status
```swift
// Show indicator while uploading
if streamingUploader.isUploading && cameraManager.isRecording {
    HStack {
        Image(systemName: "icloud.and.arrow.up")
            .symbolEffect(.bounce, options: .repeating)
        
        Text("Live Upload")
        Text("\(formatBytes(streamingUploader.bytesUploaded))")
    }
}
```

## Listen for Completion
```swift
NotificationCenter.default.addObserver(
    forName: NSNotification.Name("StreamingUploadComplete"),
    object: nil,
    queue: .main
) { notification in
    let success = notification.userInfo?["success"] as? Bool ?? false
    let bytes = notification.userInfo?["bytesUploaded"] as? Int64 ?? 0
    
    if success {
        print("✅ Uploaded \(bytes) bytes to Drive")
        // Trigger haptic
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    } else {
        let error = notification.userInfo?["error"] as? String ?? "Unknown"
        print("❌ Upload failed: \(error)")
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
```

## Format Bytes Helper
```swift
private func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
```

## Key Properties to Monitor

### CameraManager
- `isRecording: Bool` - Currently recording
- `recordingDuration: TimeInterval` - Recording length
- `currentVideoURL: URL?` - Temp file location (will be deleted)

### StreamingVideoUploader
- `isUploading: Bool` - Upload session active
- `uploadProgress: Double` - 0.0 to 1.0 (if total size known)
- `bytesUploaded: Int64` - Total bytes sent to Drive

## Important Notes

⚠️ **Do NOT save the file manually** when streaming is enabled - it's automatically uploaded and deleted

⚠️ **Ensure Google Drive auth** before starting - streaming will fail without valid token

⚠️ **Network required** - Streaming requires active internet connection

⚠️ **Temp file lifecycle** - File is created → uploaded → deleted automatically

✅ **Automatic cleanup** - Local file is deleted after successful upload

✅ **Real-time upload** - Video chunks upload while recording

✅ **Error handling** - Up to 5 consecutive errors before stopping

## Console Log Indicators

| Emoji | Meaning |
|-------|---------|
| 🎬 | Recording start |
| 📁 | File operations |
| 📡 | Monitoring started |
| 📊 | File size info |
| 📤 | Uploading chunk |
| ✅ | Success |
| ❌ | Error |
| ⚠️ | Warning |
| 🏁 | Finalization |
| 🗑️ | File deleted |

## Typical Log Sequence
```
🎬 Starting recording with streaming upload...
📁 Recording file: streaming_1234567890.mov
✅ Streaming upload session created
🎥 Starting AVFoundation recording...
✅ Recording started successfully
📡 Starting file monitoring and streaming...
✅ Recording file created (attempt 1)
📊 File grew: +524288 bytes (total: 524288 bytes)
📤 Uploading chunk: 524288 bytes from offset 0
✅ Chunk uploaded! Total: 512 KB
[... more chunks ...]
🏁 Recording stopped, finalizing upload...
📊 Final file size: 2621440 bytes
✅✅✅ Streaming upload completed successfully!
🗑️ Local recording file deleted
```

## Configuration Values

```swift
// CameraManager+StreamingUpload.swift
let chunkSize: UInt64 = 512 * 1024        // 512 KB chunks
let pollInterval: UInt64 = 1_000_000_000   // 1 second
let maxConsecutiveErrors = 5               // Stop after 5 errors

// StreamingVideoUploader.swift
request.timeoutInterval = 30               // 30 second timeout
```

## Testing Checklist

```
□ Toggle streaming on (cloud icon green)
□ Start recording (see Live Upload banner)
□ Watch bytes increase in real-time
□ Check console for chunk uploads
□ Stop recording
□ Verify completion banner
□ Check file uploaded to Google Drive
□ Verify temp file deleted
□ Test error handling (turn off wifi)
□ Test long recording (5+ minutes)
```

## Error Handling Pattern

```swift
Task {
    do {
        try await cameraManager.startRecordingWithStreaming(
            uploader: streamingUploader
        )
    } catch {
        print("❌ Failed to start streaming: \(error)")
        cameraManager.error = .captureError(
            "Streaming upload failed: \(error.localizedDescription)"
        )
    }
}
```

## Quick Troubleshooting

| Issue | Check | Solution |
|-------|-------|----------|
| Won't start | Auth token | Re-authenticate with Google |
| No chunks uploading | Network | Check internet connection |
| Upload incomplete | Drive storage | Free up Google Drive space |
| File not deleted | Upload failed | Check logs for error, retry |
| Slow upload | Network speed | Use WiFi instead of cellular |

## File Locations

- **Temp recording**: `FileManager.default.temporaryDirectory`
- **Filename pattern**: `streaming_{timestamp}.mov`
- **Final location**: Google Drive (automatically uploaded)
- **Local cleanup**: Automatic after successful upload

## Integration Pattern

```swift
struct CameraScanView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var streamingUploader = StreamingVideoUploader()
    @State private var enableStreamingUpload = false
    
    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
            
            // Streaming toggle
            Button { enableStreamingUpload.toggle() } label: {
                Image(systemName: enableStreamingUpload ? "icloud.fill" : "icloud.slash.fill")
            }
            
            // Record button
            Button {
                if cameraManager.isRecording {
                    cameraManager.stopRecording()
                } else {
                    if enableStreamingUpload {
                        Task {
                            try await cameraManager.startRecordingWithStreaming(
                                uploader: streamingUploader
                            )
                        }
                    } else {
                        cameraManager.startRecording()
                    }
                }
            } label: {
                Image(systemName: cameraManager.isRecording ? "stop.fill" : "video.fill")
            }
            
            // Upload indicator
            if streamingUploader.isUploading {
                UploadIndicatorView(uploader: streamingUploader)
            }
        }
        .onAppear {
            setupNotifications()
        }
    }
}
```

---

**Remember**: When streaming is enabled, everything is automatic - just start recording and stop when done. The video will be on Google Drive and the local file will be cleaned up!
