import SwiftUI
import AuthenticationServices
import CryptoKit

@MainActor
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var currentUser: GitHubUser?
    @Published var accessToken: String?

    // Configuration - set these for your deployment
    // The backend URL should be your abacus Cloudflare worker
    private let backendURL = "https://abacus.example.com" // TODO: Replace with your abacus URL
    private let clientId = "YOUR_GITHUB_CLIENT_ID" // TODO: Replace with actual client ID
    private let redirectUri = "abacus://oauth/callback"
    private let keychainService = "com.abacus.mobile"

    private let appAttest = AppAttestService.shared

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
        // Call our backend to exchange the OAuth code for an access token
        // The backend holds the client_secret securely
        // We use App Attest to prove this request comes from the legitimate iOS app

        guard let url = URL(string: "\(backendURL)/api/auth/mobile/token") else {
            throw AuthError.invalidURL
        }

        // Build the request body
        let requestBody = TokenExchangeRequest(
            code: code,
            redirectUri: redirectUri
        )
        let bodyData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        // Add App Attest headers
        try await addAppAttestHeaders(to: &request, bodyData: bodyData)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let tokenResponse = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)

            // Validate the token by fetching the user
            let client = GitHubClient(token: tokenResponse.accessToken)
            let user = try await client.getCurrentUser()

            self.accessToken = tokenResponse.accessToken
            self.currentUser = user
            self.isAuthenticated = true

            saveCredentials(token: tokenResponse.accessToken, user: user)

        case 400:
            let errorResponse = try? JSONDecoder().decode(TokenExchangeError.self, from: data)
            throw AuthError.tokenExchangeFailed(errorResponse?.error ?? "Bad request")

        case 401, 403:
            // Could be attestation failure - reset and try again next time
            let errorResponse = try? JSONDecoder().decode(TokenExchangeError.self, from: data)
            if errorResponse?.error.contains("attestation") == true {
                await appAttest.reset()
            }
            throw AuthError.unauthorized

        default:
            throw AuthError.httpError(httpResponse.statusCode)
        }
    }

    /// Add App Attest headers to a request for server verification
    private func addAppAttestHeaders(to request: inout URLRequest, bodyData: Data) async throws {
        // Check if App Attest is supported
        let isSupported = await appAttest.isSupported
        guard isSupported else {
            // Fall back to non-attested request (server may reject)
            request.setValue("false", forHTTPHeaderField: "X-App-Attest-Supported")
            return
        }

        request.setValue("true", forHTTPHeaderField: "X-App-Attest-Supported")

        // Prepare the key if we don't have one
        let keyId = try await appAttest.prepareKey()
        request.setValue(keyId, forHTTPHeaderField: "X-App-Attest-Key-Id")

        // Check if we need to send attestation or assertion
        let hasAttestedKey = await appAttest.hasAttestedKey

        if !hasAttestedKey {
            // First time: need to attest the key
            // Get a challenge from the server first
            let (challenge, challengeId) = try await fetchAttestationChallenge()
            let attestation = try await appAttest.getAttestation(challenge: challenge)

            request.setValue(attestation, forHTTPHeaderField: "X-App-Attest-Attestation")
            request.setValue(challenge.base64EncodedString(), forHTTPHeaderField: "X-App-Attest-Challenge")
            request.setValue(challengeId, forHTTPHeaderField: "X-App-Attest-Challenge-Id")
        } else {
            // Subsequent requests: send an assertion
            let assertion = try await appAttest.generateAssertion(for: bodyData)
            request.setValue(assertion, forHTTPHeaderField: "X-App-Attest-Assertion")
        }
    }

    /// Fetch a challenge nonce from the server for attestation
    /// Returns (challengeData, challengeId)
    private func fetchAttestationChallenge() async throws -> (Data, String) {
        guard let url = URL(string: "\(backendURL)/api/auth/mobile/challenge") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.invalidResponse
        }

        let challengeResponse = try JSONDecoder().decode(ChallengeResponse.self, from: data)

        guard let challengeData = Data(base64Encoded: challengeResponse.challenge) else {
            throw AuthError.invalidResponse
        }

        return (challengeData, challengeResponse.challengeId)
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
    case invalidResponse
    case tokenExchangeFailed(String)
    case unauthorized
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to create authentication URL"
        case .noCallback:
            return "No callback received from authentication"
        case .invalidCallback:
            return "Invalid callback from authentication"
        case .invalidResponse:
            return "Invalid response from server"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .unauthorized:
            return "Unauthorized"
        case .httpError(let code):
            return "Server error: \(code)"
        }
    }
}

// MARK: - Token Exchange Types

struct TokenExchangeRequest: Codable {
    let code: String
    let redirectUri: String

    enum CodingKeys: String, CodingKey {
        case code
        case redirectUri = "redirect_uri"
    }
}

struct TokenExchangeResponse: Codable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct TokenExchangeError: Codable {
    let error: String
}

struct ChallengeResponse: Codable {
    let challenge: String
    let challengeId: String
}
