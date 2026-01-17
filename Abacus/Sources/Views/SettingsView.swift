import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var syncManager: SyncManager

    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let user = authManager.currentUser {
                        HStack {
                            AsyncImage(url: URL(string: user.avatarURL)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())

                            VStack(alignment: .leading) {
                                Text(user.name ?? user.login)
                                    .font(.headline)
                                if user.name != nil {
                                    Text("@\(user.login)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Button("Sign Out", role: .destructive) {
                        showingSignOutConfirmation = true
                    }
                }

                Section("Sync") {
                    LabeledContent("Last Sync", value: syncManager.lastSyncDate?.formatted(.relative(presentation: .named)) ?? "Never")

                    Button("Sync Now") {
                        Task {
                            await syncManager.refresh()
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")

                    Link("View on GitHub", destination: URL(string: "https://github.com/mbinde/abacus-mobile")!)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign Out", isPresented: $showingSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager.shared)
        .environmentObject(SyncManager.shared)
}
