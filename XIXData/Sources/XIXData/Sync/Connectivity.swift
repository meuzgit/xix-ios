// Network reachability with an override for tests (airplane mode without airplane mode).
import Foundation
import Network

public actor Connectivity {
    private let monitor = NWPathMonitor()
    private var pathOnline = true
    private var override: Bool?
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    public init(startMonitoring: Bool = true) {
        if startMonitoring {
            monitor.pathUpdateHandler = { [weak self] path in
                Task { await self?.update(pathOnline: path.status == .satisfied) }
            }
            monitor.start(queue: DispatchQueue(label: "xix.connectivity"))
        }
    }

    public var isOnline: Bool { override ?? pathOnline }

    /// Tests and previews: force offline or online; nil follows the real path again.
    public func setOverride(_ online: Bool?) {
        override = online
        broadcast()
    }

    private func update(pathOnline: Bool) {
        self.pathOnline = pathOnline
        broadcast()
    }

    private func broadcast() {
        for c in continuations.values { c.yield(isOnline) }
    }

    /// Emits the current value first, then every change.
    public func changes() -> AsyncStream<Bool> {
        let id = UUID()
        let current = isOnline
        return AsyncStream { continuation in
            continuation.yield(current)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.remove(id) } }
        }
    }

    private func remove(_ id: UUID) { continuations[id] = nil }
}
