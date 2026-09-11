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

/// Shamble (B.5): members enter individually; the side counts its best `count` (1 or 2) scores per hole.
enum ShambleScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        let count = game.options.count ?? 1
        guard (1...2).contains(count) else {
            let through = round.throughHole(players: game.players)
            return ScoredGame(result: .unavailable(game, reason: "Shamble counts 1 or 2 scores, not \(count)", throughHole: through))
        }
        return SideStrokeScorer.score(game, round: round, context: context, format: .shamble,
                                      policy: .allMembers(count: count), prefix: "Shamble")
    }
}
