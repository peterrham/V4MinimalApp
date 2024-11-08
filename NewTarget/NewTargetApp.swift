//
//  NewTargetApp.swift
//  NewTarget
//
//  Created by Ham, Peter on 11/7/24.
//

import SwiftUI

@main
struct NewTargetApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
