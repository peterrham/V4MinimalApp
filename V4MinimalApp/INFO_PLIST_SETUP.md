# Adding Gemini API Key to Info.plist

## ✅ Yes, You Can Use Info.plist!

Info.plist is now supported as a configuration option for your Gemini API key.

---

## 🎯 Quick Setup (2 Minutes)

### Step 1: Open Info.plist
1. In Xcode, find `Info.plist` in your project navigator
2. Right-click → Open As → Source Code

### Step 2: Add Your API Key
Add this entry inside the `<dict>` tag:

```xml
<key>GeminiAPIKey</key>
<string>YOUR_API_KEY_HERE</string>
```

### Step 3: Save and Build
That's it! The app will automatically detect and use the key.

---

## 📝 Complete Example

Your Info.plist should look like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Your existing keys -->
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    
    <key>UILaunchScreen</key>
    <dict/>
    
    <!-- Add your Gemini API key here -->
    <key>GeminiAPIKey</key>
    <string>AIzaSyDEXAMPLEKEY123456789</string>
    
    <!-- More existing keys... -->
</dict>
</plist>
```

---

## 🎨 Visual Guide (Property List Editor)

If you prefer the visual editor:

1. Open Info.plist
2. Click the **+** button next to "Information Property List"
3. Add new row:
   - **Key**: `GeminiAPIKey`
   - **Type**: `String`
   - **Value**: Your actual API key

```
Information Property List
  ↓
  + GeminiAPIKey          String    AIzaSyDEXAMPLE...
```

---

## 🔄 API Key Priority Order

The app checks for API keys in this order:

1. **Explicit parameter** (passed directly to service)
2. **Config.plist** (separate config file) ← Most secure
3. **Info.plist** (main app plist) ← **YOU ARE HERE**
4. **Environment Variable** (Xcode scheme)

If multiple sources exist, the first one found is used.

---

## ✅ Advantages of Info.plist

### Pros ✅
- **Simple**: Just one file to edit
- **Built-in**: No extra files needed
- **Easy**: Property list editor is user-friendly
- **Quick**: Fastest way to get started

### Cons ⚠️
- **Committed to Git**: Info.plist is usually tracked
- **Visible**: Anyone with source code can see it
- **Single file**: Changes affect main app configuration

---

## 🔒 Security Considerations

### ⚠️ Important Security Warning

**Info.plist is usually committed to version control!**

If you're using Git:

#### Option A: Don't Commit the Key (Recommended)
1. Add placeholder to Info.plist:
   ```xml
   <key>GeminiAPIKey</key>
   <string>REPLACE_WITH_YOUR_KEY</string>
   ```

2. Add to `.gitignore`:
   ```gitignore
   # Don't track Info.plist changes with API key
   # (Caution: This ignores ALL Info.plist changes)
   **/Info.plist
   ```

3. Keep actual key locally or in CI/CD secrets

#### Option B: Use Config.plist Instead
For better security, use `Config.plist` (which can be gitignored):
1. Create `Config.plist` (separate file)
2. Add to `.gitignore`
3. Keep template in repo without key

See: `GEMINI_SETUP.md` for Config.plist details

#### Option C: Use Environment Variables
For development, use Xcode environment variables:
- Xcode → Edit Scheme → Environment Variables
- Add: `GEMINI_API_KEY`
- Never committed to Git

---

## 🧪 Testing It Works

### 1. Add Key to Info.plist
```xml
<key>GeminiAPIKey</key>
<string>AIzaSyD_your_actual_key_here</string>
```

### 2. Build and Run
```
Cmd + B  (Build)
Cmd + R  (Run)
```

### 3. Check Console Logs
Look for:
```
✅ Gemini API key loaded successfully
📍 API key loaded from Info.plist
```

### 4. Take a Photo
- Open camera
- Capture photo
- See "Analyzing..." then AI description

### 5. Verify in Code
You can verify which source was used by checking the console logs.

---

## 📋 Complete Setup Checklist

- [ ] Get API key from https://makersuite.google.com/app/apikey
- [ ] Open Info.plist in Xcode
- [ ] Add `GeminiAPIKey` entry
- [ ] Paste your actual API key as value
- [ ] Save file
- [ ] Build project (Cmd + B)
- [ ] Check console for success message
- [ ] Run app and test photo capture

---

## 🔧 Troubleshooting

### "API key not configured" Error

**Check 1: Key Name**
```xml
<!-- ❌ Wrong -->
<key>GEMINI_API_KEY</key>

<!-- ✅ Correct -->
<key>GeminiAPIKey</key>
```

**Check 2: Key Type**
```xml
<!-- ✅ Correct -->
<key>GeminiAPIKey</key>
<string>AIzaSyD...</string>  ← Must be String type
```

**Check 3: No Extra Spaces**
```xml
<!-- ❌ Wrong -->
<string> AIzaSyD... </string>

<!-- ✅ Correct -->
<string>AIzaSyD...</string>
```

**Check 4: Inside <dict>**
```xml
<plist version="1.0">
<dict>  ← Your key must be inside here
    <key>GeminiAPIKey</key>
    <string>AIzaSyD...</string>
</dict>
</plist>
```

### Still Not Working?

1. **Clean Build Folder**
   - Xcode → Product → Clean Build Folder (Cmd + Shift + K)
   - Build again (Cmd + B)

2. **Check Console Logs**
   ```
   ⚠️ Gemini API key not configured
   → Key not found or invalid
   
   ✅ Gemini API key loaded successfully
   → Working correctly!
   ```

3. **Verify API Key is Valid**
   - Go to https://makersuite.google.com/app/apikey
   - Check your key is active
   - Try regenerating if needed

4. **Try Different Method**
   - Use Environment Variable instead (see GEMINI_SETUP.md)
   - Use Config.plist instead (more secure)

---

## 🚀 Quick Start Code

If you want to verify the key is loading:

```swift
// Add this anywhere for debugging
let apiKey = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String
print("🔑 API Key from Info.plist: \(apiKey ?? "Not found")")
```

---

## 🔄 Switching from Environment Variable to Info.plist

Already using environment variable? Easy switch:

1. **Copy your key** from Xcode scheme
2. **Add to Info.plist** as shown above
3. **Remove from scheme** (optional, but cleaner)
4. **Build and run** - it will use Info.plist automatically

The app will use Info.plist if no Config.plist exists.

---

## 📚 Related Documentation

- **GEMINI_SETUP.md** - All configuration methods
- **QUICK_START.md** - Quick setup guide
- **GEMINI_README.md** - Comprehensive reference

---

## 💡 Best Practices

### For Personal Projects
✅ Info.plist is fine - quick and easy

### For Team Projects
⚠️ Consider Config.plist or environment variables
- Keeps keys out of shared repository
- Each developer has their own key
- Easier key rotation

### For Production Apps
🔒 Use secure key management:
- Backend API proxy (key stays on server)
- Environment-specific configurations
- Key rotation strategy
- Never hardcode in distributed apps

---

## 🎉 Summary

**Yes, you can absolutely use Info.plist!**

It's now supported and will work perfectly. Just add:

```xml
<key>GeminiAPIKey</key>
<string>YOUR_ACTUAL_KEY</string>
```

And you're done! ✨

---

## ⚡ TL;DR

```xml
1. Open Info.plist
2. Add this:
   <key>GeminiAPIKey</key>
   <string>AIzaSyD_your_key_here</string>
3. Save
4. Build & Run
5. Take photo → See AI magic! ✨
```

**That's it!** 🎊
