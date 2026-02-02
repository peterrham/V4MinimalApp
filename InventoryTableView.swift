//
//  InventoryTableView.swift
//  V4MinimalApp
//
//  Debug tabular view of all inventory data
//

import SwiftUI

struct InventoryTableView: View {
    @EnvironmentObject var inventoryStore: InventoryStore

    @State private var sortField: SortField = .createdAt
    @State private var sortAscending = false
    @State private var searchText = ""

    enum SortField: String, CaseIterable {
        case name = "Name"
        case category = "Category"
        case brand = "Brand"
        case color = "Color"
        case container = "Container"
        case room = "Room"
        case value = "Value"
        case photos = "Photos"
        case createdAt = "Created"
    }

    private var filteredItems: [InventoryItem] {
        let items: [InventoryItem]
        if searchText.isEmpty {
            items = inventoryStore.items
        } else {
            let query = searchText.lowercased()
            items = inventoryStore.items.filter {
                $0.name.lowercased().contains(query) ||
                $0.category.rawValue.lowercased().contains(query) ||
                ($0.brand?.lowercased().contains(query) ?? false) ||
                ($0.container?.lowercased().contains(query) ?? false) ||
                ($0.upc?.lowercased().contains(query) ?? false) ||
                $0.room.lowercased().contains(query) ||
                $0.notes.lowercased().contains(query)
            }
        }
        return items.sorted { a, b in
            let result: Bool
            switch sortField {
            case .name:
                result = a.name.localizedCompare(b.name) == .orderedAscending
            case .category:
                result = a.category.rawValue < b.category.rawValue
            case .brand:
                result = (a.brand ?? "") < (b.brand ?? "")
            case .color:
                result = (a.itemColor ?? "") < (b.itemColor ?? "")
            case .container:
                result = (a.container ?? "") < (b.container ?? "")
            case .room:
                result = a.room < b.room
            case .value:
                result = (a.estimatedValue ?? a.purchasePrice ?? 0) < (b.estimatedValue ?? b.purchasePrice ?? 0)
            case .photos:
                result = a.photos.count < b.photos.count
            case .createdAt:
                result = a.createdAt < b.createdAt
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary bar
            HStack {
                Text("\(filteredItems.count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Total: \(totalValue)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(AppTheme.Colors.surface)

            // Column headers
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    headerRow
                        .background(Color(.systemGray5))

                    Divider()

                    // Data rows
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                dataRow(item)
                                Divider()
                            }
                        }
                    }
                }
                .frame(minWidth: 1225)
            }
        }
        .searchable(text: $searchText, prompt: "Filter items...")
        .navigationTitle("Inventory Table")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell("#", width: 36, field: nil)
            headerCell("Name", width: 160, field: .name)
            headerCell("Qty", width: 40, field: nil)
            headerCell("Box?", width: 45, field: nil)
            headerCell("Category", width: 100, field: .category)
            headerCell("Brand", width: 100, field: .brand)
            headerCell("Color", width: 80, field: .color)
            headerCell("Size", width: 70, field: nil)
            headerCell("UPC", width: 120, field: nil)
            headerCell("Container", width: 120, field: .container)
            headerCell("Room", width: 100, field: .room)
            headerCell("Value", width: 80, field: .value)
            headerCell("Photos", width: 60, field: .photos)
            headerCell("Notes", width: 200, field: nil)
            headerCell("Created", width: 90, field: .createdAt)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private func headerCell(_ title: String, width: CGFloat, field: SortField?) -> some View {
        Button {
            if let field = field {
                if sortField == field {
                    sortAscending.toggle()
                } else {
                    sortField = field
                    sortAscending = true
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                if let field = field, sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(field == nil)
    }

    // MARK: - Data Row

    private func dataRow(_ item: InventoryItem) -> some View {
        let index = (filteredItems.firstIndex(where: { $0.id == item.id }) ?? 0) + 1
        return HStack(spacing: 0) {
            Text("\(index)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .leading)

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)

            Text(item.quantity > 1 ? "\(item.quantity)" : "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(item.quantity > 1 ? .primary : .tertiary)
                .frame(width: 40, alignment: .leading)

            Text(item.isEmptyBox ? "Yes" : "")
                .font(.caption)
                .foregroundStyle(item.isEmptyBox ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                .frame(width: 45, alignment: .leading)

            Text(item.category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Text(item.brand ?? "-")
                .font(.caption)
                .foregroundStyle(item.brand != nil ? .primary : .tertiary)
                .frame(width: 100, alignment: .leading)

            Text(item.itemColor ?? "-")
                .font(.caption)
                .foregroundStyle(item.itemColor != nil ? .primary : .tertiary)
                .frame(width: 80, alignment: .leading)

            Text(item.size ?? "-")
                .font(.caption)
                .foregroundStyle(item.size != nil ? .primary : .tertiary)
                .frame(width: 70, alignment: .leading)

            Text(item.upc ?? "-")
                .font(.caption.monospacedDigit())
                .foregroundStyle(item.upc != nil ? .primary : .tertiary)
                .frame(width: 120, alignment: .leading)

            Text(item.container ?? "-")
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(item.container != nil ? .primary : .tertiary)
                .frame(width: 120, alignment: .leading)

            Text(item.room.isEmpty ? "-" : item.room)
                .font(.caption)
                .foregroundStyle(item.room.isEmpty ? .tertiary : .primary)
                .frame(width: 100, alignment: .leading)

            Text(item.displayValue)
                .font(.caption.monospacedDigit())
                .foregroundStyle(item.estimatedValue != nil || item.purchasePrice != nil ? AnyShapeStyle(AppTheme.Colors.success) : AnyShapeStyle(.tertiary))
                .frame(width: 80, alignment: .leading)

            Text("\(item.photos.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(item.photos.isEmpty ? .tertiary : .primary)
                .frame(width: 60, alignment: .leading)

            Text(item.notes.isEmpty ? "-" : item.notes)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(item.notes.isEmpty ? .tertiary : .secondary)
                .frame(width: 200, alignment: .leading)

            Text(shortDate(item.createdAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private var totalValue: String {
        let sum = filteredItems.reduce(0.0) { $0 + ($1.purchasePrice ?? $1.estimatedValue ?? 0) }
        return "$\(InventoryItem.dollarFormatter.string(from: NSNumber(value: sum)) ?? "0")"
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: date)
    }
}

#Preview {
    NavigationStack {
        InventoryTableView()
            .environmentObject(InventoryStore())
    }
}
