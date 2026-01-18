//
//  ContentView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/7/24.
//

import SwiftUI
import CoreData

/*
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>

    var body: some View {
        NavigationView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp!, formatter: itemFormatter)")
                    } label: {
                        Text(item.timestamp!, formatter: itemFormatter)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            Text("Select an item")
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()

            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { items[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

*/


struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RecognizedTextEntity.timestamp, ascending: false)],
        animation: .default
    ) private var recognizedTexts: FetchedResults<RecognizedTextEntity>
    
    @StateObject private var speechManager = SpeechRecognitionManager(context: DynamicPersistenceController.shared.container.viewContext)
    
  
    
    init() {
        
        UIScrollView.appearance().indicatorStyle = .black // Optional: Set color style
        UIScrollView.appearance().scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -2)
        
    }
    
    var body: some View {
        NavigationStack{
            VStack(spacing: 20) {
                NavigationLink(destination: DebugView()) {
                    Text("#1 DebugView")
                }
                .buttonStyle(PrimaryButtonStyle())
                
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
