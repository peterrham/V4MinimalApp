# Google Drive Video Upload Setup Guide

This guide will help you complete the Google Drive integration for streaming/uploading recorded videos.

## Overview

The app now has:
- ✅ Video recording capability in `CameraManager`
- ✅ Google Drive upload service in `GoogleDriveService`
- ✅ UI controls for recording and uploading in `CameraScanView`
- ⚠️ Google authentication needs to be implemented

## What's Implemented

### 1. Video Recording
- Start/stop recording with the video button (bottom right)
- Recording duration indicator shows while recording
- Videos are saved to temporary directory
- Notification posted when recording completes

### 2. Upload Service
- `GoogleDriveService` with upload methods
- Progress tracking
- Error handling
- Two upload methods:
  - Multipart upload (for smaller files)
  - Resumable upload (recommended for videos)

### 3. UI
- Record button (video icon) starts/stops recording
- Upload options sheet appears after recording
- Progress overlay during upload
- Share option as alternative

## Next Steps: Google Authentication

To enable actual uploads to Google Drive, you need to:

### Step 1: Set up Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable the Google Drive API:
   - Go to "APIs & Services" > "Library"
   - Search for "Google Drive API"
   - Click "Enable"

### Step 2: Create OAuth 2.0 Credentials

1. In Google Cloud Console, go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth client ID"
3. Select "iOS" as application type
4. Enter your bundle ID (e.g., `com.yourcompany.V4MinimalApp`)
5. Download the configuration file

### Step 3: Add Google Sign-In SDK

Add the Google Sign-In SDK to your project using Swift Package Manager:

```swift
// In Xcode:
// File > Add Package Dependencies
// URL: https://github.com/google/GoogleSignIn-iOS
```

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "7.0.0")
]
```

### Step 4: Configure Info.plist

Add the following to your `Info.plist`:

```xml
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID_HERE.apps.googleusercontent.com</string>

<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

### Step 5: Implement Authentication

Update `GoogleDriveService.swift` with actual Google Sign-In:

```swift
import GoogleSignIn

@MainActor
class GoogleDriveService: ObservableObject {
    // ... existing code ...
    
    func authenticate() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            error = .notAuthenticated
            return
        }
        
        do {
            let user = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: rootViewController,
                hint: nil,
                additionalScopes: ["https://www.googleapis.com/auth/drive.file"]
            )
            
            accessToken = user.user.accessToken.tokenString
            isAuthenticated = true
            
            appBootLog.infoWithContext("✅ Google Drive authentication successful")
            
        } catch {
            appBootLog.errorWithContext("Google Sign-In failed: \(error.localizedDescription)")
            self.error = .notAuthenticated
        }
    }
    
    func restorePreviousSignIn() async {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            
            // Check if we have the Drive scope
            let hasScope = user.grantedScopes?.contains("https://www.googleapis.com/auth/drive.file") ?? false
            
            if hasScope {
                accessToken = user.accessToken.tokenString
                isAuthenticated = true
                appBootLog.infoWithContext("✅ Restored previous Google sign-in")
            } else {
                // Need to request additional scopes
                await authenticate()
            }
        } catch {
            appBootLog.infoWithContext("No previous sign-in found")
        }
    }
}
```

### Step 6: Configure App Delegate

Add to your `@main` app struct or App Delegate:

```swift
import GoogleSignIn

@main
struct V4MinimalAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
```

## Alternative: Simplified Local Storage

If you want to test the recording functionality without Google Drive initially, you can:

1. Save videos to the Photos library instead:

```swift
import Photos

func saveToPhotos(videoURL: URL) async throws {
    try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
    }
}
```

2. Or use iCloud Drive:

```swift
func saveToiCloud(videoURL: URL) throws {
    guard let iCloudURL = FileManager.default.url(
        forUbiquityContainerIdentifier: nil
    )?.appendingPathComponent("Videos") else {
        throw NSError(domain: "iCloud", code: -1)
    }
    
    try FileManager.default.createDirectory(
        at: iCloudURL,
        withIntermediateDirectories: true
    )
    
    let destinationURL = iCloudURL.appendingPathComponent(videoURL.lastPathComponent)
    try FileManager.default.copyItem(at: videoURL, to: destinationURL)
}
```

## Testing

1. **Record a video**: Tap the video button (bottom right) to start recording
2. **Stop recording**: Tap the stop button (appears while recording)
3. **Upload options**: A sheet appears with upload options
4. **Upload to Drive**: Tap "Upload to Google Drive" (requires authentication)
5. **Share**: Use the share button to save locally or share via other apps

## Permissions Required

Make sure your `Info.plist` includes:

```xml
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to scan and record items for your inventory</string>

<key>NSMicrophoneUsageDescription</key>
<string>We need access to your microphone to record audio with your videos</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>We need permission to save recorded videos to your photo library</string>
```

## Troubleshooting

### Recording not starting
- Check camera and microphone permissions
- Verify session is running before attempting to record

### Upload fails
- Verify Google authentication is complete
- Check network connection
- Ensure Drive API is enabled in Google Cloud Console
- Verify OAuth scopes include `https://www.googleapis.com/auth/drive.file`

### File too large
- Videos can be large; consider:
  - Recording at lower resolution
  - Compressing before upload
  - Using chunked/resumable upload (already implemented)

## Next Features to Consider

- [ ] Automatic upload in background
- [ ] Upload queue for multiple videos
- [ ] Compression options
- [ ] Live streaming instead of record+upload
- [ ] Delete local files after successful upload
- [ ] Folder organization in Google Drive
- [ ] Upload to specific folder
- [ ] Share link generation

## Resources

- [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios)
- [Google Drive API](https://developers.google.com/drive/api/guides/about-sdk)
- [AVFoundation Recording](https://developer.apple.com/documentation/avfoundation/capture_setup/recording_a_movie)
