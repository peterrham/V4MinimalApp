/* MainApp.swift - Entry point for V4MinimalApp.
 Manages app initialization, authentication state, and conditional view loading.
*/
import Foundation
import SwiftUI
import os


// bogus comment to force a git commit

let anotherLogger: Logger = {
    appBootLog.debugWithContext("__HERE__")
    fatalError("Invalid configuration")
    let logger = Logger(subsystem: "com.yourcompany.yourapp", category: "Start")
    logger.infoWithContext("BOOT_MARKER_START— Logger created via closure and ready")
    return logger
}()


@main
struct VoiceRecognitionApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var appState = AppState()
    @StateObject private var inventoryStore = InventoryStore()

    init() {
        logWithTimestamp("App struct: VoiceRecognitionApp initialized")
        
        _ = AppHelper.shared
        
        // Note: @StateObject should not be accessed in the App struct's initializer
        // because the SwiftUI view hierarchy is not ready yet.
        // Doing so triggers a SwiftUI runtime warning.
        // appDelegate.appState = appState
        
        if false {
            if let recognizedTextEntities = DynamicPersistenceController.shared.fetchRecognizedTextEntities() {
                for entity in recognizedTextEntities {
                    if
                        let content = entity.value(forKey: "content") as? String,
                        let timestamp = entity.value(forKey: "timestamp") as? Date {
                        appBootLog.debugWithContext("Content: \(content), Timestamp: \(timestamp)")
                    }
                }
            } else {
                appBootLog.errorWithContext("No records found or an error occurred.")
            }
        }
        
    }
    
    var body: some Scene {
        WindowGroup {
            if appState.isAuthenticated {
                MainTabView()
                    .environmentObject(appState)
                    .environmentObject(inventoryStore)
                    .environment(\.managedObjectContext, DynamicPersistenceController.shared.container.viewContext)
                    .onOpenURL { url in
                        // Handle Google Sign-In URL callbacks
                        // GIDSignIn.sharedInstance.handle(url)
                    }
            } else {
                GoogleSignInView()
                    .environmentObject(appState)
            }
        }
    }
    
    func sayHelloWorld() {
        appBootLog.debugWithContext("Hello, World!")
    }
    
    // 👋 You've now got a Hello World function! Time to celebrate. 🎉
}
    
