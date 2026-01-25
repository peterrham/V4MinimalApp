//
//  INTEGRATION_EXAMPLE.swift
//  V4MinimalApp
//
//  Quick integration examples for Live Object Detection
//

import SwiftUI

// MARK: - Example 1: Add to Main Menu

struct MainMenuWithLiveDetection: View {
    var body: some View {
        NavigationStack {
            List {
                // Your existing menu items...
                
                NavigationLink {
                    LiveObjectDetectionView()
                } label: {
                    Label("Live Object Detection", systemImage: "eye.fill")
                        .foregroundColor(.green)
                }
                
                // More menu items...
            }
            .navigationTitle("Home Inventory")
        }
    }
}

// MARK: - Example 2: Add Button to Existing Camera View

struct CameraScanViewWithLiveDetection: View {
    @State private var showLiveDetection = false
    
    var body: some View {
        ZStack {
            // Your existing camera view
            // CameraScanView()
            
            VStack {
                HStack {
                    Spacer()
                    
                    // Button to open live detection
                    Button {
                        showLiveDetection = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.title3)
                            Text("Live")
                                .font(.caption2)
                        }
                        .foregroundColor(.white)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(.green.gradient)
                                .shadow(color: .green.opacity(0.3), radius: 8)
                        )
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
        .sheet(isPresented: $showLiveDetection) {
            LiveObjectDetectionView()
        }
    }
}

// MARK: - Example 3: Tab Bar Integration

struct AppWithLiveDetectionTab: View {
    var body: some View {
        TabView {
            // Home tab
            Text("Home")
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            // Live Detection tab
            LiveObjectDetectionView()
                .tabItem {
                    Label("Live Scan", systemImage: "eye.fill")
                }
            
            // Settings tab
            Text("Settings")
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

// MARK: - Example 4: Quick Access Button

struct QuickLiveDetectionButton: View {
    @State private var showLiveDetection = false
    
    var body: some View {
        Button {
            showLiveDetection = true
        } label: {
            HStack {
                Image(systemName: "eye.fill")
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Object Detection")
                        .font(.headline)
                    Text("Stream & identify objects in real-time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showLiveDetection) {
            LiveObjectDetectionView()
        }
    }
}

// MARK: - Example 5: Dashboard Card

struct LiveDetectionDashboardCard: View {
    @State private var showLiveDetection = false
    
    var body: some View {
        Button {
            showLiveDetection = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "eye.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green.opacity(0.6))
                }
                
                Text("Live Detection")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Point your camera to identify objects in real-time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showLiveDetection) {
            LiveObjectDetectionView()
        }
    }
}

// MARK: - Previews

#Preview("Main Menu") {
    MainMenuWithLiveDetection()
}

#Preview("Quick Button") {
    QuickLiveDetectionButton()
        .padding()
}

#Preview("Dashboard Card") {
    LiveDetectionDashboardCard()
        .padding()
}
