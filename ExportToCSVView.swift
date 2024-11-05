import SwiftUI
import CoreData
import UniformTypeIdentifiers

class ExportModel: ObservableObject {
    @Published var csvFileURL: URL?
    @Published var isShowingActivityView = false
}

struct ExportToCSVView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: RecognizedTextEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \RecognizedTextEntity.timestamp, ascending: true)]
    ) private var recognizedTexts: FetchedResults<RecognizedTextEntity>
    
    @StateObject private var exportModel = ExportModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Recognized Text Data")
                .font(.largeTitle)
                .padding()

            Button(action: exportToCSV) {
                Text("Export to CSV")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .sheet(isPresented: $exportModel.isShowingActivityView) {
                if let csvFileURL = exportModel.csvFileURL {
                    CSVActivityView(activityItems: [csvFileURL])
                        .onAppear {
                            print("CSVActivityView presented with file URL: \(csvFileURL)")
                        }
                        .onDisappear {
                            print("CSVActivityView dismissed")
                        }
                }
            }
        }
        .padding()
    }
    
    // Function to export data to CSV
    private func exportToCSV() {
        print("exportToCSV function called")
        
        let headers = "Content,Timestamp\n"
        var csvText = headers
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        for textEntity in recognizedTexts {
            let content = textEntity.content ?? "N/A"
            let timestamp = dateFormatter.string(from: textEntity.timestamp ?? Date())
            let row = "\"\(content)\",\"\(timestamp)\"\n"
            csvText += row
        }
        
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
  
        
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = fileDateFormatter.string(from: Date())
        let tempFileURL = tempDirectory.appendingPathComponent("RecognizedTextData_\(dateString).csv")

        
        do {
            print("Attempting to write CSV file to temporary directory")
            try csvText.write(to: tempFileURL, atomically: true, encoding: .utf8)
            exportModel.csvFileURL = tempFileURL
            print("CSV file successfully created at: \(exportModel.csvFileURL!.path)")
            
            exportModel.isShowingActivityView = true
        } catch {
            print("Error writing CSV file: \(error)")
        }
    }
}
// SwiftUI wrapper for UIActivityViewController to share the CSV file
struct CSVActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
