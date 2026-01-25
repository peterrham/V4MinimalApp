//
//  GoogleSignInView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//

import SwiftUI


struct GoogleSignInView: View {
    
    func googleSignInManager() -> GoogleSignInManager {
        return AuthManager.shared.googleSignInManager!
    }
    
    func signIn() {
        AuthManager.shared.googleSignInManager!.signIn()
    }
    
    func signOut() {
        AuthManager.shared.googleSignInManager!.signOut()
    }
    
    var body: some View {
        
        
        Button(action: signOut) {
            Text("Sign OUT")
        }
        .buttonStyle(PrimaryButtonStyle())
        
        Button("Append") {
           appBootLog.debugWithContext("Append")
            AppendLog().append(text: "abc")
        }
        .buttonStyle(PrimaryButtonStyle())
        
        Button(action: signIn) {
            Text("Sign In")
        }
        .buttonStyle(PrimaryButtonStyle())
        Button("createSpreadsheet") {
            googleSignInManager().createSpreadsheet()
        }.buttonStyle(PrimaryButtonStyle())
        Button("PopulateGoogleSheet") {
            
            var  client =  GoogleSheetsClient(inputAccessToken: googleSignInManager().user!.accessToken.tokenString)
           client.CopyToSheet(argSpreadsheetId: googleSignInManager().spreadsheetID)
        }.buttonStyle(PrimaryButtonStyle())
        
        Button("Disconect") {
            googleSignInManager().disconnect()
        }.buttonStyle(PrimaryButtonStyle())
        Button("FetchUserInfo") {
            googleSignInManager().fetchAndPrintUserInfo()
        }.buttonStyle(PrimaryButtonStyle())
        
    }
}
