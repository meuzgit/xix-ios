/// Rival Points (B.7), awarded only on a complete round.
///
/// For each game outcome, winners receive `base(format) × opponentFactor`; base is 10 for
/// individual formats, 6 for team formats, 4 for casual-first formats and 3 for callouts.
/// `opponentFactor = 1 + 0.1 × max(0, strongestOpponentLevel − ownLevel)`. Halved outcomes
/// (and explicit ties) give half to each side. Ducked callouts give nothing. Totals are
/// accumulated as fractions and rounded once per player.
enum RivalPointsBuilder {
    static func base(for format: Format, teamed: Bool) -> Double {
        switch format {
        case .fewestBlowUps, .beatYourAverage, .bogeyGolf, .mostPars, .firstToFive, .worstHole:
            return 4
        case .bestBall, .scramble, .shamble, .alternateShot, .chapman, .vegas, .sixes:
            return 6
        case .matchPlay, .nassau:
            return teamed ? 6 : 10
        case .strokePlay, .stableford, .skins, .nines, .quota, .rabbit, .defender:
            return 10
        }
    }

    static let calloutBase: Double = 3

    static func factor(for player: PlayerID, opponents: [PlayerID], round: NormalisedRound) -> Double {
        guard let seat = round.seat(player), let own = round.players[seat].level else { return 1 }
        let strongest = opponents.compactMap { round.seat($0) }.compactMap { round.players[$0].level }.max()
        guard let strongest else { return 1 }
        return 1 + 0.1 * max(0, strongest - own)
    }

    static func build(records: [OutcomeRecord], callouts: [CalloutResult], round: NormalisedRound) -> [PlayerID: Int] {
        var totals: [PlayerID: Double] = Dictionary(uniqueKeysWithValues: round.players.map { ($0.id, 0) })

        for record in records {
            let base = base(for: record.format, teamed: record.isTeamed)
            switch record.outcome {
            case .winner, .winningSide:
                for p in record.winners {
                    totals[p, default: 0] += base * factor(for: p, opponents: record.opponents(of: p), round: round)
                }
            case .tied(let players):
                for p in players {
                    totals[p, default: 0] += base / 2 * factor(for: p, opponents: record.opponents(of: p), round: round)
                }
            case .halved:
                for p in record.participants {
                    totals[p, default: 0] += base / 2 * factor(for: p, opponents: record.opponents(of: p), round: round)
                }
            case .void, .abandoned, .unavailable:
                break
            }
        }

        for callout in callouts where callout.status == .resolved && callout.kind != .multiplier {
            let callerSide: [PlayerID]
            let otherSide: [PlayerID]
            switch callout.winner {
            case .halved?:
                // Duel or partner halved: half each way.
                (callerSide, otherSide) = sides(of: callout)
                for p in callerSide {
                    totals[p, default: 0] += calloutBase / 2 * factor(for: p, opponents: otherSide, round: round)
                }
                for p in otherSide {
                    totals[p, default: 0] += calloutBase / 2 * factor(for: p, opponents: callerSide, round: round)
                }
            case .player?, .players?:
                (callerSide, otherSide) = sides(of: callout)
                let winners = callout.winner!.players
                let losers = winners.contains(callout.caller) ? otherSide : callerSide
                for p in winners {
                    totals[p, default: 0] += calloutBase * factor(for: p, opponents: losers, round: round)
                }
            case nil:
                break
            }
        }

        return totals.mapValues { Int($0.rounded()) }
    }

    /// Caller's side (caller plus any partner who shares the win) and the receiving side.
    private static func sides(of callout: CalloutResult) -> ([PlayerID], [PlayerID]) {
        let winners = callout.winner?.players ?? []
        let callerSide = winners.contains(callout.caller) ? winners : [callout.caller]
        let other = callout.targets.filter { !callerSide.contains($0) }
        return (callerSide, other)
    }
}
