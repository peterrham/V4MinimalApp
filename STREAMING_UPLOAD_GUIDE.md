# Streaming Video Upload to Google Drive

This guide explains how to use the streaming video upload feature that uploads video chunks to Google Drive **as the video is being recorded**.

## 🎯 Features

- ✅ **Real-time Upload**: Video chunks are uploaded during recording, not after
- ✅ **Progress Tracking**: See live upload progress with bytes uploaded
- ✅ **Resumable Uploads**: Uses Google Drive's resumable upload API
- ✅ **Efficient Memory**: Streams data instead of loading entire file into memory
- ✅ **Automatic Finalization**: Completes upload when recording stops
- ✅ **Visual Feedback**: Toggle button and progress indicator

## 🚀 How to Use

### In the Camera View

1. **Enable Streaming Upload**
   - Look for the cloud icon button in the top-right corner (next to flash)
   - Tap it to toggle streaming upload on/off
   - When **enabled**: Cloud icon is filled and green ☁️✅
   - When **disabled**: Cloud icon is slashed ☁️/

2. **Start Recording**
   - Tap the video button (bottom right)
   - When streaming is enabled, you'll see:
     - A small cloud icon on the video button
     - A green progress indicator at the top showing "Streaming to Drive"
     - Live byte count of uploaded data

3. **During Recording**
   - Video is automatically chunked into 256 KB pieces
   - Each chunk is uploaded every 0.5 seconds
   - Progress updates in real-time
   - Recording continues normally

4. **Stop Recording**
   - Tap the stop button
   - Final chunks are uploaded
   - Upload is automatically finalized
   - You'll get a notification when complete

## 📋 Technical Details

### Architecture

```
CameraScanView
    └── StreamingVideoUploader (manages upload session)
        └── CameraManager+StreamingUpload (monitors file and uploads chunks)
            └── CameraManager (handles recording)
```

### Upload Flow

1. **Session Creation**
   - When recording starts with streaming enabled
   - Creates a resumable upload session with Google Drive
   - Receives a session URL for chunk uploads

2. **Chunk Monitoring**
   - Background task monitors the video file
   - Checks file size every 0.5 seconds
   - Reads new data since last upload
   - Uploads chunk with proper byte range headers

3. **Upload Request**
   ```
   PUT {session-url}
   Content-Type: video/quicktime
   Content-Range: bytes START-END/*
   
   [chunk data]
   ```

4. **Finalization**
   - When recording stops, uploads remaining data
   - Sends final request with total file size
   - Google Drive creates the final file

### Key Files

- **`StreamingVideoUploader.swift`**
  - Manages resumable upload session
  - Handles chunk uploads
  - Tracks progress and bytes uploaded

- **`CameraManager+StreamingUpload.swift`**
  - Extension to CameraManager
  - Monitors video file during recording
  - Coordinates between recording and uploading

- **`CameraScanView.swift`**
  - UI for streaming toggle
  - Progress indicators
  - Notification handling

## ⚙️ Configuration

### Chunk Size

Default: **256 KB** per chunk

To change:
```swift
// In StreamingVideoUploader.swift
private let chunkSize: Int = 512 * 1024 // 512 KB
```

### Upload Interval

Default: **0.5 seconds**

To change:
```swift
// In CameraManager+StreamingUpload.swift
try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
```

## 🔧 Advanced Usage

### Programmatic Control

```swift
// In your view
@StateObject private var streamingUploader = StreamingVideoUploader()

// Start streaming upload
Task {
    try await cameraManager.startRecordingWithStreaming(
        uploader: streamingUploader
    )
}

// Monitor progress
streamingUploader.bytesUploaded // Int64
streamingUploader.uploadProgress // Double (0.0 - 1.0)
streamingUploader.isUploading // Bool
```

### Custom Upload Logic

```swift
// Create uploader
let uploader = StreamingVideoUploader()

// Start session
let sessionURL = try await uploader.startUploadSession(
    fileName: "my_video",
    mimeType: "video/quicktime"
)

// Upload chunks manually
let chunk = Data(...) // Your video chunk
try await uploader.uploadChunk(chunk)

// Finalize
try await uploader.finalizeUpload(totalSize: totalBytes)
```

### Notifications

Listen for upload completion:

```swift
NotificationCenter.default.addObserver(
    forName: NSNotification.Name("StreamingUploadComplete"),
    object: nil,
    queue: .main
) { notification in
    if let bytesUploaded = notification.userInfo?["bytesUploaded"] as? Int64 {
        print("Uploaded \(bytesUploaded) bytes to Google Drive")
    }
}
```

## 🐛 Troubleshooting

### Upload Not Starting

**Problem**: Cloud button enabled but upload doesn't start

**Solutions**:
1. Check Google Drive authentication
2. Verify network connection
3. Check logs for authentication errors
4. Ensure `AuthManager.shared.getAccessToken()` returns valid token

### Chunks Failing to Upload

**Problem**: Recording works but chunks aren't uploading

**Solutions**:
1. Check network connection during recording
2. Reduce chunk size for slower connections
3. Check Google Drive quota
4. Review upload session expiration (sessions last 24 hours)

### Upload Incomplete

**Problem**: Recording stops but upload isn't finalized

**Solutions**:
1. Check final chunk upload in logs
2. Verify `finalizeUpload()` is called
3. Check file size matches expected size
4. Review Google Drive API response

## 📊 Performance

### Network Usage

- **256 KB chunks** every **0.5 seconds**
- Average upload rate: **~512 KB/s** (4 Mbps)
- Adjust based on your network conditions

### Memory Usage

- **Minimal**: Only one chunk in memory at a time
- **Old approach**: Entire video file loaded into memory
- **Streaming**: Constant memory footprint regardless of video length

### Battery Impact

- Background uploads consume battery
- Consider user's battery state before enabling
- Offer toggle for user control

## 🔐 Security

- Uses OAuth 2.0 access tokens
- Tokens refreshed automatically via `AuthManager`
- Upload sessions expire after 24 hours
- Files uploaded to user's own Google Drive

## 📱 User Experience Tips

1. **Show Progress**: Always display upload progress during recording
2. **Toggle Control**: Let users enable/disable streaming
3. **Network Awareness**: Warn users if on cellular data
4. **Fallback Option**: Keep regular upload as backup
5. **Error Handling**: Gracefully handle upload failures

## 🎓 Example Implementation

```swift
struct MyCameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var streamingUploader = StreamingVideoUploader()
    @State private var enableStreaming = false
    
    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.session)
            
            VStack {
                // Toggle
                Toggle("Stream to Drive", isOn: $enableStreaming)
                    .padding()
                
                Spacer()
                
                // Record button
                Button("Record") {
                    Task {
                        if enableStreaming {
                            try await cameraManager.startRecordingWithStreaming(
                                uploader: streamingUploader
                            )
                        } else {
                            cameraManager.startRecording()
                        }
                    }
                }
                
                // Progress
                if streamingUploader.isUploading {
                    Text("Uploaded: \(formatBytes(streamingUploader.bytesUploaded))")
                }
            }
        }
    }
}
```

## 📚 Resources

- [Google Drive API - Resumable Uploads](https://developers.google.com/drive/api/guides/manage-uploads#resumable)
- [AVFoundation Recording Guide](https://developer.apple.com/documentation/avfoundation/capture_setup)
- [Swift Async/Await](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)

## ✅ Best Practices

1. **Always provide a toggle** - Let users choose
2. **Show network status** - Warn about data usage
3. **Handle errors gracefully** - Don't stop recording on upload failure
4. **Test on real networks** - Simulators don't reflect real conditions
5. **Monitor battery** - Disable on low battery
6. **Provide feedback** - Show progress and completion states

---

**Happy Streaming! 🎥☁️**
