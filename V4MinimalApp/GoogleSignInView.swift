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
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
        
        Button(action: signIn) {
            Text("Sign In")
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        Button("createSpreadsheet") {
            googleSignInManager.createSpreadsheet()
        }
        Button("PopulateGoogleSheet") {
            
            var  client =  GoogleSheetsClient(inputAccessToken: googleSignInManager.user!.accessToken.tokenString)
           client.CopyToSheet(argSpreadsheetId: googleSignInManager.spreadsheetID)
        }
        Button("Disconect") {
            googleSignInManager.disconnect()
        }
        Button("FetchUserInfo") {
            googleSignInManager.fetchAndPrintUserInfo()
        }
        
    }
}
