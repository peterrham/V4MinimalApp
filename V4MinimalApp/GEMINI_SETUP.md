# Gemini API Configuration

## Setting up your Gemini API Key

To use the photo identification feature with Google's Gemini Vision API, you need to configure your API key.

### 🔑 Get Your API Key (2 minutes)

1. Visit [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Sign in with your Google account
3. Click "Create API Key"
4. Copy the generated key

---

## Configuration Options

Choose the method that works best for you:

### ⭐ Option 1: Info.plist (Easiest - Quick Start)

**Best for**: Getting started quickly, personal projects

1. Open `Info.plist` in Xcode
2. Add a new row:
   - **Key**: `GeminiAPIKey`
   - **Type**: `String`
   - **Value**: Your actual API key

**Or in Source Code view:**
```xml
<key>GeminiAPIKey</key>
<string>YOUR_API_KEY_HERE</string>
```

**⚠️ Security Note**: Info.plist is usually committed to Git. For better security, use Config.plist instead.

📖 **Detailed guide**: `INFO_PLIST_SETUP.md`

---

### 🔒 Option 2: Config.plist (Most Secure - Recommended)

**Best for**: Team projects, production apps, keeping keys private

1. Create a new file: `Config.plist`
2. Add this content:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>GeminiAPIKey</key>
       <string>YOUR_API_KEY_HERE</string>
   </dict>
   </plist>
   ```
3. Add `Config.plist` to your `.gitignore`:
   ```
   Config.plist
   ```
4. Share `Config.plist.template` with your team (without the key)

**✅ Advantages**:
- Not committed to Git
- Easy to manage multiple environments
- Template system for team sharing
- Separate from main app configuration

---

### 🛠️ Option 3: Environment Variable (Best for Development)

**Best for**: Development, debugging, temporary testing

1. In Xcode: `Product → Scheme → Edit Scheme...`
2. Select `Run` in left sidebar
3. Go to `Arguments` tab
4. Under "Environment Variables" click `+`
5. Add:
   - **Name**: `GEMINI_API_KEY`
   - **Value**: Your actual API key

**✅ Advantages**:
- Never committed to Git
- Easy to change without rebuilding
- Different keys for different schemes
- Perfect for development

**❌ Disadvantages**:
- Doesn't work in production builds
- Team members need to configure individually

---

### ⚠️ Option 4: Hardcode (Not Recommended)

**Only for**: Quick testing, throwaway code

In `GeminiVisionService.swift`:
```swift
init(apiKey: String = "your-api-key-here") {
    // ...
}
```

**⚠️ WARNING**: Never commit hardcoded API keys to version control!

---

## 🔄 Priority Order

If multiple keys are configured, the app uses them in this order:

1. **Explicit parameter** (passed to service init) - Highest priority
2. **Config.plist** - Most secure option
3. **Info.plist** - Easiest option  
4. **Environment variable** - Development option

The first valid key found is used.

---

## ✅ Verification

### Check Console Logs

After configuring, build and run. Look for:

**Success:**
```
✅ Gemini API key loaded successfully
📍 API key loaded from Info.plist
```

**Failure:**
```
⚠️ Gemini API key not configured
   Options: Info.plist, Config.plist, or GEMINI_API_KEY environment variable
```

### Test in App

1. Open camera view
2. Take a photo
3. Should see "Analyzing..." overlay
4. Should see AI description in 1-3 seconds

---

## 🔒 Security Best Practices

### For Personal Projects ✅
- Info.plist is acceptable
- Quick and easy
- Fine if you're the only developer

### For Team Projects 🔐
- Use Config.plist (gitignored)
- Share template without key
- Each developer has their own key
- Document setup process

### For Production Apps 🏢
- Never hardcode keys
- Use backend API proxy
- Key stays on your server
- App calls your backend, backend calls Gemini
- Implement rate limiting
- Monitor API usage

### Best Practices
- ✅ Rotate keys periodically
- ✅ Use different keys for dev/staging/prod
- ✅ Monitor API usage in Google Cloud Console
- ✅ Set up usage alerts
- ✅ Never commit keys to Git
- ✅ Use `.gitignore` properly

---

## 🐛 Troubleshooting

### "API key not configured"

**Check 1**: Key name is correct
```xml
<!-- ✅ Correct -->
<key>GeminiAPIKey</key>

<!-- ❌ Wrong -->
<key>GEMINI_API_KEY</key>
<key>Gemini_API_Key</key>
```

**Check 2**: Key is a String type
```xml
<key>GeminiAPIKey</key>
<string>AIzaSyD...</string>  ← Must be String
```

**Check 3**: No spaces in value
```xml
<!-- ❌ Wrong -->
<string> AIzaSyD... </string>

<!-- ✅ Correct -->
<string>AIzaSyD...</string>
```

**Check 4**: File is in correct location
- Info.plist: Must be your main app's Info.plist
- Config.plist: Must be in app bundle (added to target)

**Fix**: Clean build folder (Cmd + Shift + K) and rebuild

---

### "API Error (403)"

**Cause**: Invalid or expired API key

**Fix**:
1. Go to [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Verify your key is active
3. Try regenerating the key
4. Update in your configuration
5. Rebuild and test

---

### "API Error (429)"

**Cause**: Rate limit exceeded

**Details**:
- Free tier: 15 requests per minute
- Paid tier: Higher limits

**Fix**:
1. Wait 1 minute and try again
2. Implement request queuing in your app
3. Consider upgrading to paid tier
4. Add delay between requests

---

### Response is Slow

**Normal behavior**:
- First request: 3-5 seconds (cold start)
- Subsequent requests: 1-3 seconds
- Large images: May take longer

**Optimization**:
- Reduce image quality (currently 80%)
- Resize images before sending
- Cache frequent requests
- Use faster model (if available)

---

## 📊 API Limits & Pricing

### Free Tier
- **Requests**: 15 per minute
- **Daily limit**: 1,500 requests
- **Cost**: Free

### Paid Tier
- **Higher limits**: Contact Google Cloud
- **Pricing**: See [Google AI Pricing](https://ai.google.dev/pricing)

### Current Implementation
- **Image size**: ~50-200 KB (JPEG 80%)
- **Tokens**: ~100 per request
- **Cost per request**: Very low on free tier

---

## 🧪 Testing Your Setup

### Quick Test Checklist

- [ ] API key obtained from Google AI Studio
- [ ] Key configured (Info.plist, Config.plist, or env var)
- [ ] Build succeeds (Cmd + B)
- [ ] Console shows: "✅ Gemini API key loaded successfully"
- [ ] App runs without errors
- [ ] Camera view opens
- [ ] Can take photo
- [ ] "Analyzing..." appears
- [ ] AI description shows (1-3 seconds)
- [ ] Can dismiss and take another photo

### Test Different Scenarios

**Test 1: Simple Object**
- Take photo of a cup, chair, or book
- Should get clear description

**Test 2: Complex Scene**
- Take photo of a room
- Should describe main elements

**Test 3: Text Recognition**
- Take photo of a sign or label
- Should identify text content

**Test 4: Error Handling**
- Remove API key temporarily
- Take photo
- Should show error message
- Should not crash

---

## 🎓 Learning Resources

- [Gemini API Documentation](https://ai.google.dev/docs)
- [Vision Capabilities](https://ai.google.dev/gemini-api/docs/vision)
- [API Pricing](https://ai.google.dev/pricing)
- [Best Practices](https://ai.google.dev/gemini-api/docs/best-practices)
- [Google AI Studio](https://makersuite.google.com/)

---

## 🆘 Still Need Help?

1. Check `INFO_PLIST_SETUP.md` for Info.plist details
2. Check `QUICK_START.md` for setup checklist
3. Check `GEMINI_README.md` for comprehensive guide
4. Review console logs for specific errors
5. Verify API key is valid in Google AI Studio

---

## 📚 Related Documentation

- **INFO_PLIST_SETUP.md** - Detailed Info.plist guide (⭐ NEW!)
- **QUICK_START.md** - 5-minute setup checklist
- **GEMINI_README.md** - Complete reference
- **GEMINI_IMPLEMENTATION.md** - Technical details
- **GeminiPromptExamples.swift** - Custom prompts

---

## 🎉 Ready to Go!

Choose your configuration method and you'll be up and running in minutes!

**Recommended path for beginners:**
1. Use Info.plist (fastest)
2. Get it working
3. Move to Config.plist later for security

**Recommended path for teams:**
1. Use Config.plist from the start
2. Add to .gitignore
3. Share template with team

---

**Happy Building! 🚀✨**
