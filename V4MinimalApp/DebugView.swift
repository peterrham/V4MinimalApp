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
        
        VStack(spacing: 20) {
            
            Button("Print To Log") {
                appBootLog.debugWithContext("printing to log")
            }.buttonStyle(PrimaryButtonStyle())
            
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
            .buttonStyle(PrimaryButtonStyle())
            
            Button("Enable 30s Proactive Refresh (Test Mode)") {
                googleSignInManager.enableFixedRefreshInterval(seconds: 30)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button("Disable Fixed Refresh") {
                googleSignInManager.disableFixedRefreshInterval()
            }
            .buttonStyle(PrimaryButtonStyle())
                          
            NavigationLink(destination: GoogleSignInView()) {
                Text("GoogleSignInView")
                    .buttonStyle(PrimaryButtonStyle())
            }
            
            Button("Copy sqlite") {
                isShowingShareSheet = true
            }
            .buttonStyle(PrimaryButtonStyle())
            // Present the document picker
            .sheet(isPresented:  $isShowingShareSheet) {
                // Present the share sheet
                ShareSheet(activityItems: [sqlLitePathURL])
            }
             
            // NavigationLink(destination: GoogleAuthenticatorView()) {
            // NavigationLink(destination: GoogleSheetWriterView()) {
            NavigationLink(destination: GoogleAuthenticateViaSafariView()) {
                Text("Write Google Sheet")
                    .buttonStyle(PrimaryButtonStyle())
            }
            NavigationLink(destination: DeleteAllRecognizedTextView()) {
                Text("DeleteAllRecognizedTextView")
                    .buttonStyle(PrimaryButtonStyle())
            }
            NavigationLink(destination: ExportToCSVView()) {
                Text("ExportToCSVView")
                    .buttonStyle(PrimaryButtonStyle())
            }
            NavigationLink(destination: TextFileSharerView()) {
                Text("TextFileSharerView")
                    .buttonStyle(PrimaryButtonStyle())
            }
            NavigationLink(destination: TextFileCreatorView()) {
                Text("TextFileCreatorView")
                    .buttonStyle(PrimaryButtonStyle())
            }
            NavigationLink(destination: SecondView()) {
                Text("Go to Second Page")
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

