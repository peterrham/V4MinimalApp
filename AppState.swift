import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

// AppState to manage authentication status
class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false

    private static let skippedAuthKey = "userSkippedAuth"

    init() {
        // Check if user previously chose "Continue without signing in"
        if UserDefaults.standard.bool(forKey: Self.skippedAuthKey) {
            isAuthenticated = true
            return
        }

        // Synchronous check (may be nil if restore hasn't completed)
        if GIDSignIn.sharedInstance.currentUser != nil {
            isAuthenticated = true
            return
        }

        // Async restore — updates isAuthenticated when callback fires
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            DispatchQueue.main.async {
                if user != nil {
                    self?.isAuthenticated = true
                }
            }
        }
    }

    func checkAuthStatus() {
        isAuthenticated = GIDSignIn.sharedInstance.currentUser != nil ||
            UserDefaults.standard.bool(forKey: Self.skippedAuthKey)
    }

    /// Called when user taps "Continue without signing in"
    func skipAuth() {
        UserDefaults.standard.set(true, forKey: Self.skippedAuthKey)
        isAuthenticated = true
    }

    /// Called on sign-out to clear the skip flag too
    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.skippedAuthKey)
        GIDSignIn.sharedInstance.signOut()
        isAuthenticated = false
    }
}

/*
// Main App
@main
struct MyApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            if appState.isAuthenticated {
                MainContentView()  // Display main content if authenticated
            } else {
                NewGoogleSignInView(appState: appState)  // Display Google Sign-In view if not authenticated
            }
        }
    }
}
*/
