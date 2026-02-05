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


// MARK: - Child view that properly observes SpeechRecognitionManager
// Using @ObservedObject here allows SwiftUI to react to @Published property changes
private struct SpeechDisplayView: View {
    @ObservedObject var manager: SpeechRecognitionManager

    var body: some View {
        VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                    Text("Incremental Speech:")
                        .font(.headline)
                    Text(manager.incrementalText.isEmpty ? "(listening...)" : manager.incrementalText)
                        .font(.body)
                        .foregroundStyle(manager.incrementalText.isEmpty ? .secondary : .primary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                    Text("Finalized Speech:")
                        .font(.headline)
                    Text(manager.finalText.isEmpty ? "(say 'go' to finalize)" : manager.finalText)
                        .font(.body)
                        .foregroundStyle(manager.finalText.isEmpty ? .secondary : .primary)
                }
            }
        }
    }
}

struct ContentView: View {
    // MINIMAL VIEW - all heavy initialization is deferred to onAppear
    // NO @Environment or @FetchRequest here - they can cause crashes during navigation
    @State private var speechManager: SpeechRecognitionManager?
    @State private var realtimeService: OpenAIRealtimeService?
    @State private var pipeToOpenAI = false
    @State private var isInitialized = false
    @State private var statusMessage = "Initializing..."

    var body: some View {
        // NOTE: No NavigationStack here - already inside SettingsView's NavigationStack
        // Nested NavigationStacks cause crashes
        ScrollView {
            VStack(spacing: 12) {
                if let manager = speechManager {
                    // Use child view with @ObservedObject for proper reactivity
                    SpeechDisplayView(manager: manager)

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
                                    realtimeService?.connect()
                                    // Consumer is already called on background queue by SpeechRecognitionManager
                                    // so we just need to dispatch to main for the service call
                                    speechManager?.externalAudioConsumer = { [weak realtimeService] buffer, _ in
                                        DispatchQueue.main.async {
                                            realtimeService?.sendAudioBuffer(buffer)
                                        }
                                    }
                                } else {
                                    speechManager?.externalAudioConsumer = nil
                                    realtimeService?.disconnect()
                                }
                            }

                            if pipeToOpenAI, let rtService = realtimeService {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(rtService.connectionState == .connected ? Color.green : Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text(rtService.connectionState.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    if let ttfb = rtService.timingMetrics.ttfbMs {
                                        Text("TTFB: \(ttfb)ms")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.cyan)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Loading state while audio services initialize
                    Card {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Initializing audio...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }

                // Status card
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.headline)
                        Text(statusMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
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
                    appBootLog.infoWithContext("Audio toolbar refresh tapped")
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            // LAZY INIT: Only create audio objects when view actually appears
            guard !isInitialized else { return }
            isInitialized = true

            statusMessage = "View appeared, checking audio..."
            appBootLog.infoWithContext("[Audio] ContentView.onAppear - starting safe initialization")

            Task { @MainActor in
                statusMessage = "Running audio safety checks..."

                // Use AudioSafetyCheck to validate before creating heavy objects
                if let manager = await AudioSafetyCheck.createSpeechManagerIfSafe(
                    context: DynamicPersistenceController.shared.container.viewContext
                ) {
                    statusMessage = "Audio initialized successfully"
                    appBootLog.infoWithContext("[Audio] SpeechRecognitionManager created successfully")
                    self.speechManager = manager
                    self.realtimeService = OpenAIRealtimeService()

                    // Start listening
                    appBootLog.infoWithContext("[Audio] Starting speech recognition...")
                    manager.startListeningIfReady()
                    statusMessage = "Listening for speech..."
                } else {
                    statusMessage = "Failed to initialize audio - check permissions"
                    appBootLog.errorWithContext("[Audio] Failed to create SpeechRecognitionManager - check permissions")
                }
            }
        }
    }
}

