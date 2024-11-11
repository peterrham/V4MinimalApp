//
//  DebugView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//

import SwiftUI

struct DebugView: View {
    
    @StateObject private var googleSignInManager = GoogleSignInManager(clientID: "748381179204-hp1qqcpa5jr929nj0hs6sou0sb6df60a.apps.googleusercontent.com")
    
    var body: some View {
        
        VStack(spacing: 20) {
            
            // GoogleSignInView
            
            NavigationLink(destination: GoogleSignInView().environmentObject(googleSignInManager)) {
                Text("GoogleSignInView")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
             
            // NavigationLink(destination: GoogleAuthenticatorView()) {
            // NavigationLink(destination: GoogleSheetWriterView()) {
            NavigationLink(destination: GoogleAuthenticateViaSafariView()) {
                Text("Write Google Sheet")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            NavigationLink(destination: DeleteAllRecognizedTextView()) {
                Text("DeleteAllRecognizedTextView")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            NavigationLink(destination: ExportToCSVView()) {
                Text("ExportToCSVView")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            NavigationLink(destination: TextFileSharerView()) {
                Text("TextFileSharerView")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            NavigationLink(destination: TextFileCreatorView()) {
                Text("TextFileCreatorView")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            NavigationLink(destination: SecondView()) {
                Text("Go to Second Page")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}
