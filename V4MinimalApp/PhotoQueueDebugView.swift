//
//  PhotoQueueDebugView.swift
//  V4MinimalApp
//
//  Debug view for Photo Queue metrics and session history
//

import SwiftUI

struct PhotoQueueDebugView: View {
    @StateObject private var queueManager = PhotoQueueManager()

    var body: some View {
        List {
            // Live Stats Section
            Section("Live Stats") {
                statsGrid
            }

            // Configuration Section
            Section("Configuration") {
                Picker("Processing Mode", selection: $queueManager.processingMode) {
                    ForEach(PhotoQueueProcessingMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }

                if queueManager.processingMode == .concurrent {
                    Stepper("Workers: \(queueManager.maxConcurrentWorkers)", value: $queueManager.maxConcurrentWorkers, in: 1...5)
                }

                Text(queueManager.processingMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Current Queue Section
            if !queueManager.queue.isEmpty {
                Section("Current Queue (\(queueManager.queue.count))") {
                    ForEach(queueManager.queue) { photo in
                        HStack {
                            Image(uiImage: photo.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(photo.id.uuidString.prefix(8))
                                    .font(.caption.monospaced())
                                Text(photo.status.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundColor(statusColor(photo.status))
                            }

                            Spacer()

                            if queueManager.currentlyProcessing.contains(photo.id) {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                    }
                }
            }

            // Current Results Section
            if !queueManager.results.isEmpty {
                Section("Current Results (\(queueManager.results.count))") {
                    ForEach(queueManager.results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Photo \(result.photoId.uuidString.prefix(8))")
                                    .font(.caption.monospaced())
                                Spacer()
                                Text("\(result.processingTimeMs)ms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(result.items.count) items detected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let error = result.error {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }

            // Session History Section
            Section("Session History (\(queueManager.sessions.count))") {
                if queueManager.sessions.isEmpty {
                    Text("No sessions yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(queueManager.sessions) { session in
                        sessionRow(session)
                    }
                    .onDelete(perform: deleteSessions)
                }
            }

            // Actions Section
            Section("Actions") {
                Button("Clear Queue") {
                    queueManager.clearQueue()
                }
                .foregroundColor(.orange)

                Button("Clear Results") {
                    queueManager.clearResults()
                }
                .foregroundColor(.orange)

                Button("Reset All") {
                    queueManager.resetAll()
                }
                .foregroundColor(.red)

                Button("Delete All Sessions") {
                    deleteAllSessions()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Photo Queue Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statCell("Queued", value: "\(queueManager.totalPhotosQueued)", icon: "photo.stack", color: .purple)
            statCell("Processed", value: "\(queueManager.totalPhotosProcessed)", icon: "checkmark.circle", color: .green)
            statCell("Items", value: "\(queueManager.totalItemsDetected)", icon: "cube.box", color: .blue)
            statCell("Avg Time", value: "\(queueManager.averageProcessingTimeMs)ms", icon: "clock", color: .orange)
            statCell("Items/Photo", value: String(format: "%.1f", queueManager.averageItemsPerPhoto), icon: "chart.bar", color: .teal)
            statCell("Workers", value: "\(queueManager.maxConcurrentWorkers)", icon: "cpu", color: .gray)
        }
    }

    private func statCell(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: PhotoQueueSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(session.displayDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                Label("\(session.totalPhotos)", systemImage: "photo.stack")
                Label("\(session.totalItems)", systemImage: "cube.box")
                Label("\(session.averageProcessingTimeMs)ms", systemImage: "clock")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func statusColor(_ status: PhotoQueueStatus) -> Color {
        switch status {
        case .queued: return .gray
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = queueManager.sessions[index]
            queueManager.deleteSession(session.id)
        }
    }

    private func deleteAllSessions() {
        // Delete all sessions (iterate in reverse to avoid index issues)
        let allIds = queueManager.sessions.map { $0.id }
        for id in allIds {
            queueManager.deleteSession(id)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PhotoQueueDebugView()
    }
}
