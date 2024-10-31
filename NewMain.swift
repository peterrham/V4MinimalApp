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
        }
    }
}

// Define the RecognizedTextEntity NSManagedObject subclass
@objc(RecognizedTextEntity)
public class RecognizedTextEntity: NSManagedObject, Identifiable {
    @NSManaged public var content: String?
    @NSManaged public var timestamp: Date?
}

// MARK: - Speech Recognition Manager

class SpeechRecognitionManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let context: NSManagedObjectContext

    @Published var incrementalText: String = ""  // Shows incremental speech as it's recognized
    @Published var finalText: String = ""        // Shows finalized speech after "stop" is detected
    
    init(context: NSManagedObjectContext) {
        self.context = context
        requestMicrophonePermission()
    }
    
    func startListening() {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioSession.sharedInstance().recordPermission == .granted else {
            print("Permissions not granted.")
            return
        }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request.")
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let newText = result.bestTranscription.formattedString.lowercased()
                
                if newText.contains("stop") {
                    let segments = newText.components(separatedBy: "stop")
                    if let firstSegment = segments.first {
                        let moreText = firstSegment.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.saveRecognizedText(moreText)
                        self.finalText = "final text" // moreText  // Reset recognized text for new segment
                    }
                } else {
                    self.incrementalText = "new text" // newText
                }
            }
            
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Audio engine could not start: \(error)")
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionRequest = nil
    }
    
    private func requestMicrophonePermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Speech recognition authorized.")
            case .denied, .restricted, .notDetermined:
                print("Speech recognition not authorized.")
            @unknown default:
                break
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("Microphone access granted.")
            } else {
                print("Microphone access denied.")
            }
        }
    }
    
    private func saveRecognizedText(_ text: String) {
        let newEntry = RecognizedTextEntity(context: context)
        newEntry.content = text
        newEntry.timestamp = Date()
        
        do {
            try context.save()
        } catch {
            print("Failed to save recognized text: \(error)")
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RecognizedTextEntity.timestamp, ascending: false)],
        animation: .default
    ) private var recognizedTexts: FetchedResults<RecognizedTextEntity>
    
    @StateObject private var speechManager = SpeechRecognitionManager(context: DynamicPersistenceController.shared.container.viewContext)

    init() {
        
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Incremental Speech:")
                .font(.headline)
           // Text(speechManager.incrementalText)
            Text("bogus")
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(8)

           Text("Finalized Speech:")
           
                .font(.headline)
           //  Text(speechManager.finalText)
            Text("MORE bogus")
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(8)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(recognizedTexts) { text in
                        Text(text.content ?? "")
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
        .padding()
    }
}
    
