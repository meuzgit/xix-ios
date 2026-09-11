/// Flattens game results into the outcome records that medals and Rival Points consume.
/// Nassau contributes one record per segment; every other format one record.
struct OutcomeRecord {
    let gameID: GameID
    let format: Format
    let segment: String?                     // "front", "back", "18" for Nassau
    let outcome: Outcome
    let participants: [PlayerID]
    let sides: [[PlayerID]]?                 // two-sided games

    /// Opponents of `player`: the other side, or everyone else.
    func opponents(of player: PlayerID) -> [PlayerID] {
        if let sides, let mine = sides.firstIndex(where: { $0.contains(player) }) {
            return sides.enumerated().filter { $0.offset != mine }.flatMap(\.element)
        }
        return participants.filter { $0 != player }
    }

    /// The single opponent when the record has exactly two participants; nil otherwise.
    func soleOpponent(of player: PlayerID) -> PlayerID? {
        let others = participants.filter { $0 != player }
        return others.count == 1 ? others[0] : nil
    }

    var isTeamed: Bool { sides?.contains { $0.count > 1 } ?? false }

    /// Winners of this record: single winner, winning side, or every tied player. Halved → [].
    var winners: [PlayerID] {
        switch outcome {
        case .winner(let p): return [p]
        case .winningSide(_, let players): return players
        case .tied(let players): return players
        default: return []
        }
    }
}

enum OutcomeRecords {
    static func records(for result: GameResult, game: GameInput) -> [OutcomeRecord] {
        switch result.detail {
        case .nassau(let d):
            return d.segments.compactMap { seg in
                guard let outcome = seg.match.matchOutcome else { return nil }
                return OutcomeRecord(gameID: game.id, format: .nassau, segment: seg.name, outcome: outcome,
                                     participants: game.players, sides: seg.match.sides)
            }
        case .matchPlay(let d):
            guard let outcome = result.outcome else { return [] }
            return [OutcomeRecord(gameID: game.id, format: result.format, segment: nil, outcome: outcome,
                                  participants: game.players, sides: d.sides)]
        case .sideStroke(let d):
            guard let outcome = result.outcome else { return [] }
            return [OutcomeRecord(gameID: game.id, format: result.format, segment: nil, outcome: outcome,
                                  participants: game.players, sides: d.sides)]
        case .rabbit(let d):
            // Two awards: the holder after hole 9, and the holder after the final hole of an
            // 18-hole round (a 9-hole round has the hole-9 award only, B.8.12).
            var records: [OutcomeRecord] = []
            if let at9 = d.holderAt9 {
                records.append(OutcomeRecord(gameID: game.id, format: .rabbit, segment: "9", outcome: .winner(at9),
                                             participants: game.players, sides: nil))
            }
            if let outcome = result.outcome, d.holders.count > 9 {
                records.append(OutcomeRecord(gameID: game.id, format: .rabbit, segment: "18", outcome: outcome,
                                             participants: game.players, sides: nil))
            }
            return records
        case .vegas(let d):
            guard let outcome = result.outcome else { return [] }
            return [OutcomeRecord(gameID: game.id, format: result.format, segment: nil, outcome: outcome,
                                  participants: game.players, sides: d.sides)]
        default:
            guard let outcome = result.outcome else { return [] }
            return [OutcomeRecord(gameID: game.id, format: result.format, segment: nil, outcome: outcome,
                                  participants: game.players, sides: nil)]
        }
    }
}
