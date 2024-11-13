//
//  GlobalFunctions.swift
//  V4MinimalApp
//
//  Created by Ham, Peter on 11/4/24.
//

import Foundation
import CoreData


func debugPrint(str: String){
    print(str)
}

func logWithTimestamp(_ message: String) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let timestamp = dateFormatter.string(from: Date())
    debugPrint(str: "[\(timestamp)] \(message)")
}

import Foundation

func prettyPrintSortedJSONFromInfoDictionary() {
    if let infoDictionary = Bundle.main.infoDictionary {
        // Convert the dictionary to JSON data
        if let jsonData = try? JSONSerialization.data(withJSONObject: infoDictionary, options: []),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []),
           let jsonDict = jsonObject as? [String: Any] {
            
            // Sort the dictionary recursively and convert it back to JSON
            if let sortedJSONData = try? JSONSerialization.data(
                withJSONObject: recursivelySortDictionary(jsonDict),
                options: .prettyPrinted),
               let sortedJSONString = String(data: sortedJSONData, encoding: .utf8) {
                print(sortedJSONString)  // Output the sorted and formatted JSON string
            } else {
                print("Failed to create sorted JSON string.")
            }
        } else {
            print("Failed to parse Info.plist as JSON.")
        }
    } else {
        print("No Info.plist found.")
    }
}

func recursivelySortDictionary(_ dictionary: [String: Any]) -> [String: Any] {
    var sortedDictionary = [String: Any]()
    
    for (key, value) in dictionary.sorted(by: { $0.key < $1.key }) {
        if let nestedDictionary = value as? [String: Any] {
            // Recursively sort nested dictionaries
            sortedDictionary[key] = recursivelySortDictionary(nestedDictionary)
        } else if let nestedArray = value as? [Any] {
            // Sort each dictionary within an array of dictionaries
            sortedDictionary[key] = nestedArray.map { element -> Any in
                if let dictElement = element as? [String: Any] {
                    return recursivelySortDictionary(dictElement)
                }
                return element
            }
        } else {
            // Directly add values that are not dictionaries or arrays
            sortedDictionary[key] = value
        }
    }
    
    return sortedDictionary
}

import Foundation


func prettyPrintSortedInfoDictionaryRecursively() {
    if let infoDictionary = Bundle.main.infoDictionary {
        let sortedDictionary = recursivelySortDictionary(infoDictionary)
        
        // Convert the sorted dictionary to JSON with pretty-printing
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sortedDictionary, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)  // Output the formatted JSON string
            }
        } catch {
            print("Failed to convert Info.plist to JSON: \(error.localizedDescription)")
        }
    } else {
        print("No Info.plist found.")
    }
}



func prettyPrintInfoDictionary() {
    // Access the main info dictionary
    if let infoDictionary = Bundle.main.infoDictionary {
        // Try to serialize it into JSON data with pretty-printing
        if let jsonData = try? JSONSerialization.data(withJSONObject: infoDictionary, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)  // Output the formatted JSON string
        } else {
            print("Failed to convert Info.plist to JSON.")
        }
    } else {
        print("No Info.plist found.")
    }
}

func logEnvironmentObjects(_ objects: Any...) {
    for object in objects {
        print("Environment Object: \(object)")
    }
}


func printEnvironmentObjectDetails(_ object: Any) {
    let mirror = Mirror(reflecting: object)
    print(object)
    print(mirror)
    for child in mirror.children {
        print(child)
        printEnvironmentObjectDetails(child)
        if let propertyName = child.label {
            print("\(propertyName): \(child.value)")
        } else {
            print("empty: \(child.value)")
        }
    }
}

// Example function to check URL schemes in Info.plist
func checkURLSchemes() {
    if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
        for urlType in urlTypes {
            if let urlSchemes = urlType["CFBundleURLSchemes"] as? [String] {
                print("URL Schemes found: \(urlSchemes)")
                
                let expectedScheme = "com.googleusercontent.apps.748381179204-pmnlavrbccrsc9v17qtqepjum0rd1kok.apps.googleusercontent.com" // Replace with your scheme
                if urlSchemes.contains(expectedScheme) {
                    print("Expected URL scheme '\(expectedScheme)' is correctly registered.")
                } else {
                    print("Expected URL scheme '\(expectedScheme)' is NOT registered.")
                }
            }
        }
    } else {
        print("No URL schemes found in Info.plist.")
    }
}


import SwiftUI

// Custom button style
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}
/*

class RecognizedTextFetcher {
    private let viewContext: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.viewContext) {
        self.viewContext = context
    }

    func fetchRecognizedTexts() -> [RecognizedTextEntity] {
        let fetchRequest: NSFetchRequest<RecognizedTextEntity> = RecognizedTextEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \RecognizedTextEntity.timestamp, ascending: true)]
        
        do {
            let recognizedTexts = try viewContext.fetch(fetchRequest)
            return recognizedTexts
        } catch {
            print("Failed to fetch recognized texts: \(error)")
            return []
        }
    }
}

*/

import CoreData
    

/*
 func fetchRecognizedTexts(container: NSPersistentContainer) -> [RecognizedTextEntity] {
 let context = container.viewContext  // Access the viewContext of the container
 let fetchRequest: NSFetchRequest<RecognizedTextEntity> = RecognizedTextEntity.fetchRequest()
 
 // Optional: Add sorting by a timestamp attribute (if it exists in the entity)
 fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \RecognizedTextEntity.timestamp, ascending: true)]
 
 do {
 let results = try context.fetch(fetchRequest)
 return results
 } catch {
 print("Failed to fetch RecognizedTextEntity: \(error)")
 return []
 }
 }
 */
