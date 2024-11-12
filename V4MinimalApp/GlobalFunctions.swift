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
