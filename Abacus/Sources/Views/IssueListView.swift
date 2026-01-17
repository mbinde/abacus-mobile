import SwiftUI
import CoreData

struct IssueListView: View {
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CachedIssue.updatedAt, ascending: false)],
        animation: .default
    )
    private var issues: FetchedResults<CachedIssue>

    @State private var selectedStatus: IssueStatus?
    @State private var searchText = ""

    var filteredIssues: [CachedIssue] {
        issues.filter { issue in
            let matchesStatus = selectedStatus == nil || issue.status == selectedStatus?.rawValue
            let matchesSearch = searchText.isEmpty ||
                (issue.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (issue.issueDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesStatus && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredIssues, id: \.id) { issue in
                    NavigationLink(value: issue) {
                        IssueRowView(issue: issue)
                    }
                }
            }
            .navigationTitle("Issues")
            .navigationDestination(for: CachedIssue.self) { issue in
                IssueDetailView(issue: issue)
            }
            .searchable(text: $searchText, prompt: "Search issues")
            .refreshable {
                await syncManager.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All") { selectedStatus = nil }
                        ForEach(IssueStatus.allCases, id: \.self) { status in
                            Button(status.displayName) { selectedStatus = status }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .overlay {
                if issues.isEmpty {
                    ContentUnavailableView(
                        "No Issues",
                        systemImage: "tray",
                        description: Text("Pull to refresh or add a repository")
                    )
                }
            }
        }
    }
}

struct IssueRowView: View {
    let issue: CachedIssue
    @EnvironmentObject var syncManager: SyncManager

    var hasPendingChanges: Bool {
        syncManager.hasPendingChanges(for: issue.id ?? "")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(issue.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(1)

                    if hasPendingChanges {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    Text(issue.beadsId ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let status = issue.status {
                        StatusBadge(status: IssueStatus(rawValue: status) ?? .open)
                    }

                    if let priority = PriorityLevel(rawValue: Int(issue.priority)) {
                        PriorityBadge(priority: priority)
                    }
                }
            }

            Spacer()

            if let assignee = issue.assignee, !assignee.isEmpty {
                Text(assignee)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    IssueListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(SyncManager.shared)
        .environmentObject(NetworkMonitor.shared)
}
