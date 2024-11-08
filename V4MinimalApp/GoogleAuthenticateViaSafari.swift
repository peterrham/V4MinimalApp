//
//  GoogleAuthenticatorView 2.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/7/24.
//

import SwiftUI
import SafariServices



struct GoogleAuthenticateViaSafariView: View {
    @State private var accessToken: String?
    private let clientID = "748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok.apps.googleusercontent.com"
    // private let clientID = "com.googleusercontent.apps.748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok"
    // private let redirectURI = "com.googleusercontent.apps.748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok:/oauth2redirect"
    private let redirectURI = "com.googleusercontent.apps.748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok:/oauth2redirect"
    // com.googleusercontent.apps.748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok:/oauth2redirect"
    // = "a"
    // "www.google.com" // com.googleusercontent.apps.748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok:/oauth2redirect

    var body: some View {
        VStack {
            if let accessToken = accessToken {
                Text("Access Token: \(accessToken)")
            } else {
                Button(action: startGoogleSignIn) {
                    Text("Sign in with Google")
                }
            }
        }
    }

    private func startGoogleSignIn() {
        let authURL = getAuthorizationURL()
        let safariVC = SFSafariViewController(url: authURL)
        logWithTimestamp(authURL.absoluteString)
        UIApplication.shared.windows.first?.rootViewController?.present(safariVC, animated: true, completion: nil)
    }

    private func getAuthorizationURL() -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/userinfo.email")
        ]
        return components.url!
    }
}


// https://accounts.google.com/o/oauth2/v2/auth?client_id=com.googleusercontent.apps.1234567890-abcdefg&redirect_uri=com.googleusercontent.apps.1234567890-abcdefg%3A%2Foauth2redirect&response_type=code&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.email

