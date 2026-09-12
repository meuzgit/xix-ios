// Sign-in on the shared Meuz auth (Build Doc 2 C.4, step 1 amendment): Sign in with Apple, Google,
// and an email one-time code. No passwords, no magic links, no anonymous tier. The provider UIs live in
// the app; this exchanges tokens and codes for a session and creates the profile. A signed-in user can
// attach the other identities (linkIdentity with the provider's id token; the email-change code for email).
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

    /// Exchange a Google identity token (from the native Google Sign-In SDK) for a session.
    @discardableResult
    public func signInWithGoogle(idToken: String, accessToken: String?, displayName: String? = nil) async throws -> ProfileRow {
        _ = try await client.supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .google, idToken: idToken, accessToken: accessToken))
        if let displayName, !displayName.isEmpty, self.displayName == nil {
            _ = try? await client.supabase.auth.update(user: UserAttributes(data: ["display_name": .string(displayName)]))
        }
        return try await ensureProfile()
    }

    /// Email one-time code, step 1: send the code (creates the account on first use).
    public func sendEmailCode(email: String) async throws {
        try await client.supabase.auth.signInWithOTP(email: normalised(email), shouldCreateUser: true)
    }

    /// Email one-time code, step 2: the code from the email becomes a session.
    @discardableResult
    public func verifyEmailCode(email: String, code: String, displayName: String? = nil) async throws -> ProfileRow {
        _ = try await client.supabase.auth.verifyOTP(email: normalised(email), token: code.trimmingCharacters(in: .whitespaces), type: .email)
        if let displayName, !displayName.isEmpty, self.displayName == nil {
            _ = try? await client.supabase.auth.update(user: UserAttributes(data: ["display_name": .string(displayName)]))
        }
        return try await ensureProfile()
    }

    // MARK: Linking (Settings › Add another sign-in method)

    /// The identities attached to the signed-in user, by provider name ("apple", "google", "email").
    public func identityProviders() async throws -> [String] {
        try await client.supabase.auth.userIdentities().map(\.provider)
    }

    /// Attach an Apple identity to the signed-in user (a relay-email Apple user adds a real address later, or vice versa).
    public func linkApple(idToken: String, nonce: String) async throws {
        _ = try await client.supabase.auth.linkIdentityWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce))
    }

    public func linkGoogle(idToken: String, accessToken: String?) async throws {
        _ = try await client.supabase.auth.linkIdentityWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .google, idToken: idToken, accessToken: accessToken))
    }

    /// Attach an email address: Auth sends a code to the new address; `verifyEmailLink` confirms it.
    public func requestEmailLink(email: String) async throws {
        _ = try await client.supabase.auth.update(user: UserAttributes(email: normalised(email)))
    }

    public func verifyEmailLink(email: String, code: String) async throws {
        _ = try await client.supabase.auth.verifyOTP(email: normalised(email), token: code.trimmingCharacters(in: .whitespaces), type: .emailChange)
    }

    public var currentEmail: String? { client.supabase.auth.currentUser?.email }

    private func normalised(_ email: String) -> String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

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

    #if DEBUG
    /// Email and password on the local stack only (the debug sign-in; the shared project has no password
    /// sign-up). Creates the account when it does not exist yet. Compiled out of Release builds.
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
    #endif

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
