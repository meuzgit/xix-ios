/// Nassau (B.5): three independent Match Play instances over holes 1–9, 10–18 and 1–18.
/// Needs an 18-hole round (B.8.12). Presses are not supported in V1.
enum NassauScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let through = round.throughHole(players: game.players)
        guard round.holes == 18 else {
            return ScoredGame(result: .unavailable(game, reason: "Nassau needs an 18-hole round", throughHole: through))
        }
        guard game.options.presses != true else {
            return ScoredGame(result: .unavailable(game, reason: "presses are not supported", throughHole: through))
        }
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

        func play(_ range: Range<Int>) -> MatchPlayDetail {
            MatchEngine.play(game: game, sides: sides, range: range, strokes: strokes, round: round, context: context)
        }
        let detail = NassauDetail(front: play(0..<9), back: play(9..<18), match18: play(0..<18))

        // Display: "Nassau 3 up front · back halved · won 18 5&4"
        let display = GameDisplay(uniqueKeysWithValues: sides.flatMap { side in
            side.ids.map { id in
                let parts = detail.segments.map { MatchEngine.text($0.match, forSide: side.index, segment: $0.name) }
                return (id, "Nassau " + parts.joined(separator: " · "))
            }
        })

        // Standings: segments won so far per side.
        let segmentsWon: [Int] = sides.map { side in
            detail.segments.filter { $0.match.complete && $0.match.leader == side.label }.count
        }
        let values = sides.flatMap { side in side.ids.map { ($0, segmentsWon[side.index]) } }
        var standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { "\($0) of 3" }
        for i in standings.indices { standings[i].side = sides.first { $0.ids.contains(standings[i].player) }?.index }

        // The game-level outcome is the 18-hole match; each segment carries its own in `detail`.
        let allComplete = detail.segments.allSatisfy(\.match.complete)
        let result = GameResult(gameID: game.id, format: .nassau, throughHole: through, standings: standings,
                                outcome: allComplete ? detail.match18.matchOutcome : nil,
                                display: display, detail: .nassau(detail))
        return ScoredGame(result: result)
    }
}
