/// Scramble, Alternate Shot and Chapman (B.5): one score row per side. The round's
/// players are the side rows (or `sides` maps several rows to one side, in which case
/// the lowest entered row counts). Scored as Stroke Play across sides.
enum ScrambleScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        SideStrokeScorer.score(game, round: round, context: context, format: .scramble, policy: .anyRow, prefix: "Scramble")
    }
}

enum AlternateShotScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        SideStrokeScorer.score(game, round: round, context: context, format: .alternateShot, policy: .anyRow, prefix: "Alternate Shot")
    }
}

enum ChapmanScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        SideStrokeScorer.score(game, round: round, context: context, format: .chapman, policy: .anyRow, prefix: "Chapman")
    }
}
