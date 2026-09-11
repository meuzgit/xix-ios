/// Detail payloads for the casual-first formats (B.5).

public struct BlowUpsDetail: Equatable, Sendable {
    public var points: [PlayerID: [Int]]     // 1 if strokes ≤ par+1 else 0 (× multiplier)
    public var blowUps: [PlayerID: Int]
    public var totals: [PlayerID: Int]

    public init(points: [PlayerID: [Int]], blowUps: [PlayerID: Int], totals: [PlayerID: Int]) {
        self.points = points
        self.blowUps = blowUps
        self.totals = totals
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(points, forKey: AnyCodingKey("points"))
        try c.encode(blowUps, forKey: AnyCodingKey("blowUps"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        points = try c.decode([PlayerID: [Int]].self, forKey: AnyCodingKey("points"))
        blowUps = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("blowUps"))
        totals = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("totals"))
    }
}

public struct BeatAverageDetail: Equatable, Sendable {
    public var priorAverage: [PlayerID: Double]
    public var gross: [PlayerID: Int]
    public var improvement: [PlayerID: Double]   // priorAverage − gross

    public init(priorAverage: [PlayerID: Double], gross: [PlayerID: Int], improvement: [PlayerID: Double]) {
        self.priorAverage = priorAverage
        self.gross = gross
        self.improvement = improvement
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(priorAverage, forKey: AnyCodingKey("priorAverage"))
        try c.encode(gross, forKey: AnyCodingKey("gross"))
        try c.encode(improvement, forKey: AnyCodingKey("improvement"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        priorAverage = try c.decode([PlayerID: Double].self, forKey: AnyCodingKey("priorAverage"))
        gross = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("gross"))
        improvement = try c.decode([PlayerID: Double].self, forKey: AnyCodingKey("improvement"))
    }
}

public struct MostParsDetail: Equatable, Sendable {
    public var pars: [PlayerID: [Int]]       // 1 on a par (× multiplier)
    public var totals: [PlayerID: Int]

    public init(pars: [PlayerID: [Int]], totals: [PlayerID: Int]) {
        self.pars = pars
        self.totals = totals
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(pars, forKey: AnyCodingKey("pars"))
        try c.encode(totals, forKey: AnyCodingKey("totals"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        pars = try c.decode([PlayerID: [Int]].self, forKey: AnyCodingKey("pars"))
        totals = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("totals"))
    }
}

public struct FirstToFiveDetail: Equatable, Sendable {
    public var counts: [PlayerID: Int]           // holes at or under par so far
    public var reachedAt: [PlayerID: Int]        // hole at which the fifth was reached
    public var lastCountedAt: [PlayerID: Int]    // hole at which the current count was reached

    public init(counts: [PlayerID: Int], reachedAt: [PlayerID: Int], lastCountedAt: [PlayerID: Int]) {
        self.counts = counts
        self.reachedAt = reachedAt
        self.lastCountedAt = lastCountedAt
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(counts, forKey: AnyCodingKey("counts"))
        try c.encode(reachedAt, forKey: AnyCodingKey("reachedAt"))
        try c.encode(lastCountedAt, forKey: AnyCodingKey("lastCountedAt"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        counts = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("counts"))
        reachedAt = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("reachedAt"))
        lastCountedAt = try c.decode([PlayerID: Int].self, forKey: AnyCodingKey("lastCountedAt"))
    }
}

public struct WorstHoleDetail: Equatable, Sendable {
    public var perPlayer: [PlayerID: WorstHole]
    public var worstOverPar: Int?                // the round's single worst, once complete

    public init(perPlayer: [PlayerID: WorstHole], worstOverPar: Int?) {
        self.perPlayer = perPlayer
        self.worstOverPar = worstOverPar
    }

    func encode(into c: inout KeyedEncodingContainer<AnyCodingKey>) throws {
        try c.encode(perPlayer, forKey: AnyCodingKey("perPlayer"))
        try c.encodeIfPresent(worstOverPar, forKey: AnyCodingKey("worstOverPar"))
    }

    init(from c: KeyedDecodingContainer<AnyCodingKey>) throws {
        perPlayer = try c.decode([PlayerID: WorstHole].self, forKey: AnyCodingKey("perPlayer"))
        worstOverPar = try c.decodeIfPresent(Int.self, forKey: AnyCodingKey("worstOverPar"))
    }
}

public struct WorstHole: Codable, Equatable, Sendable {
    public var hole: Int                     // first hole at which the player's worst was reached
    public var overPar: Int

    public init(hole: Int, overPar: Int) {
        self.hole = hole
        self.overPar = overPar
    }
}
