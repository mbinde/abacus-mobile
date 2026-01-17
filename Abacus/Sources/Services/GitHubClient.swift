import Foundation

class GitHubClient {
    private let token: String
    private let baseURL = "https://api.github.com"
    private let session: URLSession

    init(token: String) {
        self.token = token

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "Abacus-iOS"
        ]
        self.session = URLSession(configuration: config)
    }

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    func getCurrentUser() async throws -> GitHubUser {
        let request = makeRequest("/user")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    func checkBeadsDirectory(owner: String, repo: String) async throws -> Bool {
        let request = makeRequest("/repos/\(owner)/\(repo)/contents/.beads")
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        return httpResponse.statusCode == 200
    }

    func fetchIssues(owner: String, repo: String) async throws -> [Issue] {
        // Fetch the issues.jsonl file from .beads directory
        let request = makeRequest("/repos/\(owner)/\(repo)/contents/.beads/issues.jsonl")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                return [] // No issues file yet
            }
            throw GitHubError.httpError(httpResponse.statusCode)
        }

        // GitHub returns file content as base64 encoded
        let fileResponse = try JSONDecoder().decode(GitHubFileResponse.self, from: data)

        guard let content = fileResponse.content,
              let decodedData = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: "")) else {
            throw GitHubError.invalidContent
        }

        return try BeadsParser.parse(data: decodedData)
    }

    func updateIssue(_ issue: Issue, owner: String, repo: String) async throws {
        // First, get current file to get its SHA
        let getRequest = makeRequest("/repos/\(owner)/\(repo)/contents/.beads/issues.jsonl")
        let (getData, getResponse) = try await session.data(for: getRequest)

        guard let httpResponse = getResponse as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GitHubError.invalidResponse
        }

        let fileResponse = try JSONDecoder().decode(GitHubFileResponse.self, from: getData)

        guard let currentContent = fileResponse.content,
              let currentData = Data(base64Encoded: currentContent.replacingOccurrences(of: "\n", with: "")) else {
            throw GitHubError.invalidContent
        }

        // Parse current issues
        var issues = try BeadsParser.parse(data: currentData)

        // Update the issue
        if let index = issues.firstIndex(where: { $0.id == issue.id }) {
            issues[index] = issue
        }

        // Serialize back to JSONL
        let updatedContent = try BeadsParser.serialize(issues: issues)

        // Commit the update
        let commitBody = GitHubCommitRequest(
            message: "Update issue \(issue.id)",
            content: updatedContent.base64EncodedString(),
            sha: fileResponse.sha
        )

        let commitData = try JSONEncoder().encode(commitBody)
        let putRequest = makeRequest("/repos/\(owner)/\(repo)/contents/.beads/issues.jsonl", method: "PUT", body: commitData)

        let (_, putResponse) = try await session.data(for: putRequest)

        guard let putHttpResponse = putResponse as? HTTPURLResponse,
              (200...201).contains(putHttpResponse.statusCode) else {
            throw GitHubError.commitFailed
        }
    }

    func createIssue(_ issue: Issue, owner: String, repo: String) async throws {
        // Similar to updateIssue but appends to the file
        let getRequest = makeRequest("/repos/\(owner)/\(repo)/contents/.beads/issues.jsonl")
        let (getData, getResponse) = try await session.data(for: getRequest)

        var existingIssues: [Issue] = []
        var existingSha: String?

        if let httpResponse = getResponse as? HTTPURLResponse,
           httpResponse.statusCode == 200 {
            let fileResponse = try JSONDecoder().decode(GitHubFileResponse.self, from: getData)
            existingSha = fileResponse.sha

            if let content = fileResponse.content,
               let data = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: "")) {
                existingIssues = try BeadsParser.parse(data: data)
            }
        }

        existingIssues.append(issue)

        let updatedContent = try BeadsParser.serialize(issues: existingIssues)

        var commitBody: GitHubCommitRequest
        if let sha = existingSha {
            commitBody = GitHubCommitRequest(
                message: "Create issue \(issue.id)",
                content: updatedContent.base64EncodedString(),
                sha: sha
            )
        } else {
            commitBody = GitHubCommitRequest(
                message: "Create issue \(issue.id)",
                content: updatedContent.base64EncodedString(),
                sha: nil
            )
        }

        let commitData = try JSONEncoder().encode(commitBody)
        let putRequest = makeRequest("/repos/\(owner)/\(repo)/contents/.beads/issues.jsonl", method: "PUT", body: commitData)

        let (_, putResponse) = try await session.data(for: putRequest)

        guard let putHttpResponse = putResponse as? HTTPURLResponse,
              (200...201).contains(putHttpResponse.statusCode) else {
            throw GitHubError.commitFailed
        }
    }
}

struct GitHubFileResponse: Codable {
    let sha: String
    let content: String?
    let encoding: String?
}

struct GitHubCommitRequest: Codable {
    let message: String
    let content: String
    let sha: String?
}

enum GitHubError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case invalidContent
    case commitFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from GitHub"
        case .httpError(let code):
            return "GitHub API error: \(code)"
        case .invalidContent:
            return "Invalid file content"
        case .commitFailed:
            return "Failed to commit changes"
        }
    }
}
