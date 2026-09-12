// Sign in with Apple on the shared Meuz auth (Build Doc 2 C.4). No anonymous tier, no linking.
// The Apple credential UI lives in the app; this exchanges the identity token and creates the profile.
import Foundation
import CryptoKit
import Supabase
import XIXModels

public struct AuthService: Sendable {
    let client: XIXClient
    public init(client: XIXClient) { self.client = client }

    public var currentUserID: UUID? { client.userID }
    public var isSignedIn: Bool { client.supabase.auth.currentSession != nil }

    /// Exchange an Apple identity token for a session, then create the profile (first sign-in) with the
    /// name from the credential when Apple provided one.
    @discardableResult
    public func signInWithApple(idToken: String, nonce: String, displayName: String? = nil) async throws -> ProfileRow {
        _ = try await client.supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
        if let displayName, !displayName.isEmpty {
            _ = try? await client.supabase.auth.update(user: UserAttributes(data: ["display_name": .string(displayName)]))
        }
        return try await ensureProfile()
    }

    /// Adopt an existing session (result links, tests). Also creates the profile if missing.
    @discardableResult
    public func adoptSession(accessToken: String, refreshToken: String) async throws -> ProfileRow {
        _ = try await client.supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
        return try await ensureProfile()
    }

    /// The name Apple gave us at first sign-in (or the one set since), if any.
    public var displayName: String? {
        if case .string(let s)? = client.supabase.auth.currentUser?.userMetadata["display_name"], !s.isEmpty { return s }
        return nil
    }

    /// Email and password on the local stack only (the debug menu; the shared project has no email sign-up).
    /// Creates the account when it does not exist yet. Never used on a Release build.
    @discardableResult
    public func signInLocally(email: String, password: String, displayName: String) async throws -> ProfileRow {
        do {
            _ = try await client.supabase.auth.signIn(email: email, password: password)
        } catch {
            _ = try await client.supabase.auth.signUp(email: email, password: password, data: ["display_name": .string(displayName)])
            if client.supabase.auth.currentSession == nil { _ = try await client.supabase.auth.signIn(email: email, password: password) }
        }
        return try await ensureProfile()
    }

    /// The persisted session, refreshed if needed; nil when signed out.
    public func restoreSession() async -> Session? {
        try? await client.supabase.auth.session
    }

    /// Upserts the caller's xix.profiles row; idempotent.
    public func ensureProfile() async throws -> ProfileRow {
        try await client.supabase.rpc("ensure_profile").single().execute().value
    }

    public func signOut() async throws {
        try await client.supabase.auth.signOut()
    }

    /// Sign in with Apple nonce: the raw value goes to Apple, the SHA-256 hex goes in the request.
    public static func makeNonce() -> (raw: String, hashed: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let raw = bytes.map { String(format: "%02x", $0) }.joined()
        let hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }
}
