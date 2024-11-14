import SwiftUI
import CoreData
import AVFoundation
import Speech
import GoogleSignIn
import UIKit



class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var appState: AppState?
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("AppDelegate received URL: \(url.absoluteString)")
        // Handle URL here
        return true
    }
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("AppDelegate didFinishLaunchingWithOptions called")
        
        // initialize singleton
        
        _ = AuthManager.shared
        AuthManager.shared.initialize()
        
        
        return true
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
            print("Failed to fetch RecognizedTextEntities: \(error)")
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
                print("Core Data SQLite database path: \n cd \"\(pathString)\"")
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
        print("inside makeView")
        let documentPicker = UIDocumentPickerViewController(forExporting: [fileURL])
        return documentPicker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        print("inside updateUIView")
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



