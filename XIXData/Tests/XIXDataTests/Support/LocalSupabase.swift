// Integration-test support against the local Supabase stack (supabase start + db reset).
// Sessions are minted from the local JWT secret: Sign in with Apple cannot run in a test, and
// the seeded users have no password by design.
import Foundation
import Supabase
import XCTest
@testable import XIXData

enum LocalSupabase {
    static let url = URL(string: ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "http://127.0.0.1:54321")!
    static let anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
        ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    static let serviceKey = ProcessInfo.processInfo.environment["SUPABASE_SERVICE_ROLE_KEY"]
        ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
    static let jwtSecret = ProcessInfo.processInfo.environment["SUPABASE_JWT_SECRET"] ?? "super-secret-jwt-token-with-at-least-32-characters-long"

    // Seeded users (supabase/seed.sql)
    static let ray = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let dave = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let mo = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let tess = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    /// Right after `supabase db reset` the containers restart. Wait until Auth, PostgREST and Realtime
    /// answer, then open a throwaway subscription: Realtime connects its replication slot lazily on the
    /// first subscriber, and the first real test would otherwise race that. Once per process.
    private static var primed = false
    static func awaitReady() async {
        if primed { return }
        primed = true
        let deadline = Date().addingTimeInterval(90)
        var okAuth = false, okRest = false, okRealtime = false
        while Date() < deadline && !(okAuth && okRest && okRealtime) {
            okAuth = okAuth || probe(url.appendingPathComponent("auth/v1/health")) != nil
            okRest = okRest || probe(url.appendingPathComponent("rest/v1/"), apikey: true) != nil
            okRealtime = okRealtime || (probe(url.appendingPathComponent("realtime/v1/api/tenants/realtime-dev/health"), apikey: true)?.contains("\"healthy\":true") ?? false)
            if !(okAuth && okRest && okRealtime) { try? await Task.sleep(for: .milliseconds(500)) }
        }
        precondition(okAuth && okRest && okRealtime, "local Supabase not ready: auth \(okAuth) rest \(okRest) realtime \(okRealtime)")
        // Prime the replication connection.
        let primer = service.realtimeV2.channel("xix:test-primer")
        _ = primer.postgresChange(AnyAction.self, schema: "xix", table: "rounds")
        await primer.subscribe()
        let slotDeadline = Date().addingTimeInterval(30)
        while Date() < slotDeadline {
            if probe(url.appendingPathComponent("realtime/v1/api/tenants/realtime-dev/health"), apikey: true)?.contains("\"replication_connected\":true") == true { break }
            try? await Task.sleep(for: .milliseconds(300))
        }
        await primer.unsubscribe()
        await service.realtimeV2.removeChannel(primer)
    }

    /// The response body when the endpoint answers 2xx/3xx, else nil.
    private static func probe(_ url: URL, apikey: Bool = false) -> String? {
        var request = URLRequest(url: url, timeoutInterval: 3)
        if apikey {
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: String? = nil
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let status = (response as? HTTPURLResponse)?.statusCode, (200..<400).contains(status) {
                result = String(decoding: data ?? Data(), as: UTF8.self)
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return result
    }

    /// A real local session: the service role sets a password on the user and the client signs in with
    /// it. Sign in with Apple cannot run in a test; minted JWTs are refused for lacking a session row;
    /// magic links set `recovery_sent_at`, which trips supabase-swift's session storage migrations.
    static func signIn(_ client: XIXClient, userID: UUID, email: String) async throws {
        await awaitReady()
        let password = "xix-local-test-\(userID.uuidString.prefix(8))"
        _ = try await service.auth.admin.updateUserById(userID, attributes: AdminUserAttributes(password: password))
        _ = try await client.supabase.auth.signIn(email: email, password: password)
        _ = try await AuthService(client: client).ensureProfile()
    }

    /// A client signed in as the seeded user with its own in-memory store and session storage.
    static func client(as user: UUID, email: String, label: String) async throws -> XIXClient {
        let client = XIXClient(url: url, anonKey: anonKey, store: try LocalStore.inMemory(), authStorage: MemoryAuthStorage(), storageKey: "xix.test.\(label)")
        try await signIn(client, userID: user, email: email)
        precondition(client.userID == user, "seeded user id mismatch for \(email)")
        return client
    }

    /// One service-role client for the whole test process: supabase-swift keys internal state by client
    /// identity, and a client released mid-request crashes.
    static let service: SupabaseClient = SupabaseClient(
        supabaseURL: url, supabaseKey: serviceKey,
        options: SupabaseClientOptions(db: .init(schema: "xix"), auth: .init(storage: MemoryAuthStorage(), storageKey: "xix.test.service")))

    /// Ray creates a live 18-hole par-4 round with Dave and a guest as unclaimed rows.
    static func freshRound(owner: XIXClient, guestNames: [String] = ["Dave", "Guest"]) async throws -> RoundBundle {
        try await RoundRepository(client: owner).createRound(
            course: CourseDraft(name: "Test Links", region: "Local", par: Array(repeating: 4, count: 18)),
            holes: 18, ownerName: "Ray", guestNames: guestNames)
    }

    /// Wait until `condition` holds, polling; fails the test after `timeout`.
    static func waitUntil(_ timeout: TimeInterval = 5, _ label: String, file: StaticString = #filePath, line: UInt = #line,
                          _ condition: () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("timed out waiting for \(label)", file: file, line: line)
    }
}
