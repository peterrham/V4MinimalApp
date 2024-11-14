//
//  GoogleSheetsClient.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/11/24.
//

import Foundation
import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct GoogleSheetsClient {
    
    var spreadsheetId : String = "YOUR_SPREADSHEET_ID"  // Replace with your Google Sheets ID
    var accessToken : String = "YOUR_ACCESS_TOKEN"      // Replace with the OAuth 2.0 access token
  
    
    init(inputAccessToken: String)
    {
        logWithTimestamp("GoogleSheetsClient")
        accessToken = inputAccessToken
    }
    
    mutating func CopyToSheet(argSpreadsheetId: String)
    {
        logWithTimestamp("****** CopyToSheet")
        
        spreadsheetId = argSpreadsheetId
        
        let headers = "Content,Timestamp\n"
        var csvText = headers
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        
        if let recognizedTextEntities = DynamicPersistenceController.shared.fetchRecognizedTextEntities() {
            for entity in recognizedTextEntities {
                if let content = entity.value(forKey: "content") as? String,
                   let timestamp = entity.value(forKey: "timestamp") as? Date {
                    // print("Content: \(content), Timestamp: \(timestamp)")
                    
                    let timestampStr = dateFormatter.string(from: entity.timestamp ?? Date())
                    let row = "\"\(content)\",\"\(timestampStr)\"\n"
                    logWithTimestamp(row)
                    csvText += row
                    
                }
            }
        } else {
            print("No records found or an error occurred.")
        }
       
        print(csvText)
        
        // TODO, next step is to actually append the data to a google sheet using the append method
        
        var rows :  [[String]] = [["Time", "Item"]]
        
        if let recognizedTextEntities = DynamicPersistenceController.shared.fetchRecognizedTextEntities() {
            
            
            for entity in recognizedTextEntities {
                if let content = entity.value(forKey: "content") as? String,
                   let timestamp = entity.value(forKey: "timestamp") as? Date {
                    
                    let timestampStr = dateFormatter.string(from: timestamp)
                    let row = [timestampStr, content]  // Each row is an array with content and timestamp
                    rows.append(row)  // Append the row to the rows array
                }
            }
        }
        
        self.appendDataToGoogleSheet(spreadsheetId: argSpreadsheetId, data: rows)
        
        
        logWithTimestamp("CopyToSheet ******")
    }
    
    func appendDataToGoogleSheet(spreadsheetId: String, data: [[String]]) {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/Sheet1!A1:append?valueInputOption=RAW")!
        
        // Prepare the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Prepare the data payload
        let body = [
            "values": data
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            print("Error serializing JSON:", error)
            return
        }
        
        // Perform the network request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Request error:", error)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Unexpected response:", response ?? "No response")
                return
            }
            
            print("Data successfully appended to Google Sheets.")
        }
        
        task.resume()
    }
}

