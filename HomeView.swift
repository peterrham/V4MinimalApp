//
//  HomeView.swift
//  V4MinimalApp
//
//  Home Inventory - Dashboard View
//

import SwiftUI
import UIKit
import AudioToolbox
import os.log

struct HomeView: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    @Binding var selectedTab: Int
    @AppStorage("showHomeDebugBar") private var showHomeDebugBar = false
    @State private var rooms: [Room] = Room.sampleRooms
    @State private var showingScanView = false
    @State private var debugTapCount = 0
    @State private var seeAllTapCount = 0
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    var totalValue: Double {
        inventoryStore.currentHomeItems.reduce(0) { sum, item in
            sum + (item.purchasePrice ?? item.estimatedValue ?? 0)
        }
    }

    var itemCount: Int {
        inventoryStore.currentHomeItems.count
    }

    var roomCount: Int {
        Set(inventoryStore.currentHomeItems.map { $0.room }).filter { !$0.isEmpty }.count
    }

    var recentItems: [InventoryItem] {
        Array(inventoryStore.currentHomeItems.sorted { $0.createdAt > $1.createdAt }.prefix(6))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // DEBUG BAR — Outside ScrollView (toggled from Debug Options)
                if showHomeDebugBar {
                    VStack(spacing: 4) {
                        Text("DEBUG: tab=\(selectedTab) | dbg=\(debugTapCount) | see=\(seeAllTapCount)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))

                        HStack(spacing: 8) {
                            // Test button: switches to Inventory tab
                            Button {
                                debugTapCount += 1
                                AudioServicesPlaySystemSound(1104)
                                haptic.impactOccurred()
                                os_log("DEBUG BAR: Go to Inventory tapped #%d, setting tab=2", debugTapCount)
                                selectedTab = 2
                            } label: {
                                Text("Go to Inventory (\(debugTapCount))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(debugTapCount % 2 == 0 ? Color.red : Color.green)
                                    )
                            }

                            // Test button: just confirms taps work
                            Button {
                                AudioServicesPlaySystemSound(1104)
                                haptic.impactOccurred()
                                os_log("DEBUG BAR: Tap test OK")
                            } label: {
                                Text("Tap Test")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.blue)
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.85))
                }

                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: AppTheme.Spacing.xl) {
                            // Welcome Header
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                                HStack {
                                    Text("Welcome Back")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    HomePickerMenu()
                                }

                                Text(inventoryStore.currentHome?.name ?? "Home Inventory")
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

                            // Recent Items
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
                                Text("Recent Items")
                                    .font(.title2)
                                    .fontWeight(.bold)
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
                                            ItemCardCompact(
                                                item: item,
                                                displayTitle: InventoryItem.disambiguatedTitle(for: item, in: recentItems)
                                            )
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

                            // Extra space so content doesn't hide behind floating button
                            Spacer(minLength: 80)
                        }
                    }

                    // Floating "See All" button — OUTSIDE ScrollView for reliable taps
                    Button {
                        seeAllTapCount += 1
                        haptic.impactOccurred()
                        AudioServicesPlaySystemSound(1104)
                        os_log("SEE ALL (floating) tapped #%d — switching to tab 2", seeAllTapCount)
                        selectedTab = 2
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.body)
                                .fontWeight(.semibold)
                            Text(showHomeDebugBar ? "See All \(itemCount) Items (\(seeAllTapCount))" : "See All \(itemCount) Items")
                                .font(.headline)
                                .fontWeight(.bold)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 24)
                        .background(
                            Capsule()
                                .fill(AppTheme.Colors.primary)
                                .shadow(color: AppTheme.Colors.primary.opacity(0.4), radius: 8, y: 4)
                        )
                    }
                    .padding(.bottom, 12)
                }
            }
            .background(AppTheme.Colors.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingScanView) {
                CameraScanView()
            }
        }
        .onAppear {
            haptic.prepare()
        }
    }

    private func itemsInRoom(_ roomName: String) -> Int {
        inventoryStore.currentHomeItems.filter { $0.room == roomName }.count
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
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.xl)
        .padding(.horizontal, AppTheme.Spacing.m)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Item Card Compact

struct ItemCardCompact: View {
    let item: InventoryItem
    var displayTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
            // Photo or placeholder
            if let photoName = item.photos.first,
               let uiImage = UIImage(contentsOfFile: InventoryStore.photoURL(for: photoName).path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(item.category.color.opacity(0.1))

                    Image(systemName: item.category.icon)
                        .font(.system(size: 44))
                        .foregroundStyle(item.category.color)
                }
                .frame(height: 120)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle ?? item.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(item.displaySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(item.displayValue)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.Colors.success)
            }
            .padding(.horizontal, AppTheme.Spacing.m)
            .padding(.bottom, AppTheme.Spacing.m)
        }
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.cornerRadius)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}



#Preview("Home View") {
    HomeView(selectedTab: .constant(0))
        .environmentObject(InventoryStore())
}

#Preview("Empty State") {
    HomeView(selectedTab: .constant(0))
        .environmentObject(InventoryStore())
}
