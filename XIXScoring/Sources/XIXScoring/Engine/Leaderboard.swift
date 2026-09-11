/// Leaderboard rows: sorted by value, ties share a rank and keep seat order.
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

    static func build(games: [GameResult], round: NormalisedRound) -> [LeaderboardMode: [LeaderboardRow]] {
        var board: [LeaderboardMode: [LeaderboardRow]] = [:]

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
