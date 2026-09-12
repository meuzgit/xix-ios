// What the hole card shows for one hole (Build Doc 2 D.4), built from plain values and the engine
// result so the app builds it from RoundSession state and the tests from a fixture.
import Foundation
import XIXScoring

public struct HoleCardModel: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var initials: String
        public var standing: String                  // "Skins 2 · Nassau 2&1 · AS · 5&4"
        public var score: String                     // "", "4", "X"
        public var mark: ScorecardModel.Mark
        public var canEdit: Bool
        public var isMe: Bool
        public var stickers: [Sticker]
        public init(id: UUID, name: String, initials: String, standing: String, score: String, mark: ScorecardModel.Mark, canEdit: Bool, isMe: Bool, stickers: [Sticker]) {
            self.id = id; self.name = name; self.initials = initials; self.standing = standing; self.score = score; self.mark = mark
            self.canEdit = canEdit; self.isMe = isMe; self.stickers = stickers
        }
    }

    public struct Sticker: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var key: String
        public var senderInitials: String
        public init(id: UUID, key: String, senderInitials: String) { self.id = id; self.key = key; self.senderInitials = senderInitials }
    }

    public enum TargetState: String, Equatable, Sendable { case pending, signed, ducked }

    public struct CalloutTarget: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var initials: String
        public var state: TargetState
        public init(id: UUID, initials: String, state: TargetState) { self.id = id; self.initials = initials; self.state = state }
    }

    public struct Callout: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var detail: String                    // "BEAT PAR ON 12 · RAY → DAVE · EXPIRES ON SCORE"
        public var callerInitials: String
        public var targets: [CalloutTarget]
        public var canRespond: Bool                  // I am a target with no response and the hole is open
        public init(id: UUID, detail: String, callerInitials: String, targets: [CalloutTarget], canRespond: Bool) {
            self.id = id; self.detail = detail; self.callerInitials = callerInitials; self.targets = targets; self.canRespond = canRespond
        }
    }

    public struct StripItem: Equatable, Sendable, Identifiable {
        public var id: Int { hole }
        public var hole: Int
        public var filled: Int
        public var total: Int
        public init(hole: Int, filled: Int, total: Int) { self.hole = hole; self.filled = filled; self.total = total }
    }

    public struct Pad: Equatable, Sendable {
        public var playerID: UUID
        public var playerName: String
        public var entered: Int?
        public var pickedUp: Bool
        public init(playerID: UUID, playerName: String, entered: Int? = nil, pickedUp: Bool = false) {
            self.playerID = playerID; self.playerName = playerName; self.entered = entered; self.pickedUp = pickedUp
        }
    }

    public enum Panel: Equatable, Sendable { case none, pad(Pad), tray(targetPlayerID: UUID, context: StickerContext) }

    public var hole: Int
    public var holes: Int
    public var par: Int?
    public var strokeIndex: Int?
    public var yards: Int?
    public var inPlay: String                        // "Skins · carry 1 · Nassau back nine"
    public var rows: [Row]
    public var callout: Callout?
    public var events: [String]                      // ink lines for this hole
    public var nudge: String?                        // "Dave made 7. React?"
    public var strip: [StripItem]
    public var panel: Panel
    public var notice: String?

    public init(hole: Int, holes: Int, par: Int?, strokeIndex: Int?, yards: Int?, inPlay: String, rows: [Row], callout: Callout?,
                events: [String], nudge: String?, strip: [StripItem], panel: Panel = .none, notice: String? = nil) {
        self.hole = hole; self.holes = holes; self.par = par; self.strokeIndex = strokeIndex; self.yards = yards; self.inPlay = inPlay
        self.rows = rows; self.callout = callout; self.events = events; self.nudge = nudge; self.strip = strip; self.panel = panel; self.notice = notice
    }

    public var isComplete: Bool { rows.allSatisfy { !$0.score.isEmpty } }

    // MARK: Building

    public struct CalloutInputModel: Equatable, Sendable {
        public var id: UUID; public var hole: Int; public var kind: String; public var callerID: UUID; public var targetIDs: [UUID]
        public var goal: String?; public var responses: [UUID: String]; public var closed: Bool
        public init(id: UUID, hole: Int, kind: String, callerID: UUID, targetIDs: [UUID], goal: String?, responses: [UUID: String], closed: Bool) {
            self.id = id; self.hole = hole; self.kind = kind; self.callerID = callerID; self.targetIDs = targetIDs; self.goal = goal; self.responses = responses; self.closed = closed
        }
    }

    public struct StickerInputModel: Equatable, Sendable {
        public var id: UUID; public var targetPlayerID: UUID; public var senderPlayerID: UUID; public var hole: Int; public var key: String; public var createdAt: Double
        public init(id: UUID, targetPlayerID: UUID, senderPlayerID: UUID, hole: Int, key: String, createdAt: Double) {
            self.id = id; self.targetPlayerID = targetPlayerID; self.senderPlayerID = senderPlayerID; self.hole = hole; self.key = key; self.createdAt = createdAt
        }
    }

    public static func build(hole: Int, holes: Int, par: [Int?], strokeIndex: [Int?], yards: [Int?],
                             players: [ScorecardModel.Player], engineID: (UUID) -> PlayerID,
                             scores: [GridScreenModel.ScoreInput], stickers: [StickerInputModel], callouts: [CalloutInputModel],
                             result: RoundResult?, myPlayerID: UUID?, isOwner: Bool, panel: Panel = .none, nudge: String? = nil) -> HoleCardModel {
        let h = hole - 1
        let initialsOf = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.initials) })
        let nameOf = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.name) })

        // Rows
        let rows: [Row] = players.map { p in
            let key = engineID(p.id)
            let s = scores.first { $0.playerID == p.id && $0.hole == hole }
            let score = s.map { $0.pickedUp ? "X" : ($0.strokes.map(String.init) ?? "") } ?? ""
            let mark = result?.perPlayer[key].flatMap { $0.marks[safe: h] }.flatMap { ScorecardModel.Mark(rawValue: $0.rawValue) } ?? .none
            let standing = (result?.games ?? []).compactMap { g -> String? in
                guard let c = g.compact[key] else { return nil }
                return "\(gameName(g.format)) \(c)"
            }.joined(separator: " · ")
            let pins = stickers.filter { $0.targetPlayerID == p.id && $0.hole == hole }.sorted { $0.createdAt < $1.createdAt }
                .map { Sticker(id: $0.id, key: $0.key, senderInitials: initialsOf[$0.senderPlayerID] ?? "?") }
            return Row(id: p.id, name: p.name, initials: p.initials, standing: standing, score: score, mark: mark,
                       canEdit: isOwner || p.id == myPlayerID, isMe: p.id == myPlayerID, stickers: pins)
        }

        // In-play strip from the games that include this hole.
        var inPlay: [String] = []
        for g in result?.games ?? [] {
            switch g.detail {
            case .skins(let d):
                let carry = h > 0 && d.perHole.count >= h ? d.perHole[h - 1].carryAfter : (d.perHole.count < h ? d.carry : 0)
                inPlay.append(carry > 0 ? "Skins · carry \(carry)" : "Skins")
            case .nassau:
                inPlay.append(hole <= 9 ? "Nassau front nine" : "Nassau back nine")
            default:
                if case .unavailable? = g.outcome { continue }
                inPlay.append(gameName(g.format))
            }
        }

        // Callout on this hole: the newest open one, or the newest of any state if none is open.
        var banner: Callout? = nil
        let onHole = callouts.filter { $0.hole == hole }
        if let c = onHole.first(where: { !$0.closed }) ?? onHole.last {
            let targets = c.targetIDs.filter { $0 != c.callerID }.map { t -> CalloutTarget in
                let state: TargetState = c.responses[t] == "signed" ? .signed : (c.responses[t] == "ducked" ? .ducked : .pending)
                return CalloutTarget(id: t, initials: initialsOf[t] ?? "?", state: state)
            }
            let what: String
            switch c.kind {
            case "target": what = c.goal == "birdie" ? "BIRDIE ON \(hole)" : (Int(c.goal ?? "").map { "UNDER \($0) ON \(hole)" } ?? "BEAT PAR ON \(hole)")
            case "duel": what = "DUEL ON \(hole)"
            case "partner": what = "PARTNER PICK ON \(hole)"
            case "multiplier": what = "DOUBLE ON \(hole)"
            default: what = c.kind.uppercased()
            }
            let who = "\(nameOf[c.callerID] ?? "?") → \(targets.map { nameOf[$0.id] ?? "?" }.joined(separator: ", "))"
            let tail = c.closed ? "CLOSED" : "EXPIRES ON SCORE"
            let mine = myPlayerID.map { me in targets.contains { $0.id == me && $0.state == .pending } } ?? false
            banner = Callout(id: c.id, detail: "\(what) · \(who) · \(tail)".uppercased(), callerInitials: initialsOf[c.callerID] ?? "?",
                             targets: targets, canRespond: mine && !c.closed)
        }

        let events = (result?.holeEvents ?? []).filter { $0.hole == hole }.map(\.text)

        let strip = (1...max(1, holes)).map { n in
            StripItem(hole: n, filled: players.filter { p in scores.contains { $0.playerID == p.id && $0.hole == n && ($0.strokes != nil || $0.pickedUp) } }.count, total: players.count)
        }

        return HoleCardModel(hole: hole, holes: holes, par: par[safe: h] ?? nil, strokeIndex: strokeIndex[safe: h] ?? nil, yards: yards[safe: h] ?? nil,
                             inPlay: inPlay.joined(separator: " · "), rows: rows, callout: banner, events: events, nudge: nudge, strip: strip, panel: panel)
    }

    /// Short game name for rows and strips: "Skins", "Nassau", "Best Ball".
    public static func gameName(_ format: Format) -> String {
        switch format {
        case .strokePlay: return "Stroke"
        case .matchPlay: return "Match"
        case .bestBall: return "Best Ball"
        case .alternateShot: return "Alt Shot"
        case .fewestBlowUps: return "Blow-Ups"
        case .beatYourAverage: return "Beat Avg"
        case .bogeyGolf: return "Bogey"
        case .mostPars: return "Pars"
        case .firstToFive: return "First to 5"
        case .worstHole: return "Worst Hole"
        default: return format.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The nudge after the last score lands: a blow-up first, else the hole's first ink event. Nil when quiet.
    public static func nudge(for hole: Int, par: Int?, rows: [Row], result: RoundResult?) -> String? {
        if let par, let blow = rows.first(where: { Int($0.score).map { $0 >= par + 2 } ?? ($0.score == "X") }) {
            let made = blow.score == "X" ? "picked up" : "made \(blow.score)"
            return "\(blow.name) \(made). React?"
        }
        if let event = result?.holeEvents.first(where: { $0.hole == hole }) {
            return "\(event.text) React?"
        }
        return nil
    }
}

/// Contextual ordering for the tray (PRD 8.7): ordering only, never a system placement.
public enum StickerContext: Equatable, Sendable {
    case none, blowUp, birdieOrBetter, ducked

    public var suggested: [StickerKey] {
        switch self {
        case .blowUp: return [.yikes, .wasted, .hahaha]
        case .birdieOrBetter: return [.clutch]
        case .ducked: return [.duckIt, .hahaha]
        case .none: return []
        }
    }

    /// Suggested first, then the rest of the pack in pack order.
    public var ordered: [StickerKey] { suggested + StickerKey.allCases.filter { !suggested.contains($0) } }
}
