// Rounds: create, join by code, claim, games, end, leave, confirm (Build Doc 2 A.4). Every write is an
// RPC or an RLS-guarded insert; reads are PostgREST selects the caller is allowed to see.
import Foundation
import Supabase
import XIXModels

public struct CourseDraft: Sendable {
    public var name: String
    public var region: String?
    public var par: [Int?]?           // one per hole; nil for no par
    public var strokeIndex: [Int?]?
    public var yards: [Int?]?
    public init(name: String, region: String? = nil, par: [Int?]? = nil, strokeIndex: [Int?]? = nil, yards: [Int?]? = nil) {
        self.name = name; self.region = region; self.par = par; self.strokeIndex = strokeIndex; self.yards = yards
    }
}

public struct GameDraft: Codable, Sendable {
    public var id: UUID?
    public var format: String
    public var options: [String: AnyJSON]
    public var players: [UUID]
    public var sides: [String: Int]?
    public init(id: UUID? = nil, format: String, options: [String: AnyJSON] = [:], players: [UUID], sides: [UUID: Int]? = nil) {
        self.id = id; self.format = format; self.options = options; self.players = players
        self.sides = sides.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.uuidString.lowercased(), $0.value) }) }
    }
}

/// Everything about one round the client can read.
public struct RoundBundle: Sendable {
    public var round: RoundRow
    public var course: CourseRow?
    public var courseHoles: [CourseHoleRow]
    public var players: [PlayerRow]
    public var scores: [ScoreRow]
    public var games: [GameRow]
    public var gamePlayers: [GamePlayerRow]
    public var callouts: [CalloutRow]
    public var responses: [CalloutResponseRow]
    public var stickers: [StickerRow]
    public var result: ResultRow?
}

/// Everything the join screen and the no-app landing page show, from one RPC (Build Doc 2 C.4).
public struct JoinScreen: Codable, Sendable, Hashable {
    public struct Round: Codable, Sendable, Hashable {
        public var id: UUID
        public var joinCode: String
        public var holes: Int
        public var status: String
        public var playedOn: String
        public var course: String?
        public var owner: String?
        enum CodingKeys: String, CodingKey { case id, joinCode = "join_code", holes, status, playedOn = "played_on", course, owner }
    }
    public struct Player: Codable, Sendable, Hashable {
        public var id: UUID
        public var displayName: String
        public var seat: Int
        public var claimable: Bool
        public var mine: Bool
        enum CodingKeys: String, CodingKey { case id, displayName = "display_name", seat, claimable, mine }
    }
    public var round: Round
    public var players: [Player]
    public var claimable: [Player] { players.filter(\.claimable) }
}

public struct RoundRepository: Sendable {
    let client: XIXClient
    public init(client: XIXClient) { self.client = client }
    private var db: PostgrestClient { client.supabase.schema("xix") }

    /// Owner creates the course (inline, no match required), the round, their own row at seat 0 and a
    /// guest row per name. Games are set separately with `setGames`.
    public func createRound(course: CourseDraft, holes: Int, ownerName: String, guestNames: [String]) async throws -> RoundBundle {
        guard let me = client.userID else { throw XIXDataError.notSignedIn }
        // Reuse a course this user already created with the same name and region (setup's "recents").
        var existingQuery = db.from("courses").select().eq("name", value: course.name).eq("created_by", value: me)
        existingQuery = course.region.map { existingQuery.eq("region", value: $0) } ?? existingQuery.is("region", value: nil)
        let existing: [CourseRow] = try await existingQuery.limit(1).execute().value
        let courseRow: CourseRow
        if let found = existing.first {
            courseRow = found
        } else {
            struct CourseInsert: Encodable { let name: String; let region: String?; let created_by: UUID }
            courseRow = try await db.from("courses")
                .insert(CourseInsert(name: course.name, region: course.region, created_by: me))
                .select().single().execute().value
        }
        if existing.isEmpty, course.par != nil || course.strokeIndex != nil || course.yards != nil {
            struct HoleInsert: Encodable { let course_id: UUID; let hole: Int; let par: Int?; let stroke_index: Int?; let yards: Int? }
            let rows = (0..<holes).map { i in
                HoleInsert(course_id: courseRow.id, hole: i + 1, par: course.par?[safe: i] ?? nil, stroke_index: course.strokeIndex?[safe: i] ?? nil,
                           yards: course.yards?[safe: i] ?? nil)
            }
            try await db.from("course_holes").insert(rows).execute()
        }
        struct RoundInsert: Encodable { let owner_id: UUID; let course_id: UUID; let holes: Int; let status: String }
        let round: RoundRow = try await db.from("rounds")
            .insert(RoundInsert(owner_id: me, course_id: courseRow.id, holes: holes, status: "live"))
            .select().single().execute().value
        struct OwnerRow: Encodable { let round_id: UUID; let profile_id: UUID; let display_name: String; let seat: Int; let claimed_at: String }
        try await db.from("players")
            .insert(OwnerRow(round_id: round.id, profile_id: me, display_name: ownerName, seat: 0, claimed_at: ISO8601.string(Date())))
            .execute()
        for name in guestNames { try await addGuest(roundID: round.id, displayName: name) }
        return try await fetchBundle(roundID: round.id)
    }

    public func fetchBundle(roundID: UUID) async throws -> RoundBundle {
        let round: RoundRow = try await db.from("rounds").select().eq("id", value: roundID).single().execute().value
        var course: CourseRow? = nil
        var courseHoles: [CourseHoleRow] = []
        if let courseID = round.courseId {
            course = try await db.from("courses").select().eq("id", value: courseID).single().execute().value
            courseHoles = try await db.from("course_holes").select().eq("course_id", value: courseID).order("hole").execute().value
        }
        let players: [PlayerRow] = try await db.from("players").select().eq("round_id", value: roundID).order("seat").execute().value
        let scores: [ScoreRow] = try await db.from("scores").select().eq("round_id", value: roundID).execute().value
        let games: [GameRow] = try await db.from("games").select().eq("round_id", value: roundID).order("position").order("created_at").execute().value
        let gamePlayers: [GamePlayerRow] = try await db.from("game_players").select().eq("round_id", value: roundID).execute().value
        let callouts: [CalloutRow] = try await db.from("callouts").select().eq("round_id", value: roundID).order("created_at").execute().value
        var responses: [CalloutResponseRow] = []
        if !callouts.isEmpty {
            responses = try await db.from("callout_responses").select().in("callout_id", values: callouts.map(\.id)).execute().value
        }
        let stickers: [StickerRow] = try await db.from("stickers").select().eq("round_id", value: roundID).order("created_at").execute().value
        let results: [ResultRow] = try await db.from("results").select().eq("round_id", value: roundID).execute().value
        return RoundBundle(round: round, course: course, courseHoles: courseHoles, players: players, scores: scores,
                           games: games, gamePlayers: gamePlayers, callouts: callouts, responses: responses,
                           stickers: stickers, result: results.first)
    }

    /// Join by link: the round for a code, without becoming a member.
    public func joinRound(code: String) async throws -> RoundRow {
        try await client.supabase.rpc("join_round", params: ["code": code]).single().execute().value
    }

    /// The join screen for a code: round, course, date, players and which rows are claimable.
    public func joinScreen(code: String) async throws -> JoinScreen {
        try await client.supabase.rpc("joinable_rows", params: ["code": code]).single().execute().value
    }

    @discardableResult
    public func claimRow(roundID: UUID, playerID: UUID) async throws -> PlayerRow {
        try await client.supabase.rpc("claim_row", params: ["round_id": roundID, "player_id": playerID]).single().execute().value
    }

    @discardableResult
    public func addGuest(roundID: UUID, displayName: String) async throws -> PlayerRow {
        struct P: Encodable { let round_id: UUID; let display_name: String }
        return try await client.supabase.rpc("add_guest", params: P(round_id: roundID, display_name: displayName)).single().execute().value
    }

    @discardableResult
    public func setGames(roundID: UUID, games: [GameDraft]) async throws -> [GameRow] {
        struct P: Encodable { let round_id: UUID; let games: [GameDraft] }
        return try await client.supabase.rpc("set_games", params: P(round_id: roundID, games: games)).execute().value
    }

    @discardableResult
    public func endRound(roundID: UUID) async throws -> RoundRow {
        try await client.supabase.rpc("end_round", params: ["round_id": roundID]).single().execute().value
    }

    @discardableResult
    public func leaveRound(roundID: UUID) async throws -> PlayerRow {
        try await client.supabase.rpc("leave_round", params: ["round_id": roundID]).single().execute().value
    }

    @discardableResult
    public func confirmRound(roundID: UUID, action: ConfirmationAction) async throws -> ConfirmationRow {
        struct P: Encodable { let round_id: UUID; let action: String }
        return try await client.supabase.rpc("confirm_round", params: P(round_id: roundID, action: action.rawValue)).single().execute().value
    }

    public func medals() async throws -> [MedalRow] {
        try await db.from("medals").select().order("created_at", ascending: false).execute().value
    }
}

public enum XIXDataError: Error, Sendable, Equatable {
    case notSignedIn
    case notInRound
    case rejected(String)
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
