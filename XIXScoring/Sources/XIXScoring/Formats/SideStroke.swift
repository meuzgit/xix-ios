/// Stroke play across sides (B.5): Best Ball in stroke mode, Scramble, Shamble, Alternate
/// Shot and Chapman. Each side's score per hole comes from its members' rows:
/// - `allMembers(count:)`: every active member must have entered; the side scores the sum of
///   its best `count` member scores (1 = best ball).
/// - `anyRow`: one row per side carries the score (the side's "player" row); the hole is
///   resolved once each side has a row entered, and the lowest entered row counts.
/// Lowest total wins; ties are shared. A multiplied hole's to-par difference counts `factor` times.
enum SideStrokeScorer {
    enum Policy {
        case allMembers(count: Int)
        case anyRow
    }

    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext,
                      format: Format, policy: Policy, prefix: String) -> ScoredGame {
        let through0 = round.throughHole(players: game.players)
        let sides: [MatchSide]
        switch SideGrouping.sides(for: game, round: round, exactlyTwo: false) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through0))
        case .success(let s): sides = s
        }
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through0))
        case .success(let s): strokes = s
        }
        let count: Int
        if case .allMembers(let n) = policy { count = max(1, n) } else { count = 1 }

        /// Side score on a hole, or nil while the hole is unresolved for that side.
        func sideScore(_ side: MatchSide, _ hole: Int) -> Int? {
            let active = side.seats.filter { hole < round.activeHoles[$0] }
            let entered = active.compactMap { strokes($0, hole) }
            switch policy {
            case .allMembers:
                guard !active.isEmpty, entered.count == active.count else { return nil }
                return entered.sorted().prefix(count).reduce(0, +)
            case .anyRow:
                return entered.min()
            }
        }

        var through = 0
        while through < round.holes, sides.allSatisfy({ sideScore($0, through) != nil }) { through += 1 }

        var perHole: [String: [Int]] = [:]
        var totals: [String: Int] = [:]
        var adjusted: [String: Int] = [:]
        for side in sides {
            var row: [Int] = []
            var adjust = 0
            for hole in 0..<through {
                let s = sideScore(side, hole)!
                row.append(s)
                let factor = context.multiplier(for: game.id, hole: hole + 1)
                if factor > 1, let par = round.par[hole] {
                    adjust += (factor - 1) * (s - count * par)
                }
            }
            perHole[side.label] = row
            totals[side.label] = row.reduce(0, +)
            adjusted[side.label] = totals[side.label]! + adjust
        }

        let complete = through == round.holes && round.holes > 0
        let ordered = sides.sorted { adjusted[$0.label]! < adjusted[$1.label]! || (adjusted[$0.label]! == adjusted[$1.label]! && $0.index < $1.index) }
        var standings: [Standing] = []
        for (i, side) in ordered.enumerated() {
            let value = adjusted[side.label]!
            let rank = (i > 0 && adjusted[ordered[i - 1].label]! == value) ? standings.last!.rank : i + 1
            for id in side.ids {
                standings.append(Standing(player: id, side: side.index, value: Double(value), rank: rank, label: "\(value)"))
            }
        }
        var outcome: Outcome? = nil
        if complete, let best = adjusted.values.min() {
            let leaders = sides.filter { adjusted[$0.label] == best }
            if leaders.count == 1 {
                let side = leaders[0]
                outcome = side.ids.count == 1 ? .winner(side.ids[0]) : .winningSide(side.index, players: side.ids)
            } else {
                outcome = .tied(leaders.flatMap(\.ids))
            }
        }
        let display = GameDisplay(uniqueKeysWithValues: sides.flatMap { side in
            side.ids.map { ($0, "\(prefix) \(totals[side.label] ?? 0)") }
        })
        let detail = SideStrokeDetail(sides: sides.map(\.ids), count: count, perHole: perHole, totals: totals, adjusted: adjusted)
        let result = GameResult(gameID: game.id, format: format, throughHole: through, standings: standings,
                                outcome: outcome, display: display, detail: .sideStroke(detail))
        return ScoredGame(result: result)
    }
}

/// Best Ball / Four-Ball (B.5): sides via `sides`; side score per hole = best member score;
/// then Match Play (`mode: match`, the default) or Stroke Play (`mode: stroke`).
enum BestBallScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        switch game.options.mode ?? .match {
        case .stroke:
            return SideStrokeScorer.score(game, round: round, context: context, format: .bestBall,
                                          policy: .allMembers(count: 1), prefix: "Best Ball")
        case .match:
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
                side.ids.map { ($0, "Best Ball \(MatchEngine.text(match, forSide: side.index, segment: nil))") }
            })
            let compact = GameDisplay(uniqueKeysWithValues: sides.flatMap { side in side.ids.map { ($0, match.compact[side.label] ?? "") } })
            let result = GameResult(gameID: game.id, format: .bestBall, throughHole: through,
                                    standings: MatchEngine.standings(match, sides: sides),
                                    outcome: match.abandonedBy.map { .abandoned(by: $0) } ?? match.matchOutcome,
                                    display: display, compact: compact, detail: .matchPlay(match))
            return ScoredGame(result: result)
        }
    }
}
