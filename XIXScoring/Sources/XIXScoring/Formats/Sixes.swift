/// Sixes / Round Robin (B.5): exactly four players over 18 holes; three six-hole best-ball
/// matches with rotating partners (1–6 AB v CD, 7–12 AC v BD, 13–18 AD v BC, by seat order).
/// Points per segment: win 2, halve 1, to each member. Highest total wins.
enum SixesScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let through = round.throughHole(players: game.players)
        guard round.holes == 18 else {
            return ScoredGame(result: .unavailable(game, reason: "Sixes needs an 18-hole round", throughHole: through))
        }
        guard game.players.count == 4, game.players.allSatisfy({ round.seat($0) != nil }) else {
            return ScoredGame(result: .unavailable(game, reason: "Sixes needs exactly four players", throughHole: through))
        }
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through))
        case .success(let s): strokes = s
        }

        let p = game.players
        let rotation: [(name: String, range: Range<Int>, pairs: [[PlayerID]])] = [
            ("1-6", 0..<6, [[p[0], p[1]], [p[2], p[3]]]),
            ("7-12", 6..<12, [[p[0], p[2]], [p[1], p[3]]]),
            ("13-18", 12..<18, [[p[0], p[3]], [p[1], p[2]]]),
        ]
        var segments: [SixesSegment] = []
        var totals: [PlayerID: Int] = Dictionary(uniqueKeysWithValues: p.map { ($0, 0) })
        for seg in rotation {
            let sides = seg.pairs.enumerated().map { i, ids in
                MatchSide(index: i, label: ids.map(\.rawValue).joined(separator: "+"), ids: ids, seats: ids.compactMap(round.seat))
            }
            let match = MatchEngine.play(game: game, sides: sides, range: seg.range, strokes: strokes, round: round, context: context)
            var points: [PlayerID: Int] = Dictionary(uniqueKeysWithValues: p.map { ($0, 0) })
            switch match.matchOutcome {
            case .winningSide(_, let players)?: for id in players { points[id] = 2 }
            case .winner(let id)?: points[id] = 2
            case .halved?: for id in p { points[id] = 1 }
            default: break
            }
            for (id, n) in points { totals[id, default: 0] += n }
            segments.append(SixesSegment(name: seg.name, match: match, points: points))
        }

        let complete = segments.allSatisfy(\.match.complete)
        let values = p.map { ($0, totals[$0] ?? 0) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { "\($0) pts" }
        let display = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "Sixes \($0.1)") })
        let abandonedBy = segments.compactMap(\.match.abandonedBy).first
        let outcome: Outcome? = abandonedBy.map { .abandoned(by: $0) }
            ?? (complete ? FormatSupport.outcome(values, higherIsBetter: true, round: round) : nil)
        let result = GameResult(gameID: game.id, format: .sixes, throughHole: through, standings: standings, outcome: outcome,
                                display: display, detail: .sixes(SixesDetail(segments: segments, totals: totals)))
        return ScoredGame(result: result)
    }
}
