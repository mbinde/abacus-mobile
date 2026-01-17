import Foundation
import DeviceCheck
import CryptoKit

/// Handles App Attest for proving requests come from the legitimate iOS app.
///
/// Flow:
/// 1. On first launch, generate a key and attest it with Apple
/// 2. Store the key ID and attestation status in Keychain
/// 3. For each sensitive request, generate an assertion proving this request
///    came from the attested app instance
///
/// The server verifies:
/// - First request: The attestation blob (proves app is legitimate)
/// - Subsequent requests: Assertions signed with the attested key
actor AppAttestService {
    static let shared = AppAttestService()

    private let service = DCAppAttestService.shared
    private let keychainService = "com.abacus.mobile.appattest"

    // Stored after successful attestation
    private var keyId: String?
    private var isAttested: Bool = false
    private var didLoadState = false

    private init() {
        // State is loaded lazily on first access
    }

    /// Ensure stored state is loaded (call at start of public methods)
    private func ensureStateLoaded() {
        guard !didLoadState else { return }
        loadStoredState()
        didLoadState = true
    }

    // MARK: - Public API

    /// Check if App Attest is supported on this device
    var isSupported: Bool {
        service.isSupported
    }

    /// Returns true if we have a valid attested key
    var hasAttestedKey: Bool {
        ensureStateLoaded()
        return isAttested && keyId != nil
    }

    /// Prepare for attestation - generates key if needed, returns key ID
    /// Call this before the OAuth flow starts
    func prepareKey() async throws -> String {
        ensureStateLoaded()

        if let existingKeyId = keyId {
            return existingKeyId
        }

        // Generate a new key
        let newKeyId = try await service.generateKey()
        self.keyId = newKeyId
        saveKeyId(newKeyId)
        return newKeyId
    }

    /// Get the attestation for the key. Call this once per app install.
    /// The server needs to verify this attestation with Apple.
    ///
    /// - Parameter challenge: A server-provided challenge (nonce) to prevent replay
    /// - Returns: Base64-encoded attestation data to send to server
    func getAttestation(challenge: Data) async throws -> String {
        guard let keyId = keyId else {
            throw AppAttestError.noKey
        }

        // Create client data hash from the challenge
        let clientDataHash = SHA256.hash(data: challenge)
        let hashData = Data(clientDataHash)

        let attestation = try await service.attestKey(keyId, clientDataHash: hashData)

        // Mark as attested (server will verify)
        self.isAttested = true
        saveAttestedState(true)

        return attestation.base64EncodedString()
    }

    /// Generate an assertion for a request. Use this for each sensitive API call
    /// after attestation has been verified.
    ///
    /// - Parameter requestData: The request payload to sign (prevents tampering)
    /// - Returns: Base64-encoded assertion to include in request headers
    func generateAssertion(for requestData: Data) async throws -> String {
        guard let keyId = keyId else {
            throw AppAttestError.noKey
        }

        guard isAttested else {
            throw AppAttestError.notAttested
        }

        // Hash the request data
        let clientDataHash = SHA256.hash(data: requestData)
        let hashData = Data(clientDataHash)

        let assertion = try await service.generateAssertion(keyId, clientDataHash: hashData)
        return assertion.base64EncodedString()
    }

    /// Reset attestation state (e.g., if server rejects our attestation)
    func reset() {
        keyId = nil
        isAttested = false
        clearStoredState()
    }

    // MARK: - Persistence

    private func loadStoredState() {
        if let keyIdData = KeychainHelper.load(service: keychainService, account: "keyId"),
           let storedKeyId = String(data: keyIdData, encoding: .utf8) {
            self.keyId = storedKeyId
        }

        if let attestedData = KeychainHelper.load(service: keychainService, account: "isAttested"),
           let attestedString = String(data: attestedData, encoding: .utf8) {
            self.isAttested = attestedString == "true"
        }
    }

    private func saveKeyId(_ keyId: String) {
        if let data = keyId.data(using: .utf8) {
            KeychainHelper.save(data, service: keychainService, account: "keyId")
        }
    }

    private func saveAttestedState(_ attested: Bool) {
        if let data = (attested ? "true" : "false").data(using: .utf8) {
            KeychainHelper.save(data, service: keychainService, account: "isAttested")
        }
    }

    private func clearStoredState() {
        KeychainHelper.delete(service: keychainService, account: "keyId")
        KeychainHelper.delete(service: keychainService, account: "isAttested")
    }
}

enum AppAttestError: LocalizedError {
    case notSupported
    case noKey
    case notAttested
    case attestationFailed(String)
    case assertionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "App Attest is not supported on this device"
        case .noKey:
            return "No attestation key available"
        case .notAttested:
            return "App has not been attested yet"
        case .attestationFailed(let message):
            return "Attestation failed: \(message)"
        case .assertionFailed(let message):
            return "Assertion failed: \(message)"
        }
    }
}
