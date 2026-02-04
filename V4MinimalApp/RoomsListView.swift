//
//  RoomsListView.swift
//  V4MinimalApp
//
//  List of rooms — tapping a room shows its items
//

import SwiftUI

struct RoomsListView: View {
    @EnvironmentObject var inventoryStore: InventoryStore

    var body: some View {
        List {
            ForEach(inventoryStore.enabledRoomsForCurrentHome) { room in
                NavigationLink {
                    InventoryListView(embedded: true, initialRoom: room.name)
                } label: {
                    HStack(spacing: AppTheme.Spacing.m) {
                        Image(systemName: room.icon)
                            .font(.title2)
                            .foregroundStyle(AppTheme.Colors.primary)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name)
                                .font(.body)
                                .fontWeight(.medium)

                            let count = inventoryStore.currentHomeItems.filter { $0.room == room.name }.count
                            Text("\(count) \(count == 1 ? "item" : "items")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Rooms")
        .navigationBarTitleDisplayMode(.inline)
    }
}
