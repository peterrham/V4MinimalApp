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

### Claude Code Log Monitoring (IMPORTANT)
The app streams logs to a Python TCP server on the Mac. **Always use this for debugging instead of `devicectl --console`.**
- **Start server**: `python3 tools/log-server/log_server.py -o /tmp/app_logs.txt` (usually already running)
- **Check if running**: `lsof -i :9999` — should show a Python process
- **Read logs**: `tail -50 /tmp/app_logs.txt` or use Read tool on `/tmp/app_logs.txt`
- **Monitor live**: Run `tail -f /tmp/app_logs.txt` in background to watch incoming logs
- **All new logging code** must use `NetworkLogger.shared.info()` (or .debug/.error etc.) so logs appear in `/tmp/app_logs.txt`. Using only `os_log()` or `print()` will NOT send logs to the TCP server.
- **API**: `NetworkLogger.shared.info("message", category: "Category")` — also `.debug()`, `.error()`, `.warning()`, `.notice()`, `.fault()`
- **Global convenience**: `appLog("message", level: .info, category: "Category")`
- **Dual logging pattern** (NewMain.swift): `appBootLog.infoWithContext("msg")` sends to both os_log AND NetworkLogger

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

## UI Specification & Feedback (Feb 2, 2026)

### 1. Homepage Cards — All Clickable
Every card/UI element on the homepage should be tappable. Most taps open filtered views over the inventory.

| Card Type | Tap Action |
|-----------|------------|
| Recently Added | Items added in last 7 days |
| Total Items | Full inventory list |
| Rooms/Locations | Items filtered by selected location |
| Categories | Items filtered by category |
| Unidentified Items | Items pending recognition/classification |
| Search/Quick Actions | Open search or action modal |
| Statistics/Insights | Detailed analytics dashboard |

### 2. Tab Bar Icon Sizing
Experiment with larger bottom tab bar icons:
- **Option A (Current):** Default size
- **Option B:** 1.5x
- **Option C:** 2x (accessibility-friendly)

Add a settings toggle or A/B test flag to switch between sizes.

### 3. UI Theme Options
Add a third "Bug" option for experimental UI features:
1. Option 1 (default)
2. Option 2 (alternative)
3. Bug/Experimental — contains features under development

### 4. Scan Page Button Audit

| Button | Status | Issue / Action |
|--------|--------|----------------|
| **Red Eye** | Unclear purpose, disliked appearance | Clarify intent: if live AI indicator → replace with subtle animated badge/dot; if red-eye reduction → remove |
| **Orange** | Experimental flow | Move to Bug UI only (hide from default) |
| **Video** | Unknown if MVP | Decide: remove, move to Bug UI, or redesign as "Scan Room" walkthrough |
| **Flash** | Toggle torch | Keep if users scan in low light; remove if not needed |
| **Cloud** | Unclear (sync status? manual upload? settings?) | Clarify: if status indicator, make subtle (not a button); if auto-sync, remove |
| **X (Close)** | "Doesn't always do anything" | **Fix:** must always dismiss scan view. Debug inconsistent state management |

### 5. Immediate Actions

**Move to Bug UI:**
- [ ] Orange button/flow

**Fix:**
- [ ] X button — make dismissal consistent

**Decide & Document:**
- [ ] Red eye button — define purpose or remove
- [ ] Video button — define purpose or remove
- [ ] Flash button — keep or remove
- [ ] Cloud button — clarify purpose

**Implement:**
- [ ] Make all homepage cards clickable with filtered inventory views
- [ ] Add 2 additional tab icon size options
- [ ] Add "Bug" UI theme option

### 6. Open Questions
1. **Red eye button:** What was the original intent?
2. **Video mode:** Is room walkthrough video capture a planned feature?
3. **Cloud button:** Manual sync, status display, or something else?
4. **Flash:** Do users actually need flash control?

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
- **ItemCardCompact kills all touch events when used outside a multi-column grid** → The image uses `.aspectRatio(contentMode: .fill)` + `.frame(height: 120)`. `.fill` renders the image larger than the frame; `.clipShape()` only clips visually, NOT the hit-testing area. In a 2-column `LazyVGrid`, the narrow column width limits overflow. Standalone or in a single-column grid (full screen width), the overflow is massive and blocks ALL ScrollView touches. **Rule: always use `ItemCardCompact` inside a multi-column `LazyVGrid` — never standalone.** Attempts to fix with `.clipped()`, `Color.clear.overlay()`, or wrapping in `Button` all failed. The grid column constraint is the only reliable fix.

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

---

## High-Level Codebase Summary

**Scale:** ~26,400 lines of Swift across 92 files, single Xcode target (plus a ReplayKit broadcast extension).

**What the app does:** Point your phone camera at household items, Gemini identifies them in real-time (~2s cycles), you save them to a local JSON-backed inventory. Photos are cropped to bounding boxes. Items can be organized by room and home. Speech recognition, Google Drive upload, and Google Sheets sync exist but are secondary features.

**Core data flow:**
```
Camera frames (CameraManager)
  → Gemini API (GeminiStreamingVisionService, every 2s)
  → Parsed DetectedObject list (name + bounding box)
  → User taps Save / Save All
  → InventoryStore persists to inventory.json + crops photo to inventory_photos/
  → HomeView / InventoryListView display items
```

**File layout (no folder structure enforced):**
- 52 Swift files in the project root (views, services, models mixed together)
- 40 Swift files in `V4MinimalApp/` subdirectory (debug views, evaluation harness, YOLO, sessions)
- 1 broadcast extension file, 3 unused `NewTarget/` files

**Largest files (complexity hotspots):**
| File | LOC | Role |
|------|-----|------|
| EvaluationView.swift | 2,091 | Evaluation harness UI + logic |
| CameraScanView.swift | 1,209 | Camera UI + capture + upload |
| InventoryStore.swift | 1,123 | JSON persistence + dedup + rooms + homes |
| PipelineRunner.swift | 1,045 | Multi-algorithm detection orchestration |
| GeminiVisionService.swift | 1,045 | Single-image Gemini API + parsing |
| LiveObjectDetectionView.swift | 918 | Real-time detection + 6 @StateObjects |

**Key services:** GeminiStreamingVisionService (live detection), GeminiVisionService (single-photo), CameraManager (AVCaptureSession), InventoryStore (persistence), BackgroundEnrichmentService (async enrichment), YOLODetector + AppleVisionClassifier (on-device fallbacks), NetworkLogger (TCP log streaming).

**Authentication:** Google Sign-In SDK with "Continue without signing in" bypass. ZStack overlay pattern in MainApp.swift.

**Test coverage:** Zero. No test targets, no test files, no mocks.

---

## Architecture Evaluation

### 1. Separation of Concerns — Poor

Views contain business logic directly. `LiveObjectDetectionView` instantiates 6 `@StateObject` services (camera, Gemini, enrichment, YOLO, Apple Vision, motion monitor), manages 11 `@State` variables, and orchestrates detection pipelines — all in a single SwiftUI struct. There is no ViewModel layer anywhere in the codebase. Every view that does anything non-trivial (CameraScanView, EvaluationView, LiveObjectDetectionView) is a god object mixing UI layout with service orchestration, state management, and persistence calls.

**Recommendation:** Introduce a ViewModel layer. Each complex view should have a corresponding `ObservableObject` class that owns the business logic and exposes `@Published` state. Views should only bind to ViewModel properties and call ViewModel methods.

### 2. Duplicate Implementations — Significant

| Area | Files | Problem |
|------|-------|---------|
| Speech recognition | 4 files (SpeechRecognition.swift, SpeechRecognitionManager.swift, SpeechRecognitionManager 2.swift, SpeechRecognitionExtension.swift) | 3 overlapping implementations, one commented out, one is a backup copy |
| Google Drive upload | 5 files (GoogleDriveService, +Authentication, GoogleDriveUploader, StreamingVideoUploader, GoogleCloudStorageUploader) | Unclear hierarchy, overlapping responsibilities |
| Google Sheets | 2 files (GoogleSheetsAPI, GoogleSheetsClient) | Similar purpose, unclear division |
| Auth | 6 files (GoogleSignInManager, GoogleSignInView, GoogleAuthenticatorView, GoogleAuthenticateViaSafari, GoogleoAuth, AuthManager) | Multiple auth mechanisms, unclear which is active |
| API key loading | Duplicated identically in GeminiVisionService and GeminiStreamingVisionService | Same `loadFromConfig()`, `loadFromInfoPlist()` code copy-pasted |
| Gemini response parsing | Duplicated across both Gemini services | Same JSON parse + fallback logic |

**Recommendation:** Consolidate each area to a single canonical implementation. Delete dead files (SpeechRecognitionManager.swift is commented out, "SpeechRecognitionManager 2.swift" is a stale copy, Vision.swift is empty). Extract shared logic (API key loading, response parsing) into shared utilities.

### 3. Dependency Management — Singleton-Heavy, No Injection

9 singletons identified (`GeminiVisionService.shared`, `DetectionSettings.shared`, `NetworkLogger.shared`, `AppHelper.shared`, `VideoUploadQueue.shared`, `Persistence.shared`, `DynamicPersistenceController.shared`, `ScreenshotStreamer.shared`, plus `InventoryStore` passed as `@EnvironmentObject`). Views instantiate services directly (`let driveUploader = GoogleDriveUploader()`) rather than receiving them through injection.

**Recommendation:** Define protocols for each service (e.g., `protocol VisionServiceProtocol`), inject dependencies via initializers or `@EnvironmentObject`, and reserve singletons for truly global concerns (logging, app configuration).

### 4. God Object: InventoryStore (1,123 LOC)

InventoryStore handles: JSON file I/O for 3 files (inventory, homes, rooms), item CRUD, room management, home management, deduplication by name similarity, photo file management, CoreData integration, item cleanup/validation, and export. This is too many responsibilities for one class.

**Recommendation:** Split into focused components: `InventoryRepository` (CRUD + file I/O), `RoomManager`, `HomeManager`, `InventoryDeduplicator`, `PhotoStorageManager`.

### 5. Testing — Non-existent

There are zero tests. No test target in the Xcode project. No mock objects. No test data factories. The architecture actively prevents testing because:
- Business logic lives in SwiftUI views (can't unit test)
- Services are singletons or directly instantiated (can't mock)
- File I/O uses `FileManager` directly (can't stub)
- Network calls are hardcoded (can't intercept)

**Recommendation (priority order):**
1. Add a test target to the Xcode project
2. Write unit tests for `Models.swift` (pure data, easy to test now)
3. Write unit tests for `ItemCategory.from(rawString:)` alias mapping
4. Extract Gemini response parsing into a pure function, test edge cases (refusals, malformed JSON, markdown fences)
5. Extract deduplication logic from InventoryStore into a testable pure function
6. Define service protocols, create mock implementations, write integration tests for save/load flows
7. Add UI tests for critical paths (scan → detect → save → verify in inventory)

### 6. File Organization — Flat and Disorganized

92 Swift files split between two directories with no consistent grouping. Views, models, services, and utilities are interleaved. There is no folder structure enforcing architectural boundaries.

**Recommended folder structure:**
```
V4MinimalApp/
├── App/           (MainApp, AppState, AppDelegate/NewMain)
├── Models/        (Models, DetectionSession, ScanSession)
├── Views/
│   ├── Home/      (HomeView, HomePickerMenu, RoomsSummaryView)
│   ├── Camera/    (CameraScanView, CameraSettingsView, CameraPreview)
│   ├── Detection/ (LiveObjectDetectionView, StreamingObjectDetectionView)
│   ├── Inventory/ (InventoryListView, ItemDetailView, InventoryTableView)
│   ├── Settings/  (SettingsView, DebugView, NetworkDiagnosticsView)
│   └── Auth/      (GoogleSignInView)
├── ViewModels/    (new — extracted from views)
├── Services/
│   ├── Vision/    (GeminiVisionService, GeminiStreamingVisionService)
│   ├── Detection/ (YOLODetector, AppleVisionClassifier, PipelineRunner)
│   ├── Storage/   (InventoryStore, GoogleDriveService)
│   ├── Camera/    (CameraManager + extensions)
│   └── Network/   (NetworkLogger, ScreenshotStreamer)
├── Utilities/     (Theme, Styles, Extensions)
└── Tests/
    ├── Unit/
    └── Integration/
```

### 7. Dead Code to Remove

| File | Reason |
|------|--------|
| `NewTarget/` (3 files) | Unused experimental target |
| `SpeechRecognitionManager.swift` | Entirely commented out |
| `SpeechRecognitionManager 2.swift` | Stale backup copy |
| `Vision.swift` | 2 lines, just `import Foundation` |
| `AppendExtention.swift` | 1 line, empty |
| `INTEGRATION_EXAMPLE.swift` | Documentation, not code |
| `QUICK_START_GUIDE.swift` | Documentation, not code |

### 8. Performance Concern: Eager Initialization

`LiveObjectDetectionView` creates all 6 detection services as `@StateObject` on init, even when the user only uses one pipeline mode. YOLO model loading and Apple Vision classifier setup run regardless of whether those pipelines are selected.

**Recommendation:** Lazy-initialize detectors based on the active pipeline setting. Only create the services that will actually be used.

### Summary: Top 5 Actions to Improve This Codebase

1. **Extract ViewModels** from the 3 largest views (LiveObjectDetectionView, CameraScanView, EvaluationView) — this is the single highest-impact change
2. **Delete dead code** (7+ files identified above) and consolidate duplicate implementations (speech, auth, Drive)
3. **Add a test target** and write tests for pure logic first (models, parsing, deduplication)
4. **Split InventoryStore** into focused components with protocols
5. **Organize files into folders** matching architectural layers
