/// A format turns a game input plus the normalised round into a `GameResult`.
/// Formats are registered in `FormatRegistry` as they are implemented.
protocol FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> GameResult
}

/// Round-wide inputs a format may need beyond its own game (multiplier callouts, B.6).
struct ScoringContext {
    let callouts: [CalloutInput]
}

enum FormatRegistry {
    static func scorer(for format: Format) -> FormatScorer.Type? {
        switch format {
        default: return nil
        }
    }
}

extension GameResult {
    static func unavailable(_ game: GameInput, reason: String, throughHole: Int) -> GameResult {
        GameResult(gameID: game.id, format: game.format, throughHole: throughHole, standings: [],
                   outcome: .unavailable(reason: reason), display: [:], detail: .none)
    }
}
