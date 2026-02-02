//
//  DebugView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//

import SwiftUI

struct DebugView: View {
    
    @State private var isShowingShareSheet = false
    
    @StateObject private var googleSignInManager = GoogleSignInManager(clientID: "748381179204-hp1qqcpa5jr929nj0hs6sou0sb6df60a.apps.googleusercontent.com")
    
    var body: some View {
        ScrollView {
        Card {
            VStack(spacing: 12) {

                // Guided Recording - motion-coached video capture
                NavigationLink(destination: GuidedRecordingView()) {
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
                NavigationLink(destination: DebugOptionsView()) {
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

                // Network Diagnostics - Featured Entry
                NavigationLink(destination: NetworkDiagnosticsView()) {
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
                              
                NavigationLink(destination: GoogleSignInView()) {
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
                NavigationLink(destination: GoogleAuthenticateViaSafariView()) {
                    Text("Write Google Sheet")
                        .unifiedNavLabel()
                }
                NavigationLink(destination: DeleteAllRecognizedTextView()) {
                    Text("DeleteAllRecognizedTextView")
                        .unifiedNavLabel()
                }
                NavigationLink(destination: ExportToCSVView()) {
                    Text("ExportToCSVView")
                        .unifiedNavLabel()
                }
                NavigationLink(destination: TextFileSharerView()) {
                    Text("TextFileSharerView")
                        .unifiedNavLabel()
                }
                NavigationLink(destination: TextFileCreatorView()) {
                    Text("TextFileCreatorView")
                        .unifiedNavLabel()
                }
                NavigationLink(destination: SecondView()) {
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

