//
//  AuthManager.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/13/24.
//

import Foundation
import GoogleSignIn


class AuthManager {
    static let shared = AuthManager()
    
    private let GoogleAuthClientID: String = "748381179204-hp1qqcpa5jr929nj0hs6sou0sb6df60a.apps.googleusercontent.com"
    
    public var googleSignInManager: GoogleSignInManager?
    
    private init() {}
    
    // for some reason I think that this is a safer place to put this ....
    
    func initialize() {
        
        // init this singleton
        _ = GIDSignIn.sharedInstance
        
        googleSignInManager = GoogleSignInManager(clientID: GoogleAuthClientID)
        
        
        // Restore previous Google Sign-In session if available
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let error = error {
                print("No previous Google Sign-In session: \(error.localizedDescription)")
            } else if let user = user {
                print("Restored Google Sign-In session for user: \(user.profile?.name ?? "Unknown")")
                // Handle restored session (e.g., notify view model)
                
                print("Restored Token String: \(GIDSignIn.sharedInstance.currentUser!.accessToken.tokenString)")
            } else {
                print("No previous Google Sign-In session found.")
            }
        }
    }
    
    // Retrieve the access token securely
    func getAccessToken() -> String? {
        return GIDSignIn.sharedInstance.currentUser!.accessToken.tokenString
    }
    
    // Store tokens securely
    func saveAccessToken(token: String) {
        // KeychainService.set("googleAccessToken", value: token)
    }
    
    // Delete tokens if user signs out
    func clearTokens() {
        //  KeychainService.delete("googleAccessToken")
    }
}
