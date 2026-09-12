// What the results screen shows (PRD 8.9, Pass 2 2e, Pass 6 6c): the headline score and games line,
// medals as patches, per-game outcomes, callouts with their marks, stickers received, highlights, Rival
// Points small. Built from the engine result and plain values so the app builds it from a session and
// the tests from a fixture. The app never says what a result means.
import Foundation
import XIXScoring

public struct ResultsModel: Equatable, Sendable {
    public struct Game: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String                   // "Skins"
        public var who: String                    // "Ray 2 · Tess 2 · carry 1" or "Ray takes the 18"
        public var tag: String                    // the viewer's standing, "2 SKINS", or ""
        public init(id: String, name: String, who: String, tag: String) { self.id = id; self.name = name; self.who = who; self.tag = tag }
    }
    public struct Callout: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String                  // "Beat par on 12"
        public var sub: String                    // "Ray → Dave"
        public var mark: String                   // "CALLED IT", "SIGNED · MISSED", "DUCKED", "EXPIRED"
        public init(id: String, title: String, sub: String, mark: String) { self.id = id; self.title = title; self.sub = sub; self.mark = mark }
    }
    public struct Highlight: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String                    // "BEST HOLE"
        public var value: String                  // "Birdie on 7"
        public init(key: String, value: String) { self.key = key; self.value = value }
    }
    /// The result-link confirm card for a guest scored by name (Pass 6 6c), or the confirmed state.
    public struct ConfirmCard: Equatable, Sendable {
        public var label: String
        public var title: String
        public var body: String
        public var button: String
        public var foot: String
        public var done: Bool
        public init(label: String, title: String, body: String, button: String, foot: String, done: Bool) {
            self.label = label; self.title = title; self.body = body; self.button = button; self.foot = foot; self.done = done
        }
        public static func pending(owner: String, medals: Int) -> ConfirmCard {
            ConfirmCard(label: "YOUR SCORES, KEPT BY \(owner.uppercased())", title: "Confirm my scores",
                        body: "\(owner) scored your row. Confirming makes your account in one step and keeps the round, medals included.",
                        button: "Confirm my scores", foot: "Nothing to fill in. No password, no email typing.", done: false)
        }
        public static func confirmed(medals: Int) -> ConfirmCard {
            let moved = medals == 0 ? "" : (medals == 1 ? " One medal moved into your cabinet." : " \(medals) medals moved into your cabinet.")
            return ConfirmCard(label: "CONFIRMED", title: "This round is yours now", body: "Your account is made and the round is attached to it.\(moved)",
                               button: "Done", foot: "Rankings count this round from now.", done: true)
        }
    }

    public var kicker: String                     // "FINAL · FRASERVIEW · 13 SEP"
    public var title: String                      // "Your results" / "Round results"
    public var headline: String                   // "84" — the viewer's gross, or the leader's
    public var headlineSub: String                // "+6 GROSS" / "2 SKINS · 21 PTS"
    public var gamesLine: String                  // "2 SKINS · 21 PTS" per viewer, or the games' names
    public var medals: [MedalPatchModel]
    public var games: [Game]
    public var callouts: [Callout]
    public var stickersReceived: [String]         // sticker keys, in order received
    public var highlights: [Highlight]
    public var rivalPoints: Int?
    public var confirm: ConfirmCard?
    public var pending: Bool                      // waiting on the server's result

    public init(kicker: String, title: String, headline: String, headlineSub: String, gamesLine: String, medals: [MedalPatchModel], games: [Game],
                callouts: [Callout], stickersReceived: [String], highlights: [Highlight], rivalPoints: Int?, confirm: ConfirmCard? = nil, pending: Bool = false) {
        self.kicker = kicker; self.title = title; self.headline = headline; self.headlineSub = headlineSub; self.gamesLine = gamesLine
        self.medals = medals; self.games = games; self.callouts = callouts; self.stickersReceived = stickersReceived
        self.highlights = highlights; self.rivalPoints = rivalPoints; self.confirm = confirm; self.pending = pending
    }

    // MARK: Building

    public struct CalloutInput: Equatable, Sendable {
        public var id: UUID; public var hole: Int; public var kind: String; public var callerID: UUID; public var targetIDs: [UUID]; public var goal: String?
        /// The game a Double doubled, when the round still has it.
        public var gameName: String?
        public init(id: UUID, hole: Int, kind: String, callerID: UUID, targetIDs: [UUID], goal: String?, gameName: String? = nil) {
            self.id = id; self.hole = hole; self.kind = kind; self.callerID = callerID; self.targetIDs = targetIDs; self.goal = goal
            self.gameName = gameName
        }
    }

    public static func build(courseName: String, dateLabel: String, par: [Int?], players: [ScorecardModel.Player], engineID: (UUID) -> PlayerID,
                             result: RoundResult?, callouts: [CalloutInput], stickers: [HoleCardModel.StickerInputModel],
                             myPlayerID: UUID?, confirm: ConfirmCard? = nil) -> ResultsModel {
        let kicker = "FINAL · \(courseName) · \(dateLabel)".uppercased()
        let nameOf = Dictionary(uniqueKeysWithValues: players.map { (engineID($0.id), $0.name) })
        let me = myPlayerID.map(engineID)
        let title = me == nil ? "Round results" : "Your results"
        guard let result else {
            return ResultsModel(kicker: kicker, title: title, headline: "—", headlineSub: "WORKING IT OUT", gamesLine: "", medals: [], games: [],
                                callouts: [], stickersReceived: [], highlights: [], rivalPoints: nil, confirm: confirm, pending: true)
        }

        // Headline: the viewer's gross, else the low gross on the card.
        let focus: PlayerID? = me ?? result.leaderboard[.gross]?.first?.player
        let summary = focus.flatMap { result.perPlayer[$0] }
        let headline = summary.map { "\($0.gross)" } ?? "—"
        var subParts: [String] = []
        if let toPar = summary?.toPar { subParts.append("\(GridScreenModel.toParText(toPar)) GROSS") } else { subParts.append("GROSS") }
        let games = result.games
        let gamesLine = focus.map { f in games.compactMap { g -> String? in
            guard let c = g.compact[f] else { return nil }
            return "\(HoleCardModel.gameName(g.format)) \(c)".uppercased()
        }.joined(separator: " · ") } ?? ""

        // Medals: the viewer's first, then everyone else's with their name in the context line.
        var medals: [MedalPatchModel] = []
        let ordered = result.medals.sorted { a, b in (a.profile == focus ? 0 : 1, a.key.rawValue) < (b.profile == focus ? 0 : 1, b.key.rawValue) }
        for m in ordered {
            let p = m.key.patch
            var ctx: [String] = []
            if m.profile != focus { ctx.append(nameOf[m.profile] ?? "?") }
            if let o = m.opponent { ctx.append("vs \(nameOf[o] ?? "?")") }
            if let holes = m.holes, !holes.isEmpty { ctx.append("Hole" + (holes.count > 1 ? "s " : " ") + holes.map(String.init).joined(separator: ", ")) }
            ctx.append(courseName)
            medals.append(MedalPatchModel(id: "\(m.profile.rawValue)#\(m.key.rawValue)", shape: p.shape, accent: m.key.accent, top: p.top, bottom: p.bottom,
                                          name: p.name, context: ctx.joined(separator: " · ")))
        }

        // Games: one line each, naming the outcome the way the engine states it.
        let gameRows: [Game] = games.map { g in
            let name = HoleCardModel.gameName(g.format)
            let who: String
            switch g.outcome {
            case .winner(let p)?: who = "\(nameOf[p] ?? "?") takes it"
            case .winningSide(_, let ps)?: who = "\(ps.compactMap { nameOf[$0] }.joined(separator: " & ")) take it"
            case .tied(let ps)?: who = "Tied · \(ps.compactMap { nameOf[$0] }.joined(separator: ", "))"
            case .halved?: who = "Halved"
            case .void?: who = "Void"
            case .abandoned(let p)?: who = "Abandoned by \(nameOf[p] ?? "?")"
            case .unavailable(let reason)?: who = reason
            case nil: who = g.standings.prefix(4).map { "\(nameOf[$0.player] ?? "?") \($0.label)" }.joined(separator: " · ")
            }
            let tag = focus.flatMap { g.compact[$0] }?.uppercased() ?? ""
            return Game(id: g.gameID.rawValue, name: name, who: who, tag: tag)
        }

        // Callouts: what was called, who, and the mark per the engine's result.
        let calloutRows: [Callout] = result.callouts.map { c in
            let input = callouts.first { $0.id.uuidString.lowercased() == c.calloutID.rawValue.lowercased() }
            let title: String
            switch c.kind {
            case .target:
                let goal = input?.goal
                title = goal == "birdie" ? "Birdie on \(c.hole)" : (Int(goal ?? "").map { "Under \($0) on \(c.hole)" } ?? "Beat par on \(c.hole)")
            case .duel: title = "Duel on \(c.hole)"
            case .partner: title = "Partner pick on \(c.hole)"
            case .multiplier:
                let game = input?.gameName.map { " · \($0)" } ?? ""
                title = "Double on \(c.hole)\(game)"
            }
            let sub = "\(nameOf[c.caller] ?? "?") → \(c.targets.compactMap { nameOf[$0] }.joined(separator: ", "))"
            var mark: String
            switch c.status {
            case .ducked: mark = "DUCKED"
            case .expired: mark = c.reason?.uppercased() ?? "EXPIRED"
            case .open, .live: mark = "OPEN"
            case .resolved:
                switch c.kind {
                case .multiplier:
                    // A double that every target signed simply counted twice; there is no winner to name.
                    mark = "DOUBLED"
                case .target:
                    if let hit = c.hit, !hit.isEmpty {
                        mark = hit.count == c.targets.count ? "THEY MADE IT" : "\(hit.compactMap { nameOf[$0] }.joined(separator: " & ")) MADE IT".uppercased()
                    } else if case .player(let w)? = c.winner, w == c.caller {
                        mark = "CALLED IT"
                    } else {
                        mark = "MISSED IT"
                    }
                case .duel, .partner:
                    if case .player(let w)? = c.winner { mark = w == c.caller ? "CALLED IT" : "\(nameOf[w] ?? "?") TOOK IT".uppercased() }
                    else if case .players(let ws)? = c.winner {
                        let names = ws.compactMap { nameOf[$0] }.joined(separator: " & ")
                        mark = ws.contains(c.caller) ? "CALLED IT · WITH \(names)".uppercased() : "\(names) TOOK IT".uppercased()
                    }
                    else if case .halved? = c.winner { mark = "HALVED" }
                    else if let reason = c.reason { mark = reason.uppercased() }
                    else { mark = "NO RESULT" }
                }
                if c.loneWolf == true { mark += " · LONE WOLF" }
            }
            if !c.ducked.isEmpty && c.status == .resolved { mark += " · \(c.ducked.compactMap { nameOf[$0] }.joined(separator: ", ")) DUCKED".uppercased() }
            return Callout(id: c.calloutID.rawValue, title: title, sub: sub, mark: mark)
        }

        // Stickers the viewer received, oldest first.
        let received = myPlayerID.map { me in stickers.filter { $0.targetPlayerID == me }.sorted { $0.createdAt < $1.createdAt }.map(\.key) } ?? []

        // Highlights from the viewer's own row: best hole, pars, the one that got away, streak.
        var highlights: [Highlight] = []
        if let s = summary {
            let toPar = s.holeToPar
            if let bestIdx = toPar.indices.filter({ toPar[$0] != nil }).min(by: { toPar[$0]! < toPar[$1]! }), let v = toPar[bestIdx], v < 0 {
                highlights.append(Highlight(key: "BEST HOLE", value: "\(v == -1 ? "Birdie" : (v == -2 ? "Eagle" : "\(v)")) on \(bestIdx + 1)"))
            }
            let pars = toPar.filter { $0 == 0 }.count
            if pars > 0 { highlights.append(Highlight(key: "PARS", value: "\(pars)")) }
            if let worstIdx = toPar.indices.filter({ toPar[$0] != nil }).max(by: { toPar[$0]! < toPar[$1]! }), let v = toPar[worstIdx], v >= 2,
               let strokes = s.effectiveStrokes[safe: worstIdx] ?? nil {
                highlights.append(Highlight(key: "GOT AWAY", value: "\(strokes) on \(worstIdx + 1)"))
            }
            var best = 0, run = 0
            for v in toPar { if let v, v <= 0 { run += 1; best = max(best, run) } else { run = 0 } }
            if best >= 3 { highlights.append(Highlight(key: "STREAK", value: "\(best) at par or better")) }
            if s.pickedUp > 0 { highlights.append(Highlight(key: "PICKED UP", value: "\(s.pickedUp)")) }
        }

        let rp = focus.flatMap { result.rivalPoints[$0] }
        // `pending` means the result has not landed, not that the card has gaps: a round ended with
        // holes left open still has a final result, and the screen must not wait for one for ever.
        return ResultsModel(kicker: kicker, title: title, headline: headline, headlineSub: subParts.joined(separator: " · "),
                            gamesLine: gamesLine, medals: medals, games: gameRows, callouts: calloutRows, stickersReceived: received,
                            highlights: highlights, rivalPoints: rp, confirm: confirm, pending: false)
    }
}
