import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext

        // Create sample data for previews
        let repo = CachedRepository(context: viewContext)
        repo.id = UUID()
        repo.owner = "example"
        repo.name = "project"
        repo.lastSynced = Date()

        for i in 0..<5 {
            let issue = CachedIssue(context: viewContext)
            issue.id = UUID()
            issue.beadsId = "task-\(String(format: "%03d", i))"
            issue.title = "Sample Issue \(i + 1)"
            issue.issueDescription = "This is a sample issue description for testing purposes."
            issue.status = ["open", "in_progress", "closed"][i % 3]
            issue.priority = Int16((i % 4) + 1)
            issue.issueType = "task"
            issue.createdAt = Date()
            issue.repository = repo
        }

        try? viewContext.save()
        return controller
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Abacus")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure for CloudKit sync
            guard let description = container.persistentStoreDescriptions.first else {
                fatalError("Failed to get persistent store description")
            }

            // Enable CloudKit sync
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.abacus.mobile"
            )

            // Enable remote change notifications
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // Enable persistent history tracking
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        }

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                // In production, handle this more gracefully
                fatalError("Failed to load persistent stores: \(error)")
            }
        }

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Listen for remote changes
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            // Handle remote changes if needed
        }
    }

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Failed to save context: \(error)")
            }
        }
    }
}

// MARK: - Preview Helpers

extension CachedIssue {
    static var preview: CachedIssue {
        let context = PersistenceController.preview.container.viewContext
        let issue = CachedIssue(context: context)
        issue.id = UUID()
        issue.beadsId = "task-001"
        issue.title = "Preview Issue"
        issue.issueDescription = "This is a preview issue for SwiftUI previews."
        issue.status = "open"
        issue.priority = 2
        issue.issueType = "task"
        issue.assignee = "developer"
        issue.createdAt = Date()
        issue.updatedAt = Date()
        return issue
    }
}
