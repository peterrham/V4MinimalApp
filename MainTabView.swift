//
//  MainTabView.swift
//  V4MinimalApp
//
//  Created for Home Inventory App
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    private let tabs: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("camera.fill", "Scan"),
        ("list.bullet.rectangle", "Inventory"),
        ("gear", "Settings")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch selectedTab {
                case 0: HomeView(selectedTab: $selectedTab)
                case 1: CameraScanView()
                case 2: InventoryListView()
                case 3: SettingsView()
                default: HomeView(selectedTab: $selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Custom tab bar
            HStack(spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    Button {
                        selectedTab = index
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: tabs[index].icon)
                                .font(.system(size: 26, weight: .medium))

                            Text(tabs[index].label)
                                .font(.system(size: 13, weight: selectedTab == index ? .semibold : .medium))
                        }
                        .foregroundStyle(selectedTab == index ? AppTheme.Colors.primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, safeAreaBottom > 0 ? safeAreaBottom : 12)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }
}

#Preview {
    MainTabView()
        .environmentObject(InventoryStore())
}
