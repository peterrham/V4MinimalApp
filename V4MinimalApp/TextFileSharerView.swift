//
//  TextFileSharerView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/4/24.
//


import SwiftUI
import UIKit

struct TextFileSharerView: View {
    @State private var isShowingActivityView = false
    @State private var fileURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text("Share the Text File")
                .font(.largeTitle)
                .padding()

            Button(action: prepareFileForSharing) {
                Text("Share File")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            // .disabled(fileURL == nil) // Disable button if file doesn't exist

            if fileURL != nil {
                Text("Ready to share!")
                    .font(.headline)
                    .foregroundColor(.green)
            } else {
                Text("File not found. Create the file first.")
                    .font(.headline)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .sheet(isPresented: $isShowingActivityView) {
            if let fileURL = fileURL {
                ActivityView(activityItems: [fileURL])
            }
        }
    }

    // Function to get the text file URL and prepare it for sharing
    func prepareFileForSharing() {
        print("inside prepareFileForSharing")
        // Access the Documents directory to retrieve the file URL
        let fileManager = FileManager.default
        do {
            let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            fileURL = documentsDirectory.appendingPathComponent("SampleTextFile.txt")
            
            // Check if the file exists before showing the activity view
            if fileManager.fileExists(atPath: fileURL!.path) {
                isShowingActivityView = true
            } else {
                print("File not found at: \(fileURL!.path)")
                fileURL = nil
            }
        } catch {
            print("Error accessing Documents directory: \(error)")
            fileURL = nil
        }
    }
}

// Wrapper for UIActivityViewController
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct TextFileSharerView_Previews: PreviewProvider {
    static var previews: some View {
        TextFileSharerView()
    }
}
