# Streaming Video Upload - Complete Usage Guide

## Overview

The streaming video upload feature allows you to record videos that are **automatically uploaded to Google Drive in real-time** as you record. The video is uploaded in chunks while recording is in progress, and the local file is automatically deleted after successful upload.

## Key Benefits

✅ **No manual upload needed** - Videos stream directly to Google Drive while recording  
✅ **Saves device storage** - Local file is deleted after successful upload  
✅ **Works for long recordings** - Chunked uploads prevent memory issues  
✅ **Real-time feedback** - Visual indicators show upload progress  
✅ **Resilient** - Handles network interruptions gracefully  

## How to Use

### 1. Enable Streaming Upload

In the camera view, tap the **cloud icon** in the top-right corner:
- **Green cloud** (icloud.fill) = Streaming enabled
- **Slashed cloud** (icloud.slash.fill) = Streaming disabled

### 2. Start Recording

When streaming is enabled, tap the **video button** to start recording. You'll see:
- A **green "Live Upload" banner** at the top showing upload progress
- The banner displays bytes uploaded in real-time
- An animated cloud icon indicates active streaming

### 3. Stop Recording

Tap the **stop button** to end recording. The system will:
1. Upload any remaining video data
2. Finalize the upload to Google Drive
3. Delete the local file automatically
4. Show a success notification

### 4. Monitor Progress

While recording and streaming:
- **Top banner** shows real-time upload status
- **Console logs** provide detailed upload information
- **Haptic feedback** confirms successful completion

## Visual Indicators

### During Recording
```
┌─────────────────────────────────────┐
│  🔵 Live Upload                     │
│  256 KB → Google Drive              │
│  ▬▬▬▬▬▬▬▬▬▬                        │
└─────────────────────────────────────┘
```

### Upload Complete
```
┌─────────────────────────────────────┐
│  ✓ Upload Complete!                 │
│  2.5 MB saved to Drive              │
└─────────────────────────────────────┘
```

## Understanding the Logs

### Console Output Examples

#### Successful Recording Start
```
🎬 Starting recording with streaming upload...
📁 Recording file: streaming_1234567890.mov
✅ Streaming upload session created
🎥 Starting AVFoundation recording...
✅ Recording started successfully
📡 Starting file monitoring and streaming...
   Chunk size: 512 KB
   Poll interval: 1s
✅ Recording file created (attempt 1)
```

#### During Streaming
```
📊 File grew: +524288 bytes (total: 524288 bytes)
📤 Uploading chunk: 524288 bytes from offset 0
   Range: bytes 0-524287/*
   Size: 524288 bytes (512 KB)
   Response: HTTP 308
   Duration: 0.45s
✅ Chunk uploaded! Total: 512 KB
   Speed: 1137.8 KB/s
```

#### Finalization
```
🏁 Recording stopped, finalizing upload...
📊 Final file size: 2621440 bytes
📊 Last uploaded position: 2097152 bytes
📤 Uploading final 524288 bytes...
📤 Final chunk size: 524288 bytes
✅ Final chunk uploaded
🏁 Finalizing upload with total size: 2621440 bytes
✅✅✅ Streaming upload completed successfully! ✅✅✅
   Total size: 2621440 bytes
   Total uploaded: 2621440 bytes
🗑️ Local recording file deleted (uploaded to Drive)
```

## Technical Details

### Upload Strategy

1. **Chunk Size**: 512 KB per chunk
   - Large enough for efficiency
   - Small enough to handle network interruptions

2. **Poll Interval**: 1 second
   - Gives AVFoundation time to write data
   - Reduces file handle conflicts
   - Balances responsiveness with system load

3. **Error Handling**: Up to 5 consecutive errors allowed
   - Prevents infinite retry loops
   - Gracefully handles temporary network issues
   - Shows clear error messages to user

### File Lifecycle

```
┌──────────────┐
│ Start Record │
└──────┬───────┘
       │
       v
┌──────────────────────┐
│ Create Temp File     │ ← AVFoundation writes here
└──────┬───────────────┘
       │
       v
┌──────────────────────┐
│ Start Upload Session │ ← Google Drive resumable session
└──────┬───────────────┘
       │
       v
┌──────────────────────┐
│ Monitor & Stream     │ ← Read new bytes, upload chunks
└──────┬───────────────┘
       │
       v
┌──────────────────────┐
│ Stop Recording       │
└──────┬───────────────┘
       │
       v
┌──────────────────────┐
│ Upload Final Chunks  │
└──────┬───────────────┘
       │
       v
┌──────────────────────┐
│ Finalize Upload      │ ← Tell Drive total size
└──────┬───────────────┘
       │
       v
┌──────────────────────┐
│ Delete Local File    │ ← Cleanup temp storage
└──────────────────────┘
```

## Important Notes

### ✅ Do This
- Enable streaming upload for long recordings
- Check that you're authenticated with Google Drive
- Ensure stable network connection
- Monitor console logs for troubleshooting

### ❌ Don't Do This
- Don't manually try to save/upload after streaming recording
- Don't delete the app during an active upload
- Don't switch to airplane mode during streaming
- Don't expect the local file to persist after upload

## Troubleshooting

### "No active upload session" error
**Cause**: Upload session wasn't created  
**Solution**: Check Google Drive authentication, retry recording

### Upload seems slow
**Cause**: Network speed or large file size  
**Solution**: Check network connection, logs show upload speed per chunk

### Recording stops unexpectedly
**Cause**: Too many upload errors (5 consecutive failures)  
**Solution**: Check network, ensure Drive has storage space

### Local file still exists after upload
**Cause**: Upload failed or was interrupted  
**Solution**: Check logs for error messages, manually delete file or retry

## Best Practices

1. **Test with short recordings first** - Verify setup before long sessions
2. **Monitor the upload indicator** - Ensure chunks are uploading during recording
3. **Use stable Wi-Fi** - Cellular data may be slow or hit limits
4. **Check Drive storage** - Ensure you have enough space
5. **Watch console logs** - Rich debugging information available

## Code Integration

### In Your View
```swift
@StateObject private var streamingUploader = StreamingVideoUploader()

Button("Record with Streaming") {
    Task {
        try await cameraManager.startRecordingWithStreaming(
            uploader: streamingUploader
        )
    }
}
```

### Listen for Completion
```swift
NotificationCenter.default.addObserver(
    forName: NSNotification.Name("StreamingUploadComplete"),
    object: nil,
    queue: .main
) { notification in
    if let success = notification.userInfo?["success"] as? Bool,
       success == true {
        print("Upload completed!")
    }
}
```

## Performance Characteristics

### Network Usage
- **Upload bandwidth**: Depends on video quality (typically 1-5 Mbps)
- **Chunk uploads**: Batched every ~1 second
- **Overhead**: Minimal (HTTP headers only)

### Storage Usage
- **Temporary file**: Grows during recording
- **Final cleanup**: Automatic deletion after upload
- **Drive space**: Permanent storage in Google Drive

### Battery Impact
- **Recording**: Same as normal video recording
- **Upload**: Additional network activity
- **Overall**: Moderate increase during recording

## Summary

The streaming upload feature provides a seamless way to record videos directly to Google Drive without manual intervention. Once enabled, simply start recording and the system handles everything else - from chunked uploads to cleanup. The comprehensive logging and visual feedback ensure you always know the upload status.

**Remember**: When streaming is enabled, videos are automatically uploaded to Google Drive and the local copy is deleted. No additional action is needed!
