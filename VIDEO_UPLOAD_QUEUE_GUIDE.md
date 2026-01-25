# Video Upload Queue - Continuous Background Uploads

## 🎯 Overview

The Video Upload Queue system automatically uploads recorded videos to Google Drive one at a time in the background. Videos are queued and processed sequentially, with automatic retry on failure.

## ✨ Key Features

- **Automatic Queueing**: Videos are automatically added to the upload queue when recording stops
- **Sequential Upload**: Uploads one video at a time to avoid overwhelming the network
- **Auto-Start**: Uploads begin automatically when videos are added to the queue
- **Retry Logic**: Failed uploads are automatically retried up to 3 times with exponential backoff
- **Progress Tracking**: Real-time progress for current upload and queue status
- **Save to Photos**: Videos are saved to Photos Library before upload
- **Auto-Delete**: Optional automatic deletion of local files after successful upload
- **Visual Feedback**: Upload queue badge shows status and count
- **Manual Control**: Pause, resume, retry, and remove videos from queue

## 🏗️ Architecture

### Components

1. **VideoUploadQueue** - Main queue manager (observable)
2. **VideoUploadQueueView** - UI for viewing and managing queue
3. **UploadQueueBadge** - Camera overlay badge showing queue status
4. **StreamingVideoUploader** - Handles actual upload to Google Drive

### Flow

```
Recording Stops
    ↓
Save to Photos Library
    ↓
Add to Upload Queue
    ↓
Queue Starts Processing (if auto-upload enabled)
    ↓
Upload Video #1
    ├─ Success → Mark Complete → Delete Local File (if enabled)
    └─ Failure → Retry (up to 3x) → Mark Failed
    ↓
Upload Video #2
    ↓
... Continue until queue empty
    ↓
Queue Complete Notification
```

## 📱 Usage

### Automatic (Default Behavior)

Videos are automatically queued and uploaded when you stop recording:

```swift
// In CameraManager - automatic when recording stops
func fileOutput(...) {
    // Save to Photos
    await saveVideoToLibrary(outputFileURL)
    
    // Add to upload queue (automatic)
    VideoUploadQueue.shared.addVideo(outputFileURL)
}
```

### Manual Queue Management

```swift
// Access the shared queue
let queue = VideoUploadQueue.shared

// Add videos manually
queue.addVideo(fileURL)
queue.addVideos([url1, url2, url3])

// Control upload
queue.startUploading()
queue.stopUploading()

// Manage queue
queue.removeVideo(video)
queue.clearQueue()

// Retry failed uploads
queue.retryFailedUpload(failed)
queue.retryAllFailed()

// Clear history
queue.clearCompleted()
queue.clearFailed()
```

### Settings

```swift
// Configure queue behavior
queue.autoUpload = true          // Auto-start when videos added
queue.deleteAfterUpload = true   // Delete local files after upload
queue.maxRetries = 3             // Number of retry attempts
queue.retryDelay = 5.0           // Base delay between retries (seconds)
```

### Accessing Queue Status

```swift
// Published properties (automatically update UI)
queue.isUploading              // Bool - is currently uploading
queue.currentUploadProgress    // Double (0.0-1.0)
queue.queuedVideos            // [QueuedVideo]
queue.currentUpload           // QueuedVideo?
queue.completedUploads        // [CompletedUpload]
queue.failedUploads           // [FailedUpload]

// Computed properties
queue.hasQueuedVideos         // Bool
queue.totalQueueSize          // Int64 (bytes)
queue.totalQueueSizeFormatted // String (e.g., "45.2 MB")
```

## 🎨 UI Components

### 1. Upload Queue Badge (Camera View)

Shows queue status in camera view:

```swift
// Add to camera view
UploadQueueBadge(queue: VideoUploadQueue.shared)
```

Features:
- Shows upload icon (pulsing when uploading)
- Badge count showing queued videos
- Tap to open full queue view

### 2. Video Upload Queue View

Full-screen queue management:

```swift
VideoUploadQueueView(queue: VideoUploadQueue.shared)
```

Sections:
- **Uploading Now**: Current upload with progress bar
- **Queue**: Pending videos (swipe to remove)
- **Completed**: Successfully uploaded videos
- **Failed**: Failed uploads with retry button
- **Settings**: Auto-upload and delete options

## 📊 Data Types

### QueuedVideo

```swift
struct QueuedVideo: Identifiable {
    let id: UUID
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let queuedAt: Date
    var fileSizeFormatted: String  // e.g., "12.5 MB"
}
```

### CompletedUpload

```swift
struct CompletedUpload: Identifiable {
    let id: UUID
    let fileName: String
    let fileSize: Int64
    let uploadedAt: Date
    let duration: TimeInterval
    let driveFileId: String?
    var speedFormatted: String  // e.g., "2.3 MB/s"
}
```

### FailedUpload

```swift
struct FailedUpload: Identifiable {
    let id: UUID
    let fileName: String
    let fileURL: URL
    let error: String
    let failedAt: Date
    let retryCount: Int
}
```

## 🔔 Notifications

The queue posts notifications for key events:

```swift
// Video upload completed successfully
NotificationCenter.default.addObserver(
    forName: .videoUploadCompleted,
    object: nil,
    queue: .main
) { notification in
    let fileName = notification.userInfo?["fileName"] as? String
    let fileSize = notification.userInfo?["fileSize"] as? Int64
    let driveFileId = notification.userInfo?["driveFileId"] as? String
}

// Video upload failed
NotificationCenter.default.addObserver(
    forName: .videoUploadFailed,
    object: nil,
    queue: .main
) { notification in
    let fileName = notification.userInfo?["fileName"] as? String
    let error = notification.userInfo?["error"] as? String
}

// Queue finished processing all videos
NotificationCenter.default.addObserver(
    forName: .videoUploadQueueComplete,
    object: nil,
    queue: .main
) { notification in
    let completed = notification.userInfo?["completed"] as? Int
    let failed = notification.userInfo?["failed"] as? Int
}
```

## ⚙️ Configuration

### Enable/Disable Auto-Upload

```swift
// Disable auto-upload (manual start required)
VideoUploadQueue.shared.autoUpload = false

// Videos will be queued but not uploaded until you call:
VideoUploadQueue.shared.startUploading()
```

### Keep Local Files After Upload

```swift
// Keep files after upload (don't auto-delete)
VideoUploadQueue.shared.deleteAfterUpload = false
```

### Adjust Retry Behavior

```swift
VideoUploadQueue.shared.maxRetries = 5        // Try up to 5 times
VideoUploadQueue.shared.retryDelay = 10.0     // Wait 10s before retry
```

## 🧪 Testing

### 1. Basic Queue Test

```swift
// Record a video
// Stop recording
// Check queue badge shows "1"
// Wait for upload to complete
// Verify video in Google Drive
// Check Photos app for saved video
```

### 2. Multiple Videos Test

```swift
// Record 3 short videos
// All should queue automatically
// Queue badge should show "3"
// Uploads should process one at a time
// Progress should update for each
```

### 3. Retry Test

```swift
// Turn off network
// Record a video
// Upload should fail and retry
// Turn network back on
// Should succeed on retry
```

### 4. Manual Control Test

```swift
// Set autoUpload = false
// Record videos
// Videos queue but don't upload
// Tap queue badge
// Tap "Start" button
// Uploads begin
```

## 📝 Logs to Watch

```
📋 Adding video to upload queue: streaming_1234567890.mov
✅ Video added to queue. Queue size: 1
   File: streaming_1234567890.mov
   Size: 12.5 MB

🚀 Starting upload queue processing...
   Videos in queue: 1

📤 Uploading 1 of 1: streaming_1234567890.mov
🔄 Upload attempt 1/3: streaming_1234567890.mov
📤 Starting upload: streaming_1234567890.mov
   Size: 12.5 MB

✅ Upload session created
📊 Progress: 10%
📊 Progress: 20%
...
📊 Progress: 100%
🏁 Finalizing upload...
✅ Upload complete: streaming_1234567890.mov

✅ Upload completed: streaming_1234567890.mov
🗑️ Deleted local file: streaming_1234567890.mov

🏁 Upload queue processing complete
   ✅ Completed: 1
   ❌ Failed: 0
```

## 🐛 Troubleshooting

### Queue Not Starting Automatically

**Check:**
- `queue.autoUpload` is `true`
- Google Drive authentication is valid
- Network is available

**Solution:**
```swift
VideoUploadQueue.shared.autoUpload = true
```

### Videos Not Being Added to Queue

**Check:**
- Video file exists at URL
- File permissions are correct

**Solution:**
```swift
// Manually add video
VideoUploadQueue.shared.addVideo(videoURL)
```

### Uploads Failing

**Check logs for:**
- Network errors
- Authentication errors
- File size issues

**Solution:**
```swift
// Retry failed uploads
VideoUploadQueue.shared.retryAllFailed()
```

### Queue Badge Not Updating

**Ensure:**
- Using `VideoUploadQueue.shared` (singleton)
- Queue is marked as `@ObservedObject` in view

**Solution:**
```swift
@ObservedObject var queue = VideoUploadQueue.shared
```

## 🚀 Advanced Usage

### Custom Upload Processing

```swift
// Observe queue changes
queue.$completedUploads
    .sink { uploads in
        print("Completed: \(uploads.count)")
    }
    .store(in: &cancellables)
```

### Batch Operations

```swift
// Add all videos from documents directory
let videos = LocalVideoStorage.listSavedVideos()
VideoUploadQueue.shared.addVideos(videos)
```

### Statistics

```swift
let queue = VideoUploadQueue.shared

print("Total queued: \(queue.queuedVideos.count)")
print("Total size: \(queue.totalQueueSizeFormatted)")
print("Completed: \(queue.completedUploads.count)")
print("Failed: \(queue.failedUploads.count)")

// Average upload speed
let avgSpeed = queue.completedUploads
    .map { Double($0.fileSize) / $0.duration }
    .reduce(0, +) / Double(queue.completedUploads.count)
print("Avg speed: \(avgSpeed / 1_048_576) MB/s")
```

## 📚 Related Files

- `VideoUploadQueue.swift` - Queue manager implementation
- `VideoUploadQueueView.swift` - UI components
- `StreamingVideoUploader.swift` - Upload handler
- `CameraManager.swift` - Integration with camera
- `LocalVideoStorage.swift` - Local file management

## 🎯 Best Practices

1. **Use Singleton**: Always use `VideoUploadQueue.shared` for consistency
2. **Monitor Queue**: Use upload queue badge to show users upload status
3. **Handle Failures**: Check failed uploads and provide retry option
4. **Save to Photos First**: Always save to Photos before upload (backup)
5. **Test Network Issues**: Test app behavior with poor/no network
6. **Manage Storage**: Enable auto-delete to free up space after upload
7. **Inform Users**: Show clear status when uploads are in progress

---

**Questions?** Check the code comments or refer to the example usage in `CameraScanView.swift`
