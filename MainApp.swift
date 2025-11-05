/* MainApp.swift - Entry point for V4MinimalApp.
 Manages app initialization, authentication state, and conditional view loading.
*/
import Foundation
import SwiftUI

// bogus comment to force a git commit

@main
struct VoiceRecognitionApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var appState = AppState()
    
    init() {
        _ = AppHelper.shared
        
        appDelegate.appState = appState
        
        if false {
            if let recognizedTextEntities = DynamicPersistenceController.shared.fetchRecognizedTextEntities() {
                for entity in recognizedTextEntities {
                    if
                        let content = entity.value(forKey: "content") as? String,
                        let timestamp = entity.value(forKey: "timestamp") as? Date {
                        print("Content: \(content), Timestamp: \(timestamp)")
                    }
                }
            } else {
                print("No records found or an error occurred.")
            }
        }
        
    }
    
    var body: some Scene {
        WindowGroup {
            
            if appState.isAuthenticated {
                ContentView()
                    .environment(\.managedObjectContext, DynamicPersistenceController.shared.container.viewContext)
            } else {
                GoogleSignInView()
            }
        }
    }
    
    func sayHelloWorld() {
        print("Hello, World!")
    }
    
    // 👋 You've now got a Hello World function! Time to celebrate. 🎉
}
    