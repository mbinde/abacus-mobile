import Foundation

enum MergeResult {
    case success(Issue)
    case conflict([ConflictingField])
}

struct ThreeWayMerge {
    static func merge(base: Issue, local: IssueChanges, remote: Issue) -> MergeResult {
        var conflicts: [ConflictingField] = []
        var merged = remote // Start with remote as the base for merged result

        // Check title
        if let localTitle = local.title {
            if remote.title == base.title {
                // Remote hasn't changed, use local
                merged.title = localTitle
            } else if localTitle != remote.title {
                // Both changed to different values - conflict
                conflicts.append(ConflictingField(
                    fieldName: "title",
                    baseValue: base.title,
                    localValue: localTitle,
                    remoteValue: remote.title
                ))
            }
            // If both changed to same value, no conflict, use that value
        }

        // Check description
        if let localDescription = local.description {
            let baseDesc = base.description ?? ""
            let remoteDesc = remote.description ?? ""

            if remoteDesc == baseDesc {
                merged.description = localDescription
            } else if localDescription != remoteDesc {
                conflicts.append(ConflictingField(
                    fieldName: "description",
                    baseValue: baseDesc,
                    localValue: localDescription,
                    remoteValue: remoteDesc
                ))
            }
        }

        // Check status
        if let localStatus = local.status {
            if remote.status.rawValue == base.status.rawValue {
                merged.status = IssueStatus(rawValue: localStatus) ?? remote.status
            } else if localStatus != remote.status.rawValue {
                conflicts.append(ConflictingField(
                    fieldName: "status",
                    baseValue: base.status.rawValue,
                    localValue: localStatus,
                    remoteValue: remote.status.rawValue
                ))
            }
        }

        // Check priority
        if let localPriority = local.priority {
            if remote.priority.rawValue == base.priority.rawValue {
                merged.priority = PriorityLevel(rawValue: localPriority) ?? remote.priority
            } else if localPriority != remote.priority.rawValue {
                conflicts.append(ConflictingField(
                    fieldName: "priority",
                    baseValue: String(base.priority.rawValue),
                    localValue: String(localPriority),
                    remoteValue: String(remote.priority.rawValue)
                ))
            }
        }

        // Check assignee
        if let localAssignee = local.assignee {
            let baseAssignee = base.assignee ?? ""
            let remoteAssignee = remote.assignee ?? ""

            if remoteAssignee == baseAssignee {
                merged.assignee = localAssignee.isEmpty ? nil : localAssignee
            } else if localAssignee != remoteAssignee {
                conflicts.append(ConflictingField(
                    fieldName: "assignee",
                    baseValue: baseAssignee,
                    localValue: localAssignee,
                    remoteValue: remoteAssignee
                ))
            }
        }

        if conflicts.isEmpty {
            // Update the updatedAt timestamp
            merged.updatedAt = Date()
            return .success(merged)
        } else {
            return .conflict(conflicts)
        }
    }

    static func applyResolution(to issue: inout Issue, field: String, value: String) {
        switch field {
        case "title":
            issue.title = value
        case "description":
            issue.description = value
        case "status":
            issue.status = IssueStatus(rawValue: value) ?? issue.status
        case "priority":
            if let intValue = Int(value) {
                issue.priority = PriorityLevel(rawValue: intValue) ?? issue.priority
            }
        case "assignee":
            issue.assignee = value.isEmpty ? nil : value
        default:
            break
        }
    }
}
