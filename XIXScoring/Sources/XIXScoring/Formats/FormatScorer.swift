/// A format turns a game input plus the normalised round into a `GameResult`
/// and the ink lines it produced. Formats are registered in `FormatRegistry`.
protocol FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame
}

struct ScoredGame {
    var result: GameResult
    var events: [HoleEvent] = []
}

/// Round-wide inputs a format may need beyond its own game (multiplier callouts, B.6).
struct ScoringContext {
    let callouts: [CalloutInput]

    /// Product of signed (or already resolved) multiplier callouts aimed at `game` on `hole` (1-based); 1 when none.
    func multiplier(for game: GameID, hole: Int) -> Int {
        callouts
            .filter { $0.kind == .multiplier && ($0.status == .signed || $0.status == .resolved)
                      && $0.params.game == game && $0.hole == hole }
            .reduce(1) { $0 * max(1, $1.params.factor ?? 2) }
    }
}

enum FormatRegistry {
    static func scorer(for format: Format) -> FormatScorer.Type? {
        switch format {
        case .skins: return SkinsScorer.self
        case .matchPlay: return MatchPlayScorer.self
        case .nassau: return NassauScorer.self
        case .stableford: return StablefordScorer.self
        case .strokePlay: return StrokePlayScorer.self
        case .bestBall: return BestBallScorer.self
        case .scramble: return ScrambleScorer.self
        case .alternateShot: return AlternateShotScorer.self
        case .chapman: return ChapmanScorer.self
        case .shamble: return ShambleScorer.self
        case .vegas: return VegasScorer.self
        case .nines: return NinesScorer.self
        case .sixes: return SixesScorer.self
        case .quota: return QuotaScorer.self
        case .rabbit: return RabbitScorer.self
        case .defender: return DefenderScorer.self
        case .fewestBlowUps: return FewestBlowUpsScorer.self
        case .beatYourAverage: return BeatYourAverageScorer.self
        case .bogeyGolf: return BogeyGolfScorer.self
        case .mostPars: return MostParsScorer.self
        case .firstToFive: return FirstToFiveScorer.self
        case .worstHole: return WorstHoleScorer.self
        }
    }
}

extension GameResult {
    static func unavailable(_ game: GameInput, reason: String, throughHole: Int) -> GameResult {
        GameResult(gameID: game.id, format: game.format, throughHole: throughHole, standings: [],
                   outcome: .unavailable(reason: reason), display: [:], detail: .none)
    }
}

/// Why a game cannot be scored as configured (B.8.13, B.8.14 …).
struct Unavailable: Error, Equatable {
    let reason: String
}

/// Groups a game's players into sides. Without a `sides` map every player is a side of one.
enum SideGrouping {
    static func sides(for game: GameInput, round: NormalisedRound, exactlyTwo: Bool) -> Result<[MatchSide], Unavailable> {
        let grouped: [[PlayerID]]
        if let map = game.sides {
            let unmapped = game.players.filter { map[$0] == nil }
            guard unmapped.isEmpty else {
                return .failure(Unavailable(reason: "players without a side: \(unmapped.map(\.rawValue).joined(separator: ", "))"))
            }
            let indices = Set(map.values).sorted()
            guard indices == Array(0..<indices.count) else {
                return .failure(Unavailable(reason: "sides must be numbered 0, 1, …"))
            }
            grouped = indices.map { side in game.players.filter { map[$0] == side } }.filter { !$0.isEmpty }
        } else if exactlyTwo {
            guard game.players.count == 2 else {
                return .failure(Unavailable(reason: "\(game.format.rawValue) needs two players, or teams via sides"))
            }
            grouped = game.players.map { [$0] }
        } else {
            grouped = game.players.map { [$0] }
        }
        if exactlyTwo, grouped.count != 2 {
            return .failure(Unavailable(reason: "\(game.format.rawValue) needs exactly two sides (0 and 1)"))
        }
        guard grouped.count >= 2 else {
            return .failure(Unavailable(reason: "\(game.format.rawValue) needs at least two sides"))
        }
        return .success(grouped.enumerated().map { index, ids in
            MatchSide(index: index, label: ids.map(\.rawValue).joined(separator: "+"), ids: ids,
                      seats: ids.compactMap(round.seat))
        })
    }
}

/// Shared helpers for formats.
enum FormatSupport {
    /// The strokes a game compares: net when `options.net`, else effective gross.
    /// Returns nil with a reason when a net game has a participant without a Level (B.4.4, B.8.14).
    static func strokeSource(_ game: GameInput, round: NormalisedRound) -> Result<(Int, Int) -> Int?, Unavailable> {
        guard game.options.isNet else {
            return .success { seat, hole in round.effective[seat][hole] }
        }
        let missing = game.players.filter { id in round.seat(id).map { round.handicapStrokes[$0] == nil } ?? true }
        guard missing.isEmpty else {
            return .failure(Unavailable(reason: "net \(game.format.rawValue) needs a Level for every player; missing: \(missing.map(\.rawValue).joined(separator: ", "))"))
        }
        return .success { seat, hole in round.net[seat][hole] }
    }

    /// Standings from per-player values, best first. Ties share a rank and keep seat order.
    static func standings(_ values: [(PlayerID, Int)], higherIsBetter: Bool, round: NormalisedRound,
                          label: (Int) -> String) -> [Standing] {
        let ordered = values.sorted { a, b in
            if a.1 != b.1 { return higherIsBetter ? a.1 > b.1 : a.1 < b.1 }
            return (round.seat(a.0) ?? 0) < (round.seat(b.0) ?? 0)
        }
        var rows: [Standing] = []
        for (i, (player, value)) in ordered.enumerated() {
            let rank = (i > 0 && ordered[i - 1].1 == value) ? rows[i - 1].rank : i + 1
            rows.append(Standing(player: player, value: Double(value), rank: rank, label: label(value)))
        }
        return rows
    }

    /// Unique best value → `.winner`; otherwise `.tied` in seat order.
    static func outcome(_ values: [(PlayerID, Int)], higherIsBetter: Bool, round: NormalisedRound) -> Outcome {
        guard let best = higherIsBetter ? values.map(\.1).max() : values.map(\.1).min() else { return .void }
        let leaders = values.filter { $0.1 == best }.map(\.0)
            .sorted { (round.seat($0) ?? 0) < (round.seat($1) ?? 0) }
        return leaders.count == 1 ? .winner(leaders[0]) : .tied(leaders)
    }
}
