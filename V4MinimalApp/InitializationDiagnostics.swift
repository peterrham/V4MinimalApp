//
//  InitializationDiagnostics.swift
//  V4MinimalApp
//
//  Diagnostic tests to catch common initialization anti-patterns that cause crashes.
//  Run these during development to validate safe initialization patterns.
//

import Foundation
import AVFoundation
import Speech

/// Anti-patterns that cause crashes - check for these during code review
enum InitializationAntiPattern: String, CaseIterable {
    case eagerAudioEngine = "Creating AVAudioEngine as a stored property (not lazy)"
    case eagerSpeechRecognizer = "Creating SFSpeechRecognizer as a stored property (not lazy)"
    case stateObjectWithHeavyInit = "@StateObject with heavy init() work"
    case fetchRequestWithMissingContext = "@FetchRequest without managedObjectContext in environment"
    case environmentWithMissingProvider = "@Environment property without provider in view hierarchy"
    case persistedNavigationPath = "Persisting NavigationStack path to UserDefaults"
    case audioBeforePermission = "Accessing audio engine before permissions granted"
}

/// Results from initialization diagnostics
struct InitDiagnosticResult {
    let pattern: InitializationAntiPattern
    let detected: Bool
    let location: String?
    let suggestion: String

    var statusEmoji: String { detected ? "❌" : "✅" }
}

/// Run diagnostic checks for common crash patterns
enum InitializationDiagnostics {

    /// Check audio session state before creating audio objects
    @MainActor
    static func checkAudioSafety() -> [InitDiagnosticResult] {
        var results: [InitDiagnosticResult] = []

        // Check microphone permission
        let micPermission = AVAudioSession.sharedInstance().recordPermission
        results.append(InitDiagnosticResult(
            pattern: .audioBeforePermission,
            detected: micPermission != .granted,
            location: nil,
            suggestion: "Request microphone permission before creating AVAudioEngine"
        ))

        // Check speech recognition permission
        let speechPermission = SFSpeechRecognizer.authorizationStatus()
        results.append(InitDiagnosticResult(
            pattern: .audioBeforePermission,
            detected: speechPermission != .authorized,
            location: "SFSpeechRecognizer",
            suggestion: "Request speech recognition permission before creating SFSpeechRecognizer"
        ))

        return results
    }

    /// Check for stale UserDefaults keys that could cause crashes
    static func checkUserDefaults() -> [InitDiagnosticResult] {
        var results: [InitDiagnosticResult] = []

        // Check for persisted navigation path
        let hasStaleNavPath = UserDefaults.standard.string(forKey: "settingsNavPath") != nil
        results.append(InitDiagnosticResult(
            pattern: .persistedNavigationPath,
            detected: hasStaleNavPath,
            location: "UserDefaults.settingsNavPath",
            suggestion: "Remove persisted navigation paths - they cause SwiftUI.AnyNavigationPath.Error.comparisonTypeMismatch"
        ))

        return results
    }

    /// Clear known problematic UserDefaults keys
    static func clearStaleUserDefaults() {
        let keysToRemove = [
            "settingsNavPath",
            // Add other known problematic keys here
        ]
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }
        appBootLog.infoWithContext("[InitDiagnostics] Cleared stale UserDefaults keys: \(keysToRemove)")
    }

    /// Run all diagnostics and log results
    @MainActor
    static func runAllDiagnostics() -> [InitDiagnosticResult] {
        appBootLog.infoWithContext("[InitDiagnostics] Running initialization diagnostics...")

        var allResults: [InitDiagnosticResult] = []

        // Audio safety checks
        allResults.append(contentsOf: checkAudioSafety())

        // UserDefaults checks
        allResults.append(contentsOf: checkUserDefaults())

        // Log results
        let failures = allResults.filter { $0.detected }
        if failures.isEmpty {
            appBootLog.infoWithContext("[InitDiagnostics] ✅ All checks passed")
        } else {
            for failure in failures {
                appBootLog.warningWithContext("[InitDiagnostics] \(failure.statusEmoji) \(failure.pattern.rawValue)")
                if let location = failure.location {
                    appBootLog.warningWithContext("  Location: \(location)")
                }
                appBootLog.warningWithContext("  Fix: \(failure.suggestion)")
            }
        }

        return allResults
    }
}

// MARK: - Safe Initialization Patterns

/// Documentation of safe patterns to follow
/*
 SAFE INITIALIZATION PATTERNS:

 1. AUDIO OBJECTS - Use lazy initialization:
    ```swift
    // BAD - crashes if audio session not ready
    private var audioEngine = AVAudioEngine()

    // GOOD - only created when accessed
    private lazy var audioEngine: AVAudioEngine = {
        return AVAudioEngine()
    }()
    ```

 2. @StateObject - Avoid heavy work in init():
    ```swift
    // BAD - heavy work during view creation
    @StateObject private var manager = HeavyManager()

    // GOOD - defer heavy work to onAppear
    @State private var manager: HeavyManager?
    .onAppear {
        self.manager = HeavyManager()
    }
    ```

 3. NAVIGATION PATH - Don't persist to UserDefaults:
    ```swift
    // BAD - causes comparisonTypeMismatch crashes
    @AppStorage("navPath") private var savedPath: String = "[]"

    // GOOD - always start fresh
    @State private var path: [MyPage] = []
    ```

 4. @Environment - Ensure provider exists:
    ```swift
    // BAD - crashes if not in environment
    @Environment(\.managedObjectContext) private var context

    // GOOD - use optional or provide in view hierarchy
    .environment(\.managedObjectContext, container.viewContext)
    ```

 5. PERMISSIONS - Check before accessing resources:
    ```swift
    // BAD - access before permission
    let inputNode = audioEngine.inputNode

    // GOOD - check permission first
    guard AVAudioSession.sharedInstance().recordPermission == .granted else { return }
    let inputNode = audioEngine.inputNode
    ```
*/
