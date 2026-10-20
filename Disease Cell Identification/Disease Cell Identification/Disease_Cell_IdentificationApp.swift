//
//  Disease_Cell_IdentificationApp.swift
//  Disease Cell Identification
//
//  Created by David Nishimoto on 10/20/26.
//

import SwiftUI
import CoreData

@main
struct Disease_Cell_IdentificationApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
