import SwiftUI

struct OfflineBanner: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var syncManager: SyncManager

    @State private var showingOfflineEditingDialog = false
    @State private var showingPendingChanges = false
    @State private var showingConflictResolution = false

    var body: some View {
        Button {
            handleBannerTap()
        } label: {
            HStack {
                Image(systemName: bannerIcon)
                Text(bannerText)
                    .font(.subheadline)
                Spacer()
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(bannerColor)
            .foregroundStyle(.white)
        }
        .confirmationDialog("Enable Offline Editing", isPresented: $showingOfflineEditingDialog) {
            Button("1 hour") { syncManager.enableOfflineEditing(hours: 1) }
            Button("2 hours") { syncManager.enableOfflineEditing(hours: 2) }
            Button("4 hours") { syncManager.enableOfflineEditing(hours: 4) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your changes will be queued until you're back online. If others edit the same issues, you may need to resolve conflicts.")
        }
        .sheet(isPresented: $showingPendingChanges) {
            PendingChangesSheet()
        }
        .sheet(isPresented: $showingConflictResolution) {
            ConflictResolutionSheet()
        }
    }

    private var bannerIcon: String {
        switch syncManager.syncState {
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .conflicts:
            return "exclamationmark.triangle.fill"
        default:
            if !networkMonitor.isConnected {
                return syncManager.isOfflineEditingEnabled ? "pencil.circle.fill" : "wifi.slash"
            }
            return "checkmark.circle.fill"
        }
    }

    private var bannerText: String {
        switch syncManager.syncState {
        case .syncing:
            return "Syncing \(syncManager.pendingChangesCount) changes..."
        case .conflicts(let count):
            return "\(count) conflicts need attention"
        default:
            if !networkMonitor.isConnected {
                if syncManager.isOfflineEditingEnabled {
                    let remaining = syncManager.offlineEditingTimeRemaining
                    let pendingCount = syncManager.pendingChangesCount
                    if pendingCount > 0 {
                        return "Offline editing: \(remaining) left \u{2022} \(pendingCount) pending"
                    } else {
                        return "Offline editing: \(remaining) left"
                    }
                } else {
                    return "Offline - tap to enable editing"
                }
            }
            if syncManager.pendingChangesCount > 0 {
                return "\(syncManager.pendingChangesCount) pending changes"
            }
            return ""
        }
    }

    private var bannerColor: Color {
        switch syncManager.syncState {
        case .syncing:
            return .blue
        case .conflicts:
            return .red
        default:
            if !networkMonitor.isConnected {
                return syncManager.isOfflineEditingEnabled ? .orange : .gray
            }
            return .green
        }
    }

    private var showsChevron: Bool {
        switch syncManager.syncState {
        case .conflicts:
            return true
        default:
            return !networkMonitor.isConnected || syncManager.pendingChangesCount > 0
        }
    }

    private func handleBannerTap() {
        switch syncManager.syncState {
        case .conflicts:
            showingConflictResolution = true
        default:
            if !networkMonitor.isConnected {
                if syncManager.isOfflineEditingEnabled {
                    showingPendingChanges = true
                } else {
                    showingOfflineEditingDialog = true
                }
            } else if syncManager.pendingChangesCount > 0 {
                showingPendingChanges = true
            }
        }
    }
}

struct PendingChangesSheet: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(syncManager.pendingChanges) { change in
                    PendingChangeRow(change: change)
                }
                .onDelete { indexSet in
                    syncManager.discardPendingChanges(at: indexSet)
                }
            }
            .navigationTitle("Pending Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if syncManager.pendingChanges.isEmpty {
                    ContentUnavailableView(
                        "No Pending Changes",
                        systemImage: "checkmark.circle",
                        description: Text("All changes have been synced")
                    )
                }
            }
        }
    }
}

struct PendingChangeRow: View {
    let change: PendingChange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.issueTitle)
                .font(.headline)
            Text(change.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Modified \(change.timestamp.formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct ConflictResolutionSheet: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(syncManager.conflicts) { conflict in
                    NavigationLink(value: conflict) {
                        ConflictRow(conflict: conflict)
                    }
                }
            }
            .navigationTitle("Resolve Conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: IssueConflict.self) { conflict in
                ConflictDetailView(conflict: conflict)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ConflictRow: View {
    let conflict: IssueConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conflict.issueTitle)
                .font(.headline)
            Text("\(conflict.conflictingFields.count) conflicting field(s)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ConflictDetailView: View {
    let conflict: IssueConflict
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(conflict.conflictingFields, id: \.fieldName) { field in
                Section(field.fieldName.capitalized) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Your Version")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(field.localValue)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading) {
                            Text("Their Version")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(field.remoteValue)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        HStack {
                            Button("Keep Mine") {
                                syncManager.resolveConflict(conflict, field: field.fieldName, keepLocal: true)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Keep Theirs") {
                                syncManager.resolveConflict(conflict, field: field.fieldName, keepLocal: false)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle(conflict.issueTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    VStack {
        OfflineBanner()
        Spacer()
    }
    .environmentObject(NetworkMonitor.shared)
    .environmentObject(SyncManager.shared)
}
