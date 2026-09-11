/// Nines / 9 Points (B.5): exactly three players. Each hole allocates 9 points by finish:
/// 5/3/1; two tied low → 4/4/1; two tied high → 5/2/2; all tied → 3/3/3. Highest total wins.
/// A multiplied hole's points count `factor` times.
enum NinesScorer: FormatScorer {
    /// Points for three scores in player order.
    static func allocate(_ scores: [Int]) -> [Int] {
        let sorted = scores.sorted()
        let (lo, mid, hi) = (sorted[0], sorted[1], sorted[2])
        if lo == hi { return [3, 3, 3] }
        if lo == mid { return scores.map { $0 == lo ? 4 : 1 } }
        if mid == hi { return scores.map { $0 == lo ? 5 : 2 } }
        return scores.map { $0 == lo ? 5 : ($0 == mid ? 3 : 1) }
    }

    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        guard seats.count == 3 else {
            return ScoredGame(result: .unavailable(game, reason: "Nines needs exactly three players", throughHole: through))
        }
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through))
        case .success(let s): strokes = s
        }

        var points: [PlayerID: [Int]] = Dictionary(uniqueKeysWithValues: game.players.map { ($0, []) })
        for hole in 0..<through {
            let scores = seats.compactMap { strokes($0, hole) }
            guard scores.count == 3 else { break }
            let factor = context.multiplier(for: game.id, hole: hole + 1)
            for (i, p) in allocate(scores).enumerated() { points[game.players[i]]!.append(p * factor) }
        }
        let totals = points.mapValues { $0.reduce(0, +) }
        let complete = through == round.holes && round.holes > 0
        let values = game.players.map { ($0, totals[$0] ?? 0) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { "\($0) pts" }
        let display = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "Nines \($0.1)") })
        let outcome: Outcome? = complete ? FormatSupport.outcome(values, higherIsBetter: true, round: round) : nil
        let result = GameResult(gameID: game.id, format: .nines, throughHole: through, standings: standings, outcome: outcome,
                                display: display, detail: .nines(NinesDetail(points: points, totals: totals)))
        return ScoredGame(result: result)
    }
}
