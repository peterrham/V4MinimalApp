# V4MinimalApp - Home Inventory iOS App

## Project Overview
iOS home inventory app that uses the camera to photograph/video items, AI (Gemini) to identify them, and speech recognition for voice annotations. Built in Swift/SwiftUI targeting iPhone.

## Architecture

### App Structure
- **TabView**: Home, Scan (camera), Inventory, Settings — defined in `MainTabView.swift`
- **@main entry**: `MainApp.swift` (injects `InventoryStore` as `@EnvironmentObject`; uses ZStack overlay pattern for auth gate)
- **AppDelegate**: `NewMain.swift` (also contains Logger extensions, Core Data setup)
- **Xcode project**: V4MinimalApp.xcodeproj
- **Bundle ID**: Test-Organization.V2NoScopesApp
- **Display name**: "Home Inventory" (set via `CFBundleDisplayName` in Info.plist)

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

### Authentication Flow
- **Google Sign-In** via GIDSignIn SDK
- **AppState.swift** — `@Published var isAuthenticated`. `checkAuthStatus()` checks `GIDSignIn.sharedInstance.currentUser != nil`. Called at init and after sign-in/sign-out.
- **GoogleSignInManager.swift** — `signIn(completion: (() -> Void)? = nil)`. Calls completion on main thread after 0.5s delay (lets OAuth sheet dismiss cleanly).
- **GoogleSignInView.swift** — Full sign-in screen: dark gradient background, app icon/branding, "Sign In with Google" button with loading spinner, "Continue without signing in" option. Receives `appState` as `@EnvironmentObject`.
- **MainApp.swift** — ZStack overlay pattern: `MainTabView` always renders underneath; `GoogleSignInView` overlays on top when `!appState.isAuthenticated`, fades out with `.transition(.opacity)` + `.animation(.easeInOut(duration: 0.35))`. No screen flash on sign-in.
- **SettingsView.swift** — Uses local `@State private var isSignedIn` for sign-out (NOT `appState.isAuthenticated`). Sign-out keeps user on home page, just updates the Account section UI. Sign-in button appears when signed out.
- **"Continue without signing in"** sets `appState.isAuthenticated = true` directly (bypasses Google).

### Cloud Services
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
- Google Sign-In not redirecting to home → `AppState.checkAuthStatus()` called via completion callback after sign-in; `appState` passed as `@EnvironmentObject`
- Sign-out UX → Sign-out in SettingsView uses local `@State isSignedIn` so user stays on home page; only Account section UI updates
- Screen flash on auth transition → ZStack overlay pattern in MainApp.swift; MainTabView always renders, GoogleSignInView fades out with opacity transition
- Sign-in screen redesign → GoogleSignInView completely rewritten: dark gradient, app branding, styled button, "Continue without signing in" option
- `currentUser` not reactive → Changed from stored property to computed property dependent on `isSignedIn` state
- Typo "Disconect" → "Disconnect" in GoogleSignInView
- App display name → Added `CFBundleDisplayName = "Home Inventory"` to Info.plist
- App icon AssetCatalogSimulatorAgent crash → Bypassed asset catalog icon processing entirely (set `ASSETCATALOG_COMPILER_APPICON_NAME = ""`); pre-rendered icon PNGs placed directly in bundle via `CFBundleIcons` in Info.plist

## Current State (as of Jan 30, 2026 session)

### What's Working
- Inventory system fully working: detect → save → persist → display with photos
- Bounding boxes: single-prompt approach (names + boxes together), crops thumbnails to box region
- Images without boxes stamped "BOUNDING BOX MISSING" in red
- Live seconds-ago timer updating every second in detection list
- Pinch-to-zoom fullscreen photo viewer on item detail
- Delete-all debug button in inventory list toolbar
- Orange dot indicator in detection list = bounding box loaded
- Google Sign-In flow: nice sign-in screen → smooth fade to home → sign-out stays on home
- "Continue without signing in" option on sign-in screen
- App displays as "Home Inventory" on home screen
- Custom app icon (indigo gradient, white house, green checkmark badge)
- ReplayKit broadcast extension streaming at ~2fps

### Uncommitted Changes (NEED TO COMMIT)
The following changes are staged but not yet committed or pushed:
- `MainApp.swift` — ZStack overlay auth gate pattern
- `SettingsView.swift` — Local `isSignedIn` state, sign-in/sign-out buttons in Account section
- `GoogleSignInView.swift` — Complete rewrite to branded sign-in screen
- `GoogleSignInManager.swift` — Completion callback with 0.5s delay on `signIn()`
- `V4MinimalApp.xcodeproj/project.pbxproj` — `ASSETCATALOG_COMPILER_APPICON_NAME = ""`, `INFOPLIST_KEY_CFBundleDisplayName = "Home Inventory"`
- `V4MinimalApp/Info.plist` — `CFBundleDisplayName`, `CFBundleIcons`, `CFBundleIcons~ipad`
- `V4MinimalApp/Assets.xcassets/AppIcon.appiconset/Contents.json` — Simplified (no filename references, icon bypassed)
- New icon PNG files in `V4MinimalApp/` directory (pre-rendered sizes: 120, 152, 167, 180, 1024)
- Source icon in `V4MinimalApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024x1024)
- `AppIcons/` directory with generated sizes (intermediate, can be gitignored)

### App Icon Workaround Details
Xcode's `actool` crashes with "Failed to launch AssetCatalogSimulatorAgent via CoreSimulator spawn" when processing app icons on this machine. Workaround:
1. `ASSETCATALOG_COMPILER_APPICON_NAME = ""` in both Debug/Release build settings (disables actool icon processing)
2. Pre-rendered icon PNGs placed directly in `V4MinimalApp/` directory (picked up by `PBXFileSystemSynchronizedRootGroup`)
3. `CFBundleIcons` and `CFBundleIcons~ipad` in Info.plist reference `AppIcon60x60`, `AppIcon76x76`, `AppIcon83.5x83.5`
4. iOS finds `AppIcon60x60@2x.png`, `AppIcon60x60@3x.png`, etc. automatically by convention
5. If this machine's Xcode is fixed later, can revert to asset catalog approach: set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, remove `CFBundleIcons` from Info.plist, restore Contents.json filenames

## ReplayKit Broadcast Upload Extension (COMPLETE — WORKING)
**Status:** Implemented and tested end-to-end. Frames stream successfully at ~2fps.

**How to use:**
1. Start `tools/log-server/log_server.py` on Mac
2. On iPhone: Control Center → long-press Screen Recording → select "Screen Broadcast" → Start
3. Use phone normally — frames arrive in `/tmp/app_screenshots/`
4. Stop via red status bar

**Files created:**
- `BroadcastUploadExtension/SampleHandler.swift` — RPBroadcastSampleHandler, throttles to ~2fps, JPEG over TCP
- `BroadcastUploadExtension/Info.plist` — Extension point config
- `BroadcastUploadExtension/BroadcastUploadExtension.entitlements` — App Group (not yet active)
- `V4MinimalApp.entitlements` — App Group (not yet active)

**Current limitation:** Server IP is hardcoded to `10.0.141.70` in SampleHandler.swift because App Group `group.Test-Organization.V2NoScopesApp` isn't registered on Apple Developer portal. Command-line builds can't register it. To fix: open project in Xcode GUI → Signing & Capabilities → add App Groups to both targets → Xcode auto-registers on portal. Then switch SampleHandler back to reading from shared UserDefaults.

**Main app files** (NetworkLogger, ScreenshotStreamer, NetworkDiagnosticsView) use `UserDefaults.standard` — NOT the shared suite. Reverted to avoid App Group provisioning errors.

## Bugs Found From Broadcast Screen Review (Jan 30, 2026)
Issues observed by recording a full app usage session via broadcast extension:

1. **[HIGH] Gemini response stored as item names** — "Recent Items" on HomeView show AI refusal text ("I cannot provide a list of physical items...", "but I cannot detect any physical items...") as item names. The Gemini response is being saved verbatim instead of being parsed/rejected. Need to fix the response parsing in GeminiVisionService or the save logic in InventoryStore.

2. **[MEDIUM] $0 Total Value with 90 items** — All 90 items have no value set. Either values aren't being parsed from AI responses, or the value fields aren't being populated on save.

3. **[MEDIUM] 0 Rooms despite 90 items** — No rooms created. Room assignment may not be happening during scan/save flow.

4. ~~**[LOW] Typo: "Disconect"**~~ — FIXED. Changed to "Disconnect".

5. **[LOW] Third stat card clipped** — The "Rooms" card on the Home dashboard is partially cut off on the right edge. Horizontal layout needs adjustment.

6. **[LOW] Debug page UX** — Flat wall of identical purple buttons with developer-facing labels. Fine for debug but could use grouping/organization.

## Next Steps (Priority Order)
1. **Commit and push** all uncommitted changes (sign-in redesign, icon, display name)
2. **Verify on device** that icon and display name appear correctly (iOS may cache icons — may need device reboot)
3. **[HIGH BUG] Fix Gemini refusal text as item names** — GeminiVisionService or InventoryStore needs to reject/filter AI responses that are refusal text rather than item names
4. **[MEDIUM BUG] Fix $0 Total Value** — Investigate whether values are being parsed from Gemini responses or if value fields need manual entry UX
5. **[MEDIUM BUG] Fix 0 Rooms** — Room assignment not happening during scan/save; may need room detection in Gemini prompt or manual room assignment UX
6. **[LOW BUG] Fix clipped stat card** — HomeView horizontal layout for the Rooms card
7. **Background Gemini enrichment** — Async service to fill in brand/color/size/category/value after initial fast detection

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
