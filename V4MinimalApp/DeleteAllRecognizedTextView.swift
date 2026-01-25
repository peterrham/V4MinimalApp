//
//  DeleteAllRecognizedTextView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/5/24.
//


import SwiftUI
import CoreData

struct DeleteAllRecognizedTextView: View {
    // Fetch all RecognizedTextEntity objects
    @FetchRequest(
        entity: RecognizedTextEntity.entity(),
        sortDescriptors: []
    ) var recognizedTextItems: FetchedResults<RecognizedTextEntity>
    
    // Get the managed object context
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        VStack {
            // Button to delete all items
            Button(action: deleteAllItems) {
                Text("Delete All Items")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Delete All Texts")
    }

    // Function to delete all RecognizedTextEntity items
    private func deleteAllItems() {
        for item in recognizedTextItems {
            viewContext.delete(item)
        }
        
        // Save context to persist deletion
        do {
            try viewContext.save()
        } catch {
            appBootLog.errorWithContext("Error saving context after deletion: \(error)")
        }
    }
}
