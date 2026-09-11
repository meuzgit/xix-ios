/// Input contract (Build Doc 1, B.2).
///
/// JSON notes:
/// - `scores` decodes from either the contract form (`[[HoleScore?]]`, seat order)
///   or the fixture form (`{ "<playerID>": [HoleScore?] }`). It always encodes in
///   the contract form.
/// - A hole score is an integer stroke count (≥ 1), the string `"PU"` for a
///   pick-up, or `null` for not entered.
public struct RoundInput: Codable, Equatable, Sendable {
    public var holes: Int                    // 9 or 18
    public var par: [Int?]                   // per hole, nil if unknown
    public var strokeIndex: [Int?]           // per hole, nil if unknown
    public var players: [PlayerInput]        // seat order
    public var scores: [[HoleScore?]]        // [player][hole]; nil = not entered
    public var games: [GameInput]
    public var callouts: [CalloutInput]

    public init(holes: Int, par: [Int?], strokeIndex: [Int?], players: [PlayerInput],
                scores: [[HoleScore?]], games: [GameInput] = [], callouts: [CalloutInput] = []) {
        self.holes = holes
        self.par = par
        self.strokeIndex = strokeIndex
        self.players = players
        self.scores = scores
        self.games = games
        self.callouts = callouts
    }

    private enum CodingKeys: String, CodingKey {
        case holes, par, strokeIndex, players, scores, games, callouts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holes = try c.decode(Int.self, forKey: .holes)
        par = try c.decodeIfPresent([Int?].self, forKey: .par) ?? []
        strokeIndex = try c.decodeIfPresent([Int?].self, forKey: .strokeIndex) ?? []
        players = try c.decode([PlayerInput].self, forKey: .players)
        games = try c.decodeIfPresent([GameInput].self, forKey: .games) ?? []
        callouts = try c.decodeIfPresent([CalloutInput].self, forKey: .callouts) ?? []

        if !c.contains(.scores) {
            scores = players.map { _ in [] }
        } else if let rows = try? c.decode([[HoleScore?]].self, forKey: .scores) {
            scores = rows
        } else {
            let keyed = try c.decode([String: [HoleScore?]].self, forKey: .scores)
            let known = Set(players.map(\.id.rawValue))
            if let stray = keyed.keys.sorted().first(where: { !known.contains($0) }) {
                throw DecodingError.dataCorruptedError(
                    forKey: .scores, in: c,
                    debugDescription: "scores has a row for unknown player '\(stray)'")
            }
            scores = players.map { keyed[$0.id.rawValue] ?? [] }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(holes, forKey: .holes)
        try c.encode(par, forKey: .par)
        try c.encode(strokeIndex, forKey: .strokeIndex)
        try c.encode(players, forKey: .players)
        try c.encode(scores, forKey: .scores)
        try c.encode(games, forKey: .games)
        try c.encode(callouts, forKey: .callouts)
    }
}

public enum HoleScore: Hashable, Codable, Sendable {
    case strokes(Int)
    case pickedUp

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) {
            guard n >= 1 else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "strokes must be ≥ 1, got \(n)")
            }
            self = .strokes(n)
            return
        }
        if let s = try? c.decode(String.self) {
            switch s.uppercased() {
            case "PU", "PICKED_UP", "PICKEDUP", "X":
                self = .pickedUp
                return
            default:
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown hole score '\(s)'")
            }
        }
        throw DecodingError.typeMismatch(
            HoleScore.self,
            .init(codingPath: c.codingPath, debugDescription: "expected an integer stroke count or \"PU\""))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .strokes(let n): try c.encode(n)
        case .pickedUp: try c.encode("PU")
        }
    }
}

public struct PlayerInput: Codable, Equatable, Sendable {
    public var id: PlayerID
    /// Level 1–10 (10 = best). nil = none; net formats unavailable.
    public var level: Double?
    /// User-entered handicap index. When present it overrides `level` for net strokes.
    public var index: Double?
    /// Display name for ink lines. Falls back to the id with its first letter capitalised.
    public var name: String?
    public var extras: PlayerExtras?

    public init(id: PlayerID, level: Double? = nil, index: Double? = nil, name: String? = nil, extras: PlayerExtras? = nil) {
        self.id = id
        self.level = level
        self.index = index
        self.name = name
        self.extras = extras
    }
}

/// Optional per-player inputs referenced by B.5/B.7/B.8.
public struct PlayerExtras: Codable, Equatable, Sendable {
    /// Beat Your Average: gross average over ≥ 3 prior rounds.
    public var priorAverage: Double?
    /// The player left the round after this hole (B.8.2). Holes beyond it are not expected.
    public var leftAfterHole: Int?
    /// Best prior gross for the `personal_best` medal.
    public var personalBest: Int?

    public init(priorAverage: Double? = nil, leftAfterHole: Int? = nil, personalBest: Int? = nil) {
        self.priorAverage = priorAverage
        self.leftAfterHole = leftAfterHole
        self.personalBest = personalBest
    }
}

public struct GameInput: Codable, Equatable, Sendable {
    public var id: GameID
    public var format: Format
    public var options: Options
    public var players: [PlayerID]
    /// Team formats: member → side (0/1). nil for individual formats.
    public var sides: [PlayerID: Int]?

    public init(id: GameID, format: Format, options: Options = Options(), players: [PlayerID], sides: [PlayerID: Int]? = nil) {
        self.id = id
        self.format = format
        self.options = options
        self.players = players
        self.sides = sides
    }

    private enum CodingKeys: String, CodingKey { case id, format, options, players, sides }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(GameID.self, forKey: .id)
        format = try c.decode(Format.self, forKey: .format)
        options = try c.decodeIfPresent(Options.self, forKey: .options) ?? Options()
        players = try c.decode([PlayerID].self, forKey: .players)
        sides = try c.decodeIfPresent([PlayerID: Int].self, forKey: .sides)
    }
}

public enum Format: String, Codable, CaseIterable, Sendable {
    case strokePlay = "stroke_play"
    case stableford
    case matchPlay = "match_play"
    case nassau
    case skins
    case bestBall = "best_ball"
    case scramble
    case shamble
    case alternateShot = "alternate_shot"
    case chapman
    case vegas
    case nines
    case sixes
    case quota
    case rabbit
    case defender
    case fewestBlowUps = "fewest_blow_ups"
    case beatYourAverage = "beat_your_average"
    case bogeyGolf = "bogey_golf"
    case mostPars = "most_pars"
    case firstToFive = "first_to_five"
    case worstHole = "worst_hole"

    /// Lenient decoding: exact raw value, or case/punctuation-insensitive match
    /// ("matchPlay", "Match Play", "match-play"), plus a few common aliases.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let f = Format(lenient: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown format '\(s)'")
        }
        self = f
    }

    public init?(lenient string: String) {
        if let f = Format(rawValue: string) { self = f; return }
        let key = Format.normalise(string)
        if let f = Format.allCases.first(where: { Format.normalise($0.rawValue) == key }) { self = f; return }
        switch key {
        case "stroke", "medal", "grossstrokeplay": self = .strokePlay
        case "fourball", "fourballs", "betterball": self = .bestBall
        case "chicago": self = .quota
        case "ninepoints", "9points", "9s": self = .nines
        case "roundrobin", "6s": self = .sixes
        case "foursomes": self = .alternateShot
        case "blowups", "fewestblowups": self = .fewestBlowUps
        case "beataverage": self = .beatYourAverage
        default: return nil
        }
    }

    private static func normalise(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

/// Per-game options. Every field is optional; formats read their own defaults.
public struct Options: Codable, Equatable, Sendable {
    public var net: Bool?
    public var carryover: Bool?
    public var validation: Bool?
    public var presses: Bool?
    public var mode: Mode?                 // Best Ball: stroke or match
    public var count: Int?                 // Shamble: best 1 or 2 scores
    public var table: StablefordTable?     // Stableford: standard (default) or modified

    public enum Mode: String, Codable, Sendable { case stroke, match }
    public enum StablefordTable: String, Codable, Sendable { case standard, modified }

    public init(net: Bool? = nil, carryover: Bool? = nil, validation: Bool? = nil, presses: Bool? = nil,
                mode: Mode? = nil, count: Int? = nil, table: StablefordTable? = nil) {
        self.net = net
        self.carryover = carryover
        self.validation = validation
        self.presses = presses
        self.mode = mode
        self.count = count
        self.table = table
    }

    public var isNet: Bool { net ?? false }
    public var carryoverEnabled: Bool { carryover ?? true }
    public var validationEnabled: Bool { validation ?? false }
}

public struct CalloutInput: Codable, Equatable, Sendable {
    public var id: CalloutID
    public var hole: Int
    public var kind: CalloutKind
    public var caller: PlayerID
    public var targets: [PlayerID]
    public var params: CalloutParams
    public var status: CalloutStatus
    /// Who signed or ducked. Optional; not part of the B.2 sketch but needed for `duckedBy`.
    public var responder: PlayerID?

    public init(id: CalloutID, hole: Int, kind: CalloutKind, caller: PlayerID, targets: [PlayerID],
                params: CalloutParams = CalloutParams(), status: CalloutStatus, responder: PlayerID? = nil) {
        self.id = id
        self.hole = hole
        self.kind = kind
        self.caller = caller
        self.targets = targets
        self.params = params
        self.status = status
        self.responder = responder
    }

    private enum CodingKeys: String, CodingKey { case id, hole, kind, caller, targets, params, status, responder }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(CalloutID.self, forKey: .id)
        hole = try c.decode(Int.self, forKey: .hole)
        kind = try c.decode(CalloutKind.self, forKey: .kind)
        caller = try c.decode(PlayerID.self, forKey: .caller)
        targets = try c.decodeIfPresent([PlayerID].self, forKey: .targets) ?? []
        params = try c.decodeIfPresent(CalloutParams.self, forKey: .params) ?? CalloutParams()
        status = try c.decode(CalloutStatus.self, forKey: .status)
        responder = try c.decodeIfPresent(PlayerID.self, forKey: .responder)
    }
}

public enum CalloutKind: String, Codable, Sendable { case target, duel, partner, multiplier }

public enum CalloutStatus: String, Codable, Sendable { case open, signed, ducked, expired, resolved }

/// `target: {"goal": "par"|"birdie"|n}`, `partner: {"partner_id": ...|null}`,
/// `multiplier: {"game_id": ..., "factor": 2}`. Accepts `partner`/`game` as key aliases.
public struct CalloutParams: Codable, Equatable, Sendable {
    public var goal: TargetGoal?
    public var partner: PlayerID?
    public var game: GameID?
    public var factor: Int?

    public init(goal: TargetGoal? = nil, partner: PlayerID? = nil, game: GameID? = nil, factor: Int? = nil) {
        self.goal = goal
        self.partner = partner
        self.game = game
        self.factor = factor
    }

    private enum CodingKeys: String, CodingKey {
        case goal, factor
        case partnerID = "partner_id", partner
        case gameID = "game_id", game
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decodeIfPresent(TargetGoal.self, forKey: .goal)
        factor = try c.decodeIfPresent(Int.self, forKey: .factor)
        partner = try c.decodeIfPresent(PlayerID.self, forKey: .partnerID)
            ?? c.decodeIfPresent(PlayerID.self, forKey: .partner)
        game = try c.decodeIfPresent(GameID.self, forKey: .gameID)
            ?? c.decodeIfPresent(GameID.self, forKey: .game)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(goal, forKey: .goal)
        try c.encodeIfPresent(partner, forKey: .partnerID)
        try c.encodeIfPresent(game, forKey: .gameID)
        try c.encodeIfPresent(factor, forKey: .factor)
    }
}

public enum TargetGoal: Equatable, Codable, Sendable {
    case par
    case birdie
    case strokes(Int)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { self = .strokes(n); return }
        let s = try c.decode(String.self)
        switch s.lowercased() {
        case "par": self = .par
        case "birdie": self = .birdie
        default:
            if let n = Int(s) { self = .strokes(n); return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown target goal '\(s)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .par: try c.encode("par")
        case .birdie: try c.encode("birdie")
        case .strokes(let n): try c.encode(n)
        }
    }
}

extension HoleScore: ExpressibleByIntegerLiteral {
    /// `let s: HoleScore = 5` reads as five strokes; handy for tests and fixtures in code.
    public init(integerLiteral value: Int) { self = .strokes(value) }
}
