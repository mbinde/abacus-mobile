import SwiftUI
import CoreData

enum SyncState: Equatable {
    case idle
    case syncing
    case conflicts(count: Int)
    case error(String)

    static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.syncing, .syncing): return true
        case (.conflicts(let a), .conflicts(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var syncState: SyncState = .idle
    @Published var lastSyncDate: Date?
    @Published var pendingChanges: [PendingChange] = []
    @Published var conflicts: [IssueConflict] = []

    @Published var isOfflineEditingEnabled = false
    @Published var offlineEditingExpiresAt: Date?

    private var offlineEditingTimer: Timer?

    var pendingChangesCount: Int { pendingChanges.count }

    var hasPendingChanges: Bool { !pendingChanges.isEmpty }

    var offlineEditingTimeRemaining: String {
        guard let expiresAt = offlineEditingExpiresAt else { return "" }
        let remaining = expiresAt.timeIntervalSince(Date())
        if remaining <= 0 { return "expired" }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private init() {
        loadPendingChanges()
    }

    func enableOfflineEditing(hours: Int) {
        isOfflineEditingEnabled = true
        offlineEditingExpiresAt = Date().addingTimeInterval(TimeInterval(hours * 3600))

        offlineEditingTimer?.invalidate()
        offlineEditingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkOfflineEditingExpiration()
            }
        }
    }

    func disableOfflineEditing() {
        isOfflineEditingEnabled = false
        offlineEditingExpiresAt = nil
        offlineEditingTimer?.invalidate()
        offlineEditingTimer = nil
    }

    private func checkOfflineEditingExpiration() {
        guard let expiresAt = offlineEditingExpiresAt else { return }
        if Date() >= expiresAt {
            disableOfflineEditing()
        }
    }

    func hasPendingChanges(for issueId: String) -> Bool {
        pendingChanges.contains { $0.issueId == issueId }
    }

    func queueOfflineChange(_ changes: IssueChanges, for issue: CachedIssue) {
        guard !changes.isEmpty else { return }

        // Convert CachedIssue to Issue for base state
        let baseState = Issue(
            id: issue.beadsId ?? "",
            title: issue.title ?? "",
            description: issue.issueDescription,
            status: IssueStatus(rawValue: issue.status ?? "") ?? .open,
            priority: PriorityLevel(rawValue: Int(issue.priority)) ?? .medium,
            issueType: IssueType(rawValue: issue.issueType ?? "") ?? .task,
            assignee: issue.assignee,
            createdAt: issue.createdAt ?? Date(),
            updatedAt: issue.updatedAt,
            closedAt: issue.closedAt,
            parent: issue.parent,
            comments: issue.commentsData
        )

        let pendingChange = PendingChange(
            id: UUID(),
            issueId: issue.beadsId ?? "",
            issueTitle: issue.title ?? "Untitled",
            changes: changes,
            timestamp: Date(),
            baseState: baseState
        )

        pendingChanges.append(pendingChange)
        savePendingChanges()

        // Apply changes locally
        applyChangesLocally(changes, to: issue)
    }

    private func applyChangesLocally(_ changes: IssueChanges, to issue: CachedIssue) {
        if let title = changes.title {
            issue.title = title
        }
        if let description = changes.description {
            issue.issueDescription = description
        }
        if let status = changes.status {
            issue.status = status
        }
        if let priority = changes.priority {
            issue.priority = Int16(priority)
        }
        if let assignee = changes.assignee {
            issue.assignee = assignee
        }
        issue.updatedAt = Date()

        try? issue.managedObjectContext?.save()
    }

    func saveChanges(_ changes: IssueChanges, for issue: CachedIssue) async {
        guard let token = AuthManager.shared.accessToken,
              let repoOwner = issue.repository?.owner,
              let repoName = issue.repository?.name else {
            return
        }

        syncState = .syncing

        do {
            let client = GitHubClient(token: token)

            // Fetch current state from GitHub
            let remoteIssues = try await client.fetchIssues(owner: repoOwner, repo: repoName)
            guard let remoteIssue = remoteIssues.first(where: { $0.id == changes.issueId }) else {
                throw SyncError.issueNotFound
            }

            // Convert CachedIssue to base state Issue
            let baseState = Issue(
                id: issue.beadsId ?? "",
                title: issue.title ?? "",
                description: issue.issueDescription,
                status: IssueStatus(rawValue: issue.status ?? "") ?? .open,
                priority: PriorityLevel(rawValue: Int(issue.priority)) ?? .medium,
                issueType: IssueType(rawValue: issue.issueType ?? "") ?? .task,
                assignee: issue.assignee,
                createdAt: issue.createdAt ?? Date(),
                updatedAt: issue.updatedAt,
                closedAt: issue.closedAt,
                parent: issue.parent,
                comments: issue.commentsData
            )

            // Perform three-way merge
            let mergeResult = ThreeWayMerge.merge(
                base: baseState,
                local: changes,
                remote: remoteIssue
            )

            switch mergeResult {
            case .success(let mergedIssue):
                // Update on GitHub
                try await client.updateIssue(mergedIssue, owner: repoOwner, repo: repoName)

                // Update local cache
                updateCachedIssue(issue, with: mergedIssue)

                syncState = .idle
                lastSyncDate = Date()

            case .conflict(let conflictingFields):
                let conflict = IssueConflict(
                    id: UUID(),
                    issueId: changes.issueId,
                    issueTitle: issue.title ?? "Untitled",
                    conflictingFields: conflictingFields
                )
                conflicts.append(conflict)
                syncState = .conflicts(count: conflicts.count)
            }

        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    func refresh() async {
        guard let token = AuthManager.shared.accessToken else { return }

        syncState = .syncing

        // First, try to sync any pending changes
        if !pendingChanges.isEmpty {
            await syncPendingChanges()
        }

        // Then refresh from GitHub
        do {
            let client = GitHubClient(token: token)
            let context = PersistenceController.shared.container.viewContext

            let repoRequest: NSFetchRequest<CachedRepository> = CachedRepository.fetchRequest()
            let repos = try context.fetch(repoRequest)

            for repo in repos {
                guard let owner = repo.owner, let name = repo.name else { continue }

                let issues = try await client.fetchIssues(owner: owner, repo: name)

                for issue in issues {
                    updateOrCreateCachedIssue(issue, in: repo, context: context)
                }

                repo.lastSynced = Date()
            }

            try context.save()
            lastSyncDate = Date()
            syncState = conflicts.isEmpty ? .idle : .conflicts(count: conflicts.count)

        } catch {
            syncState = .error(error.localizedDescription)
        }
    }

    private func syncPendingChanges() async {
        guard let token = AuthManager.shared.accessToken else { return }

        let client = GitHubClient(token: token)
        let context = PersistenceController.shared.container.viewContext

        for pendingChange in pendingChanges {
            // Find the cached issue
            let request: NSFetchRequest<CachedIssue> = CachedIssue.fetchRequest()
            request.predicate = NSPredicate(format: "beadsId == %@", pendingChange.issueId)

            guard let cachedIssue = try? context.fetch(request).first,
                  let repoOwner = cachedIssue.repository?.owner,
                  let repoName = cachedIssue.repository?.name else {
                continue
            }

            do {
                let remoteIssues = try await client.fetchIssues(owner: repoOwner, repo: repoName)
                guard let remoteIssue = remoteIssues.first(where: { $0.id == pendingChange.issueId }) else {
                    continue
                }

                let mergeResult = ThreeWayMerge.merge(
                    base: pendingChange.baseState,
                    local: pendingChange.changes,
                    remote: remoteIssue
                )

                switch mergeResult {
                case .success(let mergedIssue):
                    try await client.updateIssue(mergedIssue, owner: repoOwner, repo: repoName)
                    pendingChanges.removeAll { $0.id == pendingChange.id }

                case .conflict(let conflictingFields):
                    let conflict = IssueConflict(
                        id: UUID(),
                        issueId: pendingChange.issueId,
                        issueTitle: pendingChange.issueTitle,
                        conflictingFields: conflictingFields
                    )
                    conflicts.append(conflict)
                }

            } catch {
                // Keep the pending change for retry
                continue
            }
        }

        savePendingChanges()
    }

    func resolveConflict(_ conflict: IssueConflict, field: String, keepLocal: Bool) {
        // Implementation would apply the resolution and retry sync
        // For now, just remove the conflict
        conflicts.removeAll { $0.id == conflict.id }

        if conflicts.isEmpty {
            syncState = .idle
        } else {
            syncState = .conflicts(count: conflicts.count)
        }
    }

    func discardPendingChanges(at offsets: IndexSet) {
        pendingChanges.remove(atOffsets: offsets)
        savePendingChanges()
    }

    private func updateCachedIssue(_ cachedIssue: CachedIssue, with issue: Issue) {
        cachedIssue.title = issue.title
        cachedIssue.issueDescription = issue.description
        cachedIssue.status = issue.status.rawValue
        cachedIssue.priority = Int16(issue.priority.rawValue)
        cachedIssue.issueType = issue.issueType.rawValue
        cachedIssue.assignee = issue.assignee
        cachedIssue.updatedAt = issue.updatedAt
        cachedIssue.closedAt = issue.closedAt

        try? cachedIssue.managedObjectContext?.save()
    }

    private func updateOrCreateCachedIssue(_ issue: Issue, in repo: CachedRepository, context: NSManagedObjectContext) {
        let request: NSFetchRequest<CachedIssue> = CachedIssue.fetchRequest()
        request.predicate = NSPredicate(format: "beadsId == %@", issue.id)

        let cachedIssue: CachedIssue
        if let existing = try? context.fetch(request).first {
            cachedIssue = existing
        } else {
            cachedIssue = CachedIssue(context: context)
            cachedIssue.id = UUID()
            cachedIssue.beadsId = issue.id
            cachedIssue.repository = repo
        }

        cachedIssue.title = issue.title
        cachedIssue.issueDescription = issue.description
        cachedIssue.status = issue.status.rawValue
        cachedIssue.priority = Int16(issue.priority.rawValue)
        cachedIssue.issueType = issue.issueType.rawValue
        cachedIssue.assignee = issue.assignee
        cachedIssue.createdAt = issue.createdAt
        cachedIssue.updatedAt = issue.updatedAt
        cachedIssue.closedAt = issue.closedAt
        cachedIssue.parent = issue.parent
        cachedIssue.commentsData = issue.comments
    }

    private func loadPendingChanges() {
        // Load from UserDefaults or file storage
        // For now, start with empty array
    }

    private func savePendingChanges() {
        // Save to UserDefaults or file storage
    }
}

enum SyncError: LocalizedError {
    case issueNotFound
    case networkError
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .issueNotFound: return "Issue not found"
        case .networkError: return "Network error"
        case .unauthorized: return "Unauthorized"
        }
    }
}
