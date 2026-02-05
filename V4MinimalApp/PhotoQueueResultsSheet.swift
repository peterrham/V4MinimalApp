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
    @State private var savedItemIds: Set<UUID> = []

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

                // Save All footer
                if unsavedCount > 0 {
                    saveAllFooter
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
                            savedItemIds.removeAll()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var unsavedCount: Int {
        queueManager.results.reduce(0) { total, result in
            total + result.items.filter { !savedItemIds.contains($0.id) && !$0.isSaved }.count
        }
    }

    private var totalItemCount: Int {
        queueManager.results.reduce(0) { $0 + $1.items.count }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: AppTheme.Spacing.l) {
            statCard(
                icon: "photo.stack.fill",
                value: "\(queueManager.results.count)",
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
        let isSaved = savedItemIds.contains(item.id) || item.isSaved

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(isSaved)
                    .foregroundColor(isSaved ? .secondary : .primary)

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

            if isSaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            } else {
                Button {
                    saveItem(item, photoId: photoId)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isSaved ? 0.6 : 1.0)
    }

    // MARK: - Save All Footer

    private var saveAllFooter: some View {
        Button {
            saveAllItems()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                Text("Save All (\(unsavedCount))")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(.green))
            .foregroundColor(.white)
        }
        .padding(.horizontal, AppTheme.Spacing.l)
        .padding(.vertical, AppTheme.Spacing.m)
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func saveItem(_ item: PhotoQueueItem, photoId: UUID) {
        // Find the result containing this item to get the photo
        guard let result = queueManager.results.first(where: { $0.photoId == photoId }),
              let filename = result.photoFilename else { return }

        let url = queueManager.photoURL(for: filename)
        guard let image = UIImage(contentsOfFile: url.path) else { return }

        // Create PhotoIdentificationResult for compatibility using a helper
        let photoResult = createPhotoResult(from: item)

        inventoryStore.addItemFromPhotoAnalysis(photoResult, photo: image)

        withAnimation {
            savedItemIds.insert(item.id)
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func saveAllItems() {
        // Create a detection session for all items
        sessionStore.createSession()

        for result in queueManager.results {
            guard let filename = result.photoFilename else { continue }
            let url = queueManager.photoURL(for: filename)
            guard let image = UIImage(contentsOfFile: url.path) else { continue }

            for item in result.items where !savedItemIds.contains(item.id) && !item.isSaved {
                let photoResult = createPhotoResult(from: item)

                // Add to inventory
                inventoryStore.addItemFromPhotoAnalysis(photoResult, photo: image)

                withAnimation {
                    savedItemIds.insert(item.id)
                }
            }
        }

        sessionStore.endSession()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Create a PhotoIdentificationResult from a PhotoQueueItem
    private func createPhotoResult(from item: PhotoQueueItem) -> PhotoIdentificationResult {
        var box: (yMin: CGFloat, xMin: CGFloat, yMax: CGFloat, xMax: CGFloat)?
        if let bb = item.boundingBox {
            box = (CGFloat(bb.yMin), CGFloat(bb.xMin), CGFloat(bb.yMax), CGFloat(bb.xMax))
        }

        var result = PhotoIdentificationResult.parse(from: "{}")
        result.name = item.name
        result.brand = item.brand
        result.color = item.color
        result.size = item.size
        result.category = item.category
        result.estimatedValue = item.estimatedValue
        result.description = item.description
        result.boundingBox = box
        return result
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
