// Binds the grid screen to a RoundSession: state events rebuild the model, notices show as a toast
// for a few seconds, taps route to the hole card (a stub until step 6).
import SwiftUI
import XIXData
import XIXScoring

public struct GridScreenHost: View {
    let session: RoundSession
    let nameStyle: ScorecardModel.NameStyle
    let onOpenHole: (Int) -> Void
    let onMenu: (() -> Void)?
    let headerAccessory: AnyView?
    @State private var model: GridScreenModel?
    @State private var selectedPill: String?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    public init(session: RoundSession, nameStyle: ScorecardModel.NameStyle = .names, onOpenHole: @escaping (Int) -> Void, onMenu: (() -> Void)? = nil,
                headerAccessory: AnyView? = nil) {
        self.session = session
        self.nameStyle = nameStyle
        self.onOpenHole = onOpenHole
        self.onMenu = onMenu
        self.headerAccessory = headerAccessory
    }

    public var body: some View {
        GeometryReader { geo in
            Group {
                if let model {
                    GridScreen(model: withNotice(model), selectedPill: $selectedPill, width: geo.size.width, onOpenHole: onOpenHole, onMenu: onMenu, headerAccessory: headerAccessory)
                } else {
                    XIXColor.sheet
                }
            }
        }
        .task {
            var state = await session.currentState()
            if state.result == nil { _ = await session.recompute(); state = await session.currentState() }
            model = Self.model(from: state, nameStyle: nameStyle, selectedPill: selectedPill)
            for await event in await session.events() {
                switch event {
                case .state(let s):
                    model = Self.model(from: s, nameStyle: nameStyle, selectedPill: selectedPill)
                case .notice(let n):
                    show(notice: n.text)
                case .rejected(_, let message):
                    show(notice: message)
                case .stickerPlayed(let played):
                    show(notice: played.text)
                }
            }
        }
    }

    private func withNotice(_ m: GridScreenModel) -> GridScreenModel {
        var copy = m; copy.notice = notice; return copy
    }

    private func show(notice text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { notice = nil }
        }
    }

    /// Session state → grid model. Engine ids are the lowercased row uuids (see RoundInputBuilder).
    public static func model(from state: RoundSession.State, nameStyle: ScorecardModel.NameStyle, selectedPill: String?) -> GridScreenModel {
        let players = state.players.map { ScorecardModel.Player(id: $0.id, name: $0.display_name) }
        var par = [Int?](repeating: nil, count: state.round.holes)
        for h in state.courseHoles where h.hole >= 1 && h.hole <= state.round.holes { par[h.hole - 1] = h.par }
        return GridScreenModel.build(
            courseName: state.round.course_name ?? "Round", dateLabel: state.round.played_on, holes: state.round.holes,
            par: par, players: players, engineID: { PlayerID($0.uuidString.lowercased()) },
            scores: state.scores.map { .init(playerID: $0.player_id, hole: $0.hole, strokes: $0.strokes, pickedUp: $0.picked_up) },
            stickers: state.stickers.map { .init(targetPlayerID: $0.target_player_id, senderPlayerID: $0.sender_player_id, hole: $0.hole, key: $0.sticker_key, createdAt: $0.created_at) },
            liveCalloutHoles: state.liveCalloutHoles, result: state.result, nameStyle: nameStyle, selectedPill: selectedPill,
            joinLink: "xix.golf/r/\(state.round.join_code)")
    }
}
