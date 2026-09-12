/// Skins (B.5). Per hole the unique lowest score wins `1 + carried` skins; a tie
/// carries one more (with `carryover`, default on). With `validation`, an existing
/// carry is only won by par or better; otherwise the hole's skin joins the carry.
/// A signed multiplier callout makes the hole worth `factor` skins (B.6, B.8.9).
/// Unclaimed carry at the end of the round is void (B.8.3). Holes beyond the
/// last one every participant has scored are not played, so the carry waits (B.4.2).
enum SkinsScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        guard seats.count >= 2 else {
            return ScoredGame(result: .unavailable(game, reason: "Skins needs at least two players", throughHole: through))
        }
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let unavailable):
            return ScoredGame(result: .unavailable(game, reason: unavailable.reason, throughHole: through))
        case .success(let source):
            strokes = source
        }

        let options = game.options
        var carry = 0
        var totals: [PlayerID: Int] = Dictionary(uniqueKeysWithValues: game.players.map { ($0, 0) })
        var perHole: [SkinsHole] = []
        var events: [HoleEvent] = []
        var abandonedBy: PlayerID? = nil

        for hole in 0..<through {
            let holeNumber = hole + 1
            let isLast = holeNumber == round.holes
            let worth = context.multiplier(for: game.id, hole: holeNumber)
            let scored = seats.compactMap { seat in strokes(seat, hole).map { (seat: seat, strokes: $0) } }
            guard scored.count >= 2, let low = scored.map(\.strokes).min() else {
                // Fewer than two players left to contest the hole: a departure ends the game (B.8.2).
                if let gone = seats.first(where: { round.activeHoles[$0] < round.holes }) {
                    abandonedBy = round.players[gone].id
                    break
                }
                perHole.append(SkinsHole(hole: holeNumber, winner: nil, skins: 0, carryAfter: carry))
                continue
            }
            let leaders = scored.filter { $0.strokes == low }

            func carryText(_ prefix: String) -> String {
                guard carry > 0 else { return prefix }
                return isLast ? "\(prefix) \(carry) void." : "\(prefix) \(carry) carrying to \(holeNumber + 1)."
            }

            if leaders.count == 1 {
                let winner = round.players[leaders[0].seat].id
                let name = round.displayName(winner)
                let mustValidate = options.validationEnabled && carry > 0
                let validated = !mustValidate || round.par[hole].map { low <= $0 } ?? true
                if validated {
                    let won = worth + carry
                    totals[winner, default: 0] += won
                    perHole.append(SkinsHole(hole: holeNumber, winner: winner, skins: won, carryAfter: 0))
                    events.append(HoleEvent(hole: holeNumber,
                                            text: carry > 0 ? "Skin to \(name). Carry cleared." : "Skin to \(name).",
                                            gameID: game.id))
                    carry = 0
                } else {
                    carry += worth
                    perHole.append(SkinsHole(hole: holeNumber, winner: nil, skins: 0, carryAfter: carry, unvalidated: winner))
                    events.append(HoleEvent(hole: holeNumber,
                                            text: carryText("\(name) takes the hole but not the carry."),
                                            gameID: game.id))
                }
            } else {
                if options.carryoverEnabled {
                    carry += worth
                    events.append(HoleEvent(hole: holeNumber, text: carryText("Halved."), gameID: game.id))
                } else {
                    events.append(HoleEvent(hole: holeNumber, text: "Halved.", gameID: game.id))
                }
                perHole.append(SkinsHole(hole: holeNumber, winner: nil, skins: 0, carryAfter: carry))
            }
        }

        let complete = through == round.holes && round.holes > 0
        let voidCarry = complete ? carry : 0
        let values = game.players.map { ($0, totals[$0] ?? 0) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { n in
            "\(n) skin\(n == 1 ? "" : "s")"
        }
        let display = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "Skins \($0.1)") })
        let compact = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "\($0.1)") })
        var outcome: Outcome? = nil
        if let abandonedBy {
            outcome = .abandoned(by: abandonedBy)
        } else if complete {
            // Nobody won a skin (every hole halved, B.8.3): no winner rather than an all-way tie.
            outcome = values.allSatisfy { $0.1 == 0 } ? .void : FormatSupport.outcome(values, higherIsBetter: true, round: round)
        }

        let result = GameResult(
            gameID: game.id, format: .skins, throughHole: through, standings: standings, outcome: outcome,
            display: display, compact: compact,
            detail: .skins(SkinsDetail(perHole: perHole, totals: totals, carry: complete ? 0 : carry, voidCarry: voidCarry)))
        return ScoredGame(result: result, events: events)
    }
}
