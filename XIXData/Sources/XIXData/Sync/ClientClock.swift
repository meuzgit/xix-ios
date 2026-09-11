// client_ts source: a wall-clock timestamp that never goes backwards on this device, persisted so a
// restart cannot reissue an older stamp (Build Doc 2 C.3).
import Foundation

public actor ClientClock {
    private let store: LocalStore
    private var last: Double = 0

    init(store: LocalStore) {
        self.store = store
        last = (try? store.lastClockValue()) ?? 0
    }

    /// Millisecond precision: the value round-trips through ISO 8601 and the server unchanged.
    public func now() -> Date {
        var t = (Date().timeIntervalSince1970 * 1000).rounded() / 1000
        if t <= last { t = last + 0.001 }
        last = t
        try? store.saveClockValue(t)
        return Date(timeIntervalSince1970: t)
    }
}
