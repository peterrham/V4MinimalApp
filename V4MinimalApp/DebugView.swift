//
//  DebugView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//

import SwiftUI

struct DebugView: View {
    @EnvironmentObject var inventoryStore: InventoryStore
    @State private var isShowingShareSheet = false
    @State private var tidyResult: String?

    @StateObject private var googleSignInManager = GoogleSignInManager(clientID: "748381179204-hp1qqcpa5jr929nj0hs6sou0sb6df60a.apps.googleusercontent.com")

    var body: some View {
        ScrollView {
        Card {
            VStack(spacing: 12) {

                // Guided Recording - motion-coached video capture
                NavigationLink(value: SettingsPage.guidedRecording) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "video.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.red)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Guided Recording")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Motion-coached room video capture")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Debug Options - Tap tests, toggles
                NavigationLink(value: SettingsPage.debugOptions) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "ladybug.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Debug Options")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Button tests, toggles, diagnostics")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Pipeline Debug - Compare detection approaches
                NavigationLink(value: SettingsPage.pipelineDebug) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                .font(.system(size: 20))
                                .foregroundStyle(.green)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pipeline Debug")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Compare YOLO/Gemini/Hybrid pipelines")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Photo Queue Debug - Queue stats, session history
                NavigationLink(value: SettingsPage.photoQueueDebug) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "photo.stack.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.purple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Photo Queue Debug")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Queue stats, session history")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Audio Recognition - Old speech recognition screen
                NavigationLink(value: SettingsPage.audioRecognition) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "waveform")
                                .font(.system(size: 20))
                                .foregroundStyle(.purple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Audio Recognition")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Speech-to-text with live transcription")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // OpenAI Chat - Talk to GPT
                NavigationLink(value: SettingsPage.openAIChat) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.teal.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.system(size: 20))
                                .foregroundStyle(.teal)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Talk to OpenAI")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Chat with GPT-4o-mini via streaming")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // OpenAI Realtime - Voice conversation with GPT-4o
                NavigationLink(value: SettingsPage.openAIRealtime) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.cyan.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "waveform.badge.mic")
                                .font(.system(size: 20))
                                .foregroundStyle(.cyan)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("OpenAI Realtime")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Voice conversation with GPT-4o Realtime")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Network Diagnostics - Featured Entry
                NavigationLink(value: SettingsPage.networkDiagnostics) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.primary.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "network")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.Colors.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Network Diagnostics")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Test connectivity to debug server")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Audio Diagnostics - Test microphone
                NavigationLink(value: SettingsPage.audioDiagnostics) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.pink.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "mic.badge.xmark")
                                .font(.system(size: 20))
                                .foregroundStyle(.pink)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Audio Diagnostics")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("Test microphone and permissions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.vertical, 4)

                // Tidy Database
                Button {
                    tidyResult = inventoryStore.tidyDatabase()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 20))
                                .foregroundStyle(.purple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tidy Database")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text(tidyResult ?? "Remove bad items, auto-assign rooms")
                                .font(.caption)
                                .foregroundStyle(tidyResult != nil ? .green : .secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.vertical, 4)

                Button("Print To Log") {
                    appBootLog.debugWithContext("printing to log")
                }.buttonStyle(UnifiedButtonStyle())

                Button("Force Refresh Token") {
                    googleSignInManager.refreshAccessToken(reason: "debug-force-button") { result in
                        switch result {
                        case .success(let token):
                            appBootLog.infoWithContext("[Debug] Force refresh succeeded. token prefix=\(token.prefix(12))…")
                        case .failure(let error):
                            appBootLog.errorWithContext("[Debug] Force refresh failed: \(error.localizedDescription)")
                        }
                    }
                }
                .buttonStyle(UnifiedButtonStyle())

                Button("Enable 30s Proactive Refresh (Test Mode)") {
                    googleSignInManager.enableFixedRefreshInterval(seconds: 30)
                }
                .buttonStyle(UnifiedButtonStyle())

                Button("Disable Fixed Refresh") {
                    googleSignInManager.disableFixedRefreshInterval()
                }
                .buttonStyle(UnifiedButtonStyle())

                NavigationLink(value: SettingsPage.googleSignIn) {
                    Text("GoogleSignInView")
                        .unifiedNavLabel()
                }

                Button("Copy sqlite") {
                    isShowingShareSheet = true
                }
                .buttonStyle(UnifiedButtonStyle())
                // Present the document picker
                .sheet(isPresented:  $isShowingShareSheet) {
                    // Present the share sheet
                    ShareSheet(activityItems: [sqlLitePathURL])
                }

                // NavigationLink(destination: GoogleAuthenticatorView()) {
                // NavigationLink(destination: GoogleSheetWriterView()) {
                NavigationLink(value: SettingsPage.googleAuthSafari) {
                    Text("Write Google Sheet")
                        .unifiedNavLabel()
                }
                NavigationLink(value: SettingsPage.deleteAllText) {
                    Text("DeleteAllRecognizedTextView")
                        .unifiedNavLabel()
                }
                NavigationLink(value: SettingsPage.debugExportCSV) {
                    Text("ExportToCSVView")
                        .unifiedNavLabel()
                }
                NavigationLink(value: SettingsPage.textFileSharer) {
                    Text("TextFileSharerView")
                        .unifiedNavLabel()
                }
                NavigationLink(value: SettingsPage.textFileCreator) {
                    Text("TextFileCreatorView")
                        .unifiedNavLabel()
                }
                NavigationLink(value: SettingsPage.secondView) {
                    Text("Go to Second Page")
                        .unifiedNavLabel()
                }
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: 480)
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}
