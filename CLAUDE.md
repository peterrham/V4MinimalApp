# V4MinimalApp - Home Inventory iOS App

## Project Overview
iOS home inventory app that uses the camera to photograph/video items, AI (Gemini) to identify them, and speech recognition for voice annotations. Built in Swift/SwiftUI targeting iPhone.

## Architecture

### App Structure
- **TabView**: Home, Scan (camera), Inventory, Settings
- **@main entry**: VoiceRecognitionApp.swift
- **AppDelegate**: NewMain.swift (also contains Logger extensions, Core Data setup)
- **Xcode project**: V4MinimalApp.xcodeproj
- **Bundle ID**: Test-Organization.V2NoScopesApp

### Key Components
- **CameraManager.swift** - AVCaptureSession management, photo/video capture, Gemini identification
- **CameraScanView.swift** - Main camera UI with photo capture and video recording
- **LiveObjectDetectionView.swift** - Real-time object detection using camera frames + Gemini
- **GeminiVisionService.swift** - Gemini API integration for image identification
- **SpeechRecognition.swift** - Full speech recognition with audio recording, Drive upload, transcription
- **NetworkLogger.swift** - TCP-based log streaming to Mac for debugging
- **ScreenshotStreamer.swift** - Streams screenshots to Mac for visual debugging
- **EarlyInit.c** - C constructor for earliest possible boot logging via TCP
- **NetworkDiagnosticsView.swift** - UI for configuring/testing log server connection

### Debugging Infrastructure
- **Log server**: `tools/log-server/log_server.py` - TCP server on Mac (port 9999 logs, port 9998 screenshots)
- **Logs written to**: `/tmp/app_logs.txt`
- **Screenshots saved to**: `/tmp/app_screenshots/`
- **NetworkLogger**: Streams all logs to Mac via TCP (reads host/port from UserDefaults)
- **EarlyInit.c**: Sends first log before Swift loads using BSD sockets + CoreFoundation

### Authentication & Cloud
- **Google Sign-In** via GIDSignIn SDK
- **Google Drive** for audio chunk uploads
- **Google Sheets** for transcript/inventory sync
- **Gemini API** key in Info.plist (to be moved to server-side proxy before launch)

### Data Storage
- **Core Data**: Local SQLite via DynamicPersistenceController (programmatic model)
- **Entity**: RecognizedTextEntity (content: String, timestamp: Date)
- **Photos**: iOS Photo Library
- **Audio**: Local WAV/PCM files + Google Drive chunks

## Device & Build
- **Test device**: iPhone (ID: E2E96980-5078-5FAF-8A49-EBE55CF72365, USB ID: 00008110-000A3DCC0C32401E)
- **Build command**: `xcodebuild -project V4MinimalApp.xcodeproj -scheme V4MinimalApp -destination 'platform=iOS,id=00008110-000A3DCC0C32401E' -derivedDataPath build build`
- **Install**: `xcrun devicectl device install app --device E2E96980-5078-5FAF-8A49-EBE55CF72365 build/Build/Products/Debug-iphoneos/V4MinimalApp.app`
- **Launch**: `xcrun devicectl device process launch --device E2E96980-5078-5FAF-8A49-EBE55CF72365 Test-Organization.V2NoScopesApp`

## Known Issues Fixed
- Camera not restarting when returning from Live Detection → Added startSession() in onAppear
- NetworkLogger not in Xcode project → Added to project.pbxproj manually
- /tmp sandboxed on iOS → EarlyInit.c sends TCP directly instead of file-based approach

## Product Vision
- Family-shared home inventory
- Clutter scores and organization recommendations
- Moving/downsizing cost estimates
- Interior decorating "cozy" ratings
- Multi-provider auth (Google, Apple, Microsoft) via Firebase Auth
- Cloud storage: Firebase/Google Cloud Storage for media, Firestore for inventory
- Background processing: Cloud Functions for audio/video analysis
- Data portability: Export to Sheets, CSV, PDF

## Google Drive
- Mount: `/Users/peterham/Library/CloudStorage/GoogleDrive-peterrham@gmail.com/My Drive`
- Interview Plan stored there (.md, .docx, .pdf)

## Audio/Speech System
- SpeechRecognition.swift: Full-featured, currently only used in ContentView (Audio tab)
- Records WAV + PCM locally, uploads chunks to Google Drive
- Stop word: "go"
- Needs: Integration with main camera flow, global speech manager

## Coding Preferences
- Prefer TCP over UDP for log delivery (reliability)
- Inline status feedback preferred over popup toasts
- Want detailed TCP connection state info (SYN/ACK)
- All logging should go to both unified logging AND network logger
