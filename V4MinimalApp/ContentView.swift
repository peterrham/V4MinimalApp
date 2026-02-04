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
    @StateObject private var realtimeService = OpenAIRealtimeService()
    @State private var pipeToOpenAI = false

    
    init() {
        
        UIScrollView.appearance().indicatorStyle = .black // Optional: Set color style
        UIScrollView.appearance().scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -2)
        
    }
    
    var body: some View {
        NavigationStack{
            VStack(spacing: 12) {
                VStack(spacing: 12) {
                    NavigationLink(destination: DebugView()) {
                        Text("#1 DebugView")
                            .unifiedNavLabel()
                    }

                    NavigationLink(destination: GoogleSignInView()) {
                        Text("Sign In")
                            .unifiedNavLabel()
                    }
                }
                
                Card {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                        Text("Incremental Speech:")
                            .font(.headline)
                        Text(speechManager.incrementalText)
                            .font(.body)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                        Text("Finalized Speech:")
                            .font(.headline)
                        Text(speechManager.finalText)
                            .font(.body)
                    }
                }

                // Pipe Audio to OpenAI Realtime
                Card {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                        Toggle(isOn: $pipeToOpenAI) {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform.badge.mic")
                                    .foregroundStyle(.cyan)
                                Text("Pipe Audio to OpenAI Realtime")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .tint(.cyan)
                        .onChange(of: pipeToOpenAI) { newValue in
                            if newValue {
                                realtimeService.connect()
                                speechManager.externalAudioConsumer = { [weak realtimeService] buffer, _ in
                                    Task { @MainActor in
                                        realtimeService?.sendAudioBuffer(buffer)
                                    }
                                }
                            } else {
                                speechManager.externalAudioConsumer = nil
                                realtimeService.disconnect()
                            }
                        }

                        if pipeToOpenAI {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(realtimeService.connectionState == .connected ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(realtimeService.connectionState.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if let ttfb = realtimeService.timingMetrics.ttfbMs {
                                    Text("TTFB: \(ttfb)ms")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }
                    }
                }

                Card {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(recognizedTexts.indices, id: \.self) { index in
                                let text = recognizedTexts[index]
                                Text("\(index): \(shortDateFormatter.string(from: text.timestamp!)): \(text.content!)")
                                    .onAppear {}
                                    .padding()
                                    .background(Color(.tertiarySystemBackground))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 480)
            .navigationTitle("Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Placeholder refresh action
                        appBootLog.infoWithContext("Audio toolbar refresh tapped")
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

