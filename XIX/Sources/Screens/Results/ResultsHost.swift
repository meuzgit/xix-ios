// The results screen bound to the session: the server's result when it lands (the webhook), the local
// one until then, medals as patches, Share via the renderer, and the result-link confirm card for a
// guest who was scored by name (Pass 6 6c).
import SwiftUI
import XIXData
import XIXModels
import XIXScoring
import XIXUI

struct ResultsHost: View {
    let roundID: UUID
    /// The row a guest arrived to claim from a result link, if any.
    var claimRow: UUID? = nil
    var ownerName: String? = nil
    @Environment(AppEnvironment.self) private var env
    @State private var session: RoundSession?
    @State private var state: RoundSession.State?
    @State private var confirmed = false
    @State private var confirming = false
    @State private var share: Data?
    @State private var error: String?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let state {
                    ResultsScreen(model: model(state), width: geo.size.width, actions: ResultsActions(
                        share: { shareResults(state) },
                        back: { env.router.home() },
                        confirm: { Task { await confirm() } }))
                } else if let error {
                    Text(error).font(XIXType.body(13)).foregroundStyle(XIXColor.muted).padding(20)
                } else {
                    XIXColor.sheet
                }
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task { await open() }
        .sheet(item: Binding(get: { share.map { ShareData(data: $0) } }, set: { if $0 == nil { share = nil } })) { d in
            ShareSheet(items: [UIImage(data: d.data) as Any])
        }
    }

    struct ShareData: Identifiable { let data: Data; var id: Int { data.count } }

    private func open() async {
        do {
            let s = try await env.session(for: roundID)
            session = s
            state = await s.currentState()
            if await s.currentState().serverResult == nil { await s.resync(); state = await s.currentState() }
            for await event in await s.events() {
                if case .state(let st) = event { state = st }
            }
        } catch {
            self.error = "Could not load the results: \(error.localizedDescription)"
        }
    }

    private func model(_ s: RoundSession.State) -> ResultsModel {
        // The server's result is authoritative once it lands; until then the device's own.
        let result = s.serverResult?.status.isComplete == true || s.result == nil ? s.serverResult ?? s.result : s.result
        let players = s.players.filter { $0.left_at == nil }.sorted { $0.seat < $1.seat }.map { ScorecardModel.Player(id: $0.id, name: $0.display_name) }
        var par = [Int?](repeating: nil, count: s.round.holes)
        for h in s.courseHoles where h.hole >= 1 && h.hole <= s.round.holes { par[h.hole - 1] = h.par }
        let myID = claimRow ?? s.players.first { $0.profile_id != nil && $0.profile_id == env.userID }?.id
        let gameNames: [String: String] = Dictionary(uniqueKeysWithValues: (result?.games ?? []).map {
            ($0.gameID.rawValue.lowercased(), HoleCardModel.gameName($0.format))
        })
        let callouts = s.callouts.map { c in
            let targets = (try? JSONDecoder().decode([UUID].self, from: Data(c.target_ids.utf8))) ?? []
            let params = (try? JSONSerialization.jsonObject(with: Data(c.params.utf8))) as? [String: Any]
            let goal = params?["goal"]
            let gameID = (params?["game_id"] as? String)?.lowercased()
            return ResultsModel.CalloutInput(id: c.id, hole: c.hole, kind: c.kind, callerID: c.caller_id, targetIDs: targets,
                                             goal: (goal as? String) ?? (goal as? Int).map(String.init),
                                             gameName: gameID.flatMap { gameNames[$0] })
        }
        let stickers = s.stickers.map { HoleCardModel.StickerInputModel(id: $0.id, targetPlayerID: $0.target_player_id, senderPlayerID: $0.sender_player_id, hole: $0.hole, key: $0.sticker_key, createdAt: $0.created_at) }
        var confirm: ResultsModel.ConfirmCard? = nil
        if let claimRow {
            let myMedals = result?.medals.filter { $0.profile.rawValue == claimRow.uuidString.lowercased() }.count ?? 0
            confirm = confirmed ? .confirmed(medals: myMedals) : .pending(owner: ownerName ?? "the owner", medals: myMedals)
        }
        var m = ResultsModel.build(courseName: s.round.course_name ?? "Round", dateLabel: Date.shortLabel(playedOn: s.round.played_on), par: par,
                                   players: players, engineID: { PlayerID($0.uuidString.lowercased()) }, result: result, callouts: callouts,
                                   stickers: stickers, myPlayerID: myID, confirm: confirm)
        // Waiting on the server: the round has ended but its authoritative result has not landed yet.
        // A round ended with holes left open is not waiting for anything; it simply has blank cells.
        m.pending = s.round.status == "ended" && s.serverResult == nil
        return m
    }

    private func shareResults(_ s: RoundSession.State) {
        let grid = GridScreenHost.model(from: s, nameStyle: .names, selectedPill: nil)
        share = ScorecardRenderer.pngData(model: grid.scorecard)
    }

    /// Result-link confirm: sign in, claim the row if it is still free, confirm the round.
    private func confirm() async {
        if confirmed { env.router.home(); return }
        guard let claimRow, !confirming else { return }
        guard await env.requireSignIn(reason: "Confirm my scores") else { return }
        confirming = true; defer { confirming = false }
        do {
            _ = try? await env.rounds.claimRow(roundID: roundID, playerID: claimRow)
            _ = try await env.rounds.confirmRound(roundID: roundID, action: .confirm)
            confirmed = true
            await session?.resync()
            state = await session?.currentState()
        } catch {
            self.error = "Could not confirm: \(error.localizedDescription)"
        }
    }
}
