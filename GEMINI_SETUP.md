# Gemini API Configuration

## Setting up your Gemini API Key

To use the photo identification feature with Google's Gemini Vision API, you need to configure your API key.

### Option 1: Environment Variable (Recommended for Development)

1. Get your API key from [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Add it to your Xcode scheme:
   - Edit Scheme → Run → Arguments → Environment Variables
   - Add: `GEMINI_API_KEY` = `your-api-key-here`

### Option 2: Configuration File (Recommended for Production)

1. Create a `Config.plist` file in your project
2. Add the following:
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
3. Add `Config.plist` to your `.gitignore` to keep it secret

### Option 3: Hardcode (Not Recommended)

Update `GeminiVisionService.swift` initialization:
```swift
init(apiKey: String = "your-api-key-here") {
    // ...
}
```

**⚠️ WARNING**: Never commit API keys to version control!

## How It Works

1. **Take a Photo**: Tap the camera capture button
2. **Automatic Analysis**: The photo is automatically sent to Gemini Vision API
3. **View Results**: The identification appears in a card overlay on the camera preview
4. **Dismiss**: Tap the X button to clear the identification

## Features

- ✅ Real-time photo identification
- ✅ Concise, clear descriptions
- ✅ Error handling
- ✅ Loading states
- ✅ Beautiful UI overlay

## API Details

- **Model**: `gemini-2.0-flash-exp`
- **Endpoint**: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent`
- **Image Format**: JPEG with 0.8 compression
- **Max Tokens**: 100 (for concise responses)
- **Temperature**: 0.4 (for more focused responses)

## Troubleshooting

### "API key not configured" error
- Ensure you've set the `GEMINI_API_KEY` environment variable
- Check that the API key is valid and active

### "API Error (403)"
- Your API key may be invalid or expired
- Check your Google Cloud Console for API quotas

### "Failed to convert image"
- The captured image may be corrupted
- Try capturing another photo

## Next Steps

Consider adding:
- [ ] Custom prompts for specific identification needs
- [ ] Batch processing for multiple photos
- [ ] Local caching of results
- [ ] Integration with inventory database
- [ ] Voice narration of results using AVSpeechSynthesizer
