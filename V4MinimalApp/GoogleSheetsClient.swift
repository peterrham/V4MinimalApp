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
    
    func CopyToSheet(argSpreadsheetId: String)
    {
        logWithTimestamp("****** CopyToSheet")
        
        let headers = "Content,Timestamp\n"
        var csvText = headers
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        
        if let recognizedTextEntities = DynamicPersistenceController.shared.fetchRecognizedTextEntities() {
            for entity in recognizedTextEntities {
                if let content = entity.value(forKey: "content") as? String,
                   let timestamp = entity.value(forKey: "timestamp") as? Date {
                    print("Content: \(content), Timestamp: \(timestamp)")
                    
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
        
        logWithTimestamp("CopyToSheet ******")
    }
}

