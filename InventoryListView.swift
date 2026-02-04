//
//  InventoryListView.swift
//  V4MinimalApp
//
//  Home Inventory - Full List View
//

import SwiftUI
import UIKit

enum InventorySortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case nameAZ = "Name A-Z"
    case nameZA = "Name Z-A"
    case valueHigh = "Value: High-Low"
    case valueLow = "Value: Low-High"

    var id: String { rawValue }
}

enum InventoryTab: String, CaseIterable {
    case items = "Items"
    case sessions = "Sessions"
}

struct InventoryListView: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    @EnvironmentObject var sessionStore: DetectionSessionStore
    var embedded = false  // true when already inside a NavigationStack
    var initialSort: InventorySortOrder? = nil
    var initialCategory: ItemCategory? = nil
    var initialRoom: String? = nil
    @State private var searchText = ""
    @State private var selectedCategory: ItemCategory?
    @State private var selectedRoom: String?
    @State private var sortOrder: InventorySortOrder = .nameAZ
    @State private var isGridView = true
    @State private var showingDeleteAllAlert = false
    @State private var displayLimit = 50
    @State private var inventoryTab: InventoryTab = .items

    var filteredItems: [InventoryItem] {
        let items = inventoryStore.currentHomeItems.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.brand?.localizedCaseInsensitiveContains(searchText) ?? false ||
                item.upc?.localizedCaseInsensitiveContains(searchText) ?? false

            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            let matchesRoom = selectedRoom == nil || item.room == selectedRoom

            return matchesSearch && matchesCategory && matchesRoom
        }

        switch sortOrder {
        case .newest:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return items.sorted { $0.createdAt < $1.createdAt }
        case .nameAZ:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameZA:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .valueHigh:
            return items.sorted { ($0.purchasePrice ?? $0.estimatedValue ?? 0) > ($1.purchasePrice ?? $1.estimatedValue ?? 0) }
        case .valueLow:
            return items.sorted { ($0.purchasePrice ?? $0.estimatedValue ?? 0) < ($1.purchasePrice ?? $1.estimatedValue ?? 0) }
        }
    }

    /// Items currently visible (progressive loading)
    var visibleItems: [InventoryItem] {
        Array(filteredItems.prefix(displayLimit))
    }

    /// Pre-computed disambiguation titles (O(n) instead of O(n²))
    var disambiguationMap: [UUID: String] {
        let items = visibleItems
        // Count name occurrences
        var nameCounts: [String: Int] = [:]
        for item in items {
            let key = item.name.lowercased()
            nameCounts[key, default: 0] += 1
        }
        // Build map
        var map: [UUID: String] = [:]
        for item in items {
            let key = item.name.lowercased()
            let prefix = item.quantity > 1 ? "\(item.quantity)x " : ""
            if (nameCounts[key] ?? 0) > 1, let brand = item.brand, !brand.isEmpty {
                map[item.id] = "\(prefix)\(brand) \(item.name)"
            } else {
                map[item.id] = "\(prefix)\(item.name)"
            }
        }
        return map
    }
    
    var totalValue: Double {
        filteredItems.reduce(0) { sum, item in
            sum + (item.purchasePrice ?? item.estimatedValue ?? 0)
        }
    }
    
    var body: some View {
        if embedded {
            inventoryContent
        } else {
            NavigationStack {
                inventoryContent
            }
        }
    }

    private var inventoryContent: some View {
            VStack(spacing: 0) {
                // Segmented Picker
                Picker("View", selection: $inventoryTab) {
                    ForEach(InventoryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.Spacing.l)
                .padding(.vertical, AppTheme.Spacing.s)

                if inventoryTab == .sessions {
                    SessionsListView()
                } else {

                // Filter Chips
                if !inventoryStore.currentHomeItems.isEmpty {
                    let activeCategories = Set(inventoryStore.currentHomeItems.map(\.category))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.s) {
                            // Category filters
                            FilterChip(
                                title: "All",
                                isSelected: selectedCategory == nil
                            ) {
                                selectedCategory = nil
                            }

                            ForEach(ItemCategory.allCases.filter { activeCategories.contains($0) }) { category in
                                FilterChip(
                                    title: category.rawValue,
                                    icon: category.icon,
                                    isSelected: selectedCategory == category
                                ) {
                                    selectedCategory = selectedCategory == category ? nil : category
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.l)
                        .padding(.vertical, AppTheme.Spacing.m)
                    }
                    .background(AppTheme.Colors.background)
                }
                
                // Items List/Grid
                if filteredItems.isEmpty {
                    // Empty State
                    VStack(spacing: AppTheme.Spacing.l) {
                        Spacer()
                        
                        Image(systemName: searchText.isEmpty ? "tray.fill" : "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundStyle(.tertiary)
                        
                        Text(searchText.isEmpty ? "No items yet" : "No results found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(searchText.isEmpty ?
                             "Start scanning rooms to build your inventory" :
                             "Try adjusting your search or filters")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        if searchText.isEmpty {
                            Button {
                                // Navigate to scan
                            } label: {
                                Label("Start Scanning", systemImage: "camera.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, AppTheme.Spacing.xl)
                                    .padding(.vertical, AppTheme.Spacing.m)
                                    .background(AppTheme.Colors.primary.gradient)
                                    .cornerRadius(AppTheme.cornerRadius)
                            }
                            .padding(.top, AppTheme.Spacing.m)
                        }
                        
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Summary Bar
                            HStack {
                                Text("\(filteredItems.count) items")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

                                if visibleItems.count < filteredItems.count {
                                    Text("(showing \(visibleItems.count))")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Text("$\(InventoryItem.dollarFormatter.string(from: NSNumber(value: totalValue.rounded(.up))) ?? "0")")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.Colors.success)
                            }
                            .padding(.horizontal, AppTheme.Spacing.l)
                            .padding(.vertical, AppTheme.Spacing.m)
                            .background(AppTheme.Colors.surface.opacity(0.5))

                            // Grid or List View
                            let titles = disambiguationMap
                            if isGridView {
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: AppTheme.Spacing.m),
                                    GridItem(.flexible(), spacing: AppTheme.Spacing.m)
                                ], spacing: AppTheme.Spacing.m) {
                                    ForEach(visibleItems) { item in
                                        NavigationLink {
                                            ItemDetailView(item: item)
                                        } label: {
                                            ItemCardCompact(
                                                item: item,
                                                displayTitle: titles[item.id]
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(AppTheme.Spacing.l)
                            } else {
                                LazyVStack(spacing: AppTheme.Spacing.m) {
                                    ForEach(visibleItems) { item in
                                        NavigationLink {
                                            ItemDetailView(item: item)
                                        } label: {
                                            ItemCardList(
                                                item: item,
                                                displayTitle: titles[item.id]
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(AppTheme.Spacing.l)
                            }

                            // Load more trigger
                            if visibleItems.count < filteredItems.count {
                                Button {
                                    withAnimation {
                                        displayLimit += 50
                                    }
                                } label: {
                                    Text("Show More (\(filteredItems.count - visibleItems.count) remaining)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(AppTheme.Colors.primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, AppTheme.Spacing.l)
                                }
                                .onAppear {
                                    // Auto-load more when scrolled to bottom
                                    displayLimit += 50
                                }
                            }
                        }
                    }
                }

                } // end else (items tab)
            }
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search items...")
            .onChange(of: searchText) { _, _ in displayLimit = 50 }
            .onChange(of: selectedCategory) { _, _ in displayLimit = 50 }
            .onChange(of: selectedRoom) { _, _ in displayLimit = 50 }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if inventoryTab == .items && !inventoryStore.currentHomeItems.isEmpty {
                        Button(role: .destructive) {
                            showingDeleteAllAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    HomePickerMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if inventoryTab == .items {
                        HStack(spacing: 12) {
                            Menu {
                                ForEach(InventorySortOrder.allCases) { sort in
                                    Button {
                                        withAnimation { sortOrder = sort }
                                    } label: {
                                        Label(sort.rawValue, systemImage: sortOrder == sort ? "checkmark" : "")
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .imageScale(.large)
                            }

                            Button {
                                withAnimation {
                                    isGridView.toggle()
                                }
                            } label: {
                                Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                                    .imageScale(.large)
                            }
                        }
                    }
                }
            }
            .onAppear {
                if let initial = initialSort {
                    sortOrder = initial
                }
                if let cat = initialCategory {
                    selectedCategory = cat
                }
                if let room = initialRoom {
                    selectedRoom = room
                }
            }
            .alert("Delete All Items", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    inventoryStore.deleteCurrentHomeItems()
                }
            } message: {
                Text("This will permanently delete all \(inventoryStore.currentHomeItems.count) items in \"\(inventoryStore.currentHome?.name ?? "this home")\" and their photos.")
            }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .white : AppTheme.Colors.primary)
            .padding(.horizontal, AppTheme.Spacing.m)
            .padding(.vertical, AppTheme.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AppTheme.Colors.primary, lineWidth: isSelected ? 0 : 1)
            )
        }
    }
}

// MARK: - Item Card List View

struct ItemCardList: View {
    let item: InventoryItem
    var displayTitle: String?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            // Thumbnail
            if let photoName = item.photos.first,
               let uiImage = UIImage(contentsOfFile: InventoryStore.photoURL(for: photoName).path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(item.category.color.opacity(0.1))

                    Image(systemName: item.category.icon)
                        .font(.title)
                        .foregroundStyle(item.category.color)
                }
                .frame(width: 70, height: 70)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle ?? item.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !item.room.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "door.left.hand.closed")
                            .font(.caption2)
                        Text(item.room)
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                }

                Text(item.displayValue)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.Colors.success)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(AppTheme.Spacing.m)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Room Card

struct RoomCard: View {
    let room: Room
    let itemCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            Image(systemName: room.icon)
                .font(.title2)
                .foregroundStyle(room.color)

            Text(room.name)
                .font(.headline)

            Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(width: 160, alignment: .leading)
        .padding(AppTheme.Spacing.l)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

#Preview {
    InventoryListView()
        .environmentObject(InventoryStore())
        .environmentObject(DetectionSessionStore())
}
