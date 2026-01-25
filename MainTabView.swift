//
//  MainTabView.swift
//  V4MinimalApp
//
//  Created for Home Inventory App
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Dashboard
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            // Camera Scan
            CameraScanView()
                .tabItem {
                    Label("Scan", systemImage: "camera.fill")
                }
                .tag(1)
            
            // Inventory List
            InventoryListView()
                .tabItem {
                    Label("Inventory", systemImage: "list.bullet.rectangle")
                }
                .tag(2)
            
            // Settings
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(AppTheme.Colors.primary)
    }
}

#Preview {
    MainTabView()
}
