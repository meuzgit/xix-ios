/// Entry point. Pure and deterministic: no I/O, no clock.
public enum ScoringEngine {
    /// Increments on any rule change (B.10).
    public static let version = 1

    public static func score(_ input: RoundInput) -> RoundResult {
        let round = NormalisedRound(input)
        let through = round.throughHole(seats: round.allSeats)
        let status: RoundStatus = round.isComplete ? .complete : .inProgress(throughHole: through)

        var perPlayer: [PlayerID: PlayerSummary] = [:]
        for (seat, player) in round.players.enumerated() where perPlayer[player.id] == nil {
            perPlayer[player.id] = round.summary(seat: seat)
        }

        let context = ScoringContext(callouts: input.callouts)
        let scored = input.games.map { scoreGame($0, round: round, context: context) }
        let games = scored.map(\.result)
        // Ink lines in hole order; games in input order within a hole.
        let holeEvents = scored.flatMap(\.events).enumerated()
            .sorted { a, b in a.element.hole != b.element.hole ? a.element.hole < b.element.hole : a.offset < b.offset }
            .map(\.element)

        let callouts = input.callouts.map { CalloutResolver.resolve($0, round: round) }

        var medals: [MedalAward] = []
        var rivalPoints: [PlayerID: Int] = [:]
        if status.isComplete {
            let pairs = Array(zip(input.games, games))
            medals = MedalBuilder.build(games: pairs, callouts: Array(zip(input.callouts, callouts)), round: round)
            let records = pairs.flatMap { OutcomeRecords.records(for: $1, game: $0) }
            rivalPoints = RivalPointsBuilder.build(records: records, callouts: callouts, round: round)
        }

        return RoundResult(
            engineVersion: version,
            status: status,
            perPlayer: perPlayer,
            games: games,
            callouts: callouts,
            holeEvents: holeEvents,
            medals: medals,
            rivalPoints: rivalPoints,
            leaderboard: LeaderboardBuilder.build(perPlayer: perPlayer, games: games, round: round))
    }

    static func scoreGame(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let unknown = game.players.filter { round.seat($0) == nil }
        guard unknown.isEmpty else {
            return ScoredGame(result: .unavailable(game, reason: "unknown player \(unknown.map(\.rawValue).joined(separator: ", "))", throughHole: 0))
        }
        guard !game.players.isEmpty else {
            return ScoredGame(result: .unavailable(game, reason: "no players", throughHole: 0))
        }
        let through = round.throughHole(players: game.players)
        guard let scorer = FormatRegistry.scorer(for: game.format) else {
            return ScoredGame(result: .unavailable(game, reason: "\(game.format.rawValue) is not implemented in engine version \(version)", throughHole: through))
        }
        return scorer.score(game, round: round, context: context)
    }
}
