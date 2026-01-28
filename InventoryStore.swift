//
//  InventoryStore.swift
//  V4MinimalApp
//
//  JSON-backed persistent inventory store
//

import Foundation
import SwiftUI

class InventoryStore: ObservableObject {

    @Published private(set) var items: [InventoryItem] = []

    private let fileName = "inventory.json"

    // MARK: - Initialization

    init() {
        loadItems()
        cleanupCorruptedItems()
    }

    // MARK: - File URLs

    private var fileURL: URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDir.appendingPathComponent(fileName)
    }

    private var inventoryPhotosDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("inventory_photos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Full file URL for a photo filename
    func imageURL(for filename: String) -> URL {
        inventoryPhotosDir.appendingPathComponent(filename)
    }

    /// Static version for use in views without InventoryStore reference
    static func photoURL(for filename: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("inventory_photos")
        return dir.appendingPathComponent(filename)
    }

    /// Save image data to disk, returns the filename
    @discardableResult
    private func saveImage(_ data: Data, for itemId: UUID) -> String {
        let filename = "\(itemId.uuidString).jpg"
        let url = inventoryPhotosDir.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return filename
    }

    /// Delete photo file from disk
    private func deletePhoto(filename: String) {
        let url = inventoryPhotosDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Data Cleanup

    /// Remove items with corrupted names (JSON fragments from parsing failures)
    private func cleanupCorruptedItems() {
        let beforeCount = items.count
        items.removeAll { item in
            let name = item.name
            return name.contains("\"") || name.hasPrefix("{") || name.hasPrefix("[")
        }
        if items.count < beforeCount {
            print("🧹 Cleaned up \(beforeCount - items.count) corrupted inventory items")
            saveItems()
        }
    }

    // MARK: - CRUD Operations

    /// Add a single detected object, deduplicating against existing inventory
    func addItem(from detection: DetectedObject) {
        if let existingIndex = findExistingItem(matchingName: detection.name) {
            // Update existing item with new data
            mergeDetection(detection, into: &items[existingIndex])
            // Add photo if item doesn't already have one
            if items[existingIndex].photos.isEmpty, let imageData = detection.createThumbnailData() {
                let filename = saveImage(imageData, for: items[existingIndex].id)
                items[existingIndex].photos.append(filename)
            }
        } else {
            var item = InventoryItem(
                name: detection.name,
                category: ItemCategory.from(rawString: detection.categoryHint ?? ""),
                room: "",
                brand: detection.brand,
                itemColor: detection.color,
                size: detection.size
            )
            if let imageData = detection.createThumbnailData() {
                let filename = saveImage(imageData, for: item.id)
                item.photos.append(filename)
            }
            items.append(item)
        }
        saveItems()
    }

    /// Add multiple detected objects, deduplicating within the batch and against existing inventory
    func addItems(from detections: [DetectedObject]) {
        // Deduplicate within batch: keep the one with the longer name per normalized key
        var batchMap: [String: DetectedObject] = [:]
        for detection in detections {
            let key = Self.normalizedName(detection.name)
            if let existing = batchMap[key] {
                if detection.name.count > existing.name.count {
                    batchMap[key] = detection
                }
            } else {
                batchMap[key] = detection
            }
        }

        // Add each unique detection, deduplicating against existing inventory
        for detection in batchMap.values {
            if let existingIndex = findExistingItem(matchingName: detection.name) {
                mergeDetection(detection, into: &items[existingIndex])
                if items[existingIndex].photos.isEmpty, let imageData = detection.createThumbnailData() {
                    let filename = saveImage(imageData, for: items[existingIndex].id)
                    items[existingIndex].photos.append(filename)
                }
            } else {
                var item = InventoryItem(
                    name: detection.name,
                    category: ItemCategory.from(rawString: detection.categoryHint ?? ""),
                    room: "",
                    brand: detection.brand,
                    itemColor: detection.color,
                    size: detection.size
                )
                if let imageData = detection.createThumbnailData() {
                    let filename = saveImage(imageData, for: item.id)
                    item.photos.append(filename)
                }
                items.append(item)
            }
        }
        saveItems()
    }

    // MARK: - Deduplication Helpers

    /// Normalize a name for comparison
    static func normalizedName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Find an existing item whose name matches (exact or containment)
    private func findExistingItem(matchingName name: String) -> Int? {
        let normalized = Self.normalizedName(name)
        return items.firstIndex { existing in
            let existingNorm = Self.normalizedName(existing.name)
            return existingNorm == normalized ||
                   existingNorm.contains(normalized) ||
                   normalized.contains(existingNorm)
        }
    }

    /// Merge detection data into an existing inventory item
    private func mergeDetection(_ detection: DetectedObject, into item: inout InventoryItem) {
        item.updatedAt = Date()
        // Fill in fields that were previously nil
        if item.brand == nil, let brand = detection.brand {
            item.brand = brand
        }
        if item.itemColor == nil, let color = detection.color {
            item.itemColor = color
        }
        if item.size == nil, let size = detection.size {
            item.size = size
        }
        if item.category == .other, let hint = detection.categoryHint {
            let mapped = ItemCategory.from(rawString: hint)
            if mapped != .other { item.category = mapped }
        }
        // Use the longer/more specific name
        if detection.name.count > item.name.count {
            item.name = detection.name
        }
    }

    // MARK: - Duplicate Review

    /// Find groups of items that look like duplicates based on name similarity
    func findDuplicateGroups() -> [[InventoryItem]] {
        var groups: [[InventoryItem]] = []
        var assigned = Set<UUID>()

        for i in 0..<items.count {
            guard !assigned.contains(items[i].id) else { continue }
            var group = [items[i]]
            let normI = Self.normalizedName(items[i].name)

            for j in (i + 1)..<items.count {
                guard !assigned.contains(items[j].id) else { continue }
                let normJ = Self.normalizedName(items[j].name)
                if normI == normJ || normI.contains(normJ) || normJ.contains(normI) {
                    group.append(items[j])
                    assigned.insert(items[j].id)
                }
            }

            if group.count > 1 {
                assigned.insert(items[i].id)
                groups.append(group)
            }
        }
        return groups
    }

    /// Merge a group of duplicate items, keeping the richest one
    func mergeItems(_ ids: [UUID], keepId: UUID) {
        guard let keepIndex = items.firstIndex(where: { $0.id == keepId }) else { return }
        let others = items.filter { ids.contains($0.id) && $0.id != keepId }

        for other in others {
            if items[keepIndex].brand == nil { items[keepIndex].brand = other.brand }
            if items[keepIndex].itemColor == nil { items[keepIndex].itemColor = other.itemColor }
            if items[keepIndex].size == nil { items[keepIndex].size = other.size }
            if items[keepIndex].category == .other && other.category != .other {
                items[keepIndex].category = other.category
            }
            if other.name.count > items[keepIndex].name.count {
                items[keepIndex].name = other.name
            }
        }
        items[keepIndex].updatedAt = Date()

        // Remove the others and clean up their photos
        let idsToRemove = Set(ids).subtracting([keepId])
        for item in items where idsToRemove.contains(item.id) {
            for photo in item.photos { deletePhoto(filename: photo) }
        }
        items.removeAll { idsToRemove.contains($0.id) }
        saveItems()
    }

    func deleteItem(id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            for photo in item.photos { deletePhoto(filename: photo) }
        }
        items.removeAll { $0.id == id }
        saveItems()
    }

    func deleteItems(at offsets: IndexSet, from sortedItems: [InventoryItem]) {
        let idsToDelete = offsets.map { sortedItems[$0].id }
        for id in idsToDelete {
            if let item = items.first(where: { $0.id == id }) {
                for photo in item.photos { deletePhoto(filename: photo) }
            }
        }
        items.removeAll { idsToDelete.contains($0.id) }
        saveItems()
    }

    /// Delete all inventory items and their photos
    func deleteAllItems() {
        for item in items {
            for photo in item.photos { deletePhoto(filename: photo) }
        }
        items.removeAll()
        saveItems()
        print("🗑️ Deleted all inventory items")
    }

    // MARK: - Persistence

    private func saveItems() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save inventory: \(error)")
        }
    }

    private func loadItems() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            items = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = try decoder.decode([InventoryItem].self, from: data)
        } catch {
            print("Failed to load inventory: \(error)")
            items = []
        }
    }
}

// MARK: - Saved Inventory Sheet

struct SavedInventorySheet: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAllAlert = false

    var sortedItems: [InventoryItem] {
        inventoryStore.items.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if inventoryStore.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)

                        Text("No Saved Items")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("Tap + on detected objects to save them")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        // Debug admin section
                        Section {
                            Button(role: .destructive) {
                                showingDeleteAllAlert = true
                            } label: {
                                Label("Delete All Items (\(inventoryStore.items.count))", systemImage: "trash.fill")
                            }
                        } header: {
                            Text("Debug")
                        }

                        // Items
                        Section {
                            ForEach(sortedItems) { item in
                                NavigationLink(destination: ItemDetailView(item: item)) {
                                    HStack(spacing: 12) {
                                        if let photoName = item.photos.first,
                                           let uiImage = UIImage(contentsOfFile: inventoryStore.imageURL(for: photoName).path) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 44, height: 44)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        } else {
                                            Image(systemName: item.category.icon)
                                                .font(.title3)
                                                .foregroundStyle(item.category.color)
                                                .frame(width: 44, height: 44)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.body)
                                                .fontWeight(.medium)

                                            HStack(spacing: 6) {
                                                Text(item.category.rawValue)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)

                                                let details = [item.brand, item.itemColor, item.size]
                                                    .compactMap { $0 }
                                                if !details.isEmpty {
                                                    Text(details.joined(separator: " · "))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            HStack(spacing: 4) {
                                                if item.updatedAt > item.createdAt {
                                                    Text("Updated")
                                                        .font(.caption2)
                                                        .foregroundStyle(.blue)
                                                    Text(item.updatedAt, style: .relative)
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                } else {
                                                    Text("Added")
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                    Text(item.createdAt, style: .relative)
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .onDelete { offsets in
                                inventoryStore.deleteItems(at: offsets, from: sortedItems)
                            }
                        } header: {
                            Text("Inventory")
                        }
                    }
                }
            }
            .navigationTitle("Saved Items (\(inventoryStore.items.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if !inventoryStore.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .alert("Delete All Items", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    inventoryStore.deleteAllItems()
                }
            } message: {
                Text("This will permanently delete all \(inventoryStore.items.count) inventory items and their photos.")
            }
        }
    }
}

// MARK: - Duplicate Review Sheet

struct DuplicateReviewSheet: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var duplicateGroups: [[InventoryItem]] = []

    var body: some View {
        NavigationStack {
            Group {
                if duplicateGroups.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 50))
                            .foregroundStyle(.green)

                        Text("No Duplicates Found")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text("Your inventory looks clean")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(Array(duplicateGroups.enumerated()), id: \.offset) { groupIndex, group in
                            Section("Group \(groupIndex + 1) — \(group.count) items") {
                                ForEach(group) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.body)
                                            .fontWeight(.medium)

                                        HStack(spacing: 6) {
                                            Text(item.category.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            let details = [item.brand, item.itemColor, item.size]
                                                .compactMap { $0 }
                                            if !details.isEmpty {
                                                Text(details.joined(separator: " · "))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }

                                Button("Merge Group") {
                                    let ids = group.map { $0.id }
                                    // Pick the item with the most populated fields as keeper
                                    let keeper = group.max { a, b in
                                        fieldCount(a) < fieldCount(b)
                                    }!
                                    inventoryStore.mergeItems(ids, keepId: keeper.id)
                                    duplicateGroups = inventoryStore.findDuplicateGroups()
                                }
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                duplicateGroups = inventoryStore.findDuplicateGroups()
            }
        }
    }

    private func fieldCount(_ item: InventoryItem) -> Int {
        var count = item.name.count  // Prefer longer names
        if item.brand != nil { count += 10 }
        if item.itemColor != nil { count += 10 }
        if item.size != nil { count += 10 }
        if item.category != .other { count += 10 }
        return count
    }
}
