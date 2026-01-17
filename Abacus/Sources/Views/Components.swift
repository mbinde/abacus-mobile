import SwiftUI

struct StatusBadge: View {
    let status: IssueStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.2))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }
}

struct PriorityBadge: View {
    let priority: PriorityLevel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<priority.rawValue, id: \.self) { _ in
                Image(systemName: "exclamationmark")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(priority.color)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            ForEach(IssueStatus.allCases, id: \.self) { status in
                StatusBadge(status: status)
            }
        }

        HStack(spacing: 16) {
            ForEach(PriorityLevel.allCases, id: \.self) { priority in
                VStack {
                    PriorityBadge(priority: priority)
                    Text(priority.displayName)
                        .font(.caption)
                }
            }
        }
    }
    .padding()
}
