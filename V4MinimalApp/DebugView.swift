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
        
        VStack(spacing: 12) {
            
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
        .padding(.horizontal)
        .frame(maxWidth: 480)
    }
}

