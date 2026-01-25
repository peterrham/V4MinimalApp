# Claude Session Notes

> **Read this file at the start of each session to restore context.**

## Project Summary

**V4MinimalApp** - iOS Home Inventory app with AI-powered object detection using Google Gemini Vision API.

- **Platform**: iOS (SwiftUI + AVFoundation)
- **AI**: Google Gemini 2.0 Flash API for image analysis
- **Key Features**: Photo capture with AI identification, live real-time object detection, video recording, Google Drive upload

## Recent Session Work (2025-01-25)

### Completed
- Added `GeminiAPIKey` to Info.plist (was missing, causing "API key not configured" error)
- Added "LIVE" button to CameraScanView that opens LiveObjectDetectionView
- Fixed missing `captureOutput` delegate method in CameraManager.swift - frames weren't being processed for live detection
- Increased detected objects limit from 50 to 500 in GeminiStreamingVisionService.swift
- Live detection now works on device

### Created but NOT integrated
- `NetworkLogger.swift` - UDP logger to stream logs to Mac (not added to Xcode project)
- `LogServer.py` - Python server to receive logs from app

## Pending Tasks

### High Priority
1. **Device log streaming** - Cannot access iPhone logs from CLI (Apple requires private entitlements). Options:
   - Integrate NetworkLogger.swift for UDP logging
   - Use lldb command line attachment
   - Use `devicectl --console` with flushed print() statements

## Key Files

| File | Purpose |
|------|---------|
| `CameraManager.swift` | Camera control, photo/video capture, frame processing |
| `CameraManager+FrameCapture.swift` | Extension for streaming frame capture |
| `GeminiVisionService.swift` | Single photo analysis via Gemini API |
| `GeminiStreamingVisionService.swift` | Real-time frame analysis (2-sec intervals, 500 object limit) |
| `LiveObjectDetectionView.swift` | UI for live detection mode |
| `CameraScanView.swift` | Main camera UI with LIVE button |
| `V4MinimalApp/Info.plist` | Contains GeminiAPIKey |

## Build & Deploy Commands

```bash
# Build for device
xcodebuild -project V4MinimalApp.xcodeproj -scheme V4MinimalApp \
  -destination 'platform=iOS,id=00008110-000A3DCC0C32401E' \
  -derivedDataPath build build

# Install on device
xcrun devicectl device install app --device E2E96980-5078-5FAF-8A49-EBE55CF72365 \
  /Users/peterham/Documents/V4MinimalApp/build/Build/Products/Debug-iphoneos/V4MinimalApp.app

# Launch on device
xcrun devicectl device process launch --device E2E96980-5078-5FAF-8A49-EBE55CF72365 \
  Test-Organization.V2NoScopesApp
```

## Device Info

- **Device**: Peter's iPhone Max 13 (iPhone 13 Pro Max)
- **Device ID**: E2E96980-5078-5FAF-8A49-EBE55CF72365
- **UDID**: 00008110-000A3DCC0C32401E
- **Bundle ID**: Test-Organization.V2NoScopesApp

## Technical Notes

### Why device logs aren't accessible from CLI
- Apple's unified logging requires private entitlements (`com.apple.private.logging.stream`)
- Only Apple-signed apps (Console.app, Xcode) have these entitlements
- `idevicesyslog` doesn't work with newer CoreDevice/RemoteXPC protocol (iOS 17+)
- XPC services verify caller's code signature before streaming logs

### API Key Location
The Gemini API key is stored in:
- `V4MinimalApp/Info.plist` under key `GeminiAPIKey`
- Also in Xcode scheme as environment variable (only works when running from Xcode)

## Session Log

### 2025-01-25
- User wanted to build and run on physical iPhone (not simulator)
- Fixed API key configuration
- Added live detection button and fixed frame capture
- Explored device logging options extensively - documented why CLI access isn't possible
- Created this notes file for future session context
