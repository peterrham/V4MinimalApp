import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

// AppState to manage authentication status
class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false

    init() {
        checkAuthStatus()
    }

    func checkAuthStatus() {
        isAuthenticated = GIDSignIn.sharedInstance.currentUser != nil
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
