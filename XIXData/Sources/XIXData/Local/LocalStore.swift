// Local SQLite store (GRDB): the grid and hole card always render from here; every mutation lands
// here first (Build Doc 2 C.3). Timestamps are unix seconds. Column names match the server's.
import Foundation
import GRDB

public struct LocalRound: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "rounds"
    public var id: UUID; public var owner_id: UUID; public var course_id: UUID?; public var played_on: String
    public var holes: Int; public var status: String; public var join_code: String; public var ended_at: Double?
    public var course_name: String?
}

public struct LocalCourseHole: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "course_holes"
    public var round_id: UUID; public var hole: Int; public var par: Int?; public var stroke_index: Int?
}

public struct LocalPlayer: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "players"
    public var id: UUID; public var round_id: UUID; public var profile_id: UUID?; public var display_name: String
    public var seat: Int; public var level_snapshot: Double?; public var claimed_at: Double?; public var left_at: Double?
}

public struct LocalScore: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "scores"
    public var round_id: UUID; public var player_id: UUID; public var hole: Int
    public var strokes: Int?; public var picked_up: Bool; public var entered_by: UUID?
    public var client_ts: Double; public var updated_at: Double
    /// True while the write sits in the outbox unacknowledged.
    public var pending: Bool

    public var displayValue: String { picked_up ? "X" : strokes.map(String.init) ?? "" }
}

public struct LocalGame: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "games"
    public var id: UUID; public var round_id: UUID; public var format: String; public var options: String; public var created_at: Double
}

public struct LocalGamePlayer: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "game_players"
    public var game_id: UUID; public var round_id: UUID; public var player_id: UUID; public var side: Int?
}

public struct LocalCallout: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "callouts"
    public var id: UUID; public var round_id: UUID; public var hole: Int; public var kind: String; public var caller_id: UUID
    public var target_ids: String; public var params: String; public var status: String; public var closed_at: Double?; public var created_at: Double
}

public struct LocalCalloutResponse: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "callout_responses"
    public var callout_id: UUID; public var player_id: UUID; public var action: String; public var responded_at: Double
}

public struct LocalSticker: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "stickers"
    public var id: UUID; public var round_id: UUID; public var hole: Int; public var target_player_id: UUID
    public var sender_player_id: UUID; public var sticker_key: String; public var pack_key: String; public var played_at: Double?; public var created_at: Double
}

public struct LocalResult: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "results"
    public var round_id: UUID; public var version: Int; public var payload: String; public var computed_at: Double
}

public struct OutboxItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "outbox"
    public var id: Int64?
    public var round_id: UUID
    public var payload: String            // Mutation as JSON
    public var client_ts: Double
    public var created_at: Double
    public var attempts: Int
    public var last_error: String?
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum ScoreMerge: Sendable, Equatable {
    case inserted
    case replaced(previous: LocalScore)
    case unchanged
    case keptLocal   // local write is newer (or pending and newer); incoming ignored
}

public final class LocalStore: @unchecked Sendable {
    public let dbQueue: DatabaseQueue

    public static func inMemory() throws -> LocalStore { try LocalStore(dbQueue: DatabaseQueue()) }
    public static func onDisk(at url: URL) throws -> LocalStore { try LocalStore(dbQueue: DatabaseQueue(path: url.path)) }

    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "rounds") { t in
                t.primaryKey("id", .text); t.column("owner_id", .text).notNull(); t.column("course_id", .text)
                t.column("played_on", .text).notNull(); t.column("holes", .integer).notNull(); t.column("status", .text).notNull()
                t.column("join_code", .text).notNull(); t.column("ended_at", .double); t.column("course_name", .text)
            }
            try db.create(table: "course_holes") { t in
                t.column("round_id", .text).notNull(); t.column("hole", .integer).notNull(); t.column("par", .integer); t.column("stroke_index", .integer)
                t.primaryKey(["round_id", "hole"])
            }
            try db.create(table: "players") { t in
                t.primaryKey("id", .text); t.column("round_id", .text).notNull().indexed(); t.column("profile_id", .text)
                t.column("display_name", .text).notNull(); t.column("seat", .integer).notNull(); t.column("level_snapshot", .double)
                t.column("claimed_at", .double); t.column("left_at", .double)
            }
            try db.create(table: "scores") { t in
                t.column("round_id", .text).notNull(); t.column("player_id", .text).notNull(); t.column("hole", .integer).notNull()
                t.column("strokes", .integer); t.column("picked_up", .boolean).notNull().defaults(to: false); t.column("entered_by", .text)
                t.column("client_ts", .double).notNull(); t.column("updated_at", .double).notNull(); t.column("pending", .boolean).notNull().defaults(to: false)
                t.primaryKey(["round_id", "player_id", "hole"])
            }
            try db.create(table: "games") { t in
                t.primaryKey("id", .text); t.column("round_id", .text).notNull().indexed(); t.column("format", .text).notNull()
                t.column("options", .text).notNull(); t.column("created_at", .double).notNull()
            }
            try db.create(table: "game_players") { t in
                t.column("game_id", .text).notNull(); t.column("round_id", .text).notNull(); t.column("player_id", .text).notNull(); t.column("side", .integer)
                t.primaryKey(["game_id", "player_id"])
            }
            try db.create(table: "callouts") { t in
                t.primaryKey("id", .text); t.column("round_id", .text).notNull().indexed(); t.column("hole", .integer).notNull()
                t.column("kind", .text).notNull(); t.column("caller_id", .text).notNull(); t.column("target_ids", .text).notNull()
                t.column("params", .text).notNull(); t.column("status", .text).notNull(); t.column("closed_at", .double); t.column("created_at", .double).notNull()
            }
            try db.create(table: "callout_responses") { t in
                t.column("callout_id", .text).notNull(); t.column("player_id", .text).notNull(); t.column("action", .text).notNull(); t.column("responded_at", .double).notNull()
                t.primaryKey(["callout_id", "player_id"])
            }
            try db.create(table: "stickers") { t in
                t.primaryKey("id", .text); t.column("round_id", .text).notNull().indexed(); t.column("hole", .integer).notNull()
                t.column("target_player_id", .text).notNull(); t.column("sender_player_id", .text).notNull(); t.column("sticker_key", .text).notNull()
                t.column("pack_key", .text).notNull(); t.column("played_at", .double); t.column("created_at", .double).notNull()
            }
            try db.create(table: "results") { t in
                t.primaryKey("round_id", .text); t.column("version", .integer).notNull(); t.column("payload", .text).notNull(); t.column("computed_at", .double).notNull()
            }
            try db.create(table: "outbox") { t in
                t.autoIncrementedPrimaryKey("id"); t.column("round_id", .text).notNull(); t.column("payload", .text).notNull()
                t.column("client_ts", .double).notNull(); t.column("created_at", .double).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0); t.column("last_error", .text)
            }
            try db.create(table: "clock") { t in
                t.primaryKey("id", .integer); t.column("last_ts", .double).notNull()
            }
        }
        return m
    }

    // MARK: Scores with last-write-wins per cell (Build Doc 2 C.2, C.3)

    /// Writes a local entry (before the network). Newer than anything the cell holds by construction.
    public func writeLocalScore(_ score: LocalScore) throws {
        try dbQueue.write { db in try score.save(db) }
    }

    /// Applies a server row with last-write-wins on client_ts (updated_at when the server row has no client_ts).
    public func applyRemoteScore(_ incoming: LocalScore) throws -> ScoreMerge {
        try dbQueue.write { db in
            let existing = try LocalScore.filter(key: ["round_id": incoming.round_id, "player_id": incoming.player_id, "hole": incoming.hole]).fetchOne(db)
            guard let existing else {
                try incoming.insert(db)
                return .inserted
            }
            // Stamps are millisecond values that round-trip through ISO 8601; compare with a hair of tolerance.
            let sameStamp = abs(incoming.client_ts - existing.client_ts) < 0.0015
            if !sameStamp && incoming.client_ts < existing.client_ts { return .keptLocal }
            if sameStamp {
                // Our own write echoed back (or the server's copy of the same write): acknowledge it.
                var acked = existing; acked.pending = false; acked.updated_at = incoming.updated_at; acked.entered_by = incoming.entered_by
                acked.strokes = incoming.strokes; acked.picked_up = incoming.picked_up
                try acked.update(db)
                return .unchanged
            }
            let sameValue = existing.strokes == incoming.strokes && existing.picked_up == incoming.picked_up
            try incoming.update(db)
            return sameValue ? .unchanged : .replaced(previous: existing)
        }
    }

    /// Server rejected a pending write: restore the previous server value, or drop the cell.
    public func revertScore(roundID: UUID, playerID: UUID, hole: Int, to serverRow: LocalScore?) throws {
        try dbQueue.write { db in
            if let serverRow { try serverRow.save(db) }
            else { _ = try LocalScore.filter(key: ["round_id": roundID, "player_id": playerID, "hole": hole]).deleteAll(db) }
        }
    }

    public func scores(roundID: UUID) throws -> [LocalScore] {
        try dbQueue.read { db in try LocalScore.filter(Column("round_id") == roundID).fetchAll(db) }
    }

    // MARK: Outbox

    public func enqueue(_ item: OutboxItem) throws -> OutboxItem {
        var item = item
        try dbQueue.write { db in try item.insert(db) }
        return item
    }

    public func outbox() throws -> [OutboxItem] {
        try dbQueue.read { db in try OutboxItem.order(Column("id")).fetchAll(db) }
    }

    public func removeOutbox(id: Int64) throws {
        try dbQueue.write { db in _ = try OutboxItem.deleteOne(db, key: id) }
    }

    public func markOutboxFailure(id: Int64, error: String) throws {
        try dbQueue.write { db in
            if var item = try OutboxItem.fetchOne(db, key: id) { item.attempts += 1; item.last_error = error; try item.update(db) }
        }
    }

    // MARK: Clock

    func lastClockValue() throws -> Double? {
        try dbQueue.read { db in try Double.fetchOne(db, sql: "select last_ts from clock where id = 1") }
    }

    func saveClockValue(_ v: Double) throws {
        try dbQueue.write { db in try db.execute(sql: "insert into clock (id, last_ts) values (1, ?) on conflict(id) do update set last_ts = excluded.last_ts", arguments: [v]) }
    }
}
