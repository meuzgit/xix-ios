/// Callout resolution (B.6).
///
/// A callout resolves only when its status is `signed` (or already `resolved`) and every
/// participant has a score on the hole. `open` becomes `expired` as soon as any participant
/// scores the hole (B.8.11). `ducked` never resolves and records who ducked. Only targets can
/// hit a target; the caller never counts as one (B.8.10). Effective (gross) strokes are used.
enum CalloutResolver {
    static func resolve(_ callout: CalloutInput, round: NormalisedRound) -> CalloutResult {
        let targets = callout.targets.filter { $0 != callout.caller }
        var result = CalloutResult(calloutID: callout.id, kind: callout.kind, hole: callout.hole,
                                   status: callout.status, caller: callout.caller, targets: targets)

        switch callout.status {
        case .ducked:
            result.duckedBy = callout.responder
            return result
        case .expired:
            return result
        case .open, .signed, .resolved:
            break
        }

        guard callout.hole >= 1, callout.hole <= round.holes else {
            result.reason = "hole \(callout.hole) is not in this round"
            return result
        }
        let hole = callout.hole - 1
        let partner = callout.kind == .partner ? callout.params.partner.flatMap { $0 == callout.caller ? nil : $0 } : nil
        let participants = ([callout.caller] + targets + (partner.map { [$0] } ?? []))
            .reduce(into: [PlayerID]()) { if !$0.contains($1) { $0.append($1) } }
        let unknown = participants.filter { round.seat($0) == nil }
        guard unknown.isEmpty else {
            result.reason = "unknown player \(unknown.map(\.rawValue).joined(separator: ", "))"
            return result
        }
        func strokes(_ id: PlayerID) -> Int? { round.effective[round.seat(id)!][hole] }

        if callout.status == .open {
            if participants.contains(where: { strokes($0) != nil }) { result.status = .expired }
            return result
        }

        // Signed: wait until every participant has scored the hole.
        guard participants.allSatisfy({ strokes($0) != nil }) else {
            result.status = .signed
            return result
        }

        switch callout.kind {
        case .target:
            guard !targets.isEmpty else {
                result.reason = "target callout has no targets"
                return result
            }
            let goal: Int
            switch callout.params.goal ?? .par {
            case .strokes(let n): goal = n
            case .par:
                guard let par = round.par[hole] else { result.reason = "par unknown on hole \(callout.hole)"; return result }
                goal = par
            case .birdie:
                guard let par = round.par[hole] else { result.reason = "par unknown on hole \(callout.hole)"; return result }
                goal = par - 1
            }
            let hitters = targets.filter { strokes($0)! <= goal }
            result.status = .resolved
            result.hit = hitters
            result.winner = hitters.isEmpty ? .player(callout.caller)
                : (hitters.count == 1 ? .player(hitters[0]) : .players(hitters))

        case .duel:
            guard targets.count == 1 else {
                result.reason = "duel needs exactly one target"
                return result
            }
            let a = strokes(callout.caller)!, b = strokes(targets[0])!
            result.status = .resolved
            result.winner = a < b ? .player(callout.caller) : (b < a ? .player(targets[0]) : .halved)

        case .partner:
            let callerSide = [callout.caller] + (partner.map { [$0] } ?? [])
            let rest = targets.filter { !callerSide.contains($0) }
            guard !rest.isEmpty else {
                result.reason = "partner callout has nobody to play against"
                return result
            }
            let mine = callerSide.map { strokes($0)! }.min()!
            let theirs = rest.map { strokes($0)! }.min()!
            result.status = .resolved
            result.targets = rest
            if mine < theirs {
                result.winner = callerSide.count == 1 ? .player(callout.caller) : .players(callerSide)
                result.loneWolf = partner == nil
            } else if theirs < mine {
                result.winner = rest.count == 1 ? .player(rest[0]) : .players(rest)
                result.loneWolf = false
            } else {
                result.winner = .halved
                result.loneWolf = false
            }

        case .multiplier:
            // The factor is applied inside the referenced game; the callout itself has no winner.
            result.status = .resolved
        }
        return result
    }

    /// Players who received the callout: targets, plus the caller's partner is not a receiver.
    static func receivers(_ callout: CalloutInput) -> [PlayerID] {
        callout.targets.filter { $0 != callout.caller }
    }
}
