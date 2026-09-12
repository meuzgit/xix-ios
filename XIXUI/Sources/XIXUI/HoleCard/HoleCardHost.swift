// Binds the hole card to a RoundSession: one page per hole, opens on the current hole, swipe between
// holes, pad and tray panels, the nudge after the last score lands, rejections as a toast.
import SwiftUI
import XIXData
import XIXModels
import XIXScoring

public struct HoleCardHost: View {
    let session: RoundSession
    let isOwner: Bool
    @State private var hole: Int
    @State private var state: RoundSession.State?
    @State private var panel: HoleCardModel.Panel = .none
    @State private var nudge: (hole: Int, text: String)?
    @State private var notice: String?
    @State private var awaitingHoleComplete: Int?

    public init(session: RoundSession, isOwner: Bool, startHole: Int? = nil) {
        self.session = session
        self.isOwner = isOwner
        _hole = State(initialValue: startHole ?? 1)
    }

    public var body: some View {
        GeometryReader { geo in
            Group {
                if let state {
                    pages(state, width: geo.size.width)
                } else {
                    XIXColor.sheet
                }
            }
        }
        .task {
            var s = await session.currentState()
            if s.result == nil { _ = await session.recompute(); s = await session.currentState() }
            state = s
            if hole < 1 { hole = Self.currentHole(s) }
            for await event in await session.events() {
                switch event {
                case .state(let s):
                    state = s
                    if let waiting = awaitingHoleComplete, Self.holeComplete(s, hole: waiting) {
                        awaitingHoleComplete = nil
                        let m = Self.model(s, hole: waiting, myPlayerID: await session.myPlayerID, isOwner: isOwner, panel: .none, nudge: nil)
                        nudge = HoleCardModel.nudge(for: waiting, par: m.par, rows: m.rows, result: s.result).map { (waiting, $0) }
                    }
                case .notice(let n): show(n.text)
                case .rejected(_, let message): show(message)
                }
            }
        }
    }

    @ViewBuilder
    private func pages(_ s: RoundSession.State, width: CGFloat) -> some View {
        let holes = max(1, s.round.holes)
        #if os(iOS)
        TabView(selection: $hole) {
            ForEach(1...holes, id: \.self) { h in card(s, hole: h, width: width).tag(h) }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        card(s, hole: hole, width: width)
        #endif
    }

    private func card(_ s: RoundSession.State, hole h: Int, width: CGFloat) -> some View {
        let myID = s.players.first { $0.profile_id == sessionUserID }?.id
        var m = Self.model(s, hole: h, myPlayerID: myID, isOwner: isOwner, panel: h == hole ? panel : .none, nudge: nudge?.hole == h ? nudge?.text : nil)
        m.notice = notice
        return HoleCardView(model: m, width: width, actions: actions(for: s, hole: h))
    }

    private var sessionUserID: UUID? { session.userID }

    private func actions(for s: RoundSession.State, hole h: Int) -> HoleCardActions {
        HoleCardActions(
            openPad: { playerID in
                let name = s.players.first { $0.id == playerID }?.display_name ?? ""
                let existing = s.score(player: playerID, hole: h)
                panel = .pad(HoleCardModel.Pad(playerID: playerID, playerName: name, entered: existing?.strokes, pickedUp: existing?.picked_up ?? false))
            },
            padTap: { n in if case .pad(var p) = panel { p.entered = n; p.pickedUp = false; panel = .pad(p) } },
            padPickUp: { if case .pad(var p) = panel { p.pickedUp = true; p.entered = nil; panel = .pad(p) } },
            padClear: { if case .pad(var p) = panel { p.entered = nil; p.pickedUp = false; panel = .pad(p) } },
            padSave: {
                guard case .pad(let p) = panel, p.entered != nil || p.pickedUp else { return }
                panel = .none
                let others = s.players.filter { $0.id != p.playerID && $0.left_at == nil }
                let lastOnHole = others.allSatisfy { s.score(player: $0.id, hole: h) != nil }
                if lastOnHole { awaitingHoleComplete = h }
                Task { await session.enterScore(playerID: p.playerID, hole: h, strokes: p.entered, pickedUp: p.pickedUp) }
            },
            openTray: { target, context in panel = .tray(targetPlayerID: target, context: context); nudge = nil },
            sendSticker: { target, key in
                panel = .none
                Task { await session.sendSticker(hole: h, targetPlayerID: target, stickerKey: key.rawValue) }
            },
            closePanel: { panel = .none },
            respond: { calloutID, response in
                Task { await session.respond(calloutID: calloutID, action: response == .signed ? .signed : .ducked) }
            },
            composeCallout: { show("Callouts arrive with the composer in Build Doc 3") },
            go: { hole = $0 })
    }

    private func show(_ text: String) {
        notice = text
        Task { try? await Task.sleep(for: .seconds(3)); if notice == text { notice = nil } }
    }

    // MARK: Model from session state

    public static func currentHole(_ s: RoundSession.State) -> Int {
        let active = s.players.filter { $0.left_at == nil }
        return (1...max(1, s.round.holes)).first { h in active.contains { s.score(player: $0.id, hole: h) == nil } } ?? s.round.holes
    }

    static func holeComplete(_ s: RoundSession.State, hole: Int) -> Bool {
        s.players.filter { $0.left_at == nil }.allSatisfy { s.score(player: $0.id, hole: hole) != nil }
    }

    public static func model(_ s: RoundSession.State, hole: Int, myPlayerID: UUID?, isOwner: Bool, panel: HoleCardModel.Panel, nudge: String?) -> HoleCardModel {
        let holes = s.round.holes
        var par = [Int?](repeating: nil, count: holes), si = [Int?](repeating: nil, count: holes)
        for h in s.courseHoles where h.hole >= 1 && h.hole <= holes { par[h.hole - 1] = h.par; si[h.hole - 1] = h.stroke_index }
        let players = s.players.map { ScorecardModel.Player(id: $0.id, name: $0.display_name) }
        let callouts = s.callouts.map { c -> HoleCardModel.CalloutInputModel in
            let targets = (try? JSONDecoder().decode([UUID].self, from: Data(c.target_ids.utf8))) ?? []
            let goal = (try? JSONDecoder().decode([String: AnyJSONLite].self, from: Data(c.params.utf8)))?["goal"]?.text
            let responses = Dictionary(uniqueKeysWithValues: s.responses.filter { $0.callout_id == c.id }.map { ($0.player_id, $0.action) })
            return .init(id: c.id, hole: c.hole, kind: c.kind, callerID: c.caller_id, targetIDs: targets, goal: goal, responses: responses,
                         closed: c.closed_at != nil || c.status == "expired" || c.status == "resolved")
        }
        return HoleCardModel.build(
            hole: hole, holes: holes, par: par, strokeIndex: si, yards: [Int?](repeating: nil, count: holes),
            players: players, engineID: { PlayerID($0.uuidString.lowercased()) },
            scores: s.scores.map { .init(playerID: $0.player_id, hole: $0.hole, strokes: $0.strokes, pickedUp: $0.picked_up) },
            stickers: s.stickers.map { .init(id: $0.id, targetPlayerID: $0.target_player_id, senderPlayerID: $0.sender_player_id, hole: $0.hole, key: $0.sticker_key, createdAt: $0.created_at) },
            callouts: callouts, result: s.result, myPlayerID: myPlayerID, isOwner: isOwner, panel: panel, nudge: nudge)
    }
}

/// Just enough JSON to read a callout's goal ("par", "birdie" or a number).
enum AnyJSONLite: Decodable {
    case string(String), number(Double), other
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else { self = .other }
    }
    var text: String? {
        switch self { case .string(let s): return s; case .number(let d): return String(Int(d)); case .other: return nil }
    }
}
