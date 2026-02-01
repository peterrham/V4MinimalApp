//
//  HomesManagementView.swift
//  V4MinimalApp
//
//  CRUD management for homes/properties
//

import SwiftUI

struct HomesManagementView: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    @State private var showingAddHome = false
    @State private var editingHome: Home?
    @State private var showingDeleteAlert = false
    @State private var homeToDelete: Home?

    var body: some View {
        Form {
            Section {
                ForEach(inventoryStore.homes) { home in
                    homeRow(home)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            inventoryStore.switchHome(to: home.id)
                        }
                        .swipeActions(edge: .trailing) {
                            if inventoryStore.homes.count > 1 && home.id != inventoryStore.currentHomeId {
                                Button(role: .destructive) {
                                    homeToDelete = home
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
            } header: {
                Text("Your Homes")
            } footer: {
                Text("Tap a home to make it active. New scanned items are saved to the active home.")
            }

            Section {
                Button {
                    showingAddHome = true
                } label: {
                    Label("Add Home", systemImage: "plus.circle.fill")
                        .foregroundStyle(AppTheme.Colors.primary)
                }
            }
        }
        .navigationTitle("Homes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddHome) {
            HomeEditSheet(mode: .add)
                .environmentObject(inventoryStore)
        }
        .sheet(item: $editingHome) { home in
            HomeEditSheet(mode: .edit(home))
                .environmentObject(inventoryStore)
        }
        .alert("Delete Home", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let home = homeToDelete {
                    inventoryStore.deleteHome(id: home.id)
                }
            }
        } message: {
            if let home = homeToDelete {
                let count = inventoryStore.items.filter {
                    ($0.homeId ?? Home.defaultHomeId) == home.id
                }.count
                Text("Delete \"\(home.name)\"? Its \(count) items will be moved to your active home.")
            }
        }
    }

    private func homeRow(_ home: Home) -> some View {
        HStack(spacing: 12) {
            Image(systemName: home.icon)
                .font(.title3)
                .foregroundStyle(home.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(home.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if home.id == inventoryStore.currentHomeId {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.Colors.primary))
                    }
                }

                let count = inventoryStore.items.filter {
                    ($0.homeId ?? Home.defaultHomeId) == home.id
                }.count
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                editingHome = home
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(AppTheme.Colors.primary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Home Edit Sheet

struct HomeEditSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(Home)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let h): return h.id.uuidString
            }
        }
    }

    let mode: Mode
    @EnvironmentObject var inventoryStore: InventoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedIcon = "house.fill"

    private let iconOptions = [
        "house.fill", "building.2.fill", "building.fill",
        "tent.fill", "car.fill", "shippingbox.fill",
        "lock.fill", "mappin.circle.fill", "tree.fill"
    ]

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Home name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedIcon == icon ? AppTheme.Colors.primary : Color(.tertiarySystemBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isAdding ? "Add Home" : "Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if case .edit(let home) = mode {
                    name = home.name
                    selectedIcon = home.icon
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        switch mode {
        case .add:
            inventoryStore.addHome(Home(name: trimmed, icon: selectedIcon))
        case .edit(var home):
            home.name = trimmed
            home.icon = selectedIcon
            inventoryStore.updateHome(home)
        }
    }
}

#Preview {
    NavigationStack {
        HomesManagementView()
            .environmentObject(InventoryStore())
    }
}
