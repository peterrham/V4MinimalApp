//
//  RoomsManagementView.swift
//  V4MinimalApp
//
//  Toggle-based room management per home
//

import SwiftUI

struct RoomsManagementView: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    @State private var showingAddRoom = false
    @State private var newRoomName = ""

    private var rooms: [HomeRoom] {
        inventoryStore.currentHomeRooms
    }

    var body: some View {
        Form {
            Section {
                ForEach(rooms) { room in
                    roomRow(room)
                }
                .onDelete(perform: deleteRooms)
            } header: {
                Text("Rooms for \(inventoryStore.currentHome?.name ?? "Home")")
            } footer: {
                Text("Enabled rooms appear on your home screen. Items scanned in a room are counted there.")
            }

            Section {
                Button {
                    showingAddRoom = true
                } label: {
                    Label("Add Room", systemImage: "plus.circle.fill")
                        .foregroundStyle(AppTheme.Colors.primary)
                }
            }
        }
        .navigationTitle("Rooms")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Add Room", isPresented: $showingAddRoom) {
            TextField("Room name", text: $newRoomName)
            Button("Cancel", role: .cancel) {
                newRoomName = ""
            }
            Button("Add") {
                let trimmed = newRoomName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    let room = HomeRoom(
                        name: trimmed,
                        icon: "door.left.hand.open",
                        isEnabled: true,
                        homeId: inventoryStore.currentHomeId
                    )
                    inventoryStore.addRoom(room)
                }
                newRoomName = ""
            }
        }
    }

    private func roomRow(_ room: HomeRoom) -> some View {
        HStack(spacing: 12) {
            Image(systemName: room.icon)
                .font(.title3)
                .foregroundStyle(room.isEnabled ? AppTheme.Colors.primary : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.body)
                    .fontWeight(.medium)

                let count = inventoryStore.currentHomeItems.filter { $0.room == room.name }.count
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { room.isEnabled },
                set: { _ in inventoryStore.toggleRoom(room) }
            ))
            .labelsHidden()
        }
    }

    private func deleteRooms(at offsets: IndexSet) {
        for index in offsets {
            inventoryStore.deleteRoom(id: rooms[index].id)
        }
    }
}

#Preview {
    NavigationStack {
        RoomsManagementView()
            .environmentObject(InventoryStore())
    }
}
