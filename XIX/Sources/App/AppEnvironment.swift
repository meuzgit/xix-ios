// Everything the screens share: the client for the chosen backend, auth, repositories, the local store,
// live round sessions, and the lazy sign-in gate (Build Doc 2 C.4: identity is asked for at the first
// action that needs one).
import Foundation
import Observation
import Supabase
import XIXData
import XIXModels

@Observable @MainActor
final class AppEnvironment {
    private(set) var backend: Backend
    private(set) var client: XIXClient
    private(set) var auth: AuthService
    private(set) var rounds: RoundRepository
    private(set) var play: PlayRepository
    private(set) var connectivity = Connectivity()
    let router = Router()

    var isSignedIn = false
    var profile: ProfileRow?
    var displayName: String { profile?.displayName ?? auth.displayName ?? "You" }
    var userID: UUID? { client.userID }

    /// A pending request for identity; RootView presents the sign-in sheet while one is set.
    var signInRequest: SignInRequest?
    var quietRounds: Set<UUID> = Set((UserDefaults.standard.array(forKey: "xix.quiet") as? [String] ?? []).compactMap(UUID.init))

    private var sessions: [UUID: RoundSession] = [:]

    init() {
        let b = Backend.current
        let made = AppEnvironment.make(b)
        backend = b; client = made.client; auth = made.auth; rounds = made.rounds; play = made.play
        Task { await restore() }
    }

    private static func make(_ b: Backend) -> (client: XIXClient, auth: AuthService, rounds: RoundRepository, play: PlayRepository) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let store = (try? LocalStore.onDisk(at: support.appendingPathComponent("xix-\(b.rawValue).sqlite"))) ?? (try! LocalStore.inMemory())
        let url = b.url ?? URL(string: "http://127.0.0.1:54321")!
        let client = XIXClient(url: url, anonKey: b.anonKey ?? "", store: store, storageKey: "xix.auth.\(b.rawValue)")
        return (client, AuthService(client: client), RoundRepository(client: client), PlayRepository(client: client))
    }

    func restore() async {
        if await auth.restoreSession() != nil {
            isSignedIn = true
            profile = try? await auth.ensureProfile()
        } else {
            isSignedIn = false
            profile = nil
        }
    }

    // MARK: Backend switch (debug menu)

    func switchBackend(_ b: Backend) async {
        guard b != backend else { return }
        for s in sessions.values { await s.stop() }
        sessions = [:]
        Backend.current = b
        let made = AppEnvironment.make(b)
        backend = b; client = made.client; auth = made.auth; rounds = made.rounds; play = made.play
        router.home()
        await restore()
    }

    // MARK: Sign-in gate

    struct SignInRequest: Identifiable {
        let id = UUID()
        let reason: String
        let continuation: CheckedContinuation<Bool, Never>
    }

    /// True once signed in, asking with the Sign in with Apple sheet if needed. False when dismissed.
    func requireSignIn(reason: String) async -> Bool {
        if isSignedIn { return true }
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            signInRequest = SignInRequest(reason: reason, continuation: c)
        }
        return ok
    }

    func finishSignIn(success: Bool) {
        let request = signInRequest
        signInRequest = nil
        if success { isSignedIn = true }
        request?.continuation.resume(returning: success)
    }

    func signedIn(profile p: ProfileRow) {
        profile = p
        isSignedIn = true
    }

    func signOut() async {
        for s in sessions.values { await s.stop() }
        sessions = [:]
        try? await auth.signOut()
        isSignedIn = false
        profile = nil
        router.home()
    }

    // MARK: Sessions

    /// One live session per round, kept while the round or its results are on screen.
    func session(for roundID: UUID) async throws -> RoundSession {
        if let s = sessions[roundID] { return s }
        let s = RoundSession(client: client, roundID: roundID, connectivity: connectivity)
        try await s.start()
        sessions[roundID] = s
        return s
    }

    func closeSessions() async {
        for s in sessions.values { await s.stop() }
        sessions = [:]
    }

    // MARK: Quiet mode per round

    func isQuiet(_ roundID: UUID) -> Bool { quietRounds.contains(roundID) || UserDefaults.standard.bool(forKey: "xix.quietDefault") }
    func setQuiet(_ roundID: UUID, _ on: Bool) {
        if on { quietRounds.insert(roundID) } else { quietRounds.remove(roundID) }
        UserDefaults.standard.set(quietRounds.map(\.uuidString), forKey: "xix.quiet")
    }
}
