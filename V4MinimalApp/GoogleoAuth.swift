//
//  GoogleoAuth.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/6/24.
//

import Foundation

func getOAuthToken(completion: @escaping (String?) -> Void) {
    // Set up your OAuth endpoint and credentials
    let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    
    var request = URLRequest(url: tokenURL)
    request.httpMethod = "POST"
    
    let params: [String: String] = [
        "client_id": "748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok.apps.googleusercontent.com",
        // "client_secret": "YOUR_CLIENT_SECRET",
        "refresh_token": "YOUR_REFRESH_TOKEN",
        "grant_type": "refresh_token"
       // "grant_type": "authorization_token"
    ]
    
    request.httpBody = params
        .compactMap { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        .data(using: .utf8)
    
    request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data = data, error == nil else {
            completion(nil)
            return
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           // logWithTimestamp(json)
           let token = json["access_token"] as? String {
            logWithTimestamp(token)
            completion(token)
        } else {
            completion(nil)
        }
    }.resume()
}
