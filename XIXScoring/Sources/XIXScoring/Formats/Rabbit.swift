/// Rabbit (B.5): per hole the unique lowest score takes the rabbit; a tie leaves it where
/// it is; a different outright winner moves it. Two awards: the holder after hole 9 and
/// after the final hole. A 9-hole round has the hole-9 award only (B.8.12). Gross or net.
enum RabbitScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        guard seats.count >= 2 else {
            return ScoredGame(result: .unavailable(game, reason: "Rabbit needs at least two players", throughHole: through))
        }
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through))
        case .success(let s): strokes = s
        }

        var holder: PlayerID? = nil
        var holders: [PlayerID?] = []
        var moves: [RabbitMove] = []
        var events: [HoleEvent] = []
        for hole in 0..<through {
            let scored = seats.compactMap { seat in strokes(seat, hole).map { (seat, $0) } }
            if let low = scored.map(\.1).min() {
                let leaders = scored.filter { $0.1 == low }
                if leaders.count == 1 {
                    let winner = round.players[leaders[0].0].id
                    if winner != holder {
                        holder = winner
                        moves.append(RabbitMove(hole: hole + 1, to: winner))
                        events.append(HoleEvent(hole: hole + 1, text: "Rabbit to \(round.displayName(winner)).", gameID: game.id))
                    }
                }
            }
            holders.append(holder)
        }

        let complete = through == round.holes && round.holes > 0
        let holderAt9: PlayerID? = through >= 9 ? holders[8] : nil
        let holderAtEnd: PlayerID? = complete ? holder : nil
        let held = Dictionary(game.players.map { ($0, 0) }, uniquingKeysWith: { a, _ in a })
            .merging(holders.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
        let values = game.players.map { ($0, held[$0] ?? 0) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { "held \($0)" }
        let display = GameDisplay(uniqueKeysWithValues: game.players.map { id in
            guard let holder else { return (id, "Rabbit loose") }
            return (id, holder == id ? "Rabbit in hand" : "Rabbit with \(round.displayName(holder))")
        })
        let outcome: Outcome? = complete ? (holderAtEnd.map { .winner($0) } ?? .void) : nil
        let result = GameResult(gameID: game.id, format: .rabbit, throughHole: through, standings: standings, outcome: outcome,
                                display: display,
                                detail: .rabbit(RabbitDetail(holders: holders, moves: moves, holderAt9: holderAt9, holderAtEnd: holderAtEnd)))
        return ScoredGame(result: result, events: events)
    }
}
