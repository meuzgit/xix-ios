/// Casual-first formats (B.5). Rival Points base 4. Medals: `no_blowups`, `beat_average`,
/// `five_pars`, shared on ties.

private extension NormalisedRound {
    /// Unavailable reason when a played hole (before `through`) lacks par.
    func missingParReason(_ name: String, through: Int) -> String? {
        let missing = (0..<through).filter { par[$0] == nil }
        guard !missing.isEmpty else { return nil }
        return "\(name) needs par on every played hole; missing on \(missing.map { String($0 + 1) }.joined(separator: ", "))"
    }
}

/// Points per hole = 1 if strokes ≤ par+1 else 0; picked up = 0. Highest wins.
enum FewestBlowUpsScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        if let reason = round.missingParReason("Fewest Blow-Ups", through: through) {
            return ScoredGame(result: .unavailable(game, reason: reason, throughHole: through))
        }
        var points: [PlayerID: [Int]] = [:]
        var blowUps: [PlayerID: Int] = [:]
        for seat in seats {
            let id = round.players[seat].id
            var row: [Int] = []
            var blown = 0
            for hole in 0..<through {
                let factor = context.multiplier(for: game.id, hole: hole + 1)
                if !round.pickedUp[seat][hole], let s = round.effective[seat][hole], let par = round.par[hole], s <= par + 1 {
                    row.append(1 * factor)
                } else {
                    row.append(0)
                    blown += 1
                }
            }
            points[id] = row
            blowUps[id] = blown
        }
        let totals = points.mapValues { $0.reduce(0, +) }
        let complete = through == round.holes && round.holes > 0
        let values = game.players.map { ($0, totals[$0] ?? 0) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { "\($0) pts" }
        let display = GameDisplay(uniqueKeysWithValues: game.players.map { ($0, "Blow-Ups \(blowUps[$0] ?? 0)") })
        let outcome: Outcome? = complete ? FormatSupport.outcome(values, higherIsBetter: true, round: round) : nil
        return ScoredGame(result: GameResult(gameID: game.id, format: .fewestBlowUps, throughHole: through, standings: standings,
                                             outcome: outcome, display: display,
                                             detail: .blowUps(BlowUpsDetail(points: points, blowUps: blowUps, totals: totals))))
    }
}

/// Result = priorAverage − gross; highest (most improved) wins. Needs `priorAverage` for every participant.
enum BeatYourAverageScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        let missing = game.players.filter { id in round.seat(id).map { round.players[$0].extras?.priorAverage == nil } ?? true }
        guard missing.isEmpty else {
            return ScoredGame(result: .unavailable(game, reason: "Beat Your Average needs a prior average for every player; missing: \(missing.map(\.rawValue).joined(separator: ", "))", throughHole: through))
        }
        var prior: [PlayerID: Double] = [:]
        var gross: [PlayerID: Int] = [:]
        var improvement: [PlayerID: Double] = [:]
        for seat in seats {
            let id = round.players[seat].id
            let g = round.summary(seat: seat).gross
            prior[id] = round.players[seat].extras!.priorAverage!
            gross[id] = g
            improvement[id] = prior[id]! - Double(g)
        }
        let complete = through == round.holes && round.holes > 0
        func text(_ v: Double) -> String {
            let scaled = Int((abs(v) * 10).rounded())
            return "\(v < 0 ? "-" : "+")\(scaled / 10).\(scaled % 10)"
        }
        let ordered = game.players.sorted { a, b in
            improvement[a]! != improvement[b]! ? improvement[a]! > improvement[b]! : (round.seat(a)! < round.seat(b)!)
        }
        var standings: [Standing] = []
        for (i, id) in ordered.enumerated() {
            let v = improvement[id]!
            let rank = (i > 0 && improvement[ordered[i - 1]]! == v) ? standings[i - 1].rank : i + 1
            standings.append(Standing(player: id, value: v, rank: rank, label: text(v)))
        }
        let display = GameDisplay(uniqueKeysWithValues: game.players.map { ($0, "Beat Avg \(text(improvement[$0]!))") })
        var outcome: Outcome? = nil
        if complete, let best = improvement.values.max() {
            let leaders = ordered.filter { improvement[$0] == best }
            outcome = leaders.count == 1 ? .winner(leaders[0]) : .tied(leaders)
        }
        return ScoredGame(result: GameResult(gameID: game.id, format: .beatYourAverage, throughHole: through, standings: standings,
                                             outcome: outcome, display: display,
                                             detail: .beatAverage(BeatAverageDetail(priorAverage: prior, gross: gross, improvement: improvement))))
    }
}

/// Stableford with par redefined as par + 1.
enum BogeyGolfScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        StablefordScorer.score(game, round: round, context: context, format: .bogeyGolf, parOffset: 1, prefix: "Bogey Golf")
    }
}

/// Count of holes where gross strokes == par. Highest wins.
enum MostParsScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        if let reason = round.missingParReason("Most Pars", through: through) {
            return ScoredGame(result: .unavailable(game, reason: reason, throughHole: through))
        }
        var pars: [PlayerID: [Int]] = [:]
        for seat in seats {
            let id = round.players[seat].id
            pars[id] = (0..<through).map { hole in
                let isPar = !round.pickedUp[seat][hole] && round.effective[seat][hole] == round.par[hole]
                return isPar ? context.multiplier(for: game.id, hole: hole + 1) : 0
            }
        }
        let totals = pars.mapValues { $0.reduce(0, +) }
        let complete = through == round.holes && round.holes > 0
        let values = game.players.map { ($0, totals[$0] ?? 0) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { "\($0) pars" }
        let display = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "Pars \($0.1)") })
        let outcome: Outcome? = complete ? FormatSupport.outcome(values, higherIsBetter: true, round: round) : nil
        return ScoredGame(result: GameResult(gameID: game.id, format: .mostPars, throughHole: through, standings: standings,
                                             outcome: outcome, display: display, detail: .mostPars(MostParsDetail(pars: pars, totals: totals))))
    }
}

/// First player by hole order to reach five holes at or under par. If nobody does, most such
/// holes, ties broken by the earlier hole at which that count was reached; a genuine tie is tied.
/// Decided as soon as someone reaches five.
enum FirstToFiveScorer: FormatScorer {
    static let target = 5

    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        if let reason = round.missingParReason("First to Five", through: through) {
            return ScoredGame(result: .unavailable(game, reason: reason, throughHole: through))
        }
        var counts: [PlayerID: Int] = [:]
        var reachedAt: [PlayerID: Int] = [:]
        var lastCountedAt: [PlayerID: Int] = [:]
        for seat in seats {
            let id = round.players[seat].id
            var n = 0
            for hole in 0..<through {
                if !round.pickedUp[seat][hole], let s = round.effective[seat][hole], let par = round.par[hole], s <= par {
                    n += 1
                    lastCountedAt[id] = hole + 1
                    if n == target, reachedAt[id] == nil { reachedAt[id] = hole + 1 }
                }
            }
            counts[id] = n
        }
        let complete = through == round.holes && round.holes > 0
        // Ordering: reached five earliest first; then more holes; then earlier hole for that count; then seat.
        func key(_ id: PlayerID) -> (Int, Int, Int, Int) {
            (reachedAt[id] ?? Int.max, -(counts[id] ?? 0), lastCountedAt[id] ?? Int.max, round.seat(id) ?? 0)
        }
        let ordered = game.players.sorted { key($0) < key($1) }
        var standings: [Standing] = []
        for (i, id) in ordered.enumerated() {
            let same = i > 0 && key(ordered[i - 1]).0 == key(id).0 && key(ordered[i - 1]).1 == key(id).1 && key(ordered[i - 1]).2 == key(id).2
            let rank = same ? standings[i - 1].rank : i + 1
            let label = reachedAt[id].map { "at \($0)" } ?? "\(counts[id] ?? 0) of \(target)"
            standings.append(Standing(player: id, value: Double(counts[id] ?? 0), rank: rank, label: label))
        }
        let display = GameDisplay(uniqueKeysWithValues: standings.map { ($0.player, "First to Five \($0.label)") })
        var outcome: Outcome? = nil
        let anyReached = !reachedAt.isEmpty
        if anyReached || complete, let first = ordered.first {
            let k = key(first)
            let leaders = ordered.filter { let o = key($0); return o.0 == k.0 && o.1 == k.1 && o.2 == k.2 }
            outcome = leaders.count == 1 ? .winner(leaders[0]) : .tied(leaders)
        }
        return ScoredGame(result: GameResult(gameID: game.id, format: .firstToFive, throughHole: through, standings: standings,
                                             outcome: outcome, display: display,
                                             detail: .firstToFive(FirstToFiveDetail(counts: counts, reachedAt: reachedAt, lastCountedAt: lastCountedAt))))
    }
}

/// Per player the worst (strokes − par) hole; the round's single worst across players is the
/// award, ties shared. Picked up counts at its effective strokes.
enum WorstHoleScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        if let reason = round.missingParReason("Worst Hole", through: through) {
            return ScoredGame(result: .unavailable(game, reason: reason, throughHole: through))
        }
        var perPlayer: [PlayerID: WorstHole] = [:]
        for seat in seats {
            let id = round.players[seat].id
            for hole in 0..<through {
                guard let s = round.effective[seat][hole], let par = round.par[hole] else { continue }
                let over = s - par
                if perPlayer[id] == nil || over > perPlayer[id]!.overPar { perPlayer[id] = WorstHole(hole: hole + 1, overPar: over) }
            }
        }
        let complete = through == round.holes && round.holes > 0
        let values = game.players.map { ($0, perPlayer[$0]?.overPar ?? Int.min) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { $0 == Int.min ? "–" : ($0 > 0 ? "+\($0)" : "\($0)") }
        let display = GameDisplay(uniqueKeysWithValues: game.players.map { id in
            guard let w = perPlayer[id] else { return (id, "Worst Hole –") }
            return (id, "Worst Hole \(w.overPar > 0 ? "+" : "")\(w.overPar) (\(w.hole))")
        })
        var outcome: Outcome? = nil
        var worst: Int? = nil
        if complete, let w = perPlayer.values.map(\.overPar).max() {
            worst = w
            let holders = game.players.filter { perPlayer[$0]?.overPar == w }
            outcome = holders.count == 1 ? .winner(holders[0]) : .tied(holders)
        }
        return ScoredGame(result: GameResult(gameID: game.id, format: .worstHole, throughHole: through, standings: standings,
                                             outcome: outcome, display: display,
                                             detail: .worstHole(WorstHoleDetail(perPlayer: perPlayer, worstOverPar: worst))))
    }
}
