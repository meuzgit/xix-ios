// Edit players (Pass 7 §1, owner): rename a row, add a late guest, remove a row nobody claimed.
import SwiftUI
import XIXData
import XIXModels
import XIXUI

struct EditPlayersSheet: View {
    let session: RoundSession
    let roundID: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var players: [LocalPlayer] = []
    @State private var newName = ""
    @State private var renaming: LocalPlayer?
    @State private var renameText = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            GreenBar("EDIT PLAYERS", onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(players.filter { $0.left_at == nil }.sorted { $0.seat < $1.seat }, id: \.id) { p in
                        HStack(spacing: 14) {
                            Avatar(initials: ScorecardModel.initials(for: p.display_name), me: p.profile_id == env.userID)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.display_name).font(XIXType.body(16, weight: .semibold)).foregroundStyle(XIXColor.ink)
                                Text(p.profile_id == env.userID ? "You · owner" : (p.claimed_at != nil ? "Has XIX · claimed" : "By name · unclaimed"))
                                    .font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                            }
                            Spacer()
                            if p.profile_id != env.userID {
                                Button("Rename") { renaming = p; renameText = p.display_name }.font(XIXType.body(13, weight: .semibold)).foregroundStyle(XIXColor.green)
                                if p.claimed_at == nil {
                                    Button { Task { await remove(p) } } label: { Text("×").font(XIXType.body(20)).foregroundStyle(XIXColor.muted).frame(width: 32, height: 32) }.buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
                    }
                    if players.filter({ $0.left_at == nil }).count < 4 {
                        HStack(spacing: 10) {
                            TextField("Add a late guest", text: $newName).font(XIXType.body(15)).autocorrectionDisabled().submitLabel(.done).onSubmit { Task { await add() } }
                            Button("Add") { Task { await add() } }.font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 16).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(12)
                    }
                    if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(.horizontal, 20) }
                    Text("A late guest lands on the current hole from the link. You can fill their earlier holes.").font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(20)
                }
            }
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
        .task { players = await session.currentState().players }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func refresh() async {
        await session.resync()
        players = await session.currentState().players
    }

    private func add() async {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        do { try await env.rounds.addGuest(roundID: roundID, displayName: n); newName = ""; await refresh() } catch { self.error = error.localizedDescription }
    }

    private func rename() async {
        guard let p = renaming else { return }
        let n = renameText.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !n.isEmpty else { return }
        do { try await env.rounds.renamePlayer(playerID: p.id, displayName: n); await refresh() } catch { self.error = error.localizedDescription }
    }

    private func remove(_ p: LocalPlayer) async {
        do { try await env.rounds.removePlayer(playerID: p.id); await refresh() } catch { self.error = error.localizedDescription }
    }
}

/// Edit games from the round menu: the same picker, seeded from the round; locked once hole 1 is scored.
struct EditGamesSheet: View {
    let state: RoundSession.State
    let roundID: UUID
    let onDone: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SetupDraft()
    @State private var error: String?

    private var locked: Bool { state.scores.contains { $0.hole == 1 && ($0.strokes != nil || $0.picked_up) } }
    private var seats: [LocalPlayer] { state.players.filter { $0.left_at == nil }.sorted { $0.seat < $1.seat } }

    var body: some View {
        VStack(spacing: 0) {
            GreenBar("EDIT GAMES", onBack: { dismiss() })
            GamesStep(draft: $draft, title: "Games", locked: locked, onNext: { Task { await save() } })
            if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(12) }
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
        .onAppear { seed() }
    }

    private func seed() {
        draft.parSkipped = !state.courseHoles.contains { $0.par != nil }
        draft.guests = seats.dropFirst().map { .init(name: $0.display_name, hasXIX: $0.profile_id != nil) }
        let games = env.client.store.games(roundID: roundID)
        let gps = env.client.store.gamePlayers(roundID: roundID)
        let ids = seats.map(\.id)
        draft.games = games.compactMap { g in
            guard let entry = GamesLibrary.entry(format: g.format) else { return nil }
            let members = gps.filter { $0.game_id == g.id }
            var pick = SetupDraft.GamePick(entry: entry, seats: Set(members.compactMap { ids.firstIndex(of: $0.player_id) }))
            for m in members { if let i = ids.firstIndex(of: m.player_id), let side = m.side { pick.sides[i] = side } }
            return pick
        }
    }

    private func save() async {
        do {
            try await env.rounds.setGames(roundID: roundID, games: draft.drafts(playerIDs: seats.map(\.id)))
            onDone(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

