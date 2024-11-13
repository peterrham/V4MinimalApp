//
//  AppendLog.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/12/24.
//

import Foundation


// take items and append them to google sheets in real time

class AppendLog {
    static let appendSheetID: String = "1TPUVf37GLcvAiK1HsI6-36h_OVE_JrvGHNQ2Jd3xo9I"
    
    func append()
    {
        print("append()")
        
       // let accessToken = googleSignInManager.user!.accessToken.tokenString
        
        GoogleSheetsClient(inputAccessToken: "bogus token").appendDataToGoogleSheet(data:[["efg"]])
        
    }
}
