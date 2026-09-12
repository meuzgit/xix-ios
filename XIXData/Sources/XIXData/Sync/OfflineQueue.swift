// FIFO outbox drained when online. Every call is idempotent on the server. A server rejection removes
// the item and reports it so the session can revert the local row; a network failure keeps it queued
// (Build Doc 2 C.3).
import Foundation
import Supabase
import XIXModels

public enum QueueEvent: Sendable, Equatable {
    case sent(Mutation)
    case rejected(Mutation, message: String)
    case drained
}

public actor OfflineQueue {
    private let client: XIXClient
    private let connectivity: Connectivity
    private var draining = false
    private var listeners: [UUID: AsyncStream<QueueEvent>.Continuation] = [:]
    private var watchTask: Task<Void, Never>?

    public init(client: XIXClient, connectivity: Connectivity) {
        self.client = client
        self.connectivity = connectivity
    }

    /// Start draining whenever connectivity comes back.
    public func start() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await online in await connectivity.changes() where online {
                await self.drain()
            }
        }
    }

    public func stop() { watchTask?.cancel(); watchTask = nil }

    public func events() -> AsyncStream<QueueEvent> {
        let id = UUID()
        return AsyncStream { c in
            listeners[id] = c
            c.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        }
    }

    private func removeListener(_ id: UUID) { listeners[id] = nil }

    public func pendingCount() -> Int { (try? client.store.outbox().count) ?? 0 }

    /// Queue a mutation (already written locally) and drain if we can.
    public func enqueue(_ mutation: Mutation, clientTs: Date) async throws {
        let data = try JSONEncoder().encode(mutation)
        _ = try client.store.enqueue(OutboxItem(id: nil, round_id: mutation.roundID, payload: String(decoding: data, as: UTF8.self),
                                                client_ts: clientTs.timeIntervalSince1970, created_at: Date().timeIntervalSince1970,
                                                attempts: 0, last_error: nil))
        if await connectivity.isOnline { await drain() }
    }

    public func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        let play = PlayRepository(client: client)
        while await connectivity.isOnline, let item = (try? client.store.outbox())?.first, let id = item.id {
            guard let mutation = try? JSONDecoder().decode(Mutation.self, from: Data(item.payload.utf8)) else {
                try? client.store.removeOutbox(id: id); continue
            }
            do {
                switch mutation {
                case .enterScore(let roundID, let playerID, let hole, let strokes, let pickedUp, let clientTs):
                    let row = try await play.enterScore(roundID: roundID, playerID: playerID, hole: hole, strokes: strokes, pickedUp: pickedUp, clientTs: clientTs)
                    // The server keeps the newest client_ts; if ours lost, the row it returns is the truth.
                    _ = try? client.store.applyRemoteScore(LocalScore(row: row, pending: false))
                case .sendSticker(let localID, let roundID, let hole, let target, let key, let pack):
                    let row = try await play.sendSticker(roundID: roundID, hole: hole, targetPlayerID: target, stickerKey: key, packKey: pack)
                    // The server minted the sticker's id; swap the optimistic row for the real one.
                    try? client.store.replaceSticker(localID: localID, with: LocalSticker(row: row))
                case .createCallout(_, let roundID, let hole, let kind, let targets, let params):
                    try await play.createCallout(roundID: roundID, hole: hole, kind: kind, targets: targets, params: params)
                case .respondCallout(_, let calloutID, let action):
                    try await play.respondCallout(calloutID: calloutID, action: action)
                case .markStickerPlayed(_, let stickerID):
                    try await play.markStickerPlayed(stickerID: stickerID)
                }
                try? client.store.removeOutbox(id: id)
                emit(.sent(mutation))
            } catch let error as PostgrestError {
                // The server answered and said no: drop it and let the session revert.
                try? client.store.removeOutbox(id: id)
                emit(.rejected(mutation, message: error.message))
            } catch {
                // Network or transport: keep it and stop for now.
                try? client.store.markOutboxFailure(id: id, error: String(describing: error))
                break
            }
        }
        emit(.drained)
    }

    private func emit(_ event: QueueEvent) {
        for l in listeners.values { l.yield(event) }
    }
}

extension LocalScore {
    public init(row: ScoreRow, pending: Bool) {
        self.init(round_id: row.roundId, player_id: row.playerId, hole: Int(row.hole), strokes: row.strokes.map(Int.init),
                  picked_up: row.pickedUp, entered_by: row.enteredBy,
                  client_ts: (row.clientDate ?? row.updatedDate ?? Date()).timeIntervalSince1970,
                  updated_at: (row.updatedDate ?? Date()).timeIntervalSince1970, pending: pending)
    }
}
