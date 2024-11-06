//
//  GlobalFunctions.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/4/24.
//

import Foundation


func debugPrint(str: String){
    print(str)
}

func logWithTimestamp(_ message: String) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let timestamp = dateFormatter.string(from: Date())
   // debugPrint(str: "[\(timestamp)] \(message)")
}
