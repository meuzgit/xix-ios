/// Output contract (Build Doc 1, B.3).
///
/// Encoding is designed so a JSON fixture's `expected` block can be compared
/// field by field against the encoded result:
/// - `status` encodes as `"complete"` or `{"inProgress": n}`.
/// - `perPlayer`, `rivalPoints` and `leaderboard` encode as JSON objects keyed by id / mode.
/// - `GameResult` encodes its common fields plus the format-specific detail
///   flattened into the same object (`front`, `perHole`, `points`, …).
/// - `Outcome` encodes a single winner as a bare id string, `halved`/`void` as
///   strings, and the remaining cases as small objects.
public struct RoundResult: Codable, Equatable, Sendable {
    public var engineVersion: Int
    public var status: RoundStatus
    public var perPlayer: [PlayerID: PlayerSummary]
    public var games: [GameResult]
    public var callouts: [CalloutResult]
    public var holeEvents: [HoleEvent]
    public var medals: [MedalAward]             // only when .complete
    public var rivalPoints: [PlayerID: Int]     // only when .complete
    public var leaderboard: [LeaderboardMode: [LeaderboardRow]]

    public init(engineVersion: Int, status: RoundStatus, perPlayer: [PlayerID: PlayerSummary], games: [GameResult],
                callouts: [CalloutResult], holeEvents: [HoleEvent], medals: [MedalAward],
                rivalPoints: [PlayerID: Int], leaderboard: [LeaderboardMode: [LeaderboardRow]]) {
        self.engineVersion = engineVersion
        self.status = status
        self.perPlayer = perPlayer
        self.games = games
        self.callouts = callouts
        self.holeEvents = holeEvents
        self.medals = medals
        self.rivalPoints = rivalPoints
        self.leaderboard = leaderboard
    }
}

public enum RoundStatus: Equatable, Codable, Sendable {
    case inProgress(throughHole: Int)
    case complete

    private enum Keys: String, CodingKey { case inProgress }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            guard s == "complete" else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "unknown status '\(s)'")
            }
            self = .complete
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        self = .inProgress(throughHole: try c.decode(Int.self, forKey: .inProgress))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .complete:
            var c = encoder.singleValueContainer()
            try c.encode("complete")
        case .inProgress(let n):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(n, forKey: .inProgress)
        }
    }

    public var isComplete: Bool { if case .complete = self { return true } else { return false } }
}

/// Ink marks (B.4.3). `none` encodes as the empty string.
public enum Mark: String, Codable, Sendable {
    case none = ""
    case circle
    case square
    case filled
    case x
}

public struct PlayerSummary: Codable, Equatable, Sendable {
    public var gross: Int                    // sum of effective strokes over entered holes
    public var net: Int?                     // gross − handicap strokes received; nil without a Level/index
    public var toPar: Int?                   // nil if any played hole has nil par
    public var holesEntered: Int
    public var pickedUp: Int                 // count of picked-up holes
    public var marks: [Mark]                 // per hole; `none` where not entered or par nil
    public var effectiveStrokes: [Int?]      // per hole after pick-up normalisation
    public var holeToPar: [Int?]             // per hole; nil where not entered or par nil
    public var handicapStrokes: Int?         // strokes derived from Level / index (B.4.4)

    public init(gross: Int, net: Int?, toPar: Int?, holesEntered: Int, pickedUp: Int, marks: [Mark],
                effectiveStrokes: [Int?], holeToPar: [Int?], handicapStrokes: Int?) {
        self.gross = gross
        self.net = net
        self.toPar = toPar
        self.holesEntered = holesEntered
        self.pickedUp = pickedUp
        self.marks = marks
        self.effectiveStrokes = effectiveStrokes
        self.holeToPar = holeToPar
        self.handicapStrokes = handicapStrokes
    }
}

// MARK: - Games

public typealias GameDisplay = [PlayerID: String]

public struct GameResult: Codable, Equatable, Sendable {
    public var gameID: GameID
    public var format: Format
    /// Last hole at which every participant has a score (B.4.2).
    public var throughHole: Int
    public var standings: [Standing]
    public var outcome: Outcome?             // nil until the game is complete
    public var display: GameDisplay          // "Skins 2", "Nassau 1 up front" per player
    public var detail: GameDetail

    public init(gameID: GameID, format: Format, throughHole: Int, standings: [Standing], outcome: Outcome?,
                display: GameDisplay, detail: GameDetail) {
        self.gameID = gameID
        self.format = format
        self.throughHole = throughHole
        self.standings = standings
        self.outcome = outcome
        self.display = display
        self.detail = detail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        gameID = try c.decode(GameID.self, forKey: AnyCodingKey("gameID"))
        format = try c.decode(Format.self, forKey: AnyCodingKey("format"))
        throughHole = try c.decode(Int.self, forKey: AnyCodingKey("throughHole"))
        standings = try c.decode([Standing].self, forKey: AnyCodingKey("standings"))
        outcome = try c.decodeIfPresent(Outcome.self, forKey: AnyCodingKey("outcome"))
        display = try c.decodeIfPresent(GameDisplay.self, forKey: AnyCodingKey("display")) ?? [:]
        let kind = try c.decodeIfPresent(String.self, forKey: AnyCodingKey("detail")) ?? "none"
        detail = try GameDetail(kind: kind, from: c)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(gameID, forKey: AnyCodingKey("gameID"))
        try c.encode(format, forKey: AnyCodingKey("format"))
        try c.encode(throughHole, forKey: AnyCodingKey("throughHole"))
        try c.encode(standings, forKey: AnyCodingKey("standings"))
        try c.encodeIfPresent(outcome, forKey: AnyCodingKey("outcome"))
        try c.encode(display, forKey: AnyCodingKey("display"))
        try c.encode(detail.kind, forKey: AnyCodingKey("detail"))
        try detail.encode(into: &c)
    }
}

/// One row of a game's standings, best first. Tied rows share a `rank`.
public struct Standing: Codable, Equatable, Sendable {
    public var player: PlayerID
    public var side: Int?                    // team formats
    public var value: Double                 // skins, points, holes up, strokes … per format
    public var rank: Int                     // 1-based; ties share
    public var label: String                 // "2 skins", "3 up", "30 pts"

    public init(player: PlayerID, side: Int? = nil, value: Double, rank: Int, label: String) {
        self.player = player
        self.side = side
        self.value = value
        self.rank = rank
        self.label = label
    }
}

/// Format-specific result detail. Cases are added as formats are implemented.
public enum GameDetail: Equatable, Sendable {
    case none
    case skins(SkinsDetail)
    case matchPlay(MatchPlayDetail)
    case nassau(NassauDetail)
    case stableford(StablefordDetail)
    case strokePlay(StrokePlayDetail)
    case sideStroke(SideStrokeDetail)
    case vegas(VegasDetail)
    case quota(QuotaDetail)
    case sixes(SixesDetail)
    case nines(NinesDetail)

    var kind: String {
        switch self {
        case .none: return "none"
        case .skins: return "skins"
        case .matchPlay: return "matchPlay"
        case .nassau: return "nassau"
        case .stableford: return "stableford"
        case .strokePlay: return "strokePlay"
        case .sideStroke: return "sideStroke"
        case .vegas: return "vegas"
        case .quota: return "quota"
        case .sixes: return "sixes"
        case .nines: return "nines"
        }
    }

    init(kind: String, from container: KeyedDecodingContainer<AnyCodingKey>) throws {
        switch kind {
        case "none":
            self = .none
        case "skins":
            self = .skins(try SkinsDetail(from: container))
        case "matchPlay":
            self = .matchPlay(try MatchPlayDetail(from: container))
        case "nassau":
            self = .nassau(try NassauDetail(from: container))
        case "stableford":
            self = .stableford(try StablefordDetail(from: container))
        case "strokePlay":
            self = .strokePlay(try StrokePlayDetail(from: container))
        case "sideStroke":
            self = .sideStroke(try SideStrokeDetail(from: container))
        case "vegas":
            self = .vegas(try VegasDetail(from: container))
        case "quota":
            self = .quota(try QuotaDetail(from: container))
        case "sixes":
            self = .sixes(try SixesDetail(from: container))
        case "nines":
            self = .nines(try NinesDetail(from: container))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: AnyCodingKey("detail"), in: container, debugDescription: "unknown game detail kind '\(kind)'")
        }
    }

    func encode(into container: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        switch self {
        case .none:
            break
        case .skins(let d):
            try d.encode(into: &container)
        case .matchPlay(let d):
            try d.encode(into: &container)
        case .nassau(let d):
            try d.encode(into: &container)
        case .stableford(let d):
            try d.encode(into: &container)
        case .strokePlay(let d):
            try d.encode(into: &container)
        case .sideStroke(let d):
            try d.encode(into: &container)
        case .vegas(let d):
            try d.encode(into: &container)
        case .quota(let d):
            try d.encode(into: &container)
        case .sixes(let d):
            try d.encode(into: &container)
        case .nines(let d):
            try d.encode(into: &container)
        }
    }
}

/// Ties are explicit (`tied`, `halved`), never broken silently.
public enum Outcome: Equatable, Codable, Sendable {
    case winner(PlayerID)
    case winningSide(Int, players: [PlayerID])
    case tied([PlayerID])
    case halved
    case void
    case abandoned(by: PlayerID)
    case unavailable(reason: String)

    private enum Keys: String, CodingKey { case side, players, tied, abandoned, unavailable }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            switch s {
            case "halved": self = .halved
            case "void": self = .void
            default: self = .winner(PlayerID(rawValue: s))
            }
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        if let side = try c.decodeIfPresent(Int.self, forKey: .side) {
            self = .winningSide(side, players: try c.decode([PlayerID].self, forKey: .players))
        } else if let tied = try c.decodeIfPresent([PlayerID].self, forKey: .tied) {
            self = .tied(tied)
        } else if let by = try c.decodeIfPresent(PlayerID.self, forKey: .abandoned) {
            self = .abandoned(by: by)
        } else if let reason = try c.decodeIfPresent(String.self, forKey: .unavailable) {
            self = .unavailable(reason: reason)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .side, in: c, debugDescription: "unrecognised outcome")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .winner(let p):
            var c = encoder.singleValueContainer()
            try c.encode(p)
        case .halved:
            var c = encoder.singleValueContainer()
            try c.encode("halved")
        case .void:
            var c = encoder.singleValueContainer()
            try c.encode("void")
        case .winningSide(let side, let players):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(side, forKey: .side)
            try c.encode(players, forKey: .players)
        case .tied(let players):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(players, forKey: .tied)
        case .abandoned(let by):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(by, forKey: .abandoned)
        case .unavailable(let reason):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(reason, forKey: .unavailable)
        }
    }

    public var isUnavailable: Bool { if case .unavailable = self { return true } else { return false } }
}

// MARK: - Callouts

public struct CalloutResult: Codable, Equatable, Sendable {
    public var calloutID: CalloutID
    public var kind: CalloutKind
    public var hole: Int
    public var status: CalloutStatus
    public var caller: PlayerID
    public var targets: [PlayerID]
    public var hit: [PlayerID]?              // target callouts: who reached the goal
    public var winner: CalloutWinner?
    public var duckedBy: PlayerID?
    public var loneWolf: Bool?               // partner callout won by a lone caller
    /// Why a signed callout could not be resolved (par unknown, bad hole, missing target).
    public var reason: String?

    public init(calloutID: CalloutID, kind: CalloutKind, hole: Int, status: CalloutStatus, caller: PlayerID,
                targets: [PlayerID], hit: [PlayerID]? = nil, winner: CalloutWinner? = nil,
                duckedBy: PlayerID? = nil, loneWolf: Bool? = nil, reason: String? = nil) {
        self.calloutID = calloutID
        self.kind = kind
        self.hole = hole
        self.status = status
        self.caller = caller
        self.targets = targets
        self.hit = hit
        self.winner = winner
        self.duckedBy = duckedBy
        self.loneWolf = loneWolf
        self.reason = reason
    }
}

/// Encodes as a bare id for one winner, an array for several, or `"halved"`.
public enum CalloutWinner: Equatable, Codable, Sendable {
    case player(PlayerID)
    case players([PlayerID])
    case halved

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = s == "halved" ? .halved : .player(PlayerID(rawValue: s))
        } else {
            self = .players(try c.decode([PlayerID].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .player(let p): try c.encode(p)
        case .players(let ps): try c.encode(ps)
        case .halved: try c.encode("halved")
        }
    }

    public var players: [PlayerID] {
        switch self {
        case .player(let p): return [p]
        case .players(let ps): return ps
        case .halved: return []
        }
    }
}

// MARK: - Events, medals, leaderboard

/// One ink line for the card: "Skin to Tess. Carry cleared."
public struct HoleEvent: Codable, Equatable, Sendable {
    public var hole: Int
    public var text: String
    public var gameID: GameID?

    public init(hole: Int, text: String, gameID: GameID? = nil) {
        self.hole = hole
        self.text = text
        self.gameID = gameID
    }
}

public enum MedalKey: String, Codable, CaseIterable, Sendable {
    case nassauFront = "nassau_front"
    case nassauBack = "nassau_back"
    case nassau18 = "nassau_18"
    case skinsTwo = "skins_two"
    case skinsFour = "skins_four"
    case matchplayWin = "matchplay_win"
    case stablefordTop = "stableford_top"
    case strokeLowGross = "stroke_low_gross"
    case fivePars = "five_pars"
    case noBlowups = "no_blowups"
    case beatAverage = "beat_average"
    case calloutCalledIt = "callout_called_it"
    case calloutDuel = "callout_duel"
    case calloutLoneWolf = "callout_lone_wolf"
    case calloutDuckedNothing = "callout_ducked_nothing"
    case rabbit9 = "rabbit_9"
    case rabbit18 = "rabbit_18"
    case personalBest = "personal_best"
}

public struct MedalAward: Codable, Equatable, Sendable {
    /// The player row that earned it; the server maps player → profile.
    public var profile: PlayerID
    public var key: MedalKey
    public var opponent: PlayerID?
    public var holes: [Int]?

    public init(profile: PlayerID, key: MedalKey, opponent: PlayerID? = nil, holes: [Int]? = nil) {
        self.profile = profile
        self.key = key
        self.opponent = opponent
        self.holes = holes
    }
}

public enum LeaderboardMode: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case gross
    case net
    case toPar = "to_par"
    case skins
    case stableford
    case birdies
}

public struct LeaderboardRow: Codable, Equatable, Sendable {
    public var player: PlayerID
    public var value: Int
    public var rank: Int                     // 1-based; ties share

    public init(player: PlayerID, value: Int, rank: Int) {
        self.player = player
        self.value = value
        self.rank = rank
    }
}
