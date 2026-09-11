/// Quota / Chicago (B.5): needs a Level for every player and par on every played hole.
/// Quota = 36 − handicap strokes (min 0). Points per hole, gross: bogey 1, par 2, birdie 4,
/// eagle or better 8, anything else (including a pick-up) 0. Result = points − quota; highest wins.
/// A multiplied hole's points count `factor` times.
enum QuotaScorer: FormatScorer {
    static func points(strokesToPar diff: Int) -> Int {
        switch diff {
        case ...(-2): return 8
        case -1: return 4
        case 0: return 2
        case 1: return 1
        default: return 0
        }
    }

    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        let missingLevel = game.players.filter { id in round.seat(id).map { round.handicapStrokes[$0] == nil } ?? true }
        guard missingLevel.isEmpty else {
            return ScoredGame(result: .unavailable(game, reason: "Quota needs a Level for every player; missing: \(missingLevel.map(\.rawValue).joined(separator: ", "))", throughHole: through))
        }
        let missingPar = (0..<through).filter { round.par[$0] == nil }
        guard missingPar.isEmpty else {
            return ScoredGame(result: .unavailable(game, reason: "Quota needs par on every played hole; missing on \(missingPar.map { String($0 + 1) }.joined(separator: ", "))", throughHole: through))
        }

        var quota: [PlayerID: Int] = [:]
        var perHole: [PlayerID: [Int]] = [:]
        for seat in seats {
            let id = round.players[seat].id
            quota[id] = max(0, 36 - (round.handicapStrokes[seat] ?? 0))
            var row: [Int] = []
            for hole in 0..<through {
                let factor = context.multiplier(for: game.id, hole: hole + 1)
                if round.pickedUp[seat][hole] {
                    row.append(0)
                } else if let s = round.effective[seat][hole], let par = round.par[hole] {
                    row.append(points(strokesToPar: s - par) * factor)
                } else {
                    row.append(0)
                }
            }
            perHole[id] = row
        }
        let totals = perHole.mapValues { $0.reduce(0, +) }
        let results = Dictionary(uniqueKeysWithValues: game.players.map { ($0, (totals[$0] ?? 0) - (quota[$0] ?? 0)) })

        let complete = through == round.holes && round.holes > 0
        let values = game.players.map { ($0, results[$0] ?? 0) }
        func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { signed($0) }
        let display = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "Quota \(signed($0.1))") })
        let outcome: Outcome? = complete ? FormatSupport.outcome(values, higherIsBetter: true, round: round) : nil
        let result = GameResult(gameID: game.id, format: .quota, throughHole: through, standings: standings, outcome: outcome,
                                display: display, detail: .quota(QuotaDetail(quota: quota, points: perHole, totals: totals, results: results)))
        return ScoredGame(result: result)
    }
}
