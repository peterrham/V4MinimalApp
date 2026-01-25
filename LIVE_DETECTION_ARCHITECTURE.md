# Live Object Detection Architecture

## 📐 System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    LiveObjectDetectionView                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Camera Preview                          │   │
│  │                                                            │   │
│  │  ┌──────────────────────────────────────────────────┐    │   │
│  │  │   StreamingObjectDetectionView (Scrolling Box)   │    │   │
│  │  │  ┌────────────────────────────────────────────┐  │    │   │
│  │  │  │ • Coffee mug                         now   │  │    │   │
│  │  │  │ • Laptop computer                    2s    │  │    │   │
│  │  │  │ • Wireless mouse                     5s    │  │    │   │
│  │  │  │ • Desk lamp                          8s    │  │    │   │
│  │  │  └────────────────────────────────────────────┘  │    │   │
│  │  └──────────────────────────────────────────────────┘    │   │
│  │                                                            │   │
│  │            [Clear]  [●  STOP  ●]  [Share]                │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## 🔄 Data Flow

```
┌──────────────────┐
│  Camera Device   │
└────────┬─────────┘
         │ Video Stream
         ▼
┌──────────────────────────┐
│  CameraManager           │
│  • AVCaptureSession      │
│  • AVCaptureVideoOutput  │
└────────┬─────────────────┘
         │ Frame every 2s
         ▼
┌──────────────────────────────┐
│  CameraManager+FrameCapture  │
│  • CMSampleBuffer → UIImage  │
└────────┬─────────────────────┘
         │ UIImage
         ▼
┌────────────────────────────────────┐
│  GeminiStreamingVisionService      │
│  • Convert to Base64               │
│  • Send to Gemini API              │
│  • Parse response                  │
└────────┬───────────────────────────┘
         │ Object names (comma-separated)
         ▼
┌────────────────────────────┐
│  DetectedObject Array      │
│  • name: String            │
│  • timestamp: Date         │
└────────┬───────────────────┘
         │ @Published
         ▼
┌──────────────────────────────┐
│  StreamingObjectDetectionView│
│  • Scrolling list            │
│  • Auto-scroll to new        │
│  • Animated appearance       │
└──────────────────────────────┘
```

## 🧩 Component Responsibilities

### LiveObjectDetectionView
**Role:** Main coordinator view
- Manages camera and vision service
- Handles UI state
- Coordinates start/stop
- Manages share/clear actions

### CameraManager
**Role:** Camera hardware interface
- Configures AVCaptureSession
- Manages camera permissions
- Provides frame capture
- Controls flash

### CameraManager+FrameCapture
**Role:** Frame extraction
- Implements AVCaptureVideoDataOutputSampleBufferDelegate
- Converts CMSampleBuffer → UIImage
- Throttles frame callbacks
- Provides clean callback API

### GeminiStreamingVisionService
**Role:** AI processing
- Sends frames to Gemini API
- Parses object names
- Deduplicates detections
- Manages analysis state
- Throttles API calls (2s interval)

### StreamingObjectDetectionView
**Role:** Detection display
- Shows scrolling list
- Animates new detections
- Auto-scrolls to latest
- Displays status

### DetectedObject
**Role:** Data model
- Stores object name
- Stores timestamp
- Provides unique ID
- Equatable for comparison

## ⏱️ Timing & Throttling

```
Time:  0s    2s    4s    6s    8s    10s
       │     │     │     │     │     │
Frame: █     █     █     █     █     █
       │     │     │     │     │     │
API:   ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓▓▓ ▓▓▓▓▓
       │     │     │     │     │     │
Result:└─►   └─►   └─►   └─►   └─►
       
       █ = Frame captured
       ▓ = API call in progress
       ► = Result displayed
```

### Throttling Strategy
- **analysisInterval** = 2.0 seconds
- **lastAnalysisTime** tracked
- **isCurrentlyAnalyzing** flag prevents overlap
- **alwaysDiscardsLateVideoFrames** = true

## 📊 Object Deduplication

```
Detected: "Coffee mug" at 10:00:00
          └─► Added to list

Detected: "Coffee mug" at 10:00:03 (3s later)
          └─► IGNORED (within 10s window)

Detected: "Coffee mug" at 10:00:12 (12s later)
          └─► Added to list (outside 10s window)
```

### Deduplication Logic
```swift
let isDuplicate = detectedObjects.contains { existing in
    existing.name.lowercased() == name.lowercased() &&
    now.timeIntervalSince(existing.timestamp) < 10
}
```

## 🎯 API Request Structure

```json
{
  "contents": [
    {
      "parts": [
        {
          "text": "List all distinct objects you see..."
        },
        {
          "inline_data": {
            "mime_type": "image/jpeg",
            "data": "base64_encoded_image_data..."
          }
        }
      ]
    }
  ],
  "generationConfig": {
    "temperature": 0.2,      // Low for consistency
    "topK": 20,
    "topP": 0.8,
    "maxOutputTokens": 150
  }
}
```

## 🎨 UI State Machine

```
┌─────────────┐
│   Initial   │
│  (Paused)   │
└──────┬──────┘
       │ Tap Play
       ▼
┌─────────────┐
│   Active    │
│  (Scanning) │◄──┐
└──────┬──────┘   │
       │          │
       │ Frame    │ More Frames
       │ Analyzed │
       ▼          │
┌─────────────┐   │
│   Object    │   │
│   Detected  ├───┘
└──────┬──────┘
       │ Tap Stop
       ▼
┌─────────────┐
│   Paused    │
│  (History)  │
└─────────────┘
```

## 🔐 API Key Loading Order

```
1. Explicit Constructor Parameter
   └─► GeminiStreamingVisionService(apiKey: "AIza...")
       ❌ Not found
       ▼

2. Config.plist
   └─► Bundle.main.path(forResource: "Config", ofType: "plist")
       ❌ Not found
       ▼

3. Info.plist
   └─► Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey")
       ✅ Found! "AIzaSy..."
       ▼

4. Environment Variable
   └─► ProcessInfo.environment["GEMINI_API_KEY"]
       (Not checked - already found in step 3)
```

## 📱 View Lifecycle

```
View Appears
    │
    ├─► setupStreamingDetection()
    │   └─► cameraManager.enableFrameCapture()
    │       └─► Frame callback registered
    │
    ├─► Camera session starts
    │   └─► Frames begin flowing
    │
User Taps Play
    │
    ├─► toggleDetection()
    │   ├─► isDetectionActive = true
    │   ├─► visionService.startAnalyzing()
    │   └─► Haptic feedback
    │
    ├─► Frames analyzed every 2s
    │   └─► Objects appear in list
    │
User Taps Stop
    │
    ├─► toggleDetection()
    │   ├─► isDetectionActive = false
    │   ├─► visionService.stopAnalyzing()
    │   └─► Haptic feedback
    │
View Disappears
    │
    └─► cleanup()
        ├─► visionService.stopAnalyzing()
        ├─► cameraManager.disableFrameCapture()
        └─► cameraManager.stopSession()
```

## 🧠 Memory Management

```
┌────────────────────────┐
│  Frame Capture Queue   │
│  • DispatchQueue       │
│  • One at a time       │
│  • Discards late frames│
└────────┬───────────────┘
         │
         ▼
┌────────────────────────┐
│  Image Conversion      │
│  • CMSampleBuffer      │
│  • → CIImage           │
│  • → CGImage           │
│  • → UIImage           │
│  • Auto-released       │
└────────┬───────────────┘
         │
         ▼
┌────────────────────────┐
│  JPEG Compression      │
│  • 0.5 quality         │
│  • Smaller size        │
│  • Faster upload       │
└────────┬───────────────┘
         │
         ▼
┌────────────────────────┐
│  API Request           │
│  • Base64 encode       │
│  • HTTP POST           │
│  • 10s timeout         │
└────────┬───────────────┘
         │
         ▼
┌────────────────────────┐
│  Response              │
│  • Parse JSON          │
│  • Extract objects     │
│  • Update @Published   │
│  • SwiftUI re-render   │
└────────────────────────┘
```

## 🎭 Animation Timeline

```
New Object Detected
    │
    ├─► DetectedObject created
    │   └─► Added to array
    │       └─► @Published triggers update
    │
    ▼
SwiftUI Re-render
    │
    ├─► ObjectDetectionRow appears
    │   └─► onAppear() fires
    │       └─► appeared = true
    │
    ▼
Animations (simultaneous)
    │
    ├─► Scale: 0.95 → 1.0
    ├─► Opacity: 0.0 → 1.0
    ├─► Background: 0.05 → 0.15 opacity
    │
    └─► Spring animation (0.3s, 0.7 damping)
    
    ▼
Auto-scroll
    │
    └─► ScrollViewReader.scrollTo(object.id)
        └─► EaseOut animation (0.3s)
```

## 🔄 Complete Cycle Example

```
1. User opens LiveObjectDetectionView
   └─► Camera permission check
   └─► Camera session starts
   └─► Frame capture enabled

2. User points camera at desk

3. User taps green Play button
   └─► isDetectionActive = true
   └─► visionService.startAnalyzing()

4. Frame captured (t=0s)
   └─► UIImage created
   └─► analyzeFrame() called
   └─► Sent to Gemini API

5. API responds (t=1s)
   └─► "Coffee mug, Laptop, Mouse, Pen"
   └─► Split by comma
   └─► Create DetectedObjects
   └─► Add to array (deduplicated)
   └─► UI updates

6. UI Animation (t=1.05s)
   └─► 4 new rows appear
   └─► Animate in with spring
   └─► Auto-scroll to newest

7. Wait for next interval (t=2s)
   └─► Repeat from step 4

8. User taps red Stop button
   └─► isDetectionActive = false
   └─► No more analysis
   └─► History remains visible

9. User taps Share button
   └─► Generate text list
   └─► Show UIActivityViewController

10. User dismisses view
    └─► cleanup() called
    └─► Camera stopped
    └─► Frame capture disabled
```

---

## 🎯 Key Design Decisions

### Why 2-second interval?
- Balance between responsiveness and API costs
- Well within free tier limits (30 req/min vs 60 limit)
- Enough time for user to scan different objects
- Can be adjusted based on needs

### Why 0.5 JPEG quality?
- Faster uploads
- Lower bandwidth
- Gemini can still detect objects accurately
- 0.3 = too low, 0.8 = unnecessarily high

### Why 10-second deduplication?
- Prevents spam of same object
- Allows re-detection if object returns
- Short enough to be responsive
- Long enough to avoid duplicates

### Why max 50 objects?
- Prevents unbounded memory growth
- Scrolling more than 50 is impractical
- FIFO queue (oldest removed first)
- Can be increased if needed

### Why single prompt for all objects?
- More efficient (one API call per frame)
- Comma-separated list is easy to parse
- Gemini handles this well
- Alternative: one call per object (wasteful)

---

This architecture provides a **scalable**, **efficient**, and **user-friendly** real-time object detection system! 🚀
