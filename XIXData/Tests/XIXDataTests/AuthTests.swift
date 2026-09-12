import Supabase
import XCTest
@testable import XIXData

/// D.5: an existing Meuz user signing into XIX is the same auth user, with a profile created lazily.
final class AuthTests: XCTestCase {
    func testExistingAuthUserIsTheSameUserInXIXAndProfileIsCreatedOnce() async throws {
        // An auth user that exists already (as an MMM user would), with no XIX profile.
        let admin = LocalSupabase.service
        let email = "mmm-\(UUID().uuidString.prefix(8))@privaterelay.appleid.com"
        let user = try await admin.auth.admin.createUser(attributes: AdminUserAttributes(
            email: email, emailConfirm: true, userMetadata: ["display_name": .string("Meuz Regular")]))

        let client = XIXClient(url: LocalSupabase.url, anonKey: LocalSupabase.anonKey, store: try LocalStore.inMemory(),
                               authStorage: MemoryAuthStorage(), storageKey: "xix.test.auth")
        let auth = AuthService(client: client)
        XCTAssertFalse(auth.isSignedIn, "first launch needs no sign-in")

        try await LocalSupabase.signIn(client, userID: user.id, email: email)
        let profile = try await auth.ensureProfile()
        XCTAssertEqual(profile.id, user.id, "the XIX profile is the shared auth user, no linking step")
        XCTAssertEqual(profile.displayName, "Meuz Regular")
        XCTAssertEqual(auth.currentUserID, user.id)

        let again = try await auth.ensureProfile()
        XCTAssertEqual(again.id, profile.id)
        let count: [ProfileRowLite] = try await client.supabase.schema("xix").from("profiles").select("id").eq("id", value: user.id).execute().value
        XCTAssertEqual(count.count, 1, "ensure_profile is idempotent")
        try await auth.signOut()
        XCTAssertFalse(auth.isSignedIn)
    }

    struct ProfileRowLite: Decodable { let id: UUID }
}
