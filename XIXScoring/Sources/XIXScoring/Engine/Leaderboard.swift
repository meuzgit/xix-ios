/// Leaderboard rows. One ordering for every mode: sort by value (ascending for
/// gross, net and to-par; descending for everything else), tied values share a
/// rank number, and ties keep seat order.
enum LeaderboardBuilder {
    static func rows(_ values: [(PlayerID, Int)], higherIsBetter: Bool, round: NormalisedRound) -> [LeaderboardRow] {
        let ordered = values.sorted { a, b in
            if a.1 != b.1 { return higherIsBetter ? a.1 > b.1 : a.1 < b.1 }
            return (round.seat(a.0) ?? 0) < (round.seat(b.0) ?? 0)
        }
        var rows: [LeaderboardRow] = []
        for (i, (player, value)) in ordered.enumerated() {
            let rank = (i > 0 && ordered[i - 1].1 == value) ? rows[i - 1].rank : i + 1
            rows.append(LeaderboardRow(player: player, value: value, rank: rank))
        }
        return rows
    }

    static func build(perPlayer: [PlayerID: PlayerSummary], games: [GameResult], round: NormalisedRound) -> [LeaderboardMode: [LeaderboardRow]] {
        var board: [LeaderboardMode: [LeaderboardRow]] = [:]

        // Score boards: players who have entered at least one hole. Net and to-par only when every
        // such player has the value.
        let played = round.players.map(\.id).compactMap { id in perPlayer[id].map { (id, $0) } }
            .filter { $0.1.holesEntered > 0 }
        if !played.isEmpty {
            board[.gross] = rows(played.map { ($0.0, $0.1.gross) }, higherIsBetter: false, round: round)
            if played.allSatisfy({ $0.1.net != nil }) {
                board[.net] = rows(played.map { ($0.0, $0.1.net!) }, higherIsBetter: false, round: round)
            }
            if played.allSatisfy({ $0.1.toPar != nil }) {
                board[.toPar] = rows(played.map { ($0.0, $0.1.toPar!) }, higherIsBetter: false, round: round)
            }
        }

        // Skins: total skins across every available Skins game.
        var skins: [PlayerID: Int] = [:]
        var anySkins = false
        for game in games {
            if case .skins(let d) = game.detail {
                anySkins = true
                for (player, n) in d.totals { skins[player, default: 0] += n }
            }
        }
        if anySkins {
            board[.skins] = rows(skins.map { ($0.key, $0.value) }, higherIsBetter: true, round: round)
        }

        return board
    }
}
