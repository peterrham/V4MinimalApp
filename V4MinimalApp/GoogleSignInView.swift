//
//  GoogleSignInView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//

import SwiftUI


struct GoogleSignInView: View {
    @EnvironmentObject var appState: AppState

    func googleSignInManager() -> GoogleSignInManager {
        return AuthManager.shared.googleSignInManager!
    }

    func signIn() {
        AuthManager.shared.googleSignInManager!.signIn {
            self.appState.checkAuthStatus()
        }
    }

    func signOut() {
        AuthManager.shared.googleSignInManager!.signOut()
        appState.checkAuthStatus()
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: signOut) {
                Text("Sign OUT")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(UnifiedButtonStyle())

            Button(action: {
                appBootLog.debugWithContext("Append")
                AppendLog().append(text: "abc")
            }) {
                Text("Append")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(UnifiedButtonStyle())

            Button(action: signIn) {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(UnifiedButtonStyle())

            Button(action: {
                googleSignInManager().createSpreadsheet()
            }) {
                Text("createSpreadsheet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(UnifiedButtonStyle())

            Button(action: {
                var client = GoogleSheetsClient(inputAccessToken: googleSignInManager().user!.accessToken.tokenString)
                client.CopyToSheet(argSpreadsheetId: googleSignInManager().spreadsheetID)
            }) {
                Text("PopulateGoogleSheet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(UnifiedButtonStyle())

            Button(action: {
                googleSignInManager().disconnect()
            }) {
                Text("Disconnect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(UnifiedButtonStyle())

            Button(action: {
                googleSignInManager().fetchAndPrintUserInfo()
            }) {
                Text("FetchUserInfo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(UnifiedButtonStyle())

            NavigationLink(destination: ContentView()) {
                Text("Go to Audio Listening")
                    .unifiedNavLabel()
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: 480)
    }
}

