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
    @State private var isSignedIn = GIDSignIn.sharedInstance.currentUser != nil

    var currentUser: GIDGoogleUser? {
        isSignedIn ? GIDSignIn.sharedInstance.currentUser : nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Account Section
                Section {
                    if let user = currentUser, let profile = user.profile {
                        HStack(spacing: AppTheme.Spacing.l) {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.Colors.primary.gradient)
                                    .frame(width: 56, height: 56)

                                if let imageUrl = profile.imageURL(withDimension: 120) {
                                    AsyncImage(url: imageUrl) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.white)
                                    }
                                    .frame(width: 56, height: 56)
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
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, AppTheme.Spacing.xs)
                    }
                } header: {
                    Text("Account")
                }

                // Sign Out / Sign In
                Section {
                    if currentUser != nil {
                        Button {
                            showingSignOut = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.body)
                                Text("Sign Out")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(AppTheme.Colors.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.xs)
                        }
                    } else {
                        Button {
                            AuthManager.shared.googleSignInManager?.signIn {
                                self.isSignedIn = GIDSignIn.sharedInstance.currentUser != nil
                            }
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.body)
                                Text("Sign In with Google")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(AppTheme.Colors.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.Spacing.xs)
                        }
                    }
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
                    isSignedIn = false
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
