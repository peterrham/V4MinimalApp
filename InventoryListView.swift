//
//  InventoryListView.swift
//  V4MinimalApp
//
//  Home Inventory - Full List View
//

import SwiftUI

struct InventoryListView: View {
    @State private var items: [InventoryItem] = InventoryItem.sampleItems
    @State private var searchText = ""
    @State private var selectedCategory: ItemCategory?
    @State private var selectedRoom: String?
    @State private var isGridView = true
    
    var filteredItems: [InventoryItem] {
        items.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.brand?.localizedCaseInsensitiveContains(searchText) ?? false
            
            let matchesCategory = selectedCategory == nil || item.category == selectedCategory
            let matchesRoom = selectedRoom == nil || item.room == selectedRoom
            
            return matchesSearch && matchesCategory && matchesRoom
        }
    }
    
    var totalValue: Double {
        filteredItems.reduce(0) { sum, item in
            sum + (item.purchasePrice ?? item.estimatedValue ?? 0)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter Chips
                if !items.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.s) {
                            // Category filters
                            FilterChip(
                                title: "All",
                                isSelected: selectedCategory == nil
                            ) {
                                selectedCategory = nil
                            }
                            
                            ForEach(ItemCategory.allCases.filter { category in
                                items.contains { $0.category == category }
                            }) { category in
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
                                
                                Spacer()
                                
                                Text(String(format: "$%.2f", totalValue))
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.Colors.success)
                            }
                            .padding(.horizontal, AppTheme.Spacing.l)
                            .padding(.vertical, AppTheme.Spacing.m)
                            .background(AppTheme.Colors.surface.opacity(0.5))
                            
                            // Grid or List View
                            if isGridView {
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: AppTheme.Spacing.m),
                                    GridItem(.flexible(), spacing: AppTheme.Spacing.m)
                                ], spacing: AppTheme.Spacing.m) {
                                    ForEach(filteredItems) { item in
                                        NavigationLink {
                                            ItemDetailView(item: item)
                                        } label: {
                                            ItemCardCompact(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(AppTheme.Spacing.l)
                            } else {
                                LazyVStack(spacing: AppTheme.Spacing.m) {
                                    ForEach(filteredItems) { item in
                                        NavigationLink {
                                            ItemDetailView(item: item)
                                        } label: {
                                            ItemCardList(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(AppTheme.Spacing.l)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search items...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.category.color.opacity(0.1))
                
                Image(systemName: item.category.icon)
                    .font(.title)
                    .foregroundStyle(item.category.color)
            }
            .frame(width: 70, height: 70)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: "door.left.hand.closed")
                        .font(.caption2)
                    Text(item.room)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                
                if let brand = item.brand {
                    Text(brand)
                        .font(.caption)
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            Image(systemName: room.icon)
                .font(.title)
                .foregroundStyle(room.color)
            
            Text(room.name)
                .font(.headline)
            
            Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 130, alignment: .leading)
        .padding(AppTheme.Spacing.m)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

#Preview {
    InventoryListView()
}
