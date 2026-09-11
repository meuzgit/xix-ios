/// Defender (B.5): exactly three players. The defender rotates by seat order each hole and
/// plays the best ball of the other two. Defender wins the hole → +2 defender; loses → +1
/// each attacker; halved → 0. Highest total wins. A multiplied hole's points count `factor` times.
enum DefenderScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        guard seats.count == 3 else {
            return ScoredGame(result: .unavailable(game, reason: "Defender needs exactly three players", throughHole: through))
        }
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through))
        case .success(let s): strokes = s
        }

        var perHole: [DefenderHole] = []
        var totals: [PlayerID: Int] = Dictionary(uniqueKeysWithValues: game.players.map { ($0, 0) })
        for hole in 0..<through {
            let scores = seats.compactMap { strokes($0, hole) }
            guard scores.count == 3 else { break }
            let d = hole % 3
            let attackers = [0, 1, 2].filter { $0 != d }
            let factor = context.multiplier(for: game.id, hole: hole + 1)
            var points: [PlayerID: Int] = Dictionary(uniqueKeysWithValues: game.players.map { ($0, 0) })
            let result: String
            let best = attackers.map { scores[$0] }.min()!
            if scores[d] < best {
                result = "defended"
                points[game.players[d]] = 2 * factor
            } else if scores[d] > best {
                result = "lost"
                for i in attackers { points[game.players[i]] = 1 * factor }
            } else {
                result = "halved"
            }
            for (id, n) in points { totals[id, default: 0] += n }
            perHole.append(DefenderHole(hole: hole + 1, defender: game.players[d], result: result, points: points))
        }

        let complete = through == round.holes && round.holes > 0
        let values = game.players.map { ($0, totals[$0] ?? 0) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { "\($0) pts" }
        let display = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "Defender \($0.1)") })
        let outcome: Outcome? = complete ? FormatSupport.outcome(values, higherIsBetter: true, round: round) : nil
        let result = GameResult(gameID: game.id, format: .defender, throughHole: through, standings: standings, outcome: outcome,
                                display: display, detail: .defender(DefenderDetail(perHole: perHole, totals: totals)))
        return ScoredGame(result: result)
    }
}
