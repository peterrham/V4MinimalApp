//
//  HomeView.swift
//  V4MinimalApp
//
//  Home Inventory - Dashboard View
//

import SwiftUI

struct HomeView: View {
    @State private var items: [InventoryItem] = InventoryItem.sampleItems
    @State private var rooms: [Room] = Room.sampleRooms
    @State private var showingScanView = false
    
    var totalValue: Double {
        items.reduce(0) { sum, item in
            sum + (item.purchasePrice ?? item.estimatedValue ?? 0)
        }
    }
    
    var itemCount: Int {
        items.count
    }
    
    var roomCount: Int {
        Set(items.map { $0.room }).count
    }
    
    var recentItems: [InventoryItem] {
        Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(6))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    // Welcome Header
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                        Text("Welcome Back")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        
                        Text("Home Inventory")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.l)
                    .padding(.top, AppTheme.Spacing.m)
                    
                    // Primary Scan Button
                    Button {
                        showingScanView = true
                    } label: {
                        HStack(spacing: AppTheme.Spacing.m) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Scan Room")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text("Add items with AI")
                                    .font(.caption)
                                    .opacity(0.9)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                        }
                        .foregroundColor(.white)
                        .padding(AppTheme.Spacing.l)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .fill(AppTheme.Colors.primary.gradient)
                                .shadow(color: AppTheme.Colors.primary.opacity(0.4), radius: 12, y: 6)
                        )
                    }
                    .padding(.horizontal, AppTheme.Spacing.l)
                    
                    // Statistics Cards
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.m) {
                            StatCard(
                                icon: "cube.box.fill",
                                value: "\(itemCount)",
                                label: "Items",
                                color: AppTheme.Colors.primary
                            )
                            
                            StatCard(
                                icon: "dollarsign.circle.fill",
                                value: String(format: "$%.0f", totalValue),
                                label: "Total Value",
                                color: AppTheme.Colors.success
                            )
                            
                            StatCard(
                                icon: "door.left.hand.open",
                                value: "\(roomCount)",
                                label: "Rooms",
                                color: AppTheme.Colors.warning
                            )
                        }
                        .padding(.horizontal, AppTheme.Spacing.l)
                    }
                    
                    // Recent Items
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                        HStack {
                            Text("Recent Items")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            NavigationLink {
                                InventoryListView()
                            } label: {
                                Text("See All")
                                    .font(.callout)
                                    .foregroundStyle(AppTheme.Colors.primary)
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.l)
                        
                        if recentItems.isEmpty {
                            Card {
                                VStack(spacing: AppTheme.Spacing.m) {
                                    Image(systemName: "tray.fill")
                                        .font(.system(size: 50))
                                        .foregroundStyle(.secondary)
                                    
                                    Text("No items yet")
                                        .font(.headline)
                                    
                                    Text("Tap 'Scan Room' to start adding items")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppTheme.Spacing.xl)
                            }
                            .padding(.horizontal, AppTheme.Spacing.l)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: AppTheme.Spacing.m),
                                GridItem(.flexible(), spacing: AppTheme.Spacing.m)
                            ], spacing: AppTheme.Spacing.m) {
                                ForEach(recentItems) { item in
                                    ItemCardCompact(item: item)
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.l)
                        }
                    }
                    
                    // Rooms Section
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                        Text("Your Rooms")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal, AppTheme.Spacing.l)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.Spacing.m) {
                                ForEach(rooms) { room in
                                    RoomCard(room: room, itemCount: itemsInRoom(room.name))
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.l)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .background(AppTheme.Colors.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingScanView) {
                CameraScanView()
            }
        }
    }
    
    private func itemsInRoom(_ roomName: String) -> Int {
        items.filter { $0.room == roomName }.count
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: AppTheme.Spacing.m) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
        .padding(AppTheme.Spacing.l)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Item Card Compact

struct ItemCardCompact: View {
    let item: InventoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            // Photo or placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.category.color.opacity(0.1))
                
                Image(systemName: item.category.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(item.category.color)
            }
            .frame(height: 100)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                Text(item.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(item.displayValue)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.Colors.success)
            }
            .padding(.horizontal, AppTheme.Spacing.s)
            .padding(.bottom, AppTheme.Spacing.s)
        }
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}



#Preview("Home View") {
    HomeView()
}

#Preview("Empty State") {
    HomeView()
}
