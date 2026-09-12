/// Shared two-side match logic for Match Play, Nassau and best-ball matches.
///
/// Per hole the lower side score (best ball of the members) wins the hole, equal
/// halves. The match ends early when the lead exceeds the holes remaining; standings
/// freeze there and `decidedAtHole` records it (B.5, B.8.6). A signed multiplier
/// callout makes a hole count `factor` holes up (B.6).
struct MatchSide {
    let index: Int
    let label: String
    let ids: [PlayerID]
    let seats: [Int]
}

enum MatchEngine {
    /// Two sides from `sides` (member → 0/1) or, without a map, from exactly two players.
    static func sides(for game: GameInput, round: NormalisedRound) -> Result<[MatchSide], Unavailable> {
        SideGrouping.sides(for: game, round: round, exactlyTwo: true)
    }

    /// Plays holes `range` (0-based, half-open) between two sides.
    static func play(game: GameInput, sides: [MatchSide], range: Range<Int>, strokes: (Int, Int) -> Int?,
                     round: NormalisedRound, context: ScoringContext) -> MatchPlayDetail {
        var won = [0, 0]
        var halved = 0
        var perHole: [MatchHole] = []
        var decidedAt: Int? = nil
        var lastPlayed = range.lowerBound   // count of holes played, as an absolute 1-based hole number

        let allSeats = sides.flatMap(\.seats)
        var abandonedBy: PlayerID? = nil
        for hole in range {
            // A side with no active member left has departed: the match is void unless already decided (B.8.2).
            if let gone = sides.first(where: { side in side.seats.allSatisfy { hole >= round.activeHoles[$0] } }) {
                let leaver = gone.seats.first { round.activeHoles[$0] < round.holes } ?? gone.seats[0]
                abandonedBy = round.players[leaver].id
                break
            }
            // Every active participant must have scored the hole (B.4.2).
            guard round.isResolved(hole: hole, seats: allSeats) else { break }
            let sideScores: [Int?] = sides.map { side in
                let scores = side.seats.compactMap { strokes($0, hole) }
                return scores.isEmpty ? nil : scores.min()
            }
            guard let s0 = sideScores[0], let s1 = sideScores[1] else { break }
            lastPlayed = hole + 1
            let worth = context.multiplier(for: game.id, hole: hole + 1)
            if s0 < s1 {
                won[0] += worth
                perHole.append(MatchHole(hole: hole + 1, winner: sides[0].label, worth: worth))
            } else if s1 < s0 {
                won[1] += worth
                perHole.append(MatchHole(hole: hole + 1, winner: sides[1].label, worth: worth))
            } else {
                halved += 1
                perHole.append(MatchHole(hole: hole + 1, winner: nil, worth: worth))
            }
            let remaining = range.upperBound - (hole + 1)
            if abs(won[0] - won[1]) > remaining, remaining > 0 {
                decidedAt = hole + 1
                break
            }
        }

        let lead = won[0] - won[1]
        let leader: MatchSide? = lead == 0 ? nil : (lead > 0 ? sides[0] : sides[1])
        let up = abs(lead)
        let remaining = (decidedAt != nil || abandonedBy != nil) ? 0 : range.upperBound - lastPlayed
        let complete = decidedAt != nil || abandonedBy != nil || lastPlayed == range.upperBound

        let result: String
        var outcome: Outcome? = nil
        if abandonedBy != nil {
            result = "void"
            outcome = .void
        } else if let leader {
            if let decidedAt {
                result = "\(leader.label) \(up)&\(range.upperBound - decidedAt)"
            } else {
                result = "\(leader.label) \(up) up"
            }
            if complete {
                outcome = leader.ids.count == 1 ? .winner(leader.ids[0]) : .winningSide(leader.index, players: leader.ids)
            }
        } else {
            result = complete ? "halved" : "all square"
            if complete { outcome = .halved }
        }

        var detail = MatchPlayDetail(
            sides: sides.map(\.ids),
            holesWon: Dictionary(uniqueKeysWithValues: sides.map { ($0.label, won[$0.index]) }),
            halved: halved,
            firstHole: range.lowerBound + 1,
            lastHole: range.upperBound,
            throughHole: lastPlayed,
            holesRemaining: remaining,
            leader: leader?.label,
            up: up,
            decidedAtHole: decidedAt,
            abandonedBy: abandonedBy,
            complete: complete,
            result: result,
            matchOutcome: outcome,
            perHole: perHole)
        detail.compact = Dictionary(uniqueKeysWithValues: sides.map { ($0.label, compactText(detail, forSide: $0.index)) })
        return detail
    }

    /// The standing alone from one side's view: "3 up", "3 dn", "AS", "2&1" won, "L 2&1" lost, "void", "—" to play.
    static func compactText(_ match: MatchPlayDetail, forSide side: Int) -> String {
        let mine = match.sides[side].map(\.rawValue).joined(separator: "+")
        if match.abandonedBy != nil { return "void" }
        guard match.throughHole > match.firstHole - 1 else { return "—" }
        guard let leader = match.leader else { return "AS" }
        let leading = leader == mine
        if let decided = match.decidedAtHole {
            let margin = "\(match.up)&\(match.lastHole - decided)"
            return leading ? margin : "L \(margin)"
        }
        return leading ? "\(match.up) up" : "\(match.up) dn"
    }

    /// Per-side wording for display lines. `segment` is "front", "back", "18" or nil for a lone match.
    /// Examples: "3 up front", "back halved", "won 18 5&4", "lost 5&4", "all square", "front to play".
    static func text(_ match: MatchPlayDetail, forSide side: Int, segment: String?) -> String {
        let seg = segment.map { " \($0)" } ?? ""
        let mine = match.sides[side].map(\.rawValue).joined(separator: "+")
        if match.abandonedBy != nil { return segment.map { "\($0) void" } ?? "void" }
        let started = match.throughHole > match.firstHole - 1
        guard started else { return segment.map { "\($0) to play" } ?? "to play" }
        guard let leader = match.leader else {
            return match.complete ? (segment.map { "\($0) halved" } ?? "halved")
                                  : (segment.map { "\($0) all square" } ?? "all square")
        }
        let leading = leader == mine
        if let decided = match.decidedAtHole {
            return "\(leading ? "won" : "lost")\(seg) \(match.up)&\(match.lastHole - decided)"
        }
        return "\(match.up) \(leading ? "up" : "down")\(seg)"
    }

    /// Standings rows for a match: the leading side ranks 1, the other 2; all square shares rank 1.
    static func standings(_ match: MatchPlayDetail, sides: [MatchSide]) -> [Standing] {
        sides.flatMap { side -> [Standing] in
            let leading = match.leader == side.label
            let signed = match.leader == nil ? 0 : (leading ? match.up : -match.up)
            let rank = match.leader == nil || leading ? 1 : 2
            return side.ids.map { Standing(player: $0, side: side.index, value: Double(signed), rank: rank,
                                           label: text(match, forSide: side.index, segment: nil)) }
        }
    }
}
