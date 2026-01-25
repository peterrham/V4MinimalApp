# Photos Library Integration Setup

## Overview

Videos are now automatically saved to the iOS Photos Library after recording. This applies to both:
- Regular video recordings (`startRecording()`)
- Streaming uploads (`startRecordingWithStreaming()`)

## Required Info.plist Permissions

Add the following key to your `Info.plist` file:

```xml
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app needs to save recorded videos to your Photos Library</string>
```

### Complete Privacy Keys for Your App

Your Info.plist should include:

```xml
<!-- Camera Access -->
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to record videos and take photos of inventory items</string>

<!-- Microphone Access (for video recording with audio) -->
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to record audio with your videos</string>

<!-- Photo Library Add-Only Access -->
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app needs to save recorded videos to your Photos Library</string>

<!-- Speech Recognition (if using speech features) -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>This app needs speech recognition to transcribe your voice commands</string>
```

## How It Works

### 1. Permission Request
- The first time a video is saved, iOS will prompt the user for permission
- Permission is requested automatically when needed
- If denied, an error message will appear in the app

### 2. Automatic Saving

#### For Streaming Uploads:
```
1. Recording starts → Video streams to Google Drive
2. Recording stops → Upload finalizes
3. ✅ Video automatically saves to Photos Library
4. Local temp file is deleted
```

#### For Regular Recordings:
```
1. Recording starts → Video saves to temp file
2. Recording stops
3. ✅ Video automatically saves to Photos Library
4. Temp file remains for potential upload
```

### 3. Notifications

The app posts notifications when videos are saved:

```swift
// Listen for video saved events
NotificationCenter.default.addObserver(
    forName: NSNotification.Name("VideoSavedToPhotos"),
    object: nil,
    queue: .main
) { notification in
    if let url = notification.userInfo?["url"] as? URL,
       let assetID = notification.userInfo?["assetIdentifier"] as? String {
        print("Video saved! URL: \(url), Asset: \(assetID)")
    }
}
```

## Testing

### 1. First Run
- Record a video
- You should see a permission dialog asking to access Photos
- Tap "Allow"

### 2. Check Logs
Look for these log messages:
```
📱 Saving video to Photos Library...
✅ Video saved to Photos Library
   Asset ID: <identifier>
```

### 3. Verify in Photos App
- Open the iOS Photos app
- Check the "Recents" album
- Your recorded video should appear

## Troubleshooting

### "Photo library access denied"
**Solution:** User denied permission. Go to:
- Settings → Privacy & Security → Photos
- Find your app
- Select "Add Photos Only" or "Full Access"

### Video not appearing in Photos
**Possible causes:**
- Check console logs for errors
- Verify Info.plist contains `NSPhotoLibraryAddUsageDescription`
- Ensure the video file exists before saving
- Check if there's enough storage space

### Permission Not Being Requested
**Solution:** 
- Verify Info.plist has the privacy key
- Clean build folder and rebuild
- Reset simulator if testing on simulator

## Code Reference

### CameraManager.swift
```swift
// New method to save videos to Photos Library
func saveVideoToLibrary(_ videoURL: URL) async {
    // Requests permission if needed
    // Saves video to Photos
    // Posts notification on success
}
```

### CameraManager+StreamingUpload.swift
```swift
// After successful streaming upload:
await saveVideoToLibrary(fileURL)
```

## Benefits

✅ **Automatic Backup** - All videos are backed up to iCloud Photos (if enabled)  
✅ **Easy Access** - Users can view/share videos from the Photos app  
✅ **No Manual Save** - Videos save automatically after recording  
✅ **Cloud Storage** - Videos uploaded to Google Drive AND saved locally  
✅ **Privacy First** - Only requests "Add Photos" permission (not read access)

## Future Enhancements

Possible improvements:
- Add setting to enable/disable auto-save to Photos
- Create custom album for inventory videos
- Add metadata/location to saved videos
- Provide user feedback when video is saved (toast notification)
