/// Vegas (B.5): two sides of two. Each side's number per hole is its members' scores
/// concatenated low then high (4 and 5 → 45); the lower side takes the difference.
/// Birdie flip: if a side has a member at par−1 or better, the opposing side's digits
/// are reversed (high first) before differencing; both sides can flip. Picked up counts
/// its effective strokes. Digits are capped at 9 for the concatenation only (B.8.5), so a
/// picked-up par 5 (10 strokes) contributes a 9. A multiplied hole's points count `factor` times.
enum VegasScorer: FormatScorer {
    static let digitCap = 9

    static func number(low: Int, high: Int) -> Int { min(low, digitCap) * 10 + min(high, digitCap) }
    static func flipped(_ number: Int) -> Int { (number % 10) * 10 + number / 10 }

    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let through0 = round.throughHole(players: game.players)
        let sides: [MatchSide]
        switch MatchEngine.sides(for: game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through0))
        case .success(let s): sides = s
        }
        guard sides.allSatisfy({ $0.seats.count == 2 }) else {
            return ScoredGame(result: .unavailable(game, reason: "Vegas needs sides of two", throughHole: through0))
        }
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through0))
        case .success(let s): strokes = s
        }

        let allSeats = sides.flatMap(\.seats)
        var through = 0
        while through < round.holes, allSeats.allSatisfy({ strokes($0, through) != nil }) { through += 1 }

        var perHole: [VegasHole] = []
        var totals: [String: Int] = Dictionary(uniqueKeysWithValues: sides.map { ($0.label, 0) })
        for hole in 0..<through {
            let scores = sides.map { side in side.seats.map { strokes($0, hole)! }.sorted() }
            var numbers = scores.map { number(low: $0[0], high: $0[1]) }
            let birdie: [Bool] = sides.map { side in
                guard let par = round.par[hole] else { return false }
                return side.seats.contains { seat in
                    !round.pickedUp[seat][hole] && (round.effective[seat][hole] ?? .max) <= par - 1
                }
            }
            var flips = [false, false]
            for i in 0..<2 where birdie[i] {
                let other = 1 - i
                numbers[other] = flipped(numbers[other])
                flips[other] = true
            }
            let factor = context.multiplier(for: game.id, hole: hole + 1)
            let diff = abs(numbers[0] - numbers[1]) * factor
            var points = [0, 0]
            if numbers[0] < numbers[1] { points[0] = diff } else if numbers[1] < numbers[0] { points[1] = diff }
            for i in 0..<2 { totals[sides[i].label, default: 0] += points[i] }
            perHole.append(VegasHole(
                hole: hole + 1,
                numbers: Dictionary(uniqueKeysWithValues: sides.enumerated().map { ($1.label, numbers[$0]) }),
                flipped: Dictionary(uniqueKeysWithValues: sides.enumerated().map { ($1.label, flips[$0]) }),
                points: Dictionary(uniqueKeysWithValues: sides.enumerated().map { ($1.label, points[$0]) })))
        }

        let complete = through == round.holes && round.holes > 0
        let ordered = sides.sorted { totals[$0.label]! > totals[$1.label]! || (totals[$0.label]! == totals[$1.label]! && $0.index < $1.index) }
        var standings: [Standing] = []
        for (i, side) in ordered.enumerated() {
            let value = totals[side.label]!
            let rank = (i > 0 && totals[ordered[i - 1].label]! == value) ? standings.last!.rank : i + 1
            for id in side.ids {
                standings.append(Standing(player: id, side: side.index, value: Double(value), rank: rank, label: "\(value) pts"))
            }
        }
        var outcome: Outcome? = nil
        if complete {
            let t0 = totals[sides[0].label]!, t1 = totals[sides[1].label]!
            if t0 == t1 { outcome = .tied(sides.flatMap(\.ids)) }
            else { let w = t0 > t1 ? sides[0] : sides[1]; outcome = .winningSide(w.index, players: w.ids) }
        }
        let display = GameDisplay(uniqueKeysWithValues: sides.flatMap { side in side.ids.map { ($0, "Vegas \(totals[side.label] ?? 0)") } })
        let result = GameResult(gameID: game.id, format: .vegas, throughHole: through, standings: standings, outcome: outcome,
                                display: display, detail: .vegas(VegasDetail(sides: sides.map(\.ids), perHole: perHole, totals: totals)))
        return ScoredGame(result: result)
    }
}
