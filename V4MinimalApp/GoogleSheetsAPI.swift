//
//  GoogleSheetsAPI.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//


import Foundation

struct GoogleSheetsAPI {
    let accessToken: String
    let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
    
    // Function to create a new Google Sheet (from previous example)
    func createSpreadsheet(title: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: baseURL) else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["properties": ["title": title]]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No Data", code: -2, userInfo: nil)))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let spreadsheetId = json["spreadsheetId"] as? String {
                    completion(.success(spreadsheetId))
                } else {
                    completion(.failure(NSError(domain: "Invalid Response", code: -3, userInfo: nil)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // New Function to write data to a Google Sheet
    func appendData(to spreadsheetId: String, range: String, values: [[String]], completion: @escaping (Result<Void, Error>) -> Void) {
        let urlString = "\(baseURL)/\(spreadsheetId)/values/\(range):append?valueInputOption=RAW"
        
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["values": values]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            
            if let httpResponse = response as? HTTPURLResponse {
                   let statusCode = httpResponse.statusCode
                   appBootLog.debugWithContext("HTTP Status Code: \(statusCode)")
                   
                   if (200...299).contains(statusCode) {
                       appBootLog.debugWithContext("Success")
                   } else {
                       appBootLog.errorWithContext("Failed with status code: \(statusCode)")
                   }
               } else {
                   appBootLog.errorWithContext("Unable to cast response to HTTPURLResponse")
               }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "Invalid Response", code: -3, userInfo: nil)))
                return
            }
            
            completion(.success(()))
        }.resume()
    }
}
