//
//  NormalizationView.swift
//  V4MinimalApp
//
//  Debug view for normalizing inventory data with AI
//

import SwiftUI

struct NormalizationView: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    @StateObject private var service = InventoryNormalizationService()

    var body: some View {
        List {
            // Data Quality Summary
            Section {
                qualityRow("Total Items", value: "\(inventoryStore.items.count)", icon: "cube.box.fill")
                qualityRow("Garbage Items", value: "\(service.countGarbageItems())", icon: "trash.fill", bad: service.countGarbageItems() > 0)
                qualityRow("Missing Brand", value: "\(missingCount(\.brand))", icon: "tag.fill", bad: true)
                qualityRow("Missing Color", value: "\(missingCount(\.itemColor))", icon: "paintpalette.fill", bad: true)
                qualityRow("Missing Room", value: "\(missingRoomCount)", icon: "door.left.hand.open", bad: true)
                qualityRow("Missing Value", value: "\(missingValueCount)", icon: "dollarsign.circle.fill", bad: true)
                qualityRow("Category 'Other'", value: "\(otherCategoryCount)", icon: "questionmark.folder.fill", bad: true)
                qualityRow("Items with UPC", value: "\(upcCount)", icon: "barcode")
                qualityRow("Empty Boxes", value: "\(emptyBoxCount)", icon: "shippingbox")
                qualityRow("Quantity > 1", value: "\(multiQuantityCount)", icon: "number")
            } header: {
                Text("Data Quality")
            }

            // Actions
            Section {
                // Remove Garbage
                Button {
                    service.inventoryStore = inventoryStore
                    service.removeGarbageItems()
                } label: {
                    HStack {
                        Label("Remove Garbage Items", systemImage: "trash.fill")
                        Spacer()
                        if service.garbageRemoved > 0 {
                            Text("\(service.garbageRemoved) removed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.red)
                .disabled(service.isRunning)

                // AI Normalize
                Button {
                    service.inventoryStore = inventoryStore
                    Task {
                        await service.normalizeAll()
                    }
                } label: {
                    Label("Normalize with AI", systemImage: "wand.and.stars")
                }
                .foregroundStyle(AppTheme.Colors.primary)
                .disabled(service.isRunning)
            } header: {
                Text("Actions")
            } footer: {
                Text("AI normalization sends each item's photo to Gemini to extract brand, color, category, room, and value. Rate-limited to ~40 items/minute.")
            }

            // Progress
            if service.isRunning {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Processing...")
                                .font(.headline)
                            Spacer()
                            Button("Cancel", role: .destructive) {
                                service.cancel()
                            }
                            .font(.subheadline)
                        }

                        ProgressView(value: Double(service.progress), total: Double(max(service.total, 1)))
                            .tint(AppTheme.Colors.primary)

                        Text("\(service.progress) / \(service.total)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)

                        if !service.currentItem.isEmpty {
                            Text(service.currentItem)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 16) {
                            Label("\(service.itemsUpdated) updated", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.Colors.success)
                            if service.errors > 0 {
                                Label("\(service.errors) errors", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppTheme.Colors.warning)
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Progress")
                }
            }

            // Last Run Summary
            if let summary = service.lastRunSummary {
                Section {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Last Run")
                }
            }
        }
        .navigationTitle("Normalize Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            service.inventoryStore = inventoryStore
        }
    }

    // MARK: - Helpers

    private func qualityRow(_ label: String, value: String, icon: String, bad: Bool = false) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(bad ? .red : .primary)
        }
    }

    private func missingCount(_ keyPath: KeyPath<InventoryItem, String?>) -> Int {
        inventoryStore.items.filter { $0[keyPath: keyPath] == nil || $0[keyPath: keyPath]?.isEmpty == true }.count
    }

    private var missingRoomCount: Int {
        inventoryStore.items.filter { $0.room.isEmpty }.count
    }

    private var missingValueCount: Int {
        inventoryStore.items.filter { $0.estimatedValue == nil && $0.purchasePrice == nil }.count
    }

    private var otherCategoryCount: Int {
        inventoryStore.items.filter { $0.category == .other }.count
    }

    private var upcCount: Int {
        inventoryStore.items.filter { $0.upc != nil && !($0.upc?.isEmpty ?? true) }.count
    }

    private var emptyBoxCount: Int {
        inventoryStore.items.filter { $0.isEmptyBox }.count
    }

    private var multiQuantityCount: Int {
        inventoryStore.items.filter { $0.quantity > 1 }.count
    }
}

#Preview {
    NavigationStack {
        NormalizationView()
            .environmentObject(InventoryStore())
    }
}
