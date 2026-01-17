import SwiftUI

enum IssueStatus: String, CaseIterable, Codable {
    case open
    case inProgress = "in_progress"
    case closed

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .closed: return "Closed"
        }
    }

    var color: Color {
        switch self {
        case .open: return .green
        case .inProgress: return .blue
        case .closed: return .gray
        }
    }
}

enum PriorityLevel: Int, CaseIterable, Codable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }
}

enum IssueType: String, CaseIterable, Codable {
    case bug
    case feature
    case task
    case epic

    var displayName: String {
        switch self {
        case .bug: return "Bug"
        case .feature: return "Feature"
        case .task: return "Task"
        case .epic: return "Epic"
        }
    }

    var icon: String {
        switch self {
        case .bug: return "ladybug"
        case .feature: return "star"
        case .task: return "checkmark.square"
        case .epic: return "mountain.2"
        }
    }
}

struct Issue: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var description: String?
    var status: IssueStatus
    var priority: PriorityLevel
    var issueType: IssueType
    var assignee: String?
    var createdAt: Date
    var updatedAt: Date?
    var closedAt: Date?
    var parent: String?
    var comments: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case status
        case priority
        case issueType = "issue_type"
        case assignee
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case parent
        case comments
    }
}

struct IssueChanges {
    let issueId: String
    var title: String?
    var description: String?
    var status: String?
    var priority: Int?
    var assignee: String?

    var isEmpty: Bool {
        title == nil && description == nil && status == nil && priority == nil && assignee == nil
    }

    var changedFields: [String] {
        var fields: [String] = []
        if title != nil { fields.append("title") }
        if description != nil { fields.append("description") }
        if status != nil { fields.append("status") }
        if priority != nil { fields.append("priority") }
        if assignee != nil { fields.append("assignee") }
        return fields
    }
}

struct PendingChange: Identifiable {
    let id: UUID
    let issueId: String
    let issueTitle: String
    let changes: IssueChanges
    let timestamp: Date
    let baseState: Issue

    var summary: String {
        let fields = changes.changedFields
        if fields.count == 1 {
            return "Changed \(fields[0])"
        } else {
            return "Changed \(fields.count) fields"
        }
    }
}

struct IssueConflict: Identifiable, Hashable {
    let id: UUID
    let issueId: String
    let issueTitle: String
    let conflictingFields: [ConflictingField]

    static func == (lhs: IssueConflict, rhs: IssueConflict) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ConflictingField: Identifiable {
    var id: String { fieldName }
    let fieldName: String
    let baseValue: String
    let localValue: String
    let remoteValue: String
}

struct GitHubUser: Codable {
    let id: Int
    let login: String
    let name: String?
    let avatarURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case name
        case avatarURL = "avatar_url"
    }
}
