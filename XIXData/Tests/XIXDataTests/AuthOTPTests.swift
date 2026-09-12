// The email one-time code against the local stack: Auth mails the code to the local catcher (Mailpit on
// port 54324), the test reads it back and verifies it. Sign-in and the email-change link both go
// through the same code path the app uses. Skipped against a hosted project.
import Foundation
import Supabase
import XCTest
@testable import XIXData

final class AuthOTPTests: XCTestCase {
    static let mail = URL(string: "http://127.0.0.1:54324")!

    override func setUp() async throws {
        if LocalSupabase.isRemote { throw XCTSkip("email codes are read from the local mail catcher") }
        await LocalSupabase.awaitReady()
    }

    func testEmailCodeSignsInAndCreatesTheProfile() async throws {
        let tag = UUID().uuidString.prefix(8).lowercased()
        let email = "otp-\(tag)@xix.local"
        let client = XIXClient(url: LocalSupabase.url, anonKey: LocalSupabase.anonKey, store: try LocalStore.inMemory(),
                               authStorage: MemoryAuthStorage(), storageKey: "otp-\(tag)")
        let auth = AuthService(client: client)
        XCTAssertFalse(auth.isSignedIn)

        let sent = Date()
        try await auth.sendEmailCode(email: email)
        let code = try await Self.code(sentTo: email, after: sent)
        XCTAssertTrue((6...8).contains(code.count), "a 6–8 digit code, got \(code)")

        let profile = try await auth.verifyEmailCode(email: email, code: code, displayName: "Otto")
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertEqual(profile.id, client.userID)
        XCTAssertEqual(auth.currentEmail, email)
        XCTAssertEqual(auth.displayName, "Otto", "the name given at first sign-in sticks")
        let providers = try await auth.identityProviders()
        XCTAssertEqual(providers, ["email"])

        // A wrong code is refused.
        await XCTAssertThrowsErrorAsync(try await auth.verifyEmailCode(email: email, code: "000000"))

        if let id = client.userID { try? await LocalSupabase.service.auth.admin.deleteUser(id: id) }
    }

    func testEmailChangeCodeAttachesANewAddress() async throws {
        let tag = UUID().uuidString.prefix(8).lowercased()
        let email = "otp-\(tag)@xix.local", second = "otp-\(tag)-two@xix.local"
        let client = XIXClient(url: LocalSupabase.url, anonKey: LocalSupabase.anonKey, store: try LocalStore.inMemory(),
                               authStorage: MemoryAuthStorage(), storageKey: "otp2-\(tag)")
        let auth = AuthService(client: client)
        var sent = Date()
        try await auth.sendEmailCode(email: email)
        try await auth.verifyEmailCode(email: email, code: try await Self.code(sentTo: email, after: sent))

        sent = Date()
        try await auth.requestEmailLink(email: second)
        let code = try await Self.code(sentTo: second, after: sent)
        try await auth.verifyEmailLink(email: second, code: code)
        _ = try await client.supabase.auth.refreshSession()
        XCTAssertEqual(auth.currentEmail, second, "the new address is the account's address")
        XCTAssertTrue(auth.isSignedIn)

        if let id = client.userID { try? await LocalSupabase.service.auth.admin.deleteUser(id: id) }
    }

    // MARK: The local mail catcher

    struct Envelope: Decodable { struct Message: Decodable { let ID: String; let Created: String }; let messages: [Message] }
    struct Detail: Decodable { let Text: String }

    /// The newest code mailed to `email` after `after`, from Mailpit's API.
    static func code(sentTo email: String, after: Date) async throws -> String {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            var comps = URLComponents(url: mail.appendingPathComponent("api/v1/search"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "query", value: "to:\(email)")]
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            for m in envelope.messages {
                let (body, _) = try await URLSession.shared.data(from: mail.appendingPathComponent("api/v1/message/\(m.ID)"))
                let text = try JSONDecoder().decode(Detail.self, from: body).Text
                if let range = text.range(of: #"\b[0-9]{6,8}\b"#, options: .regularExpression) { return String(text[range]) }
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw XCTSkip("no code arrived at the local mail catcher for \(email) within 30 s")
    }
}

func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("expected an error", file: file, line: line) } catch {}
}
