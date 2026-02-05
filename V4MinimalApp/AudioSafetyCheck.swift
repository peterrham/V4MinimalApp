//
//  AudioSafetyCheck.swift
//  V4MinimalApp
//
//  Diagnostic tests to validate audio session is safe to use.
//  Run these BEFORE creating AVAudioEngine or SpeechRecognizer.
//

import AVFoundation
import Speech
import CoreData

/// Results from audio safety diagnostics
struct AudioSafetyResult {
    let canUseAudio: Bool
    let microphonePermission: AVAudioSession.RecordPermission
    let speechPermission: SFSpeechRecognizerAuthorizationStatus
    let currentCategory: AVAudioSession.Category
    let currentMode: AVAudioSession.Mode
    let isOtherAudioPlaying: Bool
    let errorMessage: String?

    var summary: String {
        var lines: [String] = []
        lines.append("Audio Safety Check Results:")
        lines.append("  Can use audio: \(canUseAudio ? "YES" : "NO")")
        lines.append("  Microphone: \(micPermissionString)")
        lines.append("  Speech: \(speechPermissionString)")
        lines.append("  Category: \(currentCategory.rawValue)")
        lines.append("  Mode: \(currentMode.rawValue)")
        lines.append("  Other audio playing: \(isOtherAudioPlaying ? "YES" : "NO")")
        if let error = errorMessage {
            lines.append("  Error: \(error)")
        }
        return lines.joined(separator: "\n")
    }

    private var micPermissionString: String {
        switch microphonePermission {
        case .granted: return "GRANTED"
        case .denied: return "DENIED"
        case .undetermined: return "NOT ASKED"
        @unknown default: return "UNKNOWN"
        }
    }

    private var speechPermissionString: String {
        switch speechPermission {
        case .authorized: return "AUTHORIZED"
        case .denied: return "DENIED"
        case .restricted: return "RESTRICTED"
        case .notDetermined: return "NOT ASKED"
        @unknown default: return "UNKNOWN"
        }
    }
}

/// Utility to check if audio services can be safely initialized
enum AudioSafetyCheck {

    /// Run all audio safety checks synchronously (call from main thread)
    @MainActor
    static func runDiagnostics() -> AudioSafetyResult {
        let session = AVAudioSession.sharedInstance()

        let micPermission = session.recordPermission
        let speechPermission = SFSpeechRecognizer.authorizationStatus()
        let isOtherPlaying = session.isOtherAudioPlaying

        // Check if permissions allow audio use
        let hasPermissions = micPermission == .granted && speechPermission == .authorized

        var errorMessage: String? = nil
        var canUse = hasPermissions

        // Try to configure audio session as a test
        if hasPermissions {
            do {
                // Test if we can configure the session
                try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
                // Don't activate yet - just test configuration
            } catch {
                errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
                canUse = false
            }
        } else {
            if micPermission != .granted {
                errorMessage = "Microphone permission not granted"
            } else if speechPermission != .authorized {
                errorMessage = "Speech recognition not authorized"
            }
        }

        let result = AudioSafetyResult(
            canUseAudio: canUse,
            microphonePermission: micPermission,
            speechPermission: speechPermission,
            currentCategory: session.category,
            currentMode: session.mode,
            isOtherAudioPlaying: isOtherPlaying,
            errorMessage: errorMessage
        )

        // Log the results
        appBootLog.infoWithContext("[AudioSafetyCheck] \(result.summary)")

        return result
    }

    /// Request permissions if not already granted
    @MainActor
    static func requestPermissionsIfNeeded() async -> Bool {
        let session = AVAudioSession.sharedInstance()

        // Request microphone permission
        if session.recordPermission == .undetermined {
            appBootLog.infoWithContext("[AudioSafetyCheck] Requesting microphone permission...")
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            appBootLog.infoWithContext("[AudioSafetyCheck] Microphone permission: \(granted ? "GRANTED" : "DENIED")")
            if !granted { return false }
        }

        // Request speech recognition permission
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            appBootLog.infoWithContext("[AudioSafetyCheck] Requesting speech recognition permission...")
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            appBootLog.infoWithContext("[AudioSafetyCheck] Speech permission: \(status == .authorized ? "AUTHORIZED" : "DENIED")")
            if status != .authorized { return false }
        }

        return session.recordPermission == .granted &&
               SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Safe initialization pattern - use this instead of creating SpeechRecognitionManager directly
    @MainActor
    static func createSpeechManagerIfSafe(context: NSManagedObjectContext) async -> SpeechRecognitionManager? {
        appBootLog.infoWithContext("[AudioSafetyCheck] Starting safe audio initialization...")

        // Step 1: Request permissions if needed
        let hasPermissions = await requestPermissionsIfNeeded()
        guard hasPermissions else {
            appBootLog.errorWithContext("[AudioSafetyCheck] Cannot create SpeechRecognitionManager - permissions not granted")
            return nil
        }

        // Step 2: Run diagnostics
        let result = runDiagnostics()
        guard result.canUseAudio else {
            appBootLog.errorWithContext("[AudioSafetyCheck] Cannot create SpeechRecognitionManager - \(result.errorMessage ?? "unknown error")")
            return nil
        }

        // Step 3: Small delay to let any other audio sessions settle
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Step 4: Create the manager
        appBootLog.infoWithContext("[AudioSafetyCheck] All checks passed, creating SpeechRecognitionManager...")
        return SpeechRecognitionManager(context: context)
    }
}
