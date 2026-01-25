import SwiftUI
import os
import CoreData
import AVFoundation
import Speech
import GoogleSignIn
import UIKit

extension Logger {
    func infoWithContext(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        self.info("[\(file, privacy: .public):\(line)] \(message, privacy: .public) \(function, privacy: .public)")
    }

    func errorWithContext(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        self.error("[\(file, privacy: .public):\(line)] \(message, privacy: .public) \(function, privacy: .public)")
    }

    func debugWithContext(
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        self.debug("[\(file, privacy: .public):\(line)] \(message, privacy: .public) \(function, privacy: .public)")
    }
}

let appBootLog: Logger = {
    let logger = Logger(subsystem: "com.yourcompany.yourapp", category: "Boot")
    logger.infoWithContext("BOOT_MARKER_INITIALIZED — Logger created via closure and ready")
    return logger
}()

/// Call once during app launch to emit an initial boot log marker.
func logInitialBootMarker() {
    appBootLog.errorWithContext("ERROR_BOOT_MARKER_123 — right after logger created")
}



class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var appState: AppState?
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        appBootLog.infoWithContext("AppDelegate received URL: \(url.absoluteString)")
        // Handle URL here
        return true
    }
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        writeTestFileToDocuments()
        listDocumentsDirectory()
        logFilesIntegrationPlistKeys()
        logInitialBootMarker()
        appBootLog.errorWithContext("BEFORE_ERROR_BOOT_MARKER_123 — didFinishLaunching (error-level test)")
        
        appBootLog.infoWithContext("INFO_BOOT_MARKER_123 — didFinishLaunching (-level test)")
        
        appBootLog.errorWithContext("AFTER_ERROR_BOOT_MARKER_123 — didFinishLaunching (error-level test)")
        
        
        appBootLog.infoWithContext("AppDelegate didFinishLaunchingWithOptions called")
        
        // initialize singleton
        
        _ = AuthManager.shared
        AuthManager.shared.initialize()
        
        
        return true
    }
    
    private func writeTestFileToDocuments() {
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = docs.appendingPathComponent("test.txt")
            let contents = "hello from app launch at: \(Date())"
            try contents.write(to: url, atomically: true, encoding: .utf8)
            appBootLog.infoWithContext("Wrote test file to: \(url.path)")
        } catch {
            appBootLog.errorWithContext("Failed writing test file: \(error.localizedDescription)")
        }
    }
    
    private func listDocumentsDirectory() {
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let contents = try FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            appBootLog.infoWithContext("Documents directory: \(docs.path)")
            if contents.isEmpty {
                appBootLog.infoWithContext("Documents is empty")
            } else {
                for url in contents {
                    appBootLog.infoWithContext(" - \(url.lastPathComponent)")
                }
            }
        } catch {
            appBootLog.errorWithContext("Failed to list Documents: \(error.localizedDescription)")
        }
    }
    
    private func logFilesIntegrationPlistKeys() {
        let fileSharing = Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool ?? false
        appBootLog.infoWithContext("UIFileSharingEnabled = \(fileSharing)")

        let supportsInPlace = Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool ?? false
        appBootLog.infoWithContext("LSSupportsOpeningDocumentsInPlace = \(supportsInPlace)")

        if let docTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] {
            appBootLog.infoWithContext("CFBundleDocumentTypes count = \(docTypes.count)")
            for (index, item) in docTypes.enumerated() {
                let name = item["CFBundleTypeName"] as? String ?? "(no name)"
                let role = item["CFBundleTypeRole"] as? String ?? "(no role)"
                let utis = item["LSItemContentTypes"] as? [String] ?? []
                appBootLog.infoWithContext("  [\(index)] name=\(name), role=\(role), UTIs=\(utis)")
            }
        } else {
            appBootLog.infoWithContext("CFBundleDocumentTypes not set")
        }
    }
}




class DynamicPersistenceController {
    static let shared = DynamicPersistenceController()
    
    let container: NSPersistentContainer
    
    func fetchRecognizedTextEntities() -> [RecognizedTextEntity]? {
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<RecognizedTextEntity>(entityName: "RecognizedTextEntity")
        
        do {
            let results = try context.fetch(fetchRequest)
            return results
        } catch {
            appBootLog.errorWithContext("Failed to fetch RecognizedTextEntities: \(error)")
            return nil
        }
    }
    
    init() {
        // Define the Core Data model programmatically
        let model = NSManagedObjectModel()
        
        // Define the entity `RecognizedTextEntity`
        let recognizedTextEntity = NSEntityDescription()
        recognizedTextEntity.name = "RecognizedTextEntity"
        recognizedTextEntity.managedObjectClassName = NSStringFromClass(RecognizedTextEntity.self)
        
        // Define the `content` attribute
        let contentAttribute = NSAttributeDescription()
        contentAttribute.name = "content"
        contentAttribute.attributeType = .stringAttributeType
        contentAttribute.isOptional = false
        
        // Define the `timestamp` attribute
        let timestampAttribute = NSAttributeDescription()
        timestampAttribute.name = "timestamp"
        timestampAttribute.attributeType = .dateAttributeType
        timestampAttribute.isOptional = false
        
        // Add attributes to the entity
        recognizedTextEntity.properties = [contentAttribute, timestampAttribute]
        
        // Set the entity to the model
        model.entities = [recognizedTextEntity]
        
        // Initialize the persistent container with the custom model
        container = NSPersistentContainer(name: "DynamicModel", managedObjectModel: model)
        
        container.loadPersistentStores { (description, error) in
            if let error = error {
                fatalError("Failed to load Core Data store: \(error)")
            }
            
            // Access and print the database file path
            if let databaseURL = description.url {
                sqlLitePathURL = databaseURL
                let pathString : String = sqlLitePathURL!.absoluteString
                appBootLog.infoWithContext("Core Data SQLite database path: \n cd \"\(pathString)\"")
            }
        }
    }
}

// Define the RecognizedTextEntity NSManagedObject subclass
@objc(RecognizedTextEntity)
public class RecognizedTextEntity: NSManagedObject, Identifiable {
    @NSManaged public var content: String?
    @NSManaged public var timestamp: Date?
}


// MARK: - Content View

// Sample DateFormatter for the desired shorter date format
let shortDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MM/dd/yyyy HH:mm:ss" // Customize format as needed
    return formatter
}()


import UIKit

func exportFile(_ fileURL: URL, viewController: UIViewController) {
    let documentPicker = UIDocumentPickerViewController(forExporting: [fileURL])
    viewController.present(documentPicker, animated: true, completion: nil)
}




// Document Picker Wrapper for Exporting
struct DocumentExporter: UIViewControllerRepresentable {
    let fileURL: URL
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Initialize the document picker for exporting the file
        appBootLog.debugWithContext("inside makeView")
        let documentPicker = UIDocumentPickerViewController(forExporting: [fileURL])
        return documentPicker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        appBootLog.debugWithContext("inside updateUIView")
    }
}

// Wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SecondView: View {
    var body: some View {
        VStack {
            Text("Second Page")
                .font(.largeTitle)
                .padding()
            NavigationLink(destination: ContentView()) {
                Text("Go to Third Page")
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}














