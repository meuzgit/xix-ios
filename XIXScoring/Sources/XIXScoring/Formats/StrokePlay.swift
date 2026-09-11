/// Stroke Play (B.5): sum of effective strokes, gross or net, over the resolved holes.
/// Lowest wins; ties are shared. A signed multiplier callout makes that hole's to-par
/// difference count `factor` times in the standings (B.6); with par unknown on that
/// hole the multiplier has no effect.
enum StrokePlayScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through))
        case .success(let s): strokes = s
        }
        let net = game.options.isNet

        var perHole: [PlayerID: [Int]] = [:]
        var totals: [PlayerID: Int] = [:]
        var adjusted: [PlayerID: Int] = [:]
        for seat in seats {
            let id = round.players[seat].id
            var row: [Int] = []
            var adjust = 0
            for hole in 0..<through {
                guard let s = strokes(seat, hole) else { break }
                row.append(s)
                let factor = context.multiplier(for: game.id, hole: hole + 1)
                if factor > 1, let par = round.par[hole] {
                    let allowance = net ? (round.allocation[seat]?[hole] ?? 0) : 0
                    adjust += (factor - 1) * (s - (par - allowance))
                }
            }
            perHole[id] = row
            totals[id] = row.reduce(0, +)
            adjusted[id] = totals[id]! + adjust
        }

        let complete = through == round.holes && round.holes > 0
        let values = game.players.map { ($0, adjusted[$0] ?? 0) }
        let prefix = net ? "Net" : "Stroke"
        let standings = FormatSupport.standings(values, higherIsBetter: false, round: round) { "\($0)" }
        let display = GameDisplay(uniqueKeysWithValues: game.players.map { ($0, "\(prefix) \(totals[$0] ?? 0)") })
        let outcome: Outcome? = complete ? FormatSupport.outcome(values, higherIsBetter: false, round: round) : nil
        let result = GameResult(gameID: game.id, format: .strokePlay, throughHole: through, standings: standings,
                                outcome: outcome, display: display,
                                detail: .strokePlay(StrokePlayDetail(net: net, strokes: perHole, totals: totals, adjusted: adjusted)))
        return ScoredGame(result: result)
    }
}
