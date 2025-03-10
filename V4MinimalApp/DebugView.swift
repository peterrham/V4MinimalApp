//
//  DebugView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//

import SwiftUI

struct DebugView: View {
    
    @State private var isShowingShareSheet = false
    
   // @StateObject private var googleSignInManager = GoogleSignInManager(clientID: "748381179204-hp1qqcpa5jr929nj0hs6sou0sb6df60a.apps.googleusercontent.com")
    
    var body: some View {
        
        VStack(spacing: 20) {
            
            // GoogleSignInView
            
           // NavigationLink(destination: GoogleSignInView().environmentObject(googleSignInManager).environment(\.managedObjectContext, // DynamicPersistenceController.shared.container.viewContext)) {
            
            Button("Create Image") {
            }.buttonStyle(PrimaryButtonStyle())
                          
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
