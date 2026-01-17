import SwiftUI
import CoreData

struct IssueDetailView: View {
    @ObservedObject var issue: CachedIssue
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Environment(\.managedObjectContext) private var viewContext

    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @State private var editedStatus: IssueStatus = .open
    @State private var editedPriority: PriorityLevel = .medium
    @State private var editedAssignee: String = ""

    var canEdit: Bool {
        networkMonitor.isConnected || syncManager.isOfflineEditingEnabled
    }

    var body: some View {
        Form {
            Section("Details") {
                if isEditing {
                    TextField("Title", text: $editedTitle)
                    TextEditor(text: $editedDescription)
                        .frame(minHeight: 100)
                } else {
                    Text(issue.title ?? "Untitled")
                        .font(.headline)
                    if let description = issue.issueDescription, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Status") {
                if isEditing {
                    Picker("Status", selection: $editedStatus) {
                        ForEach(IssueStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    StatusBadge(status: IssueStatus(rawValue: issue.status ?? "") ?? .open)
                }
            }

            Section("Priority") {
                if isEditing {
                    Picker("Priority", selection: $editedPriority) {
                        ForEach(PriorityLevel.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                } else {
                    PriorityBadge(priority: PriorityLevel(rawValue: Int(issue.priority)) ?? .medium)
                }
            }

            Section("Assignee") {
                if isEditing {
                    TextField("Assignee", text: $editedAssignee)
                } else {
                    Text(issue.assignee ?? "Unassigned")
                        .foregroundStyle(issue.assignee == nil ? .secondary : .primary)
                }
            }

            Section("Metadata") {
                LabeledContent("ID", value: issue.beadsId ?? "Unknown")
                LabeledContent("Type", value: issue.issueType ?? "task")
                if let createdAt = issue.createdAt {
                    LabeledContent("Created", value: createdAt.formatted())
                }
                if let updatedAt = issue.updatedAt {
                    LabeledContent("Updated", value: updatedAt.formatted())
                }
            }

            if let comments = issue.commentsData, !comments.isEmpty {
                Section("Comments") {
                    Text(comments)
                        .font(.body)
                }
            }
        }
        .navigationTitle(issue.beadsId ?? "Issue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    Button("Save") {
                        saveChanges()
                    }
                } else if canEdit {
                    Button("Edit") {
                        startEditing()
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isEditing = false
                    }
                }
            }
        }
        .disabled(!canEdit && !isEditing)
    }

    private func startEditing() {
        editedTitle = issue.title ?? ""
        editedDescription = issue.issueDescription ?? ""
        editedStatus = IssueStatus(rawValue: issue.status ?? "") ?? .open
        editedPriority = PriorityLevel(rawValue: Int(issue.priority)) ?? .medium
        editedAssignee = issue.assignee ?? ""
        isEditing = true
    }

    private func saveChanges() {
        let changes = IssueChanges(
            issueId: issue.beadsId ?? "",
            title: editedTitle != issue.title ? editedTitle : nil,
            description: editedDescription != issue.issueDescription ? editedDescription : nil,
            status: editedStatus.rawValue != issue.status ? editedStatus.rawValue : nil,
            priority: Int16(editedPriority.rawValue) != issue.priority ? editedPriority.rawValue : nil,
            assignee: editedAssignee != issue.assignee ? editedAssignee : nil
        )

        if networkMonitor.isConnected {
            Task {
                await syncManager.saveChanges(changes, for: issue)
            }
        } else {
            syncManager.queueOfflineChange(changes, for: issue)
        }

        isEditing = false
    }
}

#Preview {
    NavigationStack {
        IssueDetailView(issue: CachedIssue.preview)
            .environmentObject(SyncManager.shared)
            .environmentObject(NetworkMonitor.shared)
    }
}
