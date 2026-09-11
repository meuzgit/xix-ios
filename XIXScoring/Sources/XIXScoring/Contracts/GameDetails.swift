/// Format-specific result detail. Each detail encodes flattened into its
/// `GameResult` object (see `GameDetail.encode(into:)`).

// MARK: - Skins

public struct SkinsDetail: Equatable, Sendable {
    /// One entry per resolved hole, in hole order.
    public var perHole: [SkinsHole]
    public var totals: [PlayerID: Int]
    /// Skins currently carrying (0 once the round is complete).
    public var carry: Int
    /// Carry left unclaimed at the end of the round.
    public var voidCarry: Int

    public init(perHole: [SkinsHole], totals: [PlayerID: Int], carry: Int, voidCarry: Int) {
        self.perHole = perHole
        self.totals = totals
        self.carry = carry
        self.voidCarry = voidCarry
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(perHole, forKey: AnyCodingKey("perHole"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
        try c.encode(carry, forKey: AnyCodingKey("carry"))
        try c.encode(voidCarry, forKey: AnyCodingKey("voidCarry"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        perHole = try c.decode([SkinsHole].self, forKey: AnyCodingKey("perHole"))
        totals = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("totals"))
        carry = try c.decode(Int.self, forKey: AnyCodingKey("carry"))
        voidCarry = try c.decode(Int.self, forKey: AnyCodingKey("voidCarry"))
    }
}

public struct SkinsHole: Codable, Equatable, Sendable {
    public var hole: Int
    public var winner: PlayerID?             // nil when halved or not validated
    public var skins: Int                    // skins awarded on this hole
    public var carryAfter: Int
    /// With `validation`, the unique low scorer who failed to score par or better.
    public var unvalidated: PlayerID?

    public init(hole: Int, winner: PlayerID?, skins: Int, carryAfter: Int, unvalidated: PlayerID? = nil) {
        self.hole = hole
        self.winner = winner
        self.skins = skins
        self.carryAfter = carryAfter
        self.unvalidated = unvalidated
    }

    private enum CodingKeys: String, CodingKey { case hole, winner, skins, carryAfter, unvalidated }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hole, forKey: .hole)
        try c.encode(winner, forKey: .winner)          // explicit null when halved
        try c.encode(skins, forKey: .skins)
        try c.encode(carryAfter, forKey: .carryAfter)
        try c.encodeIfPresent(unvalidated, forKey: .unvalidated)
    }
}

// MARK: - Match Play

/// One two-side match over a range of holes. Used standalone (Match Play) and
/// three times by Nassau. Sides are labelled by player id for singles, or by
/// the members' ids joined with "+" for teams.
public struct MatchPlayDetail: Codable, Equatable, Sendable {
    public var sides: [[PlayerID]]
    /// Holes up earned per side label. A multiplied hole counts `factor` (B.6).
    public var holesWon: [String: Int]
    public var halved: Int
    public var firstHole: Int                // 1-based
    public var lastHole: Int                 // 1-based, inclusive
    /// Last hole played in this match; equals `decidedAtHole` after an early decision.
    public var throughHole: Int
    public var holesRemaining: Int           // 0 once decided or complete
    public var leader: String?               // side label; nil when all square
    public var up: Int                       // leader's lead
    /// Set when the match was decided before its last hole (B.5, B.8.6). Standings freeze there.
    public var decidedAtHole: Int?
    public var complete: Bool
    /// "ray 3 up", "halved", "ray 5&4", "all square".
    public var result: String
    public var matchOutcome: Outcome?
    public var perHole: [MatchHole]

    private enum CodingKeys: String, CodingKey {
        case sides, holesWon, halved, firstHole, lastHole, throughHole, holesRemaining, leader, up,
             decidedAtHole, complete, result, matchOutcome, perHole
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(sides, forKey: AnyCodingKey("sides"))
        try c.encode(holesWon, forKey: AnyCodingKey("holesWon"))
        try c.encode(halved, forKey: AnyCodingKey("halved"))
        try c.encode(firstHole, forKey: AnyCodingKey("firstHole"))
        try c.encode(lastHole, forKey: AnyCodingKey("lastHole"))
        try c.encode(throughHole, forKey: AnyCodingKey("matchThroughHole"))
        try c.encode(holesRemaining, forKey: AnyCodingKey("holesRemaining"))
        try c.encodeIfPresent(leader, forKey: AnyCodingKey("leader"))
        try c.encode(up, forKey: AnyCodingKey("up"))
        try c.encodeIfPresent(decidedAtHole, forKey: AnyCodingKey("decidedAtHole"))
        try c.encode(complete, forKey: AnyCodingKey("complete"))
        try c.encode(result, forKey: AnyCodingKey("result"))
        try c.encodeIfPresent(matchOutcome, forKey: AnyCodingKey("matchOutcome"))
        try c.encode(perHole, forKey: AnyCodingKey("perHole"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        sides = try c.decode([[PlayerID]].self, forKey: AnyCodingKey("sides"))
        holesWon = try c.decode([String: Int].self, forKey: AnyCodingKey("holesWon"))
        halved = try c.decode(Int.self, forKey: AnyCodingKey("halved"))
        firstHole = try c.decode(Int.self, forKey: AnyCodingKey("firstHole"))
        lastHole = try c.decode(Int.self, forKey: AnyCodingKey("lastHole"))
        throughHole = try c.decode(Int.self, forKey: AnyCodingKey("matchThroughHole"))
        holesRemaining = try c.decode(Int.self, forKey: AnyCodingKey("holesRemaining"))
        leader = try c.decodeIfPresent(String.self, forKey: AnyCodingKey("leader"))
        up = try c.decode(Int.self, forKey: AnyCodingKey("up"))
        decidedAtHole = try c.decodeIfPresent(Int.self, forKey: AnyCodingKey("decidedAtHole"))
        complete = try c.decode(Bool.self, forKey: AnyCodingKey("complete"))
        result = try c.decode(String.self, forKey: AnyCodingKey("result"))
        matchOutcome = try c.decodeIfPresent(Outcome.self, forKey: AnyCodingKey("matchOutcome"))
        perHole = try c.decode([MatchHole].self, forKey: AnyCodingKey("perHole"))
    }

    public init(sides: [[PlayerID]], holesWon: [String: Int], halved: Int, firstHole: Int, lastHole: Int,
                throughHole: Int, holesRemaining: Int, leader: String?, up: Int, decidedAtHole: Int?,
                complete: Bool, result: String, matchOutcome: Outcome?, perHole: [MatchHole]) {
        self.sides = sides
        self.holesWon = holesWon
        self.halved = halved
        self.firstHole = firstHole
        self.lastHole = lastHole
        self.throughHole = throughHole
        self.holesRemaining = holesRemaining
        self.leader = leader
        self.up = up
        self.decidedAtHole = decidedAtHole
        self.complete = complete
        self.result = result
        self.matchOutcome = matchOutcome
        self.perHole = perHole
    }
}

public struct MatchHole: Codable, Equatable, Sendable {
    public var hole: Int
    public var winner: String?               // side label; nil when halved
    public var worth: Int                    // holes up earned (multiplier factor)

    public init(hole: Int, winner: String?, worth: Int) {
        self.hole = hole
        self.winner = winner
        self.worth = worth
    }
}

// MARK: - Nassau

/// Three independent matches: holes 1–9, 10–18 and 1–18 (B.5).
public struct NassauDetail: Equatable, Sendable {
    public var front: MatchPlayDetail
    public var back: MatchPlayDetail
    public var match18: MatchPlayDetail

    public init(front: MatchPlayDetail, back: MatchPlayDetail, match18: MatchPlayDetail) {
        self.front = front
        self.back = back
        self.match18 = match18
    }

    public var segments: [(name: String, match: MatchPlayDetail)] {
        [("front", front), ("back", back), ("18", match18)]
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(front, forKey: AnyCodingKey("front"))
        try c.encode(back, forKey: AnyCodingKey("back"))
        try c.encode(match18, forKey: AnyCodingKey("match18"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        front = try c.decode(MatchPlayDetail.self, forKey: AnyCodingKey("front"))
        back = try c.decode(MatchPlayDetail.self, forKey: AnyCodingKey("back"))
        match18 = try c.decode(MatchPlayDetail.self, forKey: AnyCodingKey("match18"))
    }
}

// MARK: - Stableford

public struct StablefordDetail: Equatable, Sendable {
    /// Points per resolved hole, in hole order, per player. A multiplied hole is already scaled.
    public var points: [PlayerID: [Int]]
    public var totals: [PlayerID: Int]
    public var table: String                 // "standard" or "modified"

    public init(points: [PlayerID: [Int]], totals: [PlayerID: Int], table: String) {
        self.points = points
        self.totals = totals
        self.table = table
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(points, forKey: AnyCodingKey("points"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
        try c.encode(table, forKey: AnyCodingKey("table"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        points = try c.decode([PlayerID: [Int]].self, forKey: AnyCodingKey("points"))
        totals = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("totals"))
        table = try c.decode(String.self, forKey: AnyCodingKey("table"))
    }
}

// MARK: - Stroke Play

public struct StrokePlayDetail: Equatable, Sendable {
    public var net: Bool
    /// Strokes counted per resolved hole (effective gross, or net), per player.
    public var strokes: [PlayerID: [Int]]
    public var totals: [PlayerID: Int]
    /// Totals after multiplier callouts: a multiplied hole's to-par difference counts `factor` times.
    public var adjusted: [PlayerID: Int]

    public init(net: Bool, strokes: [PlayerID: [Int]], totals: [PlayerID: Int], adjusted: [PlayerID: Int]) {
        self.net = net
        self.strokes = strokes
        self.totals = totals
        self.adjusted = adjusted
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(net, forKey: AnyCodingKey("net"))
        try c.encode(strokes, forKey: AnyCodingKey("strokes"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
        try c.encode(adjusted, forKey: AnyCodingKey("adjusted"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        net = try c.decode(Bool.self, forKey: AnyCodingKey("net"))
        strokes = try c.decode([PlayerID: [Int]].self, forKey: AnyCodingKey("strokes"))
        totals = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("totals"))
        adjusted = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("adjusted"))
    }
}

// MARK: - Side stroke (Best Ball stroke mode, Scramble, Shamble, Alternate Shot, Chapman)

public struct SideStrokeDetail: Equatable, Sendable {
    public var sides: [[PlayerID]]
    /// Best scores per hole counted for each side (1 for best ball / side rows, `count` for Shamble).
    public var count: Int
    /// Side score per resolved hole, keyed by side label.
    public var perHole: [String: [Int]]
    public var totals: [String: Int]
    /// Totals after multiplier callouts (to-par difference on that hole × factor).
    public var adjusted: [String: Int]

    public init(sides: [[PlayerID]], count: Int, perHole: [String: [Int]], totals: [String: Int], adjusted: [String: Int]) {
        self.sides = sides
        self.count = count
        self.perHole = perHole
        self.totals = totals
        self.adjusted = adjusted
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(sides, forKey: AnyCodingKey("sides"))
        try c.encode(count, forKey: AnyCodingKey("count"))
        try c.encode(perHole, forKey: AnyCodingKey("perHole"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
        try c.encode(adjusted, forKey: AnyCodingKey("adjusted"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        sides = try c.decode([[PlayerID]].self, forKey: AnyCodingKey("sides"))
        count = try c.decode(Int.self, forKey: AnyCodingKey("count"))
        perHole = try c.decode([String: [Int]].self, forKey: AnyCodingKey("perHole"))
        totals = try c.decode([String: Int].self, forKey: AnyCodingKey("totals"))
        adjusted = try c.decode([String: Int].self, forKey: AnyCodingKey("adjusted"))
    }
}

// MARK: - Vegas

public struct VegasDetail: Equatable, Sendable {
    public var sides: [[PlayerID]]
    public var perHole: [VegasHole]
    public var totals: [String: Int]

    public init(sides: [[PlayerID]], perHole: [VegasHole], totals: [String: Int]) {
        self.sides = sides
        self.perHole = perHole
        self.totals = totals
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(sides, forKey: AnyCodingKey("sides"))
        try c.encode(perHole, forKey: AnyCodingKey("perHole"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        sides = try c.decode([[PlayerID]].self, forKey: AnyCodingKey("sides"))
        perHole = try c.decode([VegasHole].self, forKey: AnyCodingKey("perHole"))
        totals = try c.decode([String: Int].self, forKey: AnyCodingKey("totals"))
    }
}

public struct VegasHole: Codable, Equatable, Sendable {
    public var hole: Int
    /// Each side's number after any birdie flip, keyed by side label.
    public var numbers: [String: Int]
    public var flipped: [String: Bool]
    public var points: [String: Int]

    public init(hole: Int, numbers: [String: Int], flipped: [String: Bool], points: [String: Int]) {
        self.hole = hole
        self.numbers = numbers
        self.flipped = flipped
        self.points = points
    }
}

// MARK: - Nines

public struct NinesDetail: Equatable, Sendable {
    public var points: [PlayerID: [Int]]
    public var totals: [PlayerID: Int]

    public init(points: [PlayerID: [Int]], totals: [PlayerID: Int]) {
        self.points = points
        self.totals = totals
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(points, forKey: AnyCodingKey("points"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        points = try c.decode([PlayerID: [Int]].self, forKey: AnyCodingKey("points"))
        totals = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("totals"))
    }
}

// MARK: - Sixes

public struct SixesDetail: Equatable, Sendable {
    public var segments: [SixesSegment]
    public var totals: [PlayerID: Int]

    public init(segments: [SixesSegment], totals: [PlayerID: Int]) {
        self.segments = segments
        self.totals = totals
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(segments, forKey: AnyCodingKey("segments"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        segments = try c.decode([SixesSegment].self, forKey: AnyCodingKey("segments"))
        totals = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("totals"))
    }
}

public struct SixesSegment: Codable, Equatable, Sendable {
    public var name: String                  // "1-6", "7-12", "13-18"
    public var match: MatchPlayDetail
    public var points: [PlayerID: Int]       // win 2, halve 1, per member

    public init(name: String, match: MatchPlayDetail, points: [PlayerID: Int]) {
        self.name = name
        self.match = match
        self.points = points
    }
}
