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
                       print("Core Data SQLite database path: \n cd \"\(databaseURL.path)\"")
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


struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RecognizedTextEntity.timestamp, ascending: false)],
        animation: .default
    ) private var recognizedTexts: FetchedResults<RecognizedTextEntity>
    
    @StateObject private var speechManager = SpeechRecognitionManager(context: DynamicPersistenceController.shared.container.viewContext)
    
    init() {
        
        //  speechManager.startListening()
        
        UIScrollView.appearance().indicatorStyle = .black // Optional: Set color style
        UIScrollView.appearance().scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -2)
        
    }
    
    var body: some View {
        VStack(spacing: 20) {
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

