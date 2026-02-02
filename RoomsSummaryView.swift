//
//  RoomsSummaryView.swift
//  V4MinimalApp
//
//  Rooms summary sorted by value or item count
//

import SwiftUI

enum RoomSortMode: Hashable, Identifiable {
    case byValue
    case byItemCount

    var id: Self { self }
}

struct RoomsSummaryView: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    let sortMode: RoomSortMode

    private var roomGroups: [(name: String, icon: String, itemCount: Int, totalValue: Double)] {
        let items = inventoryStore.currentHomeItems
        let enabledRooms = inventoryStore.enabledRoomsForCurrentHome

        // Group items by room string
        var grouped: [String: [InventoryItem]] = [:]
        for item in items {
            let roomName = item.room.isEmpty ? "Unassigned" : item.room
            grouped[roomName, default: []].append(item)
        }

        // Build tuples with icon lookup
        var result: [(name: String, icon: String, itemCount: Int, totalValue: Double)] = []
        for (roomName, roomItems) in grouped {
            let icon = enabledRooms.first(where: { $0.name == roomName })?.icon ?? "door.left.hand.open"
            let value = roomItems.reduce(0.0) { sum, item in
                sum + (item.purchasePrice ?? item.estimatedValue ?? 0)
            }
            result.append((name: roomName, icon: icon, itemCount: roomItems.count, totalValue: value))
        }

        // Sort descending by primary metric
        switch sortMode {
        case .byValue:
            result.sort { $0.totalValue > $1.totalValue }
        case .byItemCount:
            result.sort { $0.itemCount > $1.itemCount }
        }

        return result
    }

    private var grandTotal: Double {
        roomGroups.reduce(0) { $0 + $1.totalValue }
    }

    var body: some View {
        List {
            if sortMode == .byValue {
                Section {
                    HStack {
                        Text("Grand Total")
                            .font(.headline)
                        Spacer()
                        Text(HomeView.formatDollar(grandTotal))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                    .padding(.vertical, 4)
                }
            }

            if roomGroups.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "door.left.hand.open")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No rooms yet")
                            .font(.headline)
                        Text("Items will appear here once scanned")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.xl)
                }
            } else {
                Section {
                    ForEach(roomGroups, id: \.name) { room in
                        HStack(spacing: 12) {
                            Image(systemName: room.icon)
                                .font(.title3)
                                .foregroundStyle(AppTheme.Colors.primary)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.name)
                                    .font(.body)
                                    .fontWeight(.medium)

                                switch sortMode {
                                case .byValue:
                                    Text("\(room.itemCount) \(room.itemCount == 1 ? "item" : "items")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                case .byItemCount:
                                    if room.totalValue > 0 {
                                        Text(HomeView.formatDollar(room.totalValue))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            switch sortMode {
                            case .byValue:
                                Text(HomeView.formatDollar(room.totalValue))
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.Colors.success)
                            case .byItemCount:
                                Text("\(room.itemCount)")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(sortMode == .byValue ? "Value by Room" : "Items by Room")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("By Value") {
    NavigationStack {
        RoomsSummaryView(sortMode: .byValue)
            .environmentObject(InventoryStore())
    }
}

#Preview("By Item Count") {
    NavigationStack {
        RoomsSummaryView(sortMode: .byItemCount)
            .environmentObject(InventoryStore())
    }
}
