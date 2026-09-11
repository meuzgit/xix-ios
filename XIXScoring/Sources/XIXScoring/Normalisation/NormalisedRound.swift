/// Normalisation (B.4), applied once before any format runs.
///
/// Rules:
/// 1. Picked up → effective strokes = 2 × par, or 10 when par is unknown.
/// 2. Missing score → the hole is unresolved for every game that includes the player.
///    "Through hole n" is the longest prefix of holes 1…n at which every participant has a score.
/// 3. Marks: circle ≤ par−1, square == par+1, filled ≥ par+2, x if picked up, none otherwise or when par is nil.
/// 4. Net strokes: Level → round((10 − level) × 2.4) clamped 0–24; a user-entered index overrides
///    with round(index). Allocated by stroke index when every hole has one, else evenly from hole 1.
/// 5. toPar is nil for the round if any played hole has nil par.
struct NormalisedRound {
    let holes: Int
    let par: [Int?]
    let strokeIndex: [Int?]
    let players: [PlayerInput]
    let seatOf: [PlayerID: Int]
    /// Raw scores padded/truncated to `holes`.
    let raw: [[HoleScore?]]
    /// Effective strokes after pick-up normalisation; nil where not entered.
    let effective: [[Int?]]
    let pickedUp: [[Bool]]
    let marks: [[Mark]]
    /// Handicap strokes per player; nil without a Level or index.
    let handicapStrokes: [Int?]
    /// Strokes received per hole per player; nil without a Level or index.
    let allocation: [[Int]?]
    /// Net strokes per hole; nil where not entered or no handicap.
    let net: [[Int?]]
    /// Holes the player is expected to play: `holes`, or `leftAfterHole` if they left.
    let activeHoles: [Int]

    init(_ input: RoundInput) {
        let holes = max(0, input.holes)
        self.holes = holes
        par = Self.pad(input.par, to: holes)
        strokeIndex = Self.pad(input.strokeIndex, to: holes)
        players = input.players
        seatOf = Dictionary(players.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        raw = players.indices.map { seat in
            Self.pad(seat < input.scores.count ? input.scores[seat] : [], to: holes)
        }
        activeHoles = players.map { p in
            guard let left = p.extras?.leftAfterHole else { return holes }
            return min(holes, max(0, left))
        }
        let par = self.par
        effective = raw.map { row in
            row.enumerated().map { hole, score in score.map { Self.effectiveStrokes($0, par: par[hole]) } }
        }
        pickedUp = raw.map { row in row.map { $0 == .pickedUp } }
        marks = raw.map { row in
            row.enumerated().map { hole, score in score.map { Self.mark(for: $0, par: par[hole]) } ?? .none }
        }
        let handicapStrokes = players.map(Self.handicapStrokes(for:))
        self.handicapStrokes = handicapStrokes
        let allocator = Self.allocator(holes: holes, strokeIndex: self.strokeIndex)
        let allocation = handicapStrokes.map { $0.map(allocator) }
        self.allocation = allocation
        let effective = self.effective
        net = players.indices.map { seat in
            guard let alloc = allocation[seat] else { return Array(repeating: nil, count: holes) }
            return effective[seat].enumerated().map { hole, strokes in strokes.map { $0 - alloc[hole] } }
        }
    }

    // MARK: Rules

    static func effectiveStrokes(_ score: HoleScore, par: Int?) -> Int {
        switch score {
        case .strokes(let n): return n
        case .pickedUp: return par.map { 2 * $0 } ?? 10
        }
    }

    static func mark(for score: HoleScore, par: Int?) -> Mark {
        guard let par else { return .none }
        switch score {
        case .pickedUp: return .x
        case .strokes(let n):
            if n <= par - 1 { return .circle }
            if n == par + 1 { return .square }
            if n >= par + 2 { return .filled }
            return .none
        }
    }

    static func strokes(forLevel level: Double) -> Int {
        let raw = ((10 - level) * 2.4).rounded()
        return Int(min(24, max(0, raw)))
    }

    static func strokes(forIndex index: Double) -> Int {
        Int(min(54, max(0, index.rounded())))
    }

    static func handicapStrokes(for player: PlayerInput) -> Int? {
        if let index = player.index { return strokes(forIndex: index) }
        if let level = player.level { return strokes(forLevel: level) }
        return nil
    }

    /// Returns a function allocating `n` strokes across holes. Holes are ordered by stroke index
    /// (lowest first, ties by hole order) when every hole has one; otherwise from hole 1. Strokes
    /// wrap around, so 24 strokes on 18 holes gives the six hardest holes two.
    static func allocator(holes: Int, strokeIndex: [Int?]) -> (Int) -> [Int] {
        let order: [Int]
        if holes > 0, strokeIndex.allSatisfy({ $0 != nil }) {
            order = strokeIndex.indices.sorted { a, b in
                let (sa, sb) = (strokeIndex[a]!, strokeIndex[b]!)
                return sa == sb ? a < b : sa < sb
            }
        } else {
            order = Array(0..<holes)
        }
        return { n in
            var alloc = Array(repeating: 0, count: holes)
            guard holes > 0 else { return alloc }
            for i in 0..<max(0, n) { alloc[order[i % holes]] += 1 }
            return alloc
        }
    }

    // MARK: Queries

    func seat(_ id: PlayerID) -> Int? { seatOf[id] }

    func hasScore(seat: Int, hole: Int) -> Bool { raw[seat][hole] != nil }

    /// A hole is resolved for a set of seats when each has a score there (or has left the round).
    func isResolved(hole: Int, seats: [Int]) -> Bool {
        seats.allSatisfy { hole >= activeHoles[$0] || raw[$0][hole] != nil }
    }

    /// Longest prefix 1…n of holes resolved for every seat given (B.4.2). 1-based count.
    func throughHole(seats: [Int]) -> Int {
        var h = 0
        while h < holes, isResolved(hole: h, seats: seats) { h += 1 }
        return h
    }

    func throughHole(players ids: [PlayerID]) -> Int {
        throughHole(seats: ids.compactMap(seat))
    }

    var allSeats: [Int] { Array(players.indices) }

    var isComplete: Bool { holes > 0 && throughHole(seats: allSeats) == holes }

    func displayName(_ id: PlayerID) -> String {
        if let seat = seatOf[id], let name = players[seat].name, !name.isEmpty { return name }
        let raw = id.rawValue
        guard let first = raw.first else { return raw }
        return first.uppercased() + raw.dropFirst()
    }

    func summary(seat: Int) -> PlayerSummary {
        let strokes = effective[seat]
        let entered = strokes.indices.filter { strokes[$0] != nil }
        let gross = entered.reduce(0) { $0 + strokes[$1]! }
        let holeToPar: [Int?] = strokes.enumerated().map { hole, s in
            guard let s, let p = par[hole] else { return nil }
            return s - p
        }
        let anyParMissing = entered.contains { par[$0] == nil }
        let toPar = anyParMissing ? nil : entered.reduce(0) { $0 + holeToPar[$1]! }
        let net: Int? = allocation[seat].map { alloc in gross - entered.reduce(0) { $0 + alloc[$1] } }
        return PlayerSummary(
            gross: gross,
            net: net,
            toPar: toPar,
            holesEntered: entered.count,
            pickedUp: pickedUp[seat].filter { $0 }.count,
            marks: marks[seat],
            effectiveStrokes: strokes,
            holeToPar: holeToPar,
            handicapStrokes: handicapStrokes[seat])
    }

    // MARK: Helpers

    private static func pad<T>(_ array: [T?], to count: Int) -> [T?] {
        if array.count >= count { return Array(array.prefix(count)) }
        return array + Array(repeating: nil, count: count - array.count)
    }
}
