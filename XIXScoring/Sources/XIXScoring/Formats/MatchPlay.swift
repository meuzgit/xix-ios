/// Match Play (B.5): two sides, players or teams via best ball, over every hole.
enum MatchPlayScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let through = round.throughHole(players: game.players)
        let sides: [MatchSide]
        switch MatchEngine.sides(for: game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through))
        case .success(let s): sides = s
        }
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through))
        case .success(let s): strokes = s
        }

        let match = MatchEngine.play(game: game, sides: sides, range: 0..<round.holes, strokes: strokes,
                                     round: round, context: context)
        let display = GameDisplay(uniqueKeysWithValues: sides.flatMap { side in
            side.ids.map { ($0, "Match \(MatchEngine.text(match, forSide: side.index, segment: nil))") }
        })
        let result = GameResult(gameID: game.id, format: .matchPlay, throughHole: through,
                                standings: MatchEngine.standings(match, sides: sides),
                                outcome: match.abandonedBy.map { .abandoned(by: $0) } ?? match.matchOutcome,
                                display: display, detail: .matchPlay(match))
        return ScoredGame(result: result)
    }
}
