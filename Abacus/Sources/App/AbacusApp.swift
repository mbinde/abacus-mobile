import SwiftUI

@main
struct AbacusApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var syncManager = SyncManager.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(authManager)
                .environmentObject(syncManager)
                .environmentObject(networkMonitor)
        }
    }
}
