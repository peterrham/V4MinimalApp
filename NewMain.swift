import SwiftUI
import CoreData
import AVFoundation
import Speech

@main
struct VoiceRecognitionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, DynamicPersistenceController.shared.container.viewContext)
        }
    }
}

// MARK: - Core Data Setup (Dynamic Persistence Controller)

var sqlLitePathURL:URL?

func exportDatabase() -> URL? {
    let fileManager = FileManager.default
    let dbURL =  sqlLitePathURL /* Your SQLite file URL here */
    let exportURL = fileManager.temporaryDirectory.appendingPathComponent("exportedDatabase.sqlite")

    do {
        try fileManager.copyItem(at: dbURL!, to: exportURL)
        print("copied the file")
        return exportURL
    } catch {
        print("Error exporting database: \(error)")
        return nil
    }
}


class DynamicPersistenceController {
    static let shared = DynamicPersistenceController()
    
    let container: NSPersistentContainer
    
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


struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RecognizedTextEntity.timestamp, ascending: false)],
        animation: .default
    ) private var recognizedTexts: FetchedResults<RecognizedTextEntity>
    
    @StateObject private var speechManager = SpeechRecognitionManager(context: DynamicPersistenceController.shared.container.viewContext)
    
    @State private var isShowingShareSheet = false
    
    init() {
        
        UIScrollView.appearance().indicatorStyle = .black // Optional: Set color style
        UIScrollView.appearance().scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -2)
        
    }
    
    
    
    
    var body: some View {
        NavigationStack{
            VStack(spacing: 20) {
                NavigationLink(destination: ExportToCSVView()) {
                    Text("ExportToCSVView")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                NavigationLink(destination: TextFileSharerView()) {
                    Text("TextFileSharerView")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                NavigationLink(destination: TextFileCreatorView()) {
                    Text("TextFileCreatorView")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                NavigationLink(destination: SecondView()) {
                    Text("Go to Second Page")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                Button("Export File to Shared Documents") {
                    isShowingShareSheet = true
                }
                .font(.title)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                // Present the document picker
                .sheet(isPresented:  $isShowingShareSheet) {
                    // Present the share sheet
                    ShareSheet(activityItems: [sqlLitePathURL])
                }
                Text("Incremental Speech:")
                    .font(.headline)
                Text(speechManager.incrementalText)
                // Text("bogus")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                Text("Finalized Speech:")
                
                    .font(.headline)
                Text(speechManager.finalText)
                //Text("MORE bogus")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(recognizedTexts.indices, id: \.self) { index in
                            let text = recognizedTexts[index]
                            // Text("abcd")
                            // Text(text.content ?? "")
                            // Text(DateFormatter().string(from: text.timestamp ?? Date()))
                            Text("\(index): \(shortDateFormatter.string(from: text.timestamp!)): \(text.content!)")
                                .onAppear {
                                    // print("timestamp: \(text.timestamp!)")
                                    
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
                .overlay(
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 6)
                            .cornerRadius(3)
                            .padding(.trailing, 4)
                            .offset(x: geometry.size.width - 10) // Position on the right side
                    },
                    alignment: .trailing
                )
            }
            .padding()
        }
    }
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



