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
    /*
     @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        entity: RecognizedTextEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \RecognizedTextEntity.timestamp, ascending: true)]
    ) private var recognizedTexts: FetchedResults<RecognizedTextEntity>
     */
    
    init(accessToken: String)
    {
        logWithTimestamp("GoogleSheetsClient")
    }
    
    func CopyToSheet()
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
        /*
        
        for textEntity in  DynamicPersistenceController.shared.fetchRecognizedTextEntities() {
            let content = textEntity.content ?? "N/A"
            let timestamp = dateFormatter.string(from: textEntity.timestamp ?? Date())
            let row = "\"\(content)\",\"\(timestamp)\"\n"
            logWithTimestamp(row)
            csvText += row
        }
        */
        logWithTimestamp("CopyToSheet ******")
    }
}

