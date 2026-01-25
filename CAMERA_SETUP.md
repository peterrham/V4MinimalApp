# Camera Integration - Setup Instructions

## ✅ Files Created

1. **CameraManager.swift** - Handles camera session, authorization, and photo capture
2. **CameraPreview.swift** - SwiftUI wrapper for AVCaptureVideoPreviewLayer
3. **CameraScanView.swift** - Updated to use real camera feed

## 📋 Required: Info.plist Configuration

You **must** add the following key to your `Info.plist` file to request camera permissions:

### Key to Add:
```xml
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to scan and identify items for your home inventory.</string>
```

### How to Add in Xcode:

1. **Open Info.plist** in your project navigator
2. **Click the "+" button** to add a new row
3. **Type:** `Privacy - Camera Usage Description`
4. **Value:** `We need access to your camera to scan and identify items for your home inventory.`

OR

1. **Select your app target** in Xcode
2. Go to the **Info** tab
3. Under **Custom iOS Target Properties**, click **+**
4. Add the key and description as above

## 🎯 What's Working Now

### Camera Features:
- ✅ Real camera preview (when authorized)
- ✅ Permission handling (request, denied, restricted states)
- ✅ Flash toggle (on/off)
- ✅ Photo capture
- ✅ Proper session lifecycle (starts on appear, stops on disappear)
- ✅ Error handling with alerts

### UI States:
- ✅ Live camera preview when authorized
- ✅ Permission request state
- ✅ Camera unavailable state
- ✅ Error alerts

## 🔜 Next Steps

### Phase 2: Image Processing & AI Detection
- [ ] Integrate Vision framework for object detection
- [ ] Add Core ML model for item recognition
- [ ] Process captured photos to detect items
- [ ] Extract item names and categories from images

### Phase 3: Photo Library Integration
- [ ] Implement photo library picker
- [ ] Allow selecting existing photos
- [ ] Process library photos for item detection

### Phase 4: Voice Integration
- [ ] Connect voice button to SpeechRecognitionManager
- [ ] Add voice input for item descriptions
- [ ] Combine camera + voice for better cataloging

## 🐛 Testing

### To Test Camera:
1. Run the app on a **physical device** (camera doesn't work in Simulator)
2. Navigate to the Camera Scan view
3. Grant camera permission when prompted
4. You should see live camera feed
5. Test flash toggle
6. Test photo capture (check logs for confirmation)

### Expected Behavior:
- First launch: Permission alert appears
- After granting: Live camera feed displays
- Flash button: Toggles between bolt.fill (on) and bolt.slash.fill (off)
- Capture button: Takes photo and logs to console
- Dismiss button: Stops camera and returns to previous view

## 📝 Notes

- Camera preview uses `AVCaptureVideoPreviewLayer` wrapped in SwiftUI
- Photo capture is high resolution with quality prioritization
- Flash state is managed by CameraManager
- Video frames are available in `captureOutput(_:didOutput:from:)` for real-time processing
- Current implementation uses back camera (can be extended to support front camera)

## 🔧 Troubleshooting

### Camera not showing?
1. Check Info.plist has NSCameraUsageDescription
2. Ensure running on physical device (not Simulator)
3. Check camera permissions in iOS Settings > [Your App] > Camera

### Black screen?
1. Check console for authorization errors
2. Verify camera session is starting (check logs)
3. Try stopping and restarting the app

### Flash not working?
1. Some devices don't have flash (iPad, iPod touch)
2. Check if `device.hasFlash` is true in logs
