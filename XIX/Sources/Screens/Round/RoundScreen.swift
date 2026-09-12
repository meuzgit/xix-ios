// The round on screen: the grid (layer 1) and the hole card (layer 2) bound to one RoundSession, the
// round menu, End round, and the hand-off to results when the round ends (Pass 7 §1).
import SwiftUI
import XIXData
import XIXModels
import XIXUI

struct RoundScreen: View {
    let roundID: UUID
    @Environment(AppEnvironment.self) private var env
    @State private var session: RoundSession?
    @State private var state: RoundSession.State?
    @State private var layer: Layer = .card
    @State private var holeToOpen: Int? = nil
    @State private var menu = false
    @State private var sheet: Sheet?
    @State private var error: String?

    enum Layer { case grid, card }
    enum Sheet: Identifiable { case end, players, games, export(Data); var id: String { switch self { case .end: "end"; case .players: "players"; case .games: "games"; case .export: "export" } } }

    private var isOwner: Bool { state.map { $0.round.owner_id == env.userID } ?? false }

    var body: some View {
        Group {
            if let session, let state {
                switch layer {
                case .grid:
                    GridScreenHost(session: session, onOpenHole: { h in holeToOpen = h; layer = .card }, onMenu: { menu = true },
                                   headerAccessory: AnyView(layerSwitch))
                case .card:
                    HoleCardHost(session: session, isOwner: isOwner, startHole: holeToOpen, onMenu: { menu = true }, headerAccessory: AnyView(layerSwitch),
                                 quiet: env.isQuiet(roundID), canCallOut: XIXFull.isActive,
                                 onSeeFull: { error = "XIX Full is not on sale yet." })
                        .id(holeToOpen ?? -1)
                }
            } else if let error {
                VStack(spacing: 12) {
                    Text(error).font(XIXType.body(13)).foregroundStyle(XIXColor.muted).padding(20)
                    SecondaryButton(title: "Back") { env.router.home() }.padding(.horizontal, 12)
                }
            } else {
                XIXColor.sheet
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task { await open() }
        .sheet(isPresented: $menu) { RoundMenuSheet(roundID: roundID, isOwner: isOwner, state: state, onPick: pick).presentationDetents([.medium, .large]) }
        .sheet(item: $sheet) { which in
            switch which {
            case .end: if let state { EndRoundSheet(state: state, onEnd: endRound) }
            case .players: if let session { EditPlayersSheet(session: session, roundID: roundID) }
            case .games: if let state { EditGamesSheet(state: state, roundID: roundID, onDone: { Task { await session?.resync() } }) }
            case .export(let png): ShareSheet(items: [UIImage(data: png) as Any])
            }
        }
    }

    private func open() async {
        do {
            let s = try await env.session(for: roundID)
            session = s
            let first = await s.currentState()
            state = first
            if first.round.status == "ended" { env.router.replaceTop(with: .results(roundID)); return }
            for await event in await s.events() {
                if case .state(let st) = event {
                    state = st
                    if st.round.status == "ended" { env.router.replaceTop(with: .results(roundID)); return }
                }
            }
        } catch {
            self.error = "Could not open the round: \(error.localizedDescription)"
        }
    }

    /// GRID / CARD in the header, before the menu dots.
    private var layerSwitch: some View {
        HStack(spacing: 0) {
            ForEach([Layer.grid, Layer.card], id: \.self) { l in
                Button { layer = l; if l == .card { holeToOpen = nil } } label: {
                    Text(l == .grid ? "GRID" : "CARD").trackedCaps(8, weight: .bold)
                        .foregroundStyle(layer == l ? XIXColor.green : XIXColor.onGreen)
                        .frame(width: 48, height: 22)
                        .background(Capsule().fill(layer == l ? XIXColor.cream : XIXColor.greenSoft))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(l == .grid ? "layer-grid" : "layer-card")
            }
        }
    }

    private func pick(_ item: RoundMenuItem) {
        menu = false
        switch item {
        case .end: sheet = .end
        case .players: sheet = .players
        case .games: sheet = .games
        case .export: exportCard()
        case .leave: Task { await leave() }
        }
    }

    private func exportCard() {
        guard let state else { return }
        let model = GridScreenHost.model(from: state, nameStyle: UserDefaults.standard.bool(forKey: "xix.initialsOnExport") ? .initials : .names, selectedPill: nil)
        if let png = ScorecardRenderer.pngData(model: model.scorecard) { sheet = .export(png) }
    }

    private func endRound() async {
        do {
            try await env.rounds.endRound(roundID: roundID)
            sheet = nil
            env.router.replaceTop(with: .results(roundID))
        } catch {
            self.error = "Could not end the round: \(error.localizedDescription)"
        }
    }

    private func leave() async {
        _ = try? await env.rounds.leaveRound(roundID: roundID)
        await env.closeSessions()
        env.router.home()
    }
}

/// UIKit's share sheet for the exported card image.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
