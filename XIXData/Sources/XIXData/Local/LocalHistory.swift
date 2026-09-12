// What the phone remembers about past rounds, read from the local store the sessions fill (Build Doc 3
// step 1): "Same as last time", the personal record for a course, recent people. Rankings come later
// from the server; this is only what this device has seen.
import Foundation
import GRDB

public struct RoundMemory: Sendable {
    public var round: LocalRound
    public var players: [LocalPlayer]
    public var games: [LocalGame]
    public var gamePlayers: [LocalGamePlayer]
    /// The viewer's gross over the holes they entered, and how many holes that was.
    public var myGross: Int?
    public var myHoles: Int

    public var courseName: String { round.course_name ?? "Round" }
    public var playerNames: [String] { players.filter { $0.left_at == nil }.sorted { $0.seat < $1.seat }.map(\.display_name) }
    public var isSolo: Bool { players.filter { $0.left_at == nil }.count <= 1 }
}

public struct CourseRecord: Sendable, Equatable {
    public var courseName: String
    public var best: Int?
    public var average: Double?
    public var rounds: Int
}

extension LocalStore {
    /// Rounds this device has opened, newest first.
    public func recentRounds(profileID: UUID?, limit: Int = 10) -> [RoundMemory] {
        (try? dbQueue.read { db -> [RoundMemory] in
            let rounds = try LocalRound.order(Column("played_on").desc, Column("ended_at").desc).limit(limit).fetchAll(db)
            return try rounds.map { r in
                let players = try LocalPlayer.filter(Column("round_id") == r.id).order(Column("seat")).fetchAll(db)
                let games = try LocalGame.filter(Column("round_id") == r.id).order(Column("position"), Column("created_at")).fetchAll(db)
                let gamePlayers = try LocalGamePlayer.filter(Column("round_id") == r.id).fetchAll(db)
                let mine = players.first { $0.profile_id != nil && $0.profile_id == profileID }
                var gross: Int? = nil, holes = 0
                if let mine {
                    let scores = try LocalScore.filter(Column("round_id") == r.id && Column("player_id") == mine.id).fetchAll(db)
                    holes = scores.filter { $0.strokes != nil || $0.picked_up }.count
                    if holes > 0 { gross = scores.reduce(0) { $0 + ($1.strokes ?? 0) } }
                }
                return RoundMemory(round: r, players: players, games: games, gamePlayers: gamePlayers, myGross: gross, myHoles: holes)
            }
        }) ?? []
    }

    /// The most recent round the viewer took part in (the "Same as last time" card).
    public func lastRound(profileID: UUID?) -> RoundMemory? {
        recentRounds(profileID: profileID, limit: 20).first { m in m.players.contains { $0.profile_id != nil && $0.profile_id == profileID } }
    }

    /// Best, average and count over the viewer's fully entered rounds on one course.
    public func record(courseName: String, profileID: UUID?) -> CourseRecord {
        let complete = recentRounds(profileID: profileID, limit: 200)
            .filter { $0.round.course_name == courseName && $0.myHoles == $0.round.holes && $0.myGross != nil }
        let grosses = complete.compactMap(\.myGross)
        return CourseRecord(courseName: courseName, best: grosses.min(),
                            average: grosses.isEmpty ? nil : Double(grosses.reduce(0, +)) / Double(grosses.count), rounds: grosses.count)
    }

    /// People this device has played with, most recent first, without the viewer.
    public func recentPeople(profileID: UUID?, limit: Int = 8) -> [(name: String, hasXIX: Bool)] {
        var seen = Set<String>()
        var out: [(String, Bool)] = []
        for m in recentRounds(profileID: profileID, limit: 30) {
            for p in m.players where p.profile_id == nil || p.profile_id != profileID {
                if seen.insert(p.display_name).inserted { out.append((p.display_name, p.profile_id != nil)) }
                if out.count >= limit { return out }
            }
        }
        return out
    }

    /// Course names this device has played, most recent first.
    public func recentCourses(limit: Int = 6) -> [String] {
        var seen = Set<String>()
        return recentRounds(profileID: nil, limit: 40).compactMap { m in
            guard let n = m.round.course_name, seen.insert(n).inserted else { return nil }
            return n
        }.prefix(limit).map { $0 }
    }
}

extension LocalStore {
    public func courseHoles(roundID: UUID) -> [LocalCourseHole] {
        (try? dbQueue.read { db in try LocalCourseHole.filter(Column("round_id") == roundID).order(Column("hole")).fetchAll(db) }) ?? []
    }
    public func games(roundID: UUID) -> [LocalGame] {
        (try? dbQueue.read { db in try LocalGame.filter(Column("round_id") == roundID).order(Column("position"), Column("created_at")).fetchAll(db) }) ?? []
    }
    /// The optimistic row a send wrote locally is replaced by the row the server created: `send_sticker`
    /// mints its own id, so without this the card would carry the same sticker twice — once under the
    /// client's id and once under the server's.
    public func replaceSticker(localID: UUID, with row: LocalSticker) throws {
        try dbQueue.write { db in
            if localID != row.id { _ = try LocalSticker.deleteOne(db, key: localID) }
            try row.save(db)
        }
    }

    public func sticker(id: UUID) -> LocalSticker? {
        (try? dbQueue.read { db in try LocalSticker.fetchOne(db, key: id) }) ?? nil
    }
    public func gamePlayers(roundID: UUID) -> [LocalGamePlayer] {
        (try? dbQueue.read { db in try LocalGamePlayer.filter(Column("round_id") == roundID).fetchAll(db) }) ?? []
    }
}
