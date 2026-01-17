import SwiftUI
import AuthenticationServices

@MainActor
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var currentUser: GitHubUser?
    @Published var accessToken: String?

    private let clientId = "YOUR_GITHUB_CLIENT_ID" // TODO: Replace with actual client ID
    private let redirectUri = "abacus://oauth/callback"
    private let keychainService = "com.abacus.mobile"

    private override init() {
        super.init()
        loadStoredCredentials()
    }

    func signInWithGitHub() async throws {
        let state = UUID().uuidString
        let scope = "repo"

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else {
            throw AuthError.invalidURL
        }

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "abacus"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.noCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            throw AuthError.invalidCallback
        }

        try await exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) async throws {
        // Note: In production, this should go through your backend to keep client_secret secure
        // For now, we'll use a device flow or expect the user to provide a PAT

        // This is a placeholder - actual implementation would either:
        // 1. Call your backend to exchange the code
        // 2. Use GitHub's device flow
        // 3. Accept a PAT directly from the user

        throw AuthError.notImplemented("Token exchange requires backend support or PAT entry")
    }

    func signInWithPAT(_ token: String) async throws {
        let client = GitHubClient(token: token)
        let user = try await client.getCurrentUser()

        self.accessToken = token
        self.currentUser = user
        self.isAuthenticated = true

        saveCredentials(token: token, user: user)
    }

    func signOut() {
        accessToken = nil
        currentUser = nil
        isAuthenticated = false
        clearCredentials()
    }

    private func loadStoredCredentials() {
        guard let tokenData = KeychainHelper.load(service: keychainService, account: "accessToken"),
              let token = String(data: tokenData, encoding: .utf8) else {
            return
        }

        if let userData = KeychainHelper.load(service: keychainService, account: "currentUser"),
           let user = try? JSONDecoder().decode(GitHubUser.self, from: userData) {
            self.accessToken = token
            self.currentUser = user
            self.isAuthenticated = true
        }
    }

    private func saveCredentials(token: String, user: GitHubUser) {
        if let tokenData = token.data(using: .utf8) {
            KeychainHelper.save(tokenData, service: keychainService, account: "accessToken")
        }
        if let userData = try? JSONEncoder().encode(user) {
            KeychainHelper.save(userData, service: keychainService, account: "currentUser")
        }
    }

    private func clearCredentials() {
        KeychainHelper.delete(service: keychainService, account: "accessToken")
        KeychainHelper.delete(service: keychainService, account: "currentUser")
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

enum AuthError: LocalizedError {
    case invalidURL
    case noCallback
    case invalidCallback
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to create authentication URL"
        case .noCallback:
            return "No callback received from authentication"
        case .invalidCallback:
            return "Invalid callback from authentication"
        case .notImplemented(let message):
            return message
        }
    }
}

struct KeychainHelper {
    static func save(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]

        SecItemDelete(query as CFDictionary)
    }
}
