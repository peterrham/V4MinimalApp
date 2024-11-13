//
//  AppHelper.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/13/24.
//

import Foundation


class AppHelper {
    static let shared = AppHelper()
    private init() {
        
        // Call the function to pretty print
        // sorting just does not work for some reason ...
        
        prettyPrintSortedJSONFromInfoDictionary()

        
        // Custom setup code, such as checking URL schemes
        checkURLSchemes()
    }
    
   
}


