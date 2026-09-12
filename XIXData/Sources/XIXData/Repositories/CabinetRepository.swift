// The cabinet, the rivalry and the boards (Build Doc 3 step 5; PRD 8.18, 8.19). All reads: medals the
// player has won, the head-to-head against one other person, the ranking boards, the crews, and the
// rounds still waiting on somebody.
import Foundation
import Supabase
import XIXModels

/// One medal, with the round it came from and the person it was won against.
public struct CabinetMedal: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var key: String
    public var roundID: UUID
    public var opponentProfileID: UUID?
    public var createdAt: String
    public var course: String?
    public var date: String?
    public var holes: [Int]?

    public init(row: MedalRow) {
        id = row.id
        key = row.key
        roundID = row.roundId
        opponentProfileID = row.opponentProfileId
        createdAt = row.createdAt
        let context = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(row.context))) as? [String: Any]
        course = context?["course"] as? String
        date = context?["date"] as? String
        holes = (context?["holes"] as? [Any])?.compactMap { $0 as? Int }
    }

    /// The season a medal belongs to: the year it was won (PRD 8.18, newest season first).
    public var season: String { String((date ?? createdAt).prefix(4)) }
}

/// The head-to-head (PRD 8.18). Everything the rivalry screen draws, from one call.
public struct Rivalry: Codable, Sendable, Hashable {
    public struct Round: Codable, Sendable, Hashable, Identifiable {
        public var roundID: UUID
        public var playedOn: String
        public var course: String?
        public var myGross: Int?
        public var theirGross: Int?
        public var outcome: String          // "W", "L", "H"
        public var stickers: [String]
        public var id: UUID { roundID }
        enum CodingKeys: String, CodingKey {
            case roundID = "round_id", playedOn = "played_on", course
            case myGross = "my_gross", theirGross = "their_gross", outcome, stickers
        }
    }
    public struct Medal: Codable, Sendable, Hashable {
        public var key: String
        public var roundID: UUID
        enum CodingKeys: String, CodingKey { case key, roundID = "round_id" }
    }

    public var me: String?
    public var them: String?
    public var rounds: Int
    public var myWins: Int
    public var theirWins: Int
    public var halved: Int
    public var myMedals: [Medal]
    public var theirMedals: [Medal]
    public var iSigned: Int
    public var iDucked: Int
    public var theySigned: Int
    public var theyDucked: Int
    public var lastFive: [Round]

    enum CodingKeys: String, CodingKey {
        case me, them, rounds, halved
        case myWins = "my_wins", theirWins = "their_wins"
        case myMedals = "my_medals", theirMedals = "their_medals"
        case iSigned = "i_signed", iDucked = "i_ducked", theySigned = "they_signed", theyDucked = "they_ducked"
        case lastFive = "last_five"
    }

    /// The streak in the last five, from the most recent backwards: who is on one, and how long.
    public var streak: (name: String, count: Int)? {
        guard let first = lastFive.first, first.outcome != "H" else { return nil }
        var n = 0
        for round in lastFive {
            if round.outcome == first.outcome { n += 1 } else { break }
        }
        guard n >= 2 else { return nil }
        return (first.outcome == "W" ? (me ?? "You") : (them ?? "They"), n)
    }
}

public struct RivalSummary: Codable, Sendable, Hashable, Identifiable {
    public var profileID: UUID
    public var displayName: String?
    public var rounds: Int
    public var lastPlayed: String?
    public var id: UUID { profileID }
    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id", displayName = "display_name", rounds, lastPlayed = "last_played"
    }
}

/// One row of a board (Pass 6 6e).
public struct RankingRow: Codable, Sendable, Hashable, Identifiable {
    public var profileID: UUID
    public var displayName: String?
    public var rounds: Int
    public var level: Double?
    public var value: Double
    public var rank: Int?
    public var previousRank: Int?
    public var isMe: Bool
    public var id: UUID { profileID }

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id", displayName = "display_name", rounds, level, value
        case rank, previousRank = "previous_rank", isMe = "is_me"
    }

    /// The movement caret: up, down, or level since the last refresh.
    public var movement: Int {
        guard let rank, let previousRank else { return 0 }
        return previousRank - rank
    }
}

/// A round of yours that has ended but does not count yet (Pass 6 6e's pending row).
public struct PendingRound: Codable, Sendable, Hashable, Identifiable {
    public var roundID: UUID
    public var course: String?
    public var playedOn: String
    public var gross: Int?
    public var endedAt: String?
    public var confirmed: Bool
    public var objected: Bool
    public var hoursLeft: Double
    public var id: UUID { roundID }

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id", course, playedOn = "played_on", gross, endedAt = "ended_at"
        case confirmed, objected, hoursLeft = "hours_left"
    }
}

public struct CrewSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var joinCode: String
    public var members: Int
    public var mine: Bool
    enum CodingKeys: String, CodingKey { case id, name, joinCode = "join_code", members, mine }
}

public enum RankingMetric: String, CaseIterable, Sendable, Identifiable {
    case stablefordVsLevel = "stableford_vs_level"
    case birdies
    case rounds
    case rivalPoints = "rival_points"
    public var id: String { rawValue }

    /// The metric pills (Pass 6 6e).
    public var title: String {
        switch self {
        case .stablefordVsLevel: return "Stableford"
        case .birdies: return "Birdies"
        case .rounds: return "Rounds"
        case .rivalPoints: return "Rival Points"
        }
    }
    /// The window this metric is read over: birdies are a monthly race (PRD 8.11).
    public var window: String { self == .birdies ? "month" : "all" }
}

public struct CabinetRepository: Sendable {
    let client: XIXClient
    public init(client: XIXClient) { self.client = client }
    private var db: PostgrestClient { client.supabase.schema("xix") }

    // MARK: Cabinet

    /// Every medal this player has won, newest first.
    public func medals() async throws -> [CabinetMedal] {
        guard let me = client.userID else { return [] }
        let rows: [MedalRow] = try await db.from("medals").select().eq("profile_id", value: me)
            .order("created_at", ascending: false).execute().value
        return rows.map(CabinetMedal.init(row:))
    }

    /// The medals from one round, whoever won them: the results screen and the context card use it.
    public func medals(roundID: UUID) async throws -> [CabinetMedal] {
        let rows: [MedalRow] = try await db.from("medals").select().eq("round_id", value: roundID)
            .order("created_at").execute().value
        return rows.map(CabinetMedal.init(row:))
    }

    // MARK: Rivalry

    public func rivals() async throws -> [RivalSummary] {
        try await client.supabase.rpc("rivals").execute().value
    }

    public func rivalry(with profileID: UUID) async throws -> Rivalry {
        struct P: Encodable { let other_profile: UUID }
        return try await client.supabase.rpc("rivalry", params: P(other_profile: profileID)).single().execute().value
    }

    // MARK: Boards

    public func rankings(_ metric: RankingMetric, crewID: UUID? = nil) async throws -> [RankingRow] {
        struct P: Encodable {
            let metric: String; let window: String; let crew_id: UUID?
            enum CodingKeys: String, CodingKey { case metric, window, crew_id }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(metric, forKey: .metric); try c.encode(window, forKey: .window)
                try c.encode(crew_id, forKey: .crew_id)   // explicit null: PostgREST matches on named parameters
            }
        }
        return try await client.supabase.rpc("rankings", params: P(metric: metric.rawValue, window: metric.window, crew_id: crewID))
            .execute().value
    }

    public func pendingRounds() async throws -> [PendingRound] {
        try await client.supabase.rpc("pending_rounds").execute().value
    }

    // MARK: Crews

    public func crews() async throws -> [CrewSummary] {
        struct Row: Decodable { let id: UUID; let name: String; let join_code: String }
        let rows: [Row] = try await db.from("crews").select("id,name,join_code").order("created_at").execute().value
        var out: [CrewSummary] = []
        for row in rows {
            struct Count: Decodable { let count: Int }
            let members = (try? await db.from("crew_members").select("*", head: true, count: .exact)
                .eq("crew_id", value: row.id).execute().count) ?? 0
            out.append(CrewSummary(id: row.id, name: row.name, joinCode: row.join_code, members: members ?? 0, mine: true))
        }
        return out
    }

    @discardableResult
    public func createCrew(name: String) async throws -> CrewSummary {
        struct Row: Decodable { let id: UUID; let name: String; let join_code: String }
        let row: Row = try await client.supabase.rpc("create_crew", params: ["name": name]).single().execute().value
        return CrewSummary(id: row.id, name: row.name, joinCode: row.join_code, members: 1, mine: true)
    }

    public func crewPreview(code: String) async throws -> CrewSummary {
        try await client.supabase.rpc("crew_preview", params: ["code": code]).single().execute().value
    }

    @discardableResult
    public func joinCrew(code: String) async throws -> CrewSummary {
        struct Row: Decodable { let id: UUID; let name: String; let join_code: String }
        let row: Row = try await client.supabase.rpc("join_crew", params: ["code": code]).single().execute().value
        return CrewSummary(id: row.id, name: row.name, joinCode: row.join_code, members: 0, mine: true)
    }

    public func leaveCrew(id: UUID) async throws {
        struct P: Encodable { let crew_id: UUID }
        _ = try await client.supabase.rpc("leave_crew", params: P(crew_id: id)).execute()
    }

    /// Add somebody you have played with straight into a crew you own.
    public func addToCrew(crewID: UUID, profileID: UUID) async throws {
        struct Row: Encodable { let crew_id: UUID; let profile_id: UUID }
        try await db.from("crew_members").insert(Row(crew_id: crewID, profile_id: profileID)).execute()
    }
}
