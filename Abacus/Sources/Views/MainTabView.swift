import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            IssueListView()
                .tabItem {
                    Label("Issues", systemImage: "list.bullet")
                }

            RepositoriesView()
                .tabItem {
                    Label("Repos", systemImage: "folder")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager.shared)
        .environmentObject(SyncManager.shared)
        .environmentObject(NetworkMonitor.shared)
}
