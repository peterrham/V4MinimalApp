//
//  GoogleSignInView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//

import SwiftUI


struct GoogleSignInView: View {
    
    @EnvironmentObject var googleSignInManager: GoogleSignInManager
    
    
    func signIn() {
        googleSignInManager.signIn()
    }
    
    var body: some View {
  
        Button("Append") {
           print("Append")
            AppendLog().append()
        }
        .buttonStyle(PrimaryButtonStyle())
        
        Button(action: signIn) {
            Text("Sign In")
        }
        .buttonStyle(PrimaryButtonStyle())
        Button("createSpreadsheet") {
            googleSignInManager.createSpreadsheet()
        }.buttonStyle(PrimaryButtonStyle())
        Button("PopulateGoogleSheet") {
            
            var  client =  GoogleSheetsClient(inputAccessToken: googleSignInManager.user!.accessToken.tokenString)
           client.CopyToSheet(argSpreadsheetId: googleSignInManager.spreadsheetID)
        }.buttonStyle(PrimaryButtonStyle())
        
        Button("Disconect") {
            googleSignInManager.disconnect()
        }.buttonStyle(PrimaryButtonStyle())
        Button("FetchUserInfo") {
            googleSignInManager.fetchAndPrintUserInfo()
        }.buttonStyle(PrimaryButtonStyle())
        
    }
}
