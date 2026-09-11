/// Medals (B.7), derived only from activated games and resolved callouts on a complete
/// round. Idempotent by (profile, key): a key is awarded to a player at most once per round.
/// Order: games in input order, then callouts, then personal bests.
enum MedalBuilder {
    static func build(games: [(GameInput, GameResult)], callouts: [(CalloutInput, CalloutResult)],
                      round: NormalisedRound) -> [MedalAward] {
        var awards: [MedalAward] = []

        for (game, result) in games {
            switch result.detail {
            case .nassau(let d):
                let keys: [String: MedalKey] = ["front": .nassauFront, "back": .nassauBack, "18": .nassau18]
                for record in OutcomeRecords.records(for: result, game: game) {
                    guard let key = record.segment.flatMap({ keys[$0] }) else { continue }
                    award(&awards, key: key, to: winnersExcludingTies(record), record: record)
                }
                _ = d
            case .matchPlay:
                for record in OutcomeRecords.records(for: result, game: game) {
                    award(&awards, key: .matchplayWin, to: winnersExcludingTies(record), record: record)
                }
            case .skins(let d):
                for standing in result.standings {
                    let n = d.totals[standing.player] ?? 0
                    if n >= 2 { awards.append(MedalAward(profile: standing.player, key: .skinsTwo)) }
                    if n >= 4 { awards.append(MedalAward(profile: standing.player, key: .skinsFour)) }
                }
            case .stableford:
                for record in OutcomeRecords.records(for: result, game: game) {
                    award(&awards, key: .stablefordTop, to: record.winners, record: record)
                }
            case .none:
                break
            }
        }

        for (_, callout) in callouts where callout.status == .resolved {
            switch callout.kind {
            case .target:
                if case .player(let w)? = callout.winner, w == callout.caller {
                    awards.append(MedalAward(profile: w, key: .calloutCalledIt,
                                             opponent: callout.targets.count == 1 ? callout.targets[0] : nil,
                                             holes: [callout.hole]))
                }
            case .duel:
                if case .player(let w)? = callout.winner {
                    let opponent = w == callout.caller ? callout.targets.first : callout.caller
                    awards.append(MedalAward(profile: w, key: .calloutDuel, opponent: opponent, holes: [callout.hole]))
                }
            case .partner:
                if callout.loneWolf == true {
                    awards.append(MedalAward(profile: callout.caller, key: .calloutLoneWolf, holes: [callout.hole]))
                }
            case .multiplier:
                break
            }
        }

        // Signed every callout received, at least two.
        for player in round.players.map(\.id) {
            let received = callouts.filter { CalloutResolver.receivers($0.0).contains(player) }
            guard received.count >= 2 else { continue }
            if received.allSatisfy({ $0.1.status == .signed || $0.1.status == .resolved }) {
                awards.append(MedalAward(profile: player, key: .calloutDuckedNothing))
            }
        }

        for (seat, player) in round.players.enumerated() {
            if let best = player.extras?.personalBest, round.summary(seat: seat).gross < best {
                awards.append(MedalAward(profile: player.id, key: .personalBest))
            }
        }

        var seen = Set<String>()
        return awards.filter { seen.insert("\($0.profile.rawValue)|\($0.key.rawValue)").inserted }
    }

    /// Single winners and winning sides; ties and halves earn no match-style medal.
    private static func winnersExcludingTies(_ record: OutcomeRecord) -> [PlayerID] {
        switch record.outcome {
        case .winner, .winningSide: return record.winners
        default: return []
        }
    }

    private static func award(_ awards: inout [MedalAward], key: MedalKey, to players: [PlayerID], record: OutcomeRecord) {
        for p in players {
            awards.append(MedalAward(profile: p, key: key, opponent: record.soleOpponent(of: p)))
        }
    }
}
