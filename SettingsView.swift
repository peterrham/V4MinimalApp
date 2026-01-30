//
//  SettingsView.swift
//  V4MinimalApp
//
//  Home Inventory - Settings View
//

import SwiftUI
import GoogleSignIn

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var autoSync = true
    @State private var aiConfidenceThreshold = 0.7
    @State private var developerMode = false
    @State private var showingSignOut = false

    var currentUser = GIDSignIn.sharedInstance.currentUser
    
    var body: some View {
        NavigationStack {
            Form {
                // Account Section
                Section {
                    if let user = currentUser, let profile = user.profile {
                        HStack(spacing: AppTheme.Spacing.m) {
                            // Profile Image
                            ZStack {
                                Circle()
                                    .fill(AppTheme.Colors.primary.gradient)
                                    .frame(width: 60, height: 60)
                                
                                if let imageUrl = profile.imageURL(withDimension: 120) {
                                    AsyncImage(url: imageUrl) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.white)
                                        .font(.title2)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.name)
                                    .font(.headline)
                                
                                Text(profile.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.s)
                        
                        Button(role: .destructive) {
                            showingSignOut = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        NavigationLink {
                            ContentView()
                        } label: {
                            Label("Sign In with Google", systemImage: "person.circle.fill")
                        }
                    }
                } header: {
                    Text("Account")
                }
                
                // Sync & Backup
                Section {
                    Toggle(isOn: $autoSync) {
                        Label("Auto-Sync to Google Sheets", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    NavigationLink {
                        Text("Backup view placeholder")
                    } label: {
                        Label("Backup & Restore", systemImage: "cloud.fill")
                    }
                    
                    Button {
                        // Manual sync
                    } label: {
                        Label("Sync Now", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("Data & Sync")
                } footer: {
                    Text("Automatically backup your inventory to Google Sheets")
                }
                
                // Camera & Detection Settings
                Section {
                    NavigationLink {
                        CameraSettingsView()
                    } label: {
                        Label("Camera & Detection", systemImage: "camera.aperture")
                    }

                    Toggle(isOn: .constant(true)) {
                        Label("Voice Annotations", systemImage: "mic.fill")
                    }
                } header: {
                    Text("AI Recognition")
                } footer: {
                    Text("Configure camera resolution, detection speed, and enrichment")
                }
                
                // Export Options
                Section {
                    NavigationLink {
                        ExportToCSVView()
                    } label: {
                        Label("Export to CSV", systemImage: "doc.text")
                    }
                    
                    Button {
                        // Export to PDF
                    } label: {
                        Label("Generate Insurance Report", systemImage: "doc.richtext")
                    }
                    
                    Button {
                        // Share all data
                    } label: {
                        Label("Share Inventory", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Export & Share")
                }
                
                // Developer Options
                Section {
                    Toggle(isOn: $developerMode) {
                        Label("Developer Mode", systemImage: "hammer.fill")
                    }
                    
                    if developerMode {
                        NavigationLink {
                            DebugView()
                        } label: {
                            Label("Debug View", systemImage: "ant.fill")
                        }
                        
                        NavigationLink {
                            Text("API logs placeholder")
                        } label: {
                            Label("API Logs", systemImage: "doc.plaintext")
                        }
                    }
                } header: {
                    Text("Advanced")
                }
                
                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://support.apple.com")!) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                    
                    Link(destination: URL(string: "https://www.apple.com/legal/privacy/")!) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Sign Out", isPresented: $showingSignOut) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    GIDSignIn.sharedInstance.signOut()
                    appState.checkAuthStatus()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
}

#Preview {
    SettingsView()
}
