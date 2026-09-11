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
