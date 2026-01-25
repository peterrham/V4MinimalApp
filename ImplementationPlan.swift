//
//  ImplementationPlan.swift
//  V4MinimalApp
//
//  Home Inventory App - Detailed Implementation Plan
//  January 2026
//

/*
 
 📋 COMPREHENSIVE IMPLEMENTATION PLAN
 =====================================
 
 OVERVIEW
 --------
 Transform your audio transcription app into a full-featured home inventory
 system with camera-based AI object recognition using Gemini Live API.
 
 
 ═══════════════════════════════════════════════════════════════════════════
 PHASE 1: UI FOUNDATION & VISUAL POLISH (Week 1-2) ⭐ START HERE
 ═══════════════════════════════════════════════════════════════════════════
 
 Priority: HIGH - Immediate user experience improvements
 
 ✅ TASK 1.1: Update App Theme System
 ─────────────────────────────────────
 File: Theme.swift
 Status: ✅ COMPLETED
 
 - [✅] Add primary indigo color (#6366F1)
 - [✅] Add success green (#10B981)
 - [✅] Add warning amber (#F59E0B)
 - [✅] Add typography system
 - [✅] Enhanced Card component with better shadows
 
 
 ✅ TASK 1.2: Create Tab-Based Navigation
 ─────────────────────────────────────────
 File: MainTabView.swift
 Status: ✅ COMPLETED
 
 - [✅] Create MainTabView with 4 tabs
 - [ ] Update app entry point to use MainTabView
 - [ ] Test tab switching and state preservation
 
 Next Steps:
 1. Update your @main app file to show MainTabView instead of ContentView
 2. Test the navigation
 
 
 📝 TASK 1.3: Create HomeView (Dashboard)
 ─────────────────────────────────────────
 File: HomeView.swift (TO CREATE)
 Status: ⏳ PENDING
 
 Features to implement:
 - [ ] Welcome header with user's name from Google
 - [ ] Statistics cards (Total Items, Total Value, Rooms)
 - [ ] Recent items list (last 5 scanned)
 - [ ] Quick scan button (large, prominent)
 - [ ] Room breakdown chart/list
 
 Estimated Time: 4-6 hours
 
 UI Elements:
 - Large "Scan Room" button at top (indigo gradient)
 - 3 stat cards in horizontal scroll
 - "Recent Items" section with thumbnail grid
 - "Rooms" section with navigable cards
 
 
 📝 TASK 1.4: Create InventoryListView
 ──────────────────────────────────────
 File: InventoryListView.swift (TO CREATE)
 Status: ⏳ PENDING
 
 Features to implement:
 - [ ] Search bar for filtering items
 - [ ] Category filter chips
 - [ ] Room filter
 - [ ] Grid/List toggle
 - [ ] Item cards with thumbnail, name, value
 - [ ] Pull-to-refresh
 - [ ] Navigation to ItemDetailView
 
 Estimated Time: 6-8 hours
 
 
 📝 TASK 1.5: Create ItemDetailView
 ───────────────────────────────────
 File: ItemDetailView.swift (TO CREATE)
 Status: ⏳ PENDING
 
 Features to implement:
 - [ ] Photo gallery (horizontal scroll)
 - [ ] Editable fields (name, value, category, room)
 - [ ] Purchase info section
 - [ ] Notes/voice transcripts
 - [ ] Share button
 - [ ] Delete button
 
 Estimated Time: 4-6 hours
 
 
 📝 TASK 1.6: Create Enhanced SettingsView
 ──────────────────────────────────────────
 File: SettingsView.swift (TO CREATE)
 Status: ⏳ PENDING
 
 Features to implement:
 - [ ] Google account section (sign in/out)
 - [ ] Sync settings (auto-backup to Sheets)
 - [ ] Export options (PDF, CSV)
 - [ ] AI settings (confidence threshold)
 - [ ] Developer mode toggle (shows debug views)
 - [ ] About section (version, credits)
 
 Estimated Time: 3-4 hours
 
 
 📝 TASK 1.7: Clean Up Existing Views
 ─────────────────────────────────────
 Files: ContentView.swift, GoogleAuthenticatorView.swift
 Status: ✅ PARTIALLY COMPLETED
 
 - [✅] Fix ContentView styling
 - [✅] Fix GoogleAuthenticatorView styling
 - [ ] Move to Settings tab or remove if no longer needed
 - [ ] Fix "Disconect" typo → "Disconnect"
 - [ ] Hide debug buttons behind developer mode
 
 
 ═══════════════════════════════════════════════════════════════════════════
 PHASE 2: DATA MODELS & STATE MANAGEMENT (Week 2-3)
 ═══════════════════════════════════════════════════════════════════════════
 
 Priority: HIGH - Foundation for all features
 
 
 📝 TASK 2.1: Create Core Data Models
 ─────────────────────────────────────
 Files: Models/InventoryItem.swift, Models/Room.swift, Models/Category.swift
 Status: ⏳ PENDING
 
 - [ ] Create InventoryItem struct/class
 - [ ] Create Room model
 - [ ] Create ItemCategory enum
 - [ ] Add Codable conformance for Google Sheets sync
 - [ ] Add sample data for testing
 
 Estimated Time: 3-4 hours
 
 InventoryItem Properties:
 - id: UUID
 - name: String
 - category: ItemCategory
 - room: String
 - estimatedValue: Double?
 - purchasePrice: Double?
 - purchaseDate: Date?
 - brand: String?
 - notes: String
 - photos: [String] // URLs or local paths
 - voiceTranscripts: [String]
 - createdAt: Date
 - updatedAt: Date
 
 
 📝 TASK 2.2: Create InventoryViewModel
 ───────────────────────────────────────
 File: ViewModels/InventoryViewModel.swift
 Status: ⏳ PENDING
 
 - [ ] @Observable class for iOS 17+
 - [ ] CRUD operations for items
 - [ ] Search and filter functionality
 - [ ] Statistics calculations
 - [ ] Google Sheets sync integration
 
 Estimated Time: 4-6 hours
 
 
 📝 TASK 2.3: Enhance Core Data or Use SwiftData
 ────────────────────────────────────────────────
 Decision: Migrate to SwiftData (recommended) or enhance existing Core Data
 Status: ⏳ PENDING
 
 - [ ] Create SwiftData models for InventoryItem and Room
 - [ ] Set up ModelContainer
 - [ ] Create sample data generator
 - [ ] Test persistence
 
 Estimated Time: 3-5 hours
 
 
 ═══════════════════════════════════════════════════════════════════════════
 PHASE 3: CAMERA INTEGRATION (Week 3-4)
 ═══════════════════════════════════════════════════════════════════════════
 
 Priority: MEDIUM-HIGH - Core feature for scanning
 
 
 📝 TASK 3.1: Create CameraManager
 ──────────────────────────────────
 File: Services/CameraManager.swift
 Status: ⏳ PENDING
 
 - [ ] Set up AVCaptureSession
 - [ ] Configure camera input/output
 - [ ] Implement photo capture
 - [ ] Extract video frames for streaming (1-2 fps)
 - [ ] Handle permissions
 - [ ] Error handling
 
 Estimated Time: 6-8 hours
 
 Key APIs:
 - AVCaptureDevice
 - AVCaptureSession
 - AVCaptureVideoDataOutput
 - AVCapturePhotoOutput
 
 
 📝 TASK 3.2: Create CameraScanView
 ───────────────────────────────────
 File: Views/CameraScanView.swift
 Status: ⏳ PENDING
 
 - [ ] Camera preview using UIViewRepresentable
 - [ ] Capture button
 - [ ] Voice recording button
 - [ ] Object detection overlay
 - [ ] Real-time bounding boxes (prepare for Gemini)
 - [ ] Item count badge
 
 Estimated Time: 6-8 hours
 
 UI Layout:
 - Full-screen camera preview
 - Bottom sheet with controls
 - Floating voice button
 - Top bar with close/flash/flip camera
 
 
 📝 TASK 3.3: Create CameraPreview Component
 ────────────────────────────────────────────
 File: Components/CameraPreview.swift
 Status: ⏳ PENDING
 
 - [ ] UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
 - [ ] Handle rotation
 - [ ] Focus/exposure tap-to-focus
 
 Estimated Time: 2-3 hours
 
 
 ═══════════════════════════════════════════════════════════════════════════
 PHASE 4: GEMINI LIVE API INTEGRATION (Week 5-6)
 ═══════════════════════════════════════════════════════════════════════════
 
 Priority: MEDIUM - AI-powered object recognition
 
 
 📝 TASK 4.1: Set Up Google Cloud Project
 ─────────────────────────────────────────
 Status: ⏳ PENDING
 
 - [ ] Create Google Cloud project
 - [ ] Enable Gemini API
 - [ ] Generate API key
 - [ ] Store securely in Keychain
 - [ ] Test API access with simple request
 
 Estimated Time: 1-2 hours
 
 
 📝 TASK 4.2: Create GeminiLiveService
 ──────────────────────────────────────
 File: Services/GeminiLiveService.swift
 Status: ⏳ PENDING
 
 - [ ] WebSocket connection manager
 - [ ] Setup message configuration
 - [ ] Video frame streaming (base64 encoded)
 - [ ] Audio streaming (PCM format)
 - [ ] Response parsing
 - [ ] Object detection result handling
 - [ ] Reconnection logic
 - [ ] Rate limiting (1-2 fps for video)
 
 Estimated Time: 10-12 hours
 
 WebSocket Endpoint:
 wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent
 
 System Prompt:
 "You are a home inventory assistant. When you see objects in the video feed:
 1) Identify each item with its common name
 2) Estimate approximate value range
 3) Suggest a category (Electronics, Furniture, Appliances, etc.)
 4) Note brand if visible
 When the user speaks, incorporate their details (exact price, purchase date,
 notes) into the item record. Be concise and conversational."
 
 
 📝 TASK 4.3: Integrate Audio Recording
 ───────────────────────────────────────
 File: Services/AudioService.swift
 Status: ⏳ PENDING (you have SpeechRecognition.swift already)
 
 - [ ] Capture microphone input
 - [ ] Convert to PCM format for Gemini
 - [ ] Stream audio chunks
 - [ ] Handle speech recognition locally as fallback
 
 Estimated Time: 4-6 hours
 
 Note: You already have speech recognition working. Adapt it to also
 stream to Gemini Live API.
 
 
 📝 TASK 4.4: Object Detection Overlay
 ──────────────────────────────────────
 File: Components/ObjectDetectionOverlay.swift
 Status: ⏳ PENDING
 
 - [ ] Draw bounding boxes from Gemini responses
 - [ ] Show labels with confidence scores
 - [ ] Animate box appearances
 - [ ] Handle coordinate conversion
 
 Estimated Time: 4-5 hours
 
 
 ═══════════════════════════════════════════════════════════════════════════
 PHASE 5: ENHANCED GOOGLE SHEETS INTEGRATION (Week 6-7)
 ═══════════════════════════════════════════════════════════════════════════
 
 Priority: MEDIUM - Data persistence and export
 
 
 📝 TASK 5.1: Enhance GoogleSheetsService
 ────────────────────────────────────────
 File: GoogleSheetsService.swift
 Status: ⏳ PENDING (you have GoogleDriveUploader.swift)
 
 - [ ] Create inventory spreadsheet template
 - [ ] Batch upload items
 - [ ] Update existing items
 - [ ] Sync photos to Google Drive
 - [ ] Handle sync conflicts
 - [ ] Add progress indicators
 
 Estimated Time: 6-8 hours
 
 Sheet Structure:
 - Sheet 1: Items (all fields)
 - Sheet 2: Rooms summary
 - Sheet 3: Category breakdown
 - Sheet 4: Value analysis
 
 
 📝 TASK 5.2: Create Export Service
 ───────────────────────────────────
 File: Services/ExportService.swift
 Status: ⏳ PENDING
 
 - [ ] PDF generation for insurance reports
 - [ ] CSV export for spreadsheets
 - [ ] JSON backup format
 - [ ] Include photos in exports
 - [ ] Share sheet integration
 
 Estimated Time: 5-7 hours
 
 
 ═══════════════════════════════════════════════════════════════════════════
 PHASE 6: POLISH & REFINEMENT (Week 7-8)
 ═══════════════════════════════════════════════════════════════════════════
 
 Priority: MEDIUM - User experience improvements
 
 
 📝 TASK 6.1: Create Onboarding Flow
 ────────────────────────────────────
 File: Views/OnboardingView.swift
 Status: ⏳ PENDING
 
 - [ ] Welcome screen
 - [ ] Feature highlights (3-4 pages)
 - [ ] Camera permission request
 - [ ] Microphone permission request
 - [ ] Google Sign-In flow
 - [ ] Skip button for returning users
 
 Estimated Time: 4-5 hours
 
 
 📝 TASK 6.2: Add Animations & Transitions
 ──────────────────────────────────────────
 Files: Various views
 Status: ⏳ PENDING
 
 - [ ] Item card appear animations
 - [ ] Scan success animation
 - [ ] Loading states
 - [ ] Empty state illustrations
 - [ ] Skeleton screens
 
 Estimated Time: 3-4 hours
 
 
 📝 TASK 6.3: Accessibility Improvements
 ────────────────────────────────────────
 Files: All views
 Status: ⏳ PENDING
 
 - [ ] VoiceOver labels
 - [ ] Dynamic Type support
 - [ ] Sufficient color contrast (WCAG AA)
 - [ ] Haptic feedback
 - [ ] Reduce motion support
 
 Estimated Time: 3-4 hours
 
 
 📝 TASK 6.4: Error Handling & Edge Cases
 ─────────────────────────────────────────
 Files: All services
 Status: ⏳ PENDING
 
 - [ ] Network error handling
 - [ ] API rate limit handling
 - [ ] Offline mode
 - [ ] Data validation
 - [ ] User-friendly error messages
 
 Estimated Time: 4-6 hours
 
 
 ═══════════════════════════════════════════════════════════════════════════
 QUICK WINS - Implement These First! 🚀
 ═══════════════════════════════════════════════════════════════════════════
 
 1. ✅ Update Theme.swift with new colors (DONE)
 2. ✅ Create MainTabView.swift (DONE)
 3. [ ] Create HomeView.swift with mock data (2 hours)
 4. [ ] Create InventoryListView.swift with mock data (3 hours)
 5. [ ] Update app entry point to show tabs (15 minutes)
 6. [ ] Hide debug UI behind Settings > Developer Mode (1 hour)
 7. [ ] Fix "Disconect" typo (5 minutes)
 
 Total Quick Wins Time: ~6.5 hours to see major visual improvements!
 
 
 ═══════════════════════════════════════════════════════════════════════════
 TECHNICAL ARCHITECTURE
 ═══════════════════════════════════════════════════════════════════════════
 
 DATA FLOW
 ─────────
 
 1. User opens Camera Scan
    ↓
 2. CameraManager captures frames (1-2 fps) + audio
    ↓
 3. GeminiLiveService streams to API via WebSocket
    ↓
 4. Gemini identifies objects + processes voice
    ↓
 5. App creates InventoryItem with details
    ↓
 6. Item saved to SwiftData locally
    ↓
 7. GoogleSheetsService syncs to cloud (background)
    ↓
 8. Item appears in Inventory list
 
 
 DEPENDENCIES
 ────────────
 
 Required:
 - AVFoundation (camera)
 - Speech (voice recognition)
 - GoogleSignIn (authentication) ✅ Already integrated
 - Foundation (networking)
 - SwiftUI (UI)
 
 Recommended:
 - SwiftData (persistence) - replaces Core Data
 - Charts (visualizations)
 - PDFKit (export)
 
 API Keys Needed:
 - Google Cloud Project API Key (Gemini Live)
 - Google OAuth Client ID ✅ Already have
 
 
 GEMINI LIVE API SPECIFICS
 ─────────────────────────
 
 Message Format (JSON over WebSocket):
 
 Setup:
 {
   "setup": {
     "model": "models/gemini-2.0-flash-exp",
     "systemInstruction": {
       "parts": [{"text": "You are a home inventory assistant..."}]
     }
   }
 }
 
 Send Video Frame:
 {
   "realtimeInput": {
     "mediaChunks": [{
       "mimeType": "image/jpeg",
       "data": "<base64_encoded_jpeg>"
     }]
   }
 }
 
 Send Audio:
 {
   "realtimeInput": {
     "mediaChunks": [{
       "mimeType": "audio/pcm",
       "data": "<base64_encoded_pcm>"
     }]
   }
 }
 
 Receive Response:
 {
   "serverContent": {
     "modelTurn": {
       "parts": [{
         "text": "I see a Samsung TV, approximately 55 inches..."
       }]
     }
   }
 }
 
 
 ═══════════════════════════════════════════════════════════════════════════
 TESTING STRATEGY
 ═══════════════════════════════════════════════════════════════════════════
 
 Unit Tests:
 - [ ] InventoryItem CRUD operations
 - [ ] Search/filter logic
 - [ ] Value calculations
 - [ ] Export formatting
 
 Integration Tests:
 - [ ] Google Sheets sync
 - [ ] Camera capture
 - [ ] Gemini API responses
 
 UI Tests:
 - [ ] Tab navigation
 - [ ] Item creation flow
 - [ ] Search functionality
 
 
 ═══════════════════════════════════════════════════════════════════════════
 NEXT IMMEDIATE STEPS (What to do NOW)
 ═══════════════════════════════════════════════════════════════════════════
 
 Step 1: Update your main app file to use MainTabView
 Step 2: Create HomeView.swift with mock data
 Step 3: Create InventoryListView.swift with mock data
 Step 4: Test the tab navigation
 Step 5: Once UI looks good, move to camera integration
 
 Would you like me to:
 A) Create the HomeView.swift file now?
 B) Create the InventoryListView.swift file?
 C) Create the data models (InventoryItem, Room, Category)?
 D) Create a complete CameraManager service?
 E) Show you how to update the app entry point?
 
 */
