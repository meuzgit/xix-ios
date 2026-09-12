// The single source of truth for a live round on device (Build Doc 2 C.2): local store + local engine,
// one Realtime channel per round, last-write-wins per cell, merge notices, offline queue.
import Foundation
import GRDB
import Supabase
import XIXModels
import XIXScoring

public actor RoundSession {
    public struct State: Sendable {
        public var round: LocalRound
        public var players: [LocalPlayer]
        public var scores: [LocalScore]
        public var courseHoles: [LocalCourseHole]
        public var stickers: [LocalSticker]
        public var callouts: [LocalCallout]
        public var responses: [LocalCalloutResponse]
        public var result: RoundResult?
        public var serverResult: RoundResult?
        public var present: Set<UUID>     // player ids on the card right now
        public var pendingWrites: Int

        public func score(player: UUID, hole: Int) -> LocalScore? { scores.first { $0.player_id == player && $0.hole == hole } }

        /// A callout still awaiting signatures or scores on its hole (the ink mark on the column header).
        public var liveCalloutHoles: [Int] {
            callouts.filter { $0.closed_at == nil && ($0.status == "open" || $0.status == "live") }.map(\.hole)
        }
    }

    public enum Event: Sendable {
        case state(State)
        case notice(MergeNotice)
        case rejected(Mutation, message: String)
    }

    public let roundID: UUID
    private let client: XIXClient
    private let connectivity: Connectivity
    private let queue: OfflineQueue
    private var channel: RealtimeChannelV2?
    private var tasks: [Task<Void, Never>] = []
    private var engineTask: Task<Void, Never>?
    private var listeners: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var present: Set<UUID> = []
    private var lastResult: RoundResult?
    private var serverResult: RoundResult?
    public private(set) var notices: [MergeNotice] = []
    public private(set) var myPlayerID: UUID?
    /// The signed-in user's id (nonisolated: the client holds it).
    public nonisolated var userID: UUID? { client.userID }

    public init(client: XIXClient, roundID: UUID, connectivity: Connectivity) {
        self.client = client
        self.roundID = roundID
        self.connectivity = connectivity
        self.queue = OfflineQueue(client: client, connectivity: connectivity)
    }

    public func events() -> AsyncStream<Event> {
        let id = UUID()
        return AsyncStream { c in
            listeners[id] = c
            c.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        }
    }
    private func removeListener(_ id: UUID) { listeners[id] = nil }

    // MARK: Lifecycle

    /// Load the round from the server into the local store, subscribe to its channel, run the engine.
    public func start() async throws {
        let bundle = try await RoundRepository(client: client).fetchBundle(roundID: roundID)
        try ingest(bundle)
        myPlayerID = bundle.players.first { $0.profileId == client.userID }?.id
        await queue.start()
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await event in await self.queue.events() { await self.handle(queueEvent: event) }
        })
        try await subscribe()
        watchConnectivity()
        runEngine()
    }

    /// Offline: leave the channel (nothing is replayed later anyway). Online again: refetch the round
    /// under last-write-wins to catch up, then rejoin. The queue drains on its own signal.
    private func watchConnectivity() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            var first = true
            for await online in await self.connectivity.changes() {
                if first { first = false; continue }   // the current value, already reflected
                await self.connectivityChanged(online: online)
            }
        })
    }

    private func connectivityChanged(online: Bool) async {
        guard let channel else { return }
        if online {
            await resync()
            await channel.subscribe()
        } else {
            await channel.unsubscribe()
        }
    }

    /// Pull the whole round again and merge it (last-write-wins per cell keeps pending local writes).
    public func resync() async {
        guard let bundle = try? await RoundRepository(client: client).fetchBundle(roundID: roundID) else { return }
        try? ingest(bundle)
        runEngine()
    }

    public func stop() async {
        for t in tasks { t.cancel() }
        tasks = []
        engineTask?.cancel()
        await queue.stop()
        if let channel { await channel.unsubscribe(); await client.supabase.realtimeV2.removeChannel(channel) }
        channel = nil
    }

    public func currentState() -> State { makeState() }

    // MARK: Writes (local first, then queued)

    public func enterScore(playerID: UUID, hole: Int, strokes: Int?, pickedUp: Bool) async {
        let ts = await client.clock.now()
        let local = LocalScore(round_id: roundID, player_id: playerID, hole: hole, strokes: pickedUp ? nil : strokes, picked_up: pickedUp,
                               entered_by: client.userID, client_ts: ts.timeIntervalSince1970, updated_at: ts.timeIntervalSince1970, pending: true)
        try? client.store.writeLocalScore(local)
        runEngine()
        try? await queue.enqueue(.enterScore(roundID: roundID, playerID: playerID, hole: hole, strokes: strokes, pickedUp: pickedUp, clientTs: ts), clientTs: ts)
    }

    public func sendSticker(hole: Int, targetPlayerID: UUID, stickerKey: String, packKey: String = "base") async {
        guard let me = myPlayerID else { return }
        let ts = await client.clock.now()
        let id = UUID()
        let rid = roundID
        try? await client.store.dbQueue.write { db in
            try LocalSticker(id: id, round_id: rid, hole: hole, target_player_id: targetPlayerID, sender_player_id: me,
                             sticker_key: stickerKey, pack_key: packKey, played_at: nil, created_at: ts.timeIntervalSince1970).save(db)
        }
        publishState()
        try? await queue.enqueue(.sendSticker(id: id, roundID: roundID, hole: hole, targetPlayerID: targetPlayerID, stickerKey: stickerKey, packKey: packKey), clientTs: ts)
    }

    public func createCallout(hole: Int, kind: String, targets: [UUID], params: [String: AnyJSON]) async {
        let ts = await client.clock.now()
        try? await queue.enqueue(.createCallout(id: UUID(), roundID: roundID, hole: hole, kind: kind, targets: targets, params: params), clientTs: ts)
    }

    public func respond(calloutID: UUID, action: CalloutResponseAction) async {
        let ts = await client.clock.now()
        try? await queue.enqueue(.respondCallout(roundID: roundID, calloutID: calloutID, action: action), clientTs: ts)
    }

    /// Tests and previews: go offline or online explicitly.
    public func setOnline(_ online: Bool?) async { await connectivity.setOverride(online) }
    public func pendingWrites() async -> Int { await queue.pendingCount() }

    // MARK: Realtime

    private func subscribe() async throws {
        let realtime = client.supabase.realtimeV2
        let ch = realtime.channel("xix:round:\(roundID.uuidString.lowercased())") { config in config.presence.key = UUID().uuidString }
        channel = ch
        let id = roundID.uuidString.lowercased()
        let scores = ch.postgresChange(AnyAction.self, schema: "xix", table: "scores", filter: .eq("round_id", value: id))
        let players = ch.postgresChange(AnyAction.self, schema: "xix", table: "players", filter: .eq("round_id", value: id))
        let games = ch.postgresChange(AnyAction.self, schema: "xix", table: "games", filter: .eq("round_id", value: id))
        let gamePlayers = ch.postgresChange(AnyAction.self, schema: "xix", table: "game_players", filter: .eq("round_id", value: id))
        let callouts = ch.postgresChange(AnyAction.self, schema: "xix", table: "callouts", filter: .eq("round_id", value: id))
        let responses = ch.postgresChange(AnyAction.self, schema: "xix", table: "callout_responses")
        let stickers = ch.postgresChange(AnyAction.self, schema: "xix", table: "stickers", filter: .eq("round_id", value: id))
        let results = ch.postgresChange(AnyAction.self, schema: "xix", table: "results", filter: .eq("round_id", value: id))
        let presence = ch.presenceChange()

        tasks.append(Task { [weak self] in for await a in scores { await self?.apply(scoreAction: a) } })
        tasks.append(Task { [weak self] in for await a in players { await self?.apply(playerAction: a) } })
        tasks.append(Task { [weak self] in for await _ in games { await self?.refreshGames() } })
        tasks.append(Task { [weak self] in for await _ in gamePlayers { await self?.refreshGames() } })
        tasks.append(Task { [weak self] in for await _ in callouts { await self?.refreshCallouts() } })
        tasks.append(Task { [weak self] in for await _ in responses { await self?.refreshCallouts() } })
        tasks.append(Task { [weak self] in for await a in stickers { await self?.apply(stickerAction: a) } })
        tasks.append(Task { [weak self] in for await a in results { await self?.apply(resultAction: a) } })
        tasks.append(Task { [weak self] in for await p in presence { await self?.apply(presence: p) } })

        await ch.subscribe()
        if let me = myPlayerID { try? await ch.track(PresenceState(playerID: me)) }
    }

    struct PresenceState: Codable { let playerID: UUID }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private static let rowDecoder = JSONDecoder()

    private static let debug = ProcessInfo.processInfo.environment["XIX_DEBUG_REALTIME"] != nil

    private func apply(scoreAction action: AnyAction) {
        if Self.debug { print("[xix realtime] scores \(action)") }
        switch action {
        case .insert(let a):
            guard let row = try? a.decodeRecord(as: ScoreRow.self, decoder: Self.rowDecoder) else { return }
            merge(remote: LocalScore(row: row, pending: false))
        case .update(let a):
            guard let row = try? a.decodeRecord(as: ScoreRow.self, decoder: Self.rowDecoder) else { return }
            merge(remote: LocalScore(row: row, pending: false))
        case .delete:
            break
        }
    }

    private func merge(remote: LocalScore) {
        guard let outcome = try? client.store.applyRemoteScore(remote) else { return }
        if Self.debug { print("[xix merge] player \(remote.player_id.uuidString.prefix(8)) hole \(remote.hole) \(remote.displayValue) ts \(remote.client_ts) → \(outcome)") }
        if case .replaced(let previous) = outcome, remote.player_id != myPlayerID {
            let players = (try? client.store.dbQueue.read { db in try LocalPlayer.filter(Column("round_id") == roundID).fetchAll(db) }) ?? []
            let rowName = players.first { $0.id == remote.player_id }?.display_name ?? "Someone"
            let byName = players.first { $0.profile_id != nil && $0.profile_id == remote.entered_by }?.display_name
            let who = byName ?? rowName
            let text = who == rowName ? "\(rowName) changed hole \(remote.hole)" : "\(who) changed \(rowName)'s hole \(remote.hole)"
            let notice = MergeNotice(playerID: remote.player_id, hole: remote.hole, previous: previous.displayValue, current: remote.displayValue, text: text)
            notices.append(notice)
            emit(.notice(notice))
        }
        if outcome != .keptLocal { runEngine() }
    }

    private func apply(playerAction action: AnyAction) {
        let record: [String: AnyJSON]?
        switch action {
        case .insert(let a): record = a.record
        case .update(let a): record = a.record
        case .delete: record = nil
        }
        guard let record, let row = try? decodeRow(PlayerRow.self, record) else { return }
        try? client.store.dbQueue.write { db in try LocalPlayer(row: row).save(db) }
        if row.profileId == client.userID { myPlayerID = row.id }
        runEngine()
    }

    private func apply(stickerAction action: AnyAction) {
        let record: [String: AnyJSON]?
        switch action {
        case .insert(let a): record = a.record
        case .update(let a): record = a.record
        case .delete: record = nil
        }
        guard let record, let row = try? decodeRow(StickerRow.self, record) else { return }
        try? client.store.dbQueue.write { db in try LocalSticker(row: row).save(db) }
        publishState()
    }

    private func apply(resultAction action: AnyAction) {
        let record: [String: AnyJSON]?
        switch action {
        case .insert(let a): record = a.record
        case .update(let a): record = a.record
        case .delete: record = nil
        }
        guard let record, let row = try? decodeRow(ResultRow.self, record) else { return }
        storeServerResult(row)
        publishState()
    }

    private func apply(presence p: any PresenceAction) {
        if let joins = try? p.decodeJoins(as: PresenceState.self) { for j in joins { present.insert(j.playerID) } }
        if let leaves = try? p.decodeLeaves(as: PresenceState.self) { for l in leaves { present.remove(l.playerID) } }
        publishState()
    }

    private func refreshGames() async {
        guard let bundle = try? await RoundRepository(client: client).fetchBundle(roundID: roundID) else { return }
        try? ingestGames(bundle)
        runEngine()
    }

    private func refreshCallouts() async {
        guard let bundle = try? await RoundRepository(client: client).fetchBundle(roundID: roundID) else { return }
        try? ingestCallouts(bundle)
        runEngine()
    }

    private func decodeRow<T: Decodable>(_ type: T.Type, _ record: [String: AnyJSON]) throws -> T {
        let data = try JSONEncoder().encode(record)
        return try Self.rowDecoder.decode(T.self, from: data)
    }

    // MARK: Queue outcomes

    private func handle(queueEvent: QueueEvent) async {
        switch queueEvent {
        case .rejected(let mutation, let message):
            if case .enterScore(_, let playerID, let hole, _, _, _) = mutation {
                // Restore whatever the server holds for that cell.
                let rows: [ScoreRow] = (try? await client.supabase.schema("xix").from("scores").select()
                    .eq("round_id", value: roundID).eq("player_id", value: playerID).eq("hole", value: hole).execute().value) ?? []
                try? client.store.revertScore(roundID: roundID, playerID: playerID, hole: hole, to: rows.first.map { LocalScore(row: $0, pending: false) })
                runEngine()
            }
            emit(.rejected(mutation, message: message))
        case .sent, .drained:
            publishState()
        }
    }

    // MARK: Engine

    /// Re-run the local engine, debounced 150 ms.
    private func runEngine() {
        engineTask?.cancel()
        engineTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            await self.computeNow()
        }
    }

    private func computeNow() {
        guard let input = try? RoundInputBuilder.build(roundID: roundID, store: client.store) else { return }
        lastResult = ScoringEngine.score(input)
        publishState()
    }

    /// Run the engine synchronously (tests).
    public func recompute() -> RoundResult? {
        computeNow()
        return lastResult
    }

    private func makeState() -> State {
        let round = (try? client.store.dbQueue.read { db in try LocalRound.fetchOne(db, key: roundID) })
            ?? LocalRound(id: roundID, owner_id: UUID(), course_id: nil, played_on: "", holes: 18, status: "setup", join_code: "", ended_at: nil, course_name: nil)
        let players = (try? client.store.dbQueue.read { db in try LocalPlayer.filter(Column("round_id") == roundID).order(Column("seat")).fetchAll(db) }) ?? []
        let scores = (try? client.store.scores(roundID: roundID)) ?? []
        let courseHoles = (try? client.store.dbQueue.read { db in try LocalCourseHole.filter(Column("round_id") == roundID).order(Column("hole")).fetchAll(db) }) ?? []
        let stickers = (try? client.store.dbQueue.read { db in try LocalSticker.filter(Column("round_id") == roundID).order(Column("created_at")).fetchAll(db) }) ?? []
        let callouts = (try? client.store.dbQueue.read { db in try LocalCallout.filter(Column("round_id") == roundID).order(Column("created_at")).fetchAll(db) }) ?? []
        let responses = (try? client.store.dbQueue.read { db in try LocalCalloutResponse.fetchAll(db) }) ?? []
        let pending = (try? client.store.outbox().filter { $0.round_id == roundID }.count) ?? 0
        return State(round: round, players: players, scores: scores, courseHoles: courseHoles, stickers: stickers, callouts: callouts, responses: responses,
                     result: lastResult, serverResult: serverResult, present: present, pendingWrites: pending)
    }

    private func publishState() {
        let state = makeState()
        emit(.state(state))
    }

    private func emit(_ event: Event) {
        for l in listeners.values { l.yield(event) }
    }

    // MARK: Ingest server rows into the local store

    private func ingest(_ b: RoundBundle) throws {
        try client.store.dbQueue.write { db in
            try LocalRound(row: b.round, courseName: b.course?.name).save(db)
            for h in b.courseHoles {
                try LocalCourseHole(round_id: b.round.id, hole: Int(h.hole), par: h.par.map(Int.init), stroke_index: h.strokeIndex.map(Int.init)).save(db)
            }
            for p in b.players { try LocalPlayer(row: p).save(db) }
            for s in b.stickers { try LocalSticker(row: s).save(db) }
        }
        for s in b.scores { _ = try client.store.applyRemoteScore(LocalScore(row: s, pending: false)) }
        try ingestGames(b)
        try ingestCallouts(b)
        if let r = b.result { storeServerResult(r) }
    }

    private func ingestGames(_ b: RoundBundle) throws {
        try client.store.dbQueue.write { db in
            _ = try LocalGamePlayer.filter(Column("round_id") == roundID).deleteAll(db)
            _ = try LocalGame.filter(Column("round_id") == roundID).deleteAll(db)
            for g in b.games {
                let options = String(decoding: (try? JSONEncoder().encode(g.options)) ?? Data("{}".utf8), as: UTF8.self)
                try LocalGame(id: g.id, round_id: g.roundId, format: g.format, options: options,
                              created_at: (ISO8601.date(g.createdAt) ?? Date()).timeIntervalSince1970).save(db)
            }
            for gp in b.gamePlayers {
                try LocalGamePlayer(game_id: gp.gameId, round_id: gp.roundId, player_id: gp.playerId, side: gp.side.map(Int.init)).save(db)
            }
        }
    }

    private func ingestCallouts(_ b: RoundBundle) throws {
        try client.store.dbQueue.write { db in
            let ids = b.callouts.map(\.id)
            _ = try LocalCalloutResponse.filter(ids.contains(Column("callout_id"))).deleteAll(db)
            _ = try LocalCallout.filter(Column("round_id") == roundID).deleteAll(db)
            for c in b.callouts {
                let targets = String(decoding: (try? JSONEncoder().encode(c.targetIds)) ?? Data("[]".utf8), as: UTF8.self)
                let params = String(decoding: (try? JSONEncoder().encode(c.params)) ?? Data("{}".utf8), as: UTF8.self)
                try LocalCallout(id: c.id, round_id: c.roundId, hole: Int(c.hole), kind: c.kind, caller_id: c.callerId, target_ids: targets,
                                 params: params, status: c.status, closed_at: ISO8601.date(c.closedAt)?.timeIntervalSince1970,
                                 created_at: (ISO8601.date(c.createdAt) ?? Date()).timeIntervalSince1970).save(db)
            }
            for r in b.responses {
                try LocalCalloutResponse(callout_id: r.calloutId, player_id: r.playerId, action: r.action,
                                         responded_at: (ISO8601.date(r.respondedAt) ?? Date()).timeIntervalSince1970).save(db)
            }
        }
    }

    private func storeServerResult(_ r: ResultRow) {
        let payload = String(decoding: (try? JSONEncoder().encode(r.payload)) ?? Data("{}".utf8), as: UTF8.self)
        try? client.store.dbQueue.write { db in
            try LocalResult(round_id: r.roundId, version: Int(r.version), payload: payload,
                            computed_at: (ISO8601.date(r.computedAt) ?? Date()).timeIntervalSince1970).save(db)
        }
        serverResult = try? JSONDecoder().decode(RoundResult.self, from: Data(payload.utf8))
    }
}

extension LocalRound {
    init(row: RoundRow, courseName: String?) {
        self.init(id: row.id, owner_id: row.ownerId, course_id: row.courseId, played_on: row.playedOn, holes: Int(row.holes), status: row.status,
                  join_code: row.joinCode, ended_at: ISO8601.date(row.endedAt)?.timeIntervalSince1970, course_name: courseName)
    }
}

extension LocalPlayer {
    init(row: PlayerRow) {
        self.init(id: row.id, round_id: row.roundId, profile_id: row.profileId, display_name: row.displayName, seat: Int(row.seat),
                  level_snapshot: row.levelSnapshot.map { NSDecimalNumber(decimal: $0).doubleValue },
                  claimed_at: ISO8601.date(row.claimedAt)?.timeIntervalSince1970, left_at: ISO8601.date(row.leftAt)?.timeIntervalSince1970)
    }
}

extension LocalSticker {
    init(row: StickerRow) {
        self.init(id: row.id, round_id: row.roundId, hole: Int(row.hole), target_player_id: row.targetPlayerId, sender_player_id: row.senderPlayerId,
                  sticker_key: row.stickerKey, pack_key: row.packKey, played_at: ISO8601.date(row.playedAt)?.timeIntervalSince1970,
                  created_at: (ISO8601.date(row.createdAt) ?? Date()).timeIntervalSince1970)
    }
}
