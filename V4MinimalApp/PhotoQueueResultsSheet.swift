//
//  PhotoQueueResultsSheet.swift
//  V4MinimalApp
//
//  Results review sheet for Photo Queue mode
//

import SwiftUI

struct PhotoQueueResultsSheet: View {
    @ObservedObject var queueManager: PhotoQueueManager
    @ObservedObject var inventoryStore: InventoryStore
    @ObservedObject var sessionStore: DetectionSessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var expandedPhotoIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Session summary header
                summaryHeader
                    .padding(.horizontal, AppTheme.Spacing.l)
                    .padding(.vertical, AppTheme.Spacing.m)
                    .background(Color(.secondarySystemBackground))

                // Results list
                if queueManager.results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Queue Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !queueManager.results.isEmpty {
                        Button("Clear") {
                            queueManager.clearResults()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var totalItemCount: Int {
        queueManager.results.reduce(0) { $0 + $1.items.count }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        VStack(spacing: AppTheme.Spacing.m) {
            // Processing status banner
            processingStatusBanner

            // Stats row
            HStack(spacing: AppTheme.Spacing.l) {
                statCard(
                    icon: "photo.stack.fill",
                    value: "\(queueManager.totalPhotosProcessed)/\(queueManager.totalPhotosQueued)",
                    label: "Photos",
                    color: .purple
                )
                statCard(
                    icon: "cube.box.fill",
                    value: "\(totalItemCount)",
                    label: "Items",
                    color: .blue
                )
                statCard(
                    icon: "clock.fill",
                    value: "\(queueManager.averageProcessingTimeMs)ms",
                    label: "Avg Time",
                    color: .orange
                )
                statCard(
                    icon: "chart.line.uptrend.xyaxis",
                    value: String(format: "%.1f", queueManager.averageItemsPerPhoto),
                    label: "Per Photo",
                    color: .green
                )
            }
        }
    }

    private var processingStatusBanner: some View {
        let total = queueManager.totalPhotosQueued
        let processed = queueManager.totalPhotosProcessed
        let isProcessing = queueManager.isProcessing
        let isDone = processed == total && total > 0

        return HStack(spacing: 10) {
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Processing \(processed)/\(total) photos...")
                    .font(.subheadline)
                    .fontWeight(.medium)
            } else if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Complete - \(total) photos processed")
                    .font(.subheadline)
                    .fontWeight(.medium)
            } else if total == 0 {
                Image(systemName: "photo.badge.plus")
                    .foregroundColor(.secondary)
                Text("No photos queued")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
                Text("\(processed)/\(total) processed - Waiting")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDone ? Color.green.opacity(0.1) : (isProcessing ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1)))
        )
    }

    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.callout)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.l) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Results Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Capture photos to see detected items here")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            ForEach(queueManager.results) { result in
                Section {
                    photoResultRow(result)
                } header: {
                    photoHeader(result)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func photoHeader(_ result: PhotoQueueResult) -> some View {
        HStack {
            if let filename = result.photoFilename {
                let url = queueManager.photoURL(for: filename)
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.items.count) items")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("\(result.processingTimeMs)ms")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if result.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private func photoResultRow(_ result: PhotoQueueResult) -> some View {
        if let error = result.error {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            ForEach(result.items) { item in
                itemRow(item, photoId: result.photoId)
            }
        }
    }

    private func itemRow(_ item: PhotoQueueItem, photoId: UUID) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                let subtitle = [item.brand, item.color, item.category]
                    .compactMap { $0 }
                    .joined(separator: " \u{00B7} ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let value = item.estimatedValue {
                Text("$\(Int(value))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }

            // Items are auto-saved to session
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)
        }
    }

}

// MARK: - Preview

#Preview {
    PhotoQueueResultsSheet(
        queueManager: PhotoQueueManager(),
        inventoryStore: InventoryStore(),
        sessionStore: DetectionSessionStore()
    )
}
