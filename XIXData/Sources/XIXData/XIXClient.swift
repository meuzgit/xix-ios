// The Supabase client configured for the xix schema, the local store and the client clock (Build Doc 2 C).
import Foundation
import Supabase

public final class XIXClient: @unchecked Sendable {
    public let supabase: SupabaseClient
    public let store: LocalStore
    public let clock: ClientClock

    /// - Parameters:
    ///   - authStorage: where sessions persist; nil uses the platform keychain. Tests pass `MemoryAuthStorage`.
    ///   - storageKey: keeps several clients in one process apart (tests run two users side by side).
    public init(url: URL, anonKey: String, store: LocalStore, authStorage: (any AuthLocalStorage)? = nil,
                storageKey: String = "xix.auth") {
        var authOptions = SupabaseClientOptions.AuthOptions(storageKey: storageKey)
        if let authStorage { authOptions = SupabaseClientOptions.AuthOptions(storage: authStorage, storageKey: storageKey) }
        supabase = SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(db: .init(schema: "xix"), auth: authOptions))
        self.store = store
        clock = ClientClock(store: store)
    }

    /// The signed-in user's id, if any.
    public var userID: UUID? { supabase.auth.currentUser?.id }
}

/// Session storage that lives for the process only. Used by tests and previews.
public final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func store(key: String, value: Data) throws { lock.lock(); values[key] = value; lock.unlock() }
    public func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    public func remove(key: String) throws { lock.lock(); values[key] = nil; lock.unlock() }
}
