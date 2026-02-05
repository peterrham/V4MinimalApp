//
//  SettingsView.swift
//  V4MinimalApp
//
//  Home Inventory - Settings View
//

import SwiftUI
import GoogleSignIn

enum SettingsPage: String, Hashable, Codable {
    // Settings pages
    case homes, rooms, backup, cameraSettings, exportCSV
    case inventoryTable, normalization, debugView, apiLogs, evaluation
    // Debug subpages
    case guidedRecording, debugOptions, pipelineDebug, photoQueueDebug, audioRecognition, audioDiagnostics
    case openAIChat, openAIRealtime, networkDiagnostics
    case googleSignIn, googleAuthSafari, deleteAllText
    case debugExportCSV, textFileSharer, textFileCreator, secondView
    case uiExerciser
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var autoSync = true
    @State private var aiConfidenceThreshold = 0.7
    @AppStorage("developerMode") private var developerMode = false
    @State private var showingSignOut = false
    @State private var isSignedIn = GIDSignIn.sharedInstance.currentUser != nil
    // Navigation path - DO NOT persist to avoid type mismatch crashes
    // Bug: SwiftUI.AnyNavigationPath.Error.comparisonTypeMismatch when restoring stale paths
    @State private var path: [SettingsPage] = []

    init() {
        // Clear any stale navigation path data on init
        UserDefaults.standard.removeObject(forKey: "settingsNavPath")
    }

    var currentUser: GIDGoogleUser? {
        isSignedIn ? GIDSignIn.sharedInstance.currentUser : nil
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                    NavigationLink(value: SettingsPage.homes) {
                        Label("Manage Homes", systemImage: "house.fill")
                    }

                    NavigationLink(value: SettingsPage.rooms) {
                        Label("Manage Rooms", systemImage: "door.left.hand.open")
                    }

                    Toggle(isOn: $autoSync) {
                        Label("Auto-Sync to Google Sheets", systemImage: "arrow.triangle.2.circlepath")
                    }

                    NavigationLink(value: SettingsPage.backup) {
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
                    NavigationLink(value: SettingsPage.cameraSettings) {
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
                    NavigationLink(value: SettingsPage.exportCSV) {
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
                        NavigationLink(value: SettingsPage.inventoryTable) {
                            Label("Inventory Table", systemImage: "tablecells")
                        }

                        NavigationLink(value: SettingsPage.normalization) {
                            Label("Normalize Inventory", systemImage: "wand.and.stars")
                        }

                        NavigationLink(value: SettingsPage.debugView) {
                            Label("Debug View", systemImage: "ant.fill")
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            appBootLog.infoWithContext("[Nav] Debug View tapped, path=\(path)")
                        })

                        NavigationLink(value: SettingsPage.apiLogs) {
                            Label("API Logs", systemImage: "doc.plaintext")
                        }

                        NavigationLink(value: SettingsPage.evaluation) {
                            Label("Evaluation Harness", systemImage: "gauge.with.dots.needle.33percent")
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
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .homes: HomesManagementView()
                case .rooms: RoomsManagementView()
                case .backup: Text("Backup view placeholder")
                case .cameraSettings: CameraSettingsView()
                case .exportCSV: ExportToCSVView()
                case .inventoryTable: InventoryTableView()
                case .normalization: NormalizationView()
                case .debugView: DebugView()
                        .onAppear { appBootLog.infoWithContext("[Nav] DebugView appeared") }
                case .apiLogs: Text("API logs placeholder")
                case .evaluation: EvaluationView()
                case .guidedRecording: GuidedRecordingView()
                case .debugOptions: DebugOptionsView()
                case .pipelineDebug: PipelineDebugView()
                case .photoQueueDebug: PhotoQueueDebugView()
                case .audioRecognition: ContentView()
                case .openAIChat: OpenAIChatView()
                case .openAIRealtime: OpenAIRealtimeView()
                case .networkDiagnostics: NetworkDiagnosticsView()
                case .audioDiagnostics: AudioDiagnosticsView()
                case .googleSignIn: GoogleSignInView()
                case .googleAuthSafari: GoogleAuthenticateViaSafariView()
                case .deleteAllText: DeleteAllRecognizedTextView()
                case .debugExportCSV: ExportToCSVView()
                case .textFileSharer: TextFileSharerView()
                case .textFileCreator: TextFileCreatorView()
                case .secondView: SecondView()
                case .uiExerciser: UIExerciserView()
                }
            }
            .alert("Sign Out", isPresented: $showingSignOut) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    GIDSignIn.sharedInstance.signOut()
                    UserDefaults.standard.removeObject(forKey: "userSkippedAuth")
                    isSignedIn = false
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .debugScreenName("SettingsView")
        }
        // REMOVED: .onChange path persistence - caused SwiftUI.AnyNavigationPath.Error.comparisonTypeMismatch crashes
    }
}

#Preview {
    SettingsView()
}
