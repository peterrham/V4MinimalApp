# Camera View UI Guide - Streaming Upload

## 🎨 UI Layout

```
┌─────────────────────────────────────┐
│  [X]        [📦 2]       [⚡] [☁️]  │ ← Top Controls
│                                     │
│          CAMERA PREVIEW             │
│                                     │
│    ┌──────────────────────┐         │
│    │  Streaming to Drive  │         │ ← Streaming Indicator
│    │  1.2 MB uploaded     │         │   (only when streaming)
│    └──────────────────────┘         │
│                                     │
│                                     │
│  [Sample Item 1] [Sample Item 2]   │ ← Detected Items
│                                     │
│  [📷]     (  ●  )     [🎥☁️]        │ ← Bottom Controls
└─────────────────────────────────────┘
```

## 🔘 Control Buttons

### Top Bar (Left to Right)

1. **[X] Close Button**
   - Dismisses camera view
   - Returns to previous screen

2. **[📦 2] Item Counter** (when items detected)
   - Shows number of detected items
   - Green background
   - Or **[REC 0:15]** when recording (red dot + time)

3. **[⚡] Flash Button**
   - Yellow when ON
   - White when OFF
   - Slash icon when disabled

4. **[☁️] Streaming Toggle** ⭐ NEW!
   - **Enabled**: `icloud.fill` + Green color
   - **Disabled**: `icloud.slash.fill` + White color
   - Controls real-time upload to Google Drive

### Bottom Bar (Left to Right)

1. **[📷] Photo Library**
   - Opens iOS photo picker
   - Can select existing photos
   - Photo saved to iPhone automatically

2. **(●) Capture/Record Button** (Center)
   - **White circle**: Take photo
   - **Red square**: Stop recording
   - **Pulsing**: When recording

3. **[🎥] Video Record Button**
   - **Regular**: Video icon only
   - **Streaming Active**: Video icon + small cloud badge ☁️
   - Tap to start/stop recording

## 🎯 Streaming Upload States

### State 1: Disabled (Default)
```
Top Right: [☁️/] (slashed cloud, white)
Status: Regular recording (no streaming)
```

### State 2: Enabled, Not Recording
```
Top Right: [☁️] (filled cloud, green)
Status: Ready to stream
```

### State 3: Enabled, Recording & Streaming
```
Top Right: [☁️] (filled cloud, green)
Top Center: [Streaming to Drive | 1.2 MB uploaded] (green banner)
Video Button: [🎥☁️] (video icon + cloud badge)
Status: Actively uploading chunks
```

### State 4: Upload Complete
```
Notification: "Streaming upload complete"
Status: Video on Google Drive ✅
```

## 💡 Visual Indicators

### Streaming Active
When recording with streaming enabled, you'll see:

1. **Green Banner** at top center
   ```
   ┌──────────────────────┐
   │ ⟳ Streaming to Drive │
   │   1.2 MB uploaded    │
   └──────────────────────┘
   ```

2. **Cloud Badge** on video button
   ```
   [🎥] → [🎥☁️]
   ```

3. **Pulsing Effect** on video button
   - Button pulses while recording

### Not Streaming
Regular recording without streaming:
- No green banner
- No cloud badge
- Normal recording indicator (red dot + time)

## 🎬 User Flow

### Scenario 1: Streaming Upload

```
1. User opens camera
2. Taps cloud toggle → turns green ☁️
3. Taps video button → [🎥☁️]
4. Sees "Streaming to Drive" banner
5. Records video
6. Taps stop
7. Upload automatically finalized ✅
8. Done! No manual upload needed
```

### Scenario 2: Regular Recording

```
1. User opens camera
2. Cloud toggle stays slashed (disabled)
3. Taps video button → [🎥]
4. Records video
5. Taps stop
6. Upload options sheet appears
7. Manually uploads to Drive or Photos
```

### Scenario 3: Photo Capture

```
1. User opens camera
2. Taps center capture button (●)
3. Photo taken instantly
4. Photo saved to Photos app ✅
5. Success alert appears
```

## 🎨 Color Coding

| Element | Color | Meaning |
|---------|-------|---------|
| Cloud Toggle (ON) | 🟢 Green | Streaming enabled |
| Cloud Toggle (OFF) | ⚪ White | Streaming disabled |
| Flash (ON) | 🟡 Yellow | Flash enabled |
| Flash (OFF) | ⚪ White | Flash disabled |
| Recording Indicator | 🔴 Red | Recording active |
| Item Counter | 🟢 Green | Items detected |
| Streaming Banner | 🟢 Green | Upload in progress |

## 📱 Interaction Guide

### Enable Streaming
**Tap**: Cloud button (top right)
**Result**: Button turns green, icon changes to filled cloud

### Disable Streaming  
**Tap**: Cloud button again (top right)
**Result**: Button turns white, icon changes to slashed cloud

### Start Streaming Recording
**Prerequisites**: 
1. Cloud toggle must be green (enabled)
2. Camera must be authorized

**Action**: Tap video button (bottom right)

**What You'll See**:
1. Green "Streaming to Drive" banner appears
2. Cloud badge appears on video button
3. Byte counter starts incrementing
4. Recording timer shows elapsed time

### Stop Streaming Recording
**Action**: Tap video button again (shows stop icon)

**What Happens**:
1. Recording stops
2. Final chunks upload
3. Upload finalized automatically
4. Success notification
5. Video available on Google Drive

## 🔍 Progress Indicators

### Upload Progress Display

```
┌─────────────────────────┐
│  ⟳ Streaming to Drive   │
│    📊 1.2 MB uploaded   │
└─────────────────────────┘
```

- **Spinner**: Indicates active upload
- **Text**: "Streaming to Drive"
- **Byte Count**: Real-time upload progress
- **Updates**: Every 0.5 seconds

### Recording Duration Display

```
┌─────────────────┐
│  ● REC 0:15     │
└─────────────────┘
```

- **Red Dot**: Recording indicator
- **REC**: Recording label
- **0:15**: Elapsed time (min:sec)
- **Updates**: Every 0.1 seconds

## ⚠️ Error States

### Authentication Error
```
Alert: "Camera Error"
Message: "Not authenticated with Google Drive"
Solution: Sign in to Google Drive
```

### Network Error
```
Alert: "Camera Error"
Message: "Upload failed: Network error"
Solution: Check internet connection
```

### Permission Error
```
View: Camera access required screen
Action: Button to open Settings
```

## 🎯 Tips for Best UX

1. **Enable streaming on WiFi**: Better for large uploads
2. **Disable on cellular**: Save mobile data
3. **Check battery**: Streaming uses more power
4. **Monitor progress**: Watch byte counter for verification
5. **Test connection**: Try small recording first

## 📊 Visual Feedback Summary

| Action | Visual Feedback |
|--------|----------------|
| Enable streaming | Cloud icon turns green |
| Start streaming record | Green banner + cloud badge |
| Upload chunk | Byte counter increments |
| Stop recording | Banner disappears |
| Upload complete | Notification |
| Take photo | Quick shutter animation |
| Photo saved | Success alert |

---

**Quick Reference**:
- ☁️ = Streaming enabled
- ☁️/ = Streaming disabled  
- 🟢 Banner = Actively uploading
- 🎥☁️ = Recording with streaming
- 📊 = Upload progress

**Remember**: Toggle is top-right, next to flash! ⚡☁️
