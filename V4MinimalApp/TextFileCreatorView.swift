//
//  TextFileCreatorView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/4/24.
//


import SwiftUI

struct TextFileCreatorView: View {
    @State private var fileCreated = false
    @State private var filePath: String = ""

    // GoogleSheetWriterView
    var body: some View {
        VStack(spacing: 20) {
            Text("Create a Text File")
                .font(.largeTitle)
                .padding()

            Button(action: createTextFile) {
                Text("Create File")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            if fileCreated {
                Text("File created successfully!")
                    .font(.headline)
                    .foregroundColor(.green)
                Text("Path: \(filePath)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .padding()
    }

    // Function to create a small text file in the Documents directory
    func createTextFile() {
        let textContent = """
        This is the first line of text.
        This is the second line of text.
        This is the third line of text.
        """
        
        // Get the URL for the app's Documents directory
        let fileManager = FileManager.default
        do {
            let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            // Create the file URL by appending the file name to the Documents directory URL
            let fileURL = documentsDirectory.appendingPathComponent("SampleTextFile.txt")
            
            // Write the text content to the file
            try textContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Update state to indicate file creation was successful
            fileCreated = true
            filePath = fileURL.path
            print("File created at: \(filePath)")
        } catch {
            print("Error creating file: \(error)")
            fileCreated = false
        }
    }
}

struct TextFileCreatorView_Previews: PreviewProvider {
    static var previews: some View {
        TextFileCreatorView()
    }
}
