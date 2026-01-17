import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var networkMonitor: NetworkMonitor

    var body: some View {
        ZStack {
            if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .overlay(alignment: .top) {
            if !networkMonitor.isConnected || syncManager.hasPendingChanges {
                OfflineBanner()
            }
        }
    }

    @EnvironmentObject private var syncManager: SyncManager
}

#Preview {
    ContentView()
        .environmentObject(AuthManager.shared)
        .environmentObject(SyncManager.shared)
        .environmentObject(NetworkMonitor.shared)
}
