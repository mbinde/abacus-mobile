import SwiftUI
import CoreData

struct RepositoriesView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CachedRepository.name, ascending: true)],
        animation: .default
    )
    private var repositories: FetchedResults<CachedRepository>

    @State private var showingAddRepo = false
    @State private var newRepoURL = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(repositories) { repo in
                    RepositoryRowView(repository: repo)
                }
                .onDelete(perform: deleteRepositories)
            }
            .navigationTitle("Repositories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddRepo = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if repositories.isEmpty {
                    ContentUnavailableView(
                        "No Repositories",
                        systemImage: "folder.badge.plus",
                        description: Text("Add a repository with a .beads directory")
                    )
                }
            }
            .sheet(isPresented: $showingAddRepo) {
                AddRepositorySheet(isPresented: $showingAddRepo)
            }
        }
    }

    private func deleteRepositories(offsets: IndexSet) {
        withAnimation {
            offsets.map { repositories[$0] }.forEach(viewContext.delete)
            try? viewContext.save()
        }
    }
}

struct RepositoryRowView: View {
    let repository: CachedRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(repository.owner ?? "")/\(repository.name ?? "")")
                .font(.headline)

            if let lastSynced = repository.lastSynced {
                Text("Last synced: \(lastSynced.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddRepositorySheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.managedObjectContext) private var viewContext

    @State private var repoInput = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("owner/repo", text: $repoInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Repository")
                } footer: {
                    Text("Enter a GitHub repository that has a .beads directory")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRepository()
                    }
                    .disabled(repoInput.isEmpty || isLoading)
                }
            }
        }
    }

    private func addRepository() {
        guard let (owner, name) = parseRepoInput(repoInput) else {
            errorMessage = "Invalid format. Use owner/repo"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let gitHubClient = GitHubClient(token: authManager.accessToken ?? "")
                let hasBeads = try await gitHubClient.checkBeadsDirectory(owner: owner, repo: name)

                if hasBeads {
                    await MainActor.run {
                        let repo = CachedRepository(context: viewContext)
                        repo.id = UUID()
                        repo.owner = owner
                        repo.name = name
                        repo.lastSynced = nil
                        try? viewContext.save()
                        isPresented = false
                    }
                } else {
                    errorMessage = "Repository doesn't have a .beads directory"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func parseRepoInput(_ input: String) -> (owner: String, name: String)? {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/")
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

#Preview {
    RepositoriesView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AuthManager.shared)
}
