/// Callout resolution (B.6, Build Doc 1 v1.1).
///
/// Responses are per target. A callout resolves among the targets who signed, once the
/// caller and those targets have scores on the hole. Ducked targets are recorded with no
/// result. Targets with no response when any participant (caller or target) scores the hole
/// are expired for that callout (B.8.11). If nobody signed there is no result: `expired`, or
/// `ducked` when every target ducked. The caller is never a target (B.8.10). Effective
/// (gross) strokes are used.
enum CalloutResolver {
    static func resolve(_ callout: CalloutInput, round: NormalisedRound) -> CalloutResult {
        let targets = callout.effectiveTargets
        let signed = targets.filter { callout.responses[$0] == .signed }
        let ducked = targets.filter { callout.responses[$0] == .ducked }
        let unanswered = targets.filter { callout.responses[$0] == nil }
        let partner = callout.kind == .partner ? callout.params.partner.flatMap { $0 == callout.caller ? nil : $0 } : nil

        func make(_ status: CalloutStatus, expired: [PlayerID], reason: String? = nil) -> CalloutResult {
            let perTarget = targets.map { t -> CalloutTargetResult in
                switch callout.responses[t] {
                case .signed?: return CalloutTargetResult(player: t, response: .signed)
                case .ducked?: return CalloutTargetResult(player: t, response: .ducked)
                case nil: return CalloutTargetResult(player: t, response: expired.contains(t) ? .expired : .pending)
                }
            }
            return CalloutResult(calloutID: callout.id, kind: callout.kind, hole: callout.hole, status: status,
                                 caller: callout.caller, targets: targets, perTarget: perTarget, ducked: ducked,
                                 expired: expired, reason: reason)
        }

        guard callout.hole >= 1, callout.hole <= round.holes else {
            return make(.expired, expired: unanswered, reason: "hole \(callout.hole) is not in this round")
        }
        let hole = callout.hole - 1
        let known = ([callout.caller] + targets + (partner.map { [$0] } ?? [])).filter { round.seat($0) == nil }
        guard known.isEmpty else {
            return make(.expired, expired: unanswered, reason: "unknown player \(known.map(\.rawValue).joined(separator: ", "))")
        }
        func strokes(_ id: PlayerID) -> Int? { round.effective[round.seat(id)!][hole] }

        // A participant's score closes the hole to responses: unanswered targets expire.
        let landed = ([callout.caller] + targets).contains { strokes($0) != nil }
        let expired = landed ? unanswered : []

        guard !signed.isEmpty else {
            if !targets.isEmpty, ducked.count == targets.count { return make(.ducked, expired: []) }
            return make(landed ? .expired : .open, expired: expired,
                        reason: targets.isEmpty ? "callout has no targets" : nil)
        }

        // Signed: wait until the caller (and partner) and every signed target have scored.
        let mustScore = [callout.caller] + signed + (partner.map { [$0] } ?? [])
        guard mustScore.allSatisfy({ strokes($0) != nil }) else { return make(.live, expired: expired) }

        var result = make(.resolved, expired: expired)
        switch callout.kind {
        case .target:
            let goal: Int
            switch callout.params.goal ?? .par {
            case .strokes(let n): goal = n
            case .par:
                guard let par = round.par[hole] else { return make(.live, expired: expired, reason: "par unknown on hole \(callout.hole)") }
                goal = par
            case .birdie:
                guard let par = round.par[hole] else { return make(.live, expired: expired, reason: "par unknown on hole \(callout.hole)") }
                goal = par - 1
            }
            let hitters = signed.filter { strokes($0)! <= goal }
            result.hit = hitters
            for i in result.perTarget.indices where result.perTarget[i].response == .signed {
                result.perTarget[i].hit = hitters.contains(result.perTarget[i].player)
            }
            result.winner = hitters.isEmpty ? .player(callout.caller)
                : (hitters.count == 1 ? .player(hitters[0]) : .players(hitters))

        case .duel:
            guard targets.count == 1 else { return make(.live, expired: expired, reason: "duel needs exactly one target") }
            let a = strokes(callout.caller)!, b = strokes(signed[0])!
            result.winner = a < b ? .player(callout.caller) : (b < a ? .player(signed[0]) : .halved)

        case .partner:
            let callerSide = [callout.caller] + (partner.map { [$0] } ?? [])
            let rest = signed.filter { !callerSide.contains($0) }
            guard !rest.isEmpty else { return make(.expired, expired: expired, reason: "partner callout has nobody to play against") }
            let mine = callerSide.map { strokes($0)! }.min()!
            let theirs = rest.map { strokes($0)! }.min()!
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
            // The factor is applied inside the referenced game only when every target signed.
            guard signed.count == targets.count else {
                return make(.expired, expired: expired, reason: "multiplier needs every target to sign")
            }
        }
        return result
    }

    /// Players who received the callout as a target (the caller never does).
    static func receivers(_ callout: CalloutInput) -> [PlayerID] { callout.effectiveTargets }

    /// A multiplier callout takes effect only when every target signed.
    static func isEffectiveMultiplier(_ callout: CalloutInput) -> Bool {
        let targets = callout.effectiveTargets
        return callout.kind == .multiplier && !targets.isEmpty && targets.allSatisfy { callout.responses[$0] == .signed }
    }
}
