# V4MinimalApp - Home Inventory iOS App

## Project Overview
iOS home inventory app that uses the camera to photograph/video items, AI (Gemini) to identify them, and speech recognition for voice annotations. Built in Swift/SwiftUI targeting iPhone.

## Architecture

### App Structure
- **TabView**: Home, Scan (camera), Inventory, Settings — defined in `MainTabView.swift`
- **@main entry**: `MainApp.swift` (injects `InventoryStore` as `@EnvironmentObject`)
- **AppDelegate**: `NewMain.swift` (also contains Logger extensions, Core Data setup)
- **Xcode project**: V4MinimalApp.xcodeproj
- **Bundle ID**: Test-Organization.V2NoScopesApp

### Key Components
- **CameraManager.swift** - AVCaptureSession management, photo/video capture, frame capture for live detection. Rear camera frames use `UIImage(cgImage:scale:orientation: .right)` to fix portrait orientation.
- **CameraScanView.swift** - Main camera UI with photo capture and video recording
- **LiveObjectDetectionView.swift** - Real-time object detection view. Hosts `CameraManager` + `GeminiStreamingVisionService`. Save individual items or "Save All". Shows `StreamingObjectDetectionView` overlay. Has inventory sheet, duplicate review sheet.
- **GeminiStreamingVisionService.swift** - Core detection service. Sends frames to Gemini every 2s. Combined prompt returns item names + bounding boxes as JSON in one call. Parses `[{"name":"...","box":[ymin,xmin,ymax,xmax]}]` with coordinates 0-1000. Falls back to comma-separated parsing if JSON fails. Stores `lastAnalyzedFrame` for deferred thumbnail creation. Max 200 detections in memory.
- **StreamingObjectDetectionView.swift** - Scrolling detection list overlay. Shows item name, brand/color/size subtitle, live seconds-ago timer via `TimelineView(.periodic(from: .now, by: 1))`. Orange dot = bounding box loaded, green = no box yet. Save button per item + "Save All".
- **GeminiVisionService.swift** - Gemini API integration for single image identification (used by CameraScanView photo capture)
- **InventoryStore.swift** - JSON-backed persistent inventory (`inventory.json` in Documents). Photo storage in `Documents/inventory_photos/`. Deduplication by name similarity (exact, substring containment). `deleteAllItems()` for debug. Contains `SavedInventorySheet` and `DuplicateReviewSheet` views.
- **InventoryListView.swift** - Full inventory list tab. Search, category filter, grid/list toggle. Delete-all debug button (trash icon, top-left toolbar).
- **ItemDetailView.swift** - Item detail with photo gallery, tap-to-zoom fullscreen (`ZoomablePhotoView` with pinch/drag/double-tap). Edit, share, delete buttons.
- **HomeView.swift** - Dashboard with stats cards, recent items grid, room cards, "Scan Room" button.
- **Models.swift** - `InventoryItem` (Codable), `ItemCategory` enum with `.from(rawString:)` alias mapping, `Room`, `Card`, `AppTheme`. `InventoryItem` has: name, category, room, brand, itemColor, size, photos, notes, voiceTranscripts, purchasePrice, estimatedValue, purchaseDate.
- **SpeechRecognition.swift** - Full speech recognition with audio recording, Drive upload, transcription
- **NetworkLogger.swift** - TCP-based log streaming to Mac for debugging
- **ScreenshotStreamer.swift** - Streams screenshots to Mac for visual debugging
- **EarlyInit.c** - C constructor for earliest possible boot logging via TCP
- **NetworkDiagnosticsView.swift** - UI for configuring/testing log server connection

### Detection Pipeline (GeminiStreamingVisionService)
1. `CameraManager.enableFrameCapture` sends frames to `analyzeFrame()`
2. Throttled to every 2 seconds, skips if previous analysis still in-flight
3. Combined JSON prompt asks for item names + bounding boxes in one Gemini call
4. `parseDetectionsWithBoxes()` extracts `[DetectedObject]` with `boundingBoxes` attached
5. Falls back to `parseDetections()` (comma-separated) if JSON parse fails
6. Each `DetectedObject` stores `sourceFrame: UIImage?` (lazy — JPEG created only on save)
7. `createThumbnailData()`: if bounding box exists, crops to box with 15% padding + green outline + 20pt label. If no box, stamps "BOUNDING BOX MISSING" in red.
8. Dedup: skips if same name detected within last 10 seconds

### Inventory Save Flow
1. User taps + on detection row → `inventoryStore.addItem(from: detection)`
2. Or "Save All" → `inventoryStore.addItems(from: detections)` (batch dedup)
3. `InventoryStore` deduplicates by normalized name (exact/substring match)
4. Calls `detection.createThumbnailData()` → saves JPEG to `inventory_photos/`
5. Merges fields (brand, color, size, category) from new detection into existing item
6. Persists to `inventory.json` with ISO 8601 dates

### Debugging Infrastructure
- **Log server**: `tools/log-server/log_server.py` - TCP server on Mac (port 9999 logs, port 9998 screenshots)
- **Logs written to**: `/tmp/app_logs.txt`
- **Screenshots saved to**: `/tmp/app_screenshots/`
- **NetworkLogger**: Streams all logs to Mac via TCP (reads host/port from UserDefaults)
- **EarlyInit.c**: Sends first log before Swift loads using BSD sockets + CoreFoundation
- **Debug admin**: Delete-all button in InventoryListView toolbar + SavedInventorySheet
- **Bounding box logging**: Lines starting with `📦` show request/response/parse/match status

### Authentication & Cloud
- **Google Sign-In** via GIDSignIn SDK
- **Google Drive** for audio chunk uploads
- **Google Sheets** for transcript/inventory sync
- **Gemini API** key loaded from: Config.plist → Info.plist → env var. Stored in `Secrets.xcconfig` (gitignored), referenced via `$(GEMINI_API_KEY)` in Info.plist.

### Data Storage
- **Inventory**: `Documents/inventory.json` (JSON array of InventoryItem)
- **Photos**: `Documents/inventory_photos/*.jpg` (480px thumbnails, cropped to bounding box)
- **Core Data**: Local SQLite via DynamicPersistenceController (programmatic model)
- **Entity**: RecognizedTextEntity (content: String, timestamp: Date)
- **Audio**: Local WAV/PCM files + Google Drive chunks

### API Configuration
- **Gemini model**: `gemini-2.5-flash-lite` (upgraded from retired `gemini-2.0-flash-exp`)
- **Endpoint**: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent`
- **Detection prompt**: Combined names + bounding boxes, maxOutputTokens: 400, temperature: 0.2
- **Timeout**: 10s for detection, frame analysis every 2s

## Device & Build
- **Test device**: iPhone (ID: E2E96980-5078-5FAF-8A49-EBE55CF72365, USB ID: 00008110-000A3DCC0C32401E)
- **Build command**: `xcodebuild -project V4MinimalApp.xcodeproj -scheme V4MinimalApp -destination 'platform=iOS,id=00008110-000A3DCC0C32401E' -derivedDataPath build build`
- **Install**: `xcrun devicectl device install app --device E2E96980-5078-5FAF-8A49-EBE55CF72365 build/Build/Products/Debug-iphoneos/V4MinimalApp.app`
- **Launch**: `xcrun devicectl device process launch --device E2E96980-5078-5FAF-8A49-EBE55CF72365 Test-Organization.V2NoScopesApp`
- **Build + deploy one-liner**: Build, then `xcrun devicectl device install app ... && xcrun devicectl device process launch ...`

## Known Issues Fixed
- Camera not restarting when returning from Live Detection → Added startSession() in onAppear
- NetworkLogger not in Xcode project → Added to project.pbxproj manually
- /tmp sandboxed on iOS → EarlyInit.c sends TCP directly instead of file-based approach
- JSON fragments as item names → Robust JSON parser with markdown fence stripping + fallback refusal when text contains `{`/`[`
- Scanning slowed by complex JSON prompt → Reverted to fast prompt, then combined names+boxes in single call
- Photos rotated 90° CCW → `UIImage(cgImage:scale:orientation: .right)` for rear camera
- API key leaked in repo → `.gitignore`, `Secrets.xcconfig`, Info.plist `$(GEMINI_API_KEY)` reference
- Retired Gemini model → Updated from `gemini-2.0-flash-exp` to `gemini-2.5-flash-lite`
- Bounding box race condition → Combined detection+boxes in single prompt instead of fire-and-forget second call
- Corrupted inventory items → `cleanupCorruptedItems()` on init removes items with JSON fragments in names

## Current State (as of last session)
- Inventory system fully working: detect → save → persist → display with photos
- Bounding boxes: single-prompt approach (names + boxes together), crops thumbnails to box region
- Images without boxes stamped "BOUNDING BOX MISSING" in red
- Live seconds-ago timer updating every second in detection list
- Pinch-to-zoom fullscreen photo viewer on item detail
- Delete-all debug button in inventory list toolbar
- Orange dot indicator in detection list = bounding box loaded
- All changes committed and pushed to `origin/main`

## Future Work (user mentioned)
- Background Gemini enrichment for colors/brands/sizes/categories ("eventually")
- On-device YOLO bounding boxes (considered, deferred for Gemini approach first)
- Family-shared inventory, clutter scores, moving cost estimates
- Firebase Auth, Cloud Storage, Firestore migration
- Export to Sheets/CSV/PDF

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
- Fast scanning feedback is the #1 priority — background enrichment is acceptable
- Keep detection prompt simple/fast; do heavy processing asynchronously
