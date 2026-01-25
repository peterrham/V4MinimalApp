# Gemini API Troubleshooting Guide

## "API key not configured" Error

This error occurs when the app cannot find your Gemini API key during photo identification.

---

## 🔍 Step-by-Step Debugging

### Step 1: Check Console Logs

With the enhanced logging, you should now see detailed diagnostic information. Look for:

**At App Launch:**
```
🔧 Initializing GeminiVisionService...
```

**If Key is NOT Found:**
```
❌❌❌ GEMINI API KEY NOT CONFIGURED ❌❌❌
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Troubleshooting Checklist:

1️⃣ Config.plist:
   ❌ Config.plist not found in bundle
   
2️⃣ Info.plist:
   ❌ No 'GeminiAPIKey' in Info.plist
   
3️⃣ Environment Variable:
   ❌ GEMINI_API_KEY environment variable not set
```

**If Key is Found:**
```
✅ API key loaded from Info.plist (length: 39 chars)
✅ Gemini API key configured successfully
   ✓ Key format looks valid (starts with 'AIza')
```

**When Taking a Photo:**
```
🔍 Starting Gemini photo identification...
🔍 Identifying image with Gemini Vision API...
   Image size: 3024×4032
   Image data: 156.3 KB
```

---

### Step 2: Verify Your API Key

#### Option A: Using Info.plist (Quickest)

1. **Open Info.plist in Xcode**
   - Select your project in Navigator
   - Select your app target
   - Go to "Info" tab
   - Or open `Info.plist` directly

2. **Add the Key**
   - Right-click in the list → "Add Row"
   - Key: `GeminiAPIKey` (exact spelling, case-sensitive)
   - Type: `String`
   - Value: Your actual API key from Google

3. **Verify the Entry**
   - Key should show as `GeminiAPIKey` (not "Gemini API Key")
   - Value should start with `AIza` (if it's a valid Gemini key)
   - No spaces before or after the key

4. **Clean and Rebuild**
   - `Cmd + Shift + K` (Clean Build Folder)
   - `Cmd + B` (Build)
   - Run the app

#### Option B: Using Config.plist (Recommended for Teams)

1. **Create Config.plist**
   - File → New → File → Property List
   - Name it exactly: `Config.plist`
   - Save in your project directory

2. **Add Your Key**
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>GeminiAPIKey</key>
       <string>YOUR_ACTUAL_API_KEY_HERE</string>
   </dict>
   </plist>
   ```

3. **Add to Target**
   - Select `Config.plist` in Navigator
   - In File Inspector (right panel)
   - Under "Target Membership", check your app target
   - This ensures the file is included in the app bundle

4. **Verify in Build Phases**
   - Select your project → Target → Build Phases
   - Open "Copy Bundle Resources"
   - `Config.plist` should be listed

5. **Add to .gitignore**
   ```
   # Ignore Config.plist (contains API keys)
   Config.plist
   ```

6. **Clean and Rebuild**

#### Option C: Using Environment Variable (Best for Development)

1. **Edit Scheme**
   - Product → Scheme → Edit Scheme... (or `Cmd + <`)
   - Select "Run" in left sidebar
   - Go to "Arguments" tab

2. **Add Environment Variable**
   - Under "Environment Variables" section
   - Click `+` button
   - Name: `GEMINI_API_KEY`
   - Value: Your actual API key
   - Check the box to enable it

3. **Run from Xcode**
   - This only works when running from Xcode
   - Won't work in production builds
   - Perfect for development/testing

---

### Step 3: Get Your API Key (If You Don't Have One)

1. **Visit Google AI Studio**
   - Go to: https://makersuite.google.com/app/apikey
   - Sign in with your Google account

2. **Create API Key**
   - Click "Create API Key"
   - Copy the generated key (starts with `AIza`)
   - Keep it secure!

3. **Verify the Key**
   - Should be ~39 characters long
   - Should start with `AIza`
   - Example format: `AIzaSyD...` (your actual key will be different)

---

### Step 4: Common Issues and Fixes

#### ❌ "Config.plist not found in bundle"

**Cause:** File exists but isn't included in app bundle

**Fix:**
1. Select `Config.plist` in Xcode Navigator
2. Open File Inspector (right panel)
3. Under "Target Membership", check your app target
4. Rebuild

#### ❌ "No 'GeminiAPIKey' in Info.plist"

**Cause:** Key name is incorrect or missing

**Fix:**
- Key must be exactly: `GeminiAPIKey` (case-sensitive)
- Common mistakes:
  - ❌ `GEMINI_API_KEY` (wrong)
  - ❌ `Gemini API Key` (wrong - has spaces)
  - ❌ `geminiApiKey` (wrong - lowercase)
  - ✅ `GeminiAPIKey` (correct)

#### ❌ "GeminiAPIKey exists but is EMPTY"

**Cause:** Key is defined but has no value

**Fix:**
1. Open Info.plist or Config.plist
2. Find `GeminiAPIKey` row
3. Add your actual API key in the Value column
4. Make sure there are no extra spaces
5. Rebuild

#### ❌ "Key format may be invalid (should start with 'AIza')"

**Cause:** You may have entered the wrong key or have extra characters

**Fix:**
1. Verify your key from Google AI Studio
2. Make sure you copied the entire key
3. Check for accidental spaces or line breaks
4. Gemini keys should start with `AIza`

#### ❌ API Error (403): Forbidden

**Cause:** API key is invalid or expired

**Fix:**
1. Go to https://makersuite.google.com/app/apikey
2. Check if your key is still active
3. Try regenerating the key
4. Update in your configuration
5. Rebuild

#### ❌ API Error (429): Rate Limited

**Cause:** Too many requests (free tier limit: 15/minute)

**Fix:**
- Wait 1 minute
- Try again
- Free tier limits:
  - 15 requests per minute
  - 1,500 requests per day

---

## 🎯 Quick Checklist

Use this checklist to verify your setup:

- [ ] **API Key Obtained**
  - [ ] Visited Google AI Studio
  - [ ] Created API key
  - [ ] Key starts with `AIza`
  - [ ] Key is ~39 characters

- [ ] **Configuration Method** (choose one)
  - [ ] Added to Info.plist with key `GeminiAPIKey`
  - [ ] Created Config.plist with key `GeminiAPIKey`
  - [ ] Set `GEMINI_API_KEY` environment variable in scheme

- [ ] **Build Steps**
  - [ ] Cleaned build folder (`Cmd + Shift + K`)
  - [ ] Rebuilt project (`Cmd + B`)
  - [ ] No build errors

- [ ] **Verification**
  - [ ] Check console logs at launch
  - [ ] Look for "✅ Gemini API key configured successfully"
  - [ ] No "❌ API KEY NOT CONFIGURED" errors

- [ ] **Test**
  - [ ] Open camera view
  - [ ] Take a photo
  - [ ] Should see "Analyzing..." briefly
  - [ ] Should get AI description within 1-3 seconds

---

## 📋 Console Log Guide

### What to Look For

**✅ Success Indicators:**
```
✅ Gemini API key configured successfully
   ✓ Key format looks valid (starts with 'AIza')

🔍 Identifying image with Gemini Vision API...
   Image size: 3024×4032
   Image data: 156.3 KB

📡 Sending request to Gemini API...
📥 API Response received
   Status Code: 200

✅ Image identified successfully!
   Result: A red coffee mug on a wooden table.
```

**❌ Error Indicators:**
```
❌❌❌ GEMINI API KEY NOT CONFIGURED ❌❌❌
```
→ **Fix:** Add API key to Info.plist or Config.plist

```
❌❌❌ CANNOT IDENTIFY IMAGE: API KEY NOT CONFIGURED ❌❌❌
```
→ **Fix:** App found no valid API key at launch

```
❌ API Error Response:
   Status Code: 403
   💡 403 Forbidden - API key may be invalid or expired
```
→ **Fix:** Regenerate API key from Google AI Studio

```
❌ API Error Response:
   Status Code: 429
   💡 429 Rate Limited - Too many requests
```
→ **Fix:** Wait 1 minute (free tier: 15 requests/min)

---

## 🔧 Advanced Debugging

### Enable All Logging

If you're still having issues, check your logging configuration:

1. Make sure `appBootLog` is configured for `.debug` level
2. Check Xcode console (not device console)
3. Filter for "Gemini" or "API" in console search

### Verify Bundle Resources

1. Build your app
2. In Xcode: Product → Show Build Folder in Finder
3. Navigate to: Products → Debug-iphoneos → YourApp.app
4. Right-click → Show Package Contents
5. Config.plist should be there (if you're using that method)

### Test API Key Manually

You can test your API key with curl:

```bash
curl -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent?key=YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{
      "parts": [{"text": "Hello"}]
    }]
  }'
```

Replace `YOUR_API_KEY` with your actual key. Should return JSON response.

---

## 📞 Still Stuck?

### Check These Resources

1. **Project Documentation**
   - `GEMINI_SETUP.md` - Complete setup guide
   - `GEMINI_IMPLEMENTATION.md` - Technical details
   - `IMPLEMENTATION_COMPLETE.md` - Overview

2. **Google Documentation**
   - [Gemini API Docs](https://ai.google.dev/docs)
   - [Google AI Studio](https://makersuite.google.com/)
   - [API Pricing](https://ai.google.dev/pricing)

3. **Console Logs**
   - Enable debug logging
   - Look for specific error messages
   - Check the detailed diagnostic output

---

## 📝 Summary

**Most Common Issues:**

1. **API key not added** → Add to Info.plist or Config.plist
2. **Wrong key name** → Must be exactly `GeminiAPIKey`
3. **Config.plist not in bundle** → Check Target Membership
4. **Invalid API key** → Regenerate from Google AI Studio
5. **Rate limited** → Wait 1 minute between bursts of photos

**Quick Fix for Most Cases:**

1. Get API key from: https://makersuite.google.com/app/apikey
2. Add to Info.plist with key `GeminiAPIKey` and your key as value
3. Clean build folder (Cmd + Shift + K)
4. Rebuild and run
5. Check console for "✅ Gemini API key configured successfully"

**With the enhanced logging, you'll now see exactly where the issue is!**

---

## 🎉 Success!

When everything is working, you should see:

1. At app launch: "✅ Gemini API key configured successfully"
2. When taking photo: "🔍 Identifying image with Gemini Vision API..."
3. After 1-3 seconds: "✅ Image identified successfully!"
4. In UI: AI description of your photo

Happy debugging! 🚀✨
