/// Stableford (B.5). Per hole, strokes (gross or net) vs par → points from a table;
/// picked up → 0 regardless of table (B.4.1). Highest total wins. Unavailable when
/// any played hole has nil par. A signed multiplier callout scales that hole's points (B.6).
///
/// The table is pluggable: `Options.table` picks `standard` (default) or `modified`.
/// `parOffset` lets Bogey Golf reuse the scorer with par redefined as par + 1.
struct StablefordTable: Sendable {
    let name: String
    let points: @Sendable (_ strokesToPar: Int) -> Int

    /// {≤−2: 4, −1: 3, 0: 2, +1: 1, ≥+2: 0}
    static let standard = StablefordTable(name: "standard") { diff in
        switch diff {
        case ...(-2): return 4
        case -1: return 3
        case 0: return 2
        case 1: return 1
        default: return 0
        }
    }

    /// {≤−3: 8, −2: 5, −1: 2, 0: 0, +1: −1, ≥+2: −3}. Not in the V1 UI.
    static let modified = StablefordTable(name: "modified") { diff in
        switch diff {
        case ...(-3): return 8
        case -2: return 5
        case -1: return 2
        case 0: return 0
        case 1: return -1
        default: return -3
        }
    }

    static func named(_ option: Options.StablefordTable?) -> StablefordTable {
        switch option ?? .standard {
        case .standard: return .standard
        case .modified: return .modified
        }
    }
}

enum StablefordScorer: FormatScorer {
    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext) -> ScoredGame {
        score(game, round: round, context: context, format: .stableford, parOffset: 0, prefix: "Stableford")
    }

    static func score(_ game: GameInput, round: NormalisedRound, context: ScoringContext,
                      format: Format, parOffset: Int, prefix: String) -> ScoredGame {
        let seats = game.players.compactMap(round.seat)
        let through = round.throughHole(seats: seats)
        let strokes: (Int, Int) -> Int?
        switch FormatSupport.strokeSource(game, round: round) {
        case .failure(let u): return ScoredGame(result: .unavailable(game, reason: u.reason, throughHole: through))
        case .success(let s): strokes = s
        }
        let missingPar = (0..<through).filter { round.par[$0] == nil }
        guard missingPar.isEmpty else {
            let holes = missingPar.map { String($0 + 1) }.joined(separator: ", ")
            return ScoredGame(result: .unavailable(game, reason: "\(prefix) needs par on every played hole; missing on \(holes)", throughHole: through))
        }

        let table = StablefordTable.named(game.options.table)
        var points: [PlayerID: [Int]] = [:]
        var totals: [PlayerID: Int] = [:]
        for seat in seats {
            let id = round.players[seat].id
            var row: [Int] = []
            for hole in 0..<through {
                let factor = context.multiplier(for: game.id, hole: hole + 1)
                let p: Int
                if round.pickedUp[seat][hole] {
                    p = 0
                } else if let s = strokes(seat, hole), let par = round.par[hole] {
                    p = table.points(s - (par + parOffset)) * factor
                } else {
                    p = 0
                }
                row.append(p)
            }
            points[id] = row
            totals[id] = row.reduce(0, +)
        }

        let complete = through == round.holes && round.holes > 0
        let values = game.players.map { ($0, totals[$0] ?? 0) }
        let standings = FormatSupport.standings(values, higherIsBetter: true, round: round) { "\($0) pts" }
        let display = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "\(prefix) \($0.1)") })
        let outcome: Outcome? = complete ? FormatSupport.outcome(values, higherIsBetter: true, round: round) : nil
        let compact = GameDisplay(uniqueKeysWithValues: values.map { ($0.0, "\($0.1)") })
        let result = GameResult(gameID: game.id, format: format, throughHole: through, standings: standings,
                                outcome: outcome, display: display, compact: compact,
                                detail: .stableford(StablefordDetail(points: points, totals: totals, table: table.name)))
        return ScoredGame(result: result)
    }
}
