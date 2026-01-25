//
//  GoogleAuthenticatorView.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/7/24.
//

import SwiftUI
import WebKit

let clientID = "748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok.apps.googleusercontent.com"
let redirectURI = "com.googleusercontent.apps.748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok:/oauth2redirect" // Custom URI scheme registered in your project
let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
let tokenEndpoint = "https://oauth2.googleapis.com/token"

struct WebView: UIViewRepresentable {
    let url: URL
    var onAuthorizationCodeReceived: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "myapp", let code = extractCode(from: url) {
                parent.onAuthorizationCodeReceived(code)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func extractCode(from url: URL) -> String? {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return components?.queryItems?.first { $0.name == "code" }?.value
        }
    }
}


struct GoogleAuthenticatorView: View {
    @State private var authorizationCode: String?
    @State private var accessToken: String?
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                if let accessToken = accessToken {
                    // Success State
                    ScrollView {
                        VStack(spacing: 24) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 70))
                                .foregroundStyle(.green.gradient)
                                .padding(.top, 40)
                            
                            Text("Authentication Successful")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("You've been successfully authenticated")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            GroupBox {
                                ScrollView {
                                    Text(accessToken)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                }
                                .frame(height: 120)
                            } label: {
                                Label("Access Token", systemImage: "key.fill")
                                    .font(.headline)
                            }
                            .padding(.horizontal)
                            .padding(.top, 20)
                            
                            Spacer()
                        }
                    }
                } else if authorizationCode == nil {
                    // WebView for Authentication
                    VStack(spacing: 0) {
                        // Top Bar
                        VStack(spacing: 8) {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            
                            Text("Secure Authentication")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.regularMaterial)
                        
                        // WebView
                        WebView(url: getAuthorizationURL()) { code in
                            self.authorizationCode = code
                            requestAccessToken(authorizationCode: code) { token in
                                if let token = token {
                                    withAnimation {
                                        self.accessToken = token
                                    }
                                } else {
                                    self.errorMessage = "Failed to retrieve access token"
                                    self.showError = true
                                    self.authorizationCode = nil
                                }
                            }
                        }
                    }
                } else {
                    // Loading State
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 8)
                        
                        Text("Authenticating...")
                            .font(.headline)
                        
                        Text("Please wait while we verify your credentials")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
            }
            .navigationTitle("Google OAuth")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Authentication Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func getAuthorizationURL() -> URL {
        var components = URLComponents(string: authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/userinfo.email")
        ]
        return components.url!
    }

    private func requestAccessToken(authorizationCode: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: tokenEndpoint) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": authorizationCode,
            "redirect_uri": redirectURI
        ]
        let bodyString = bodyParameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                DispatchQueue.main.async {
                    completion(accessToken)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }.resume()
    }
}
