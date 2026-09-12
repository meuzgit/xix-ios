// Home (PRD 8.16, 8.21; Pass 6 6a, 6i): "Same as last time" from what this phone remembers, New round,
// Solo round, the personal record for the last course. First run is the solo empty state. Nothing here
// needs a sign-in; identity is asked for when a round is created.
import SwiftUI
import XIXData
import XIXModels
import XIXUI

struct HomeScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var last: RoundMemory?
    @State private var record: CourseRecord?
    @State private var starting = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                if let last {
                    sameAsLastTime(last)
                } else {
                    firstRun
                }
                actions
                recordBlock
                if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(20) }
            }
        }
        .background(XIXColor.sheet)
        .task { await env.closeSessions(); reload() }
        .onChange(of: env.isSignedIn) { reload() }
    }

    private func reload() {
        last = env.client.store.lastRound(profileID: env.userID)
        if let name = last?.round.course_name { record = env.client.store.record(courseName: name, profileID: env.userID) } else { record = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("XIX").trackedCaps(11, weight: .bold).foregroundStyle(XIXColor.onGreen)
                Spacer()
                Text(Date().homeLabel).trackedCaps(9).foregroundStyle(XIXColor.faint)
                Button { env.router.path.append(.settings) } label: {
                    Text("···").font(XIXType.body(16, weight: .bold)).foregroundStyle(XIXColor.onGreen).frame(width: 28, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            Text("XIX").font(.system(size: 44, weight: .black)).foregroundStyle(XIXColor.onGreen).padding(.top, 10)
            Text(env.isSignedIn ? env.displayName.uppercased() : "SCORING IS FREE").trackedCaps(9).foregroundStyle(XIXColor.faint)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XIXColor.green)
    }

    private func sameAsLastTime(_ m: RoundMemory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Same as last time").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.faint)
            Text(m.courseName).font(XIXType.body(24, weight: .bold)).foregroundStyle(XIXColor.onGreen)
            Text(m.isSolo ? "Solo" : m.playerNames.joined(separator: ", ")).font(XIXType.body(14)).foregroundStyle(XIXColor.onGreen.opacity(0.75))
            let games = m.games.map { GamesLibrary.name(for: $0.format) }
            Text(games.isEmpty ? "No games" : games.joined(separator: " · ")).font(XIXType.body(13)).foregroundStyle(XIXColor.onGreen.opacity(0.6))
            Button { Task { await startSame(m) } } label: {
                Text(starting ? "Starting…" : "Start it").font(XIXType.body(15, weight: .bold)).foregroundStyle(XIXColor.green)
                    .frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(XIXColor.cream))
            }
            .buttonStyle(.plain).disabled(starting)
            .padding(.top, 12)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: XIXMetric.cardRadius).fill(XIXColor.greenSoft))
        .padding(.horizontal, 12).padding(.top, 12)
    }

    private var firstRun: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Play a round.\nEverything else\nfollows from it.").font(.system(size: 28, weight: .black)).foregroundStyle(XIXColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("On your own is fine. Score it solo and add people whenever they turn up.").font(XIXType.body(13)).foregroundStyle(XIXColor.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: "New round") { env.router.path.append(.setup(.group)) }
            SecondaryButton(title: "Solo round") { env.router.path.append(.setup(.solo)) }
            HStack(spacing: 8) {
                SecondaryButton(title: "Cabinet") { env.router.path.append(.cabinet) }
                SecondaryButton(title: "Boards") { env.router.path.append(.rankings) }
                SecondaryButton(title: "Rivals") { env.router.path.append(.rivals) }
            }
        }
        .padding(.horizontal, 12).padding(.top, 12)
    }

    private var recordBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: record.map { "Your record · \($0.courseName)" } ?? "Your record")
            HStack(spacing: 0) {
                stat(record?.best.map(String.init) ?? "—", "best")
                stat(record?.average.map { String(format: "%.1f", $0) } ?? "—", "average")
                stat(record.map { "\($0.rounds)" } ?? "0", "rounds")
            }
            .padding(.horizontal, 20)
            if (record?.rounds ?? 0) < 3 {
                Text("Three rounds gives you a Level and Beat Your Average.").font(XIXType.body(12)).foregroundStyle(XIXColor.muted)
                    .padding(.horizontal, 20).padding(.top, 12)
            }
        }
        .padding(.bottom, 30)
    }

    private func stat(_ value: String, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(XIXType.number(28, weight: .black)).foregroundStyle(XIXColor.ink)
            Text(key).trackedCaps(8).foregroundStyle(XIXColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same course (with its par), same people, same games: one tap to the share screen.
    private func startSame(_ m: RoundMemory) async {
        guard await env.requireSignIn(reason: "Sign in to start a round") else { return }
        starting = true; defer { starting = false }
        var draft = SetupDraft()
        draft.courseName = m.courseName
        let holes = env.client.store.courseHoles(roundID: m.round.id)
        draft.holes = m.round.holes
        if holes.contains(where: { $0.par != nil }) {
            draft.par = (1...draft.holes).map { h in holes.first { $0.hole == h }?.par ?? 4 }
            draft.strokeIndex = (1...draft.holes).map { h in holes.first { $0.hole == h }?.stroke_index }
            draft.yards = (1...draft.holes).map { h in holes.first { $0.hole == h }?.yards }
            draft.parSkipped = false
        } else {
            draft.parSkipped = true
        }
        let me = env.userID
        draft.guests = m.players.filter { $0.left_at == nil && !($0.profile_id != nil && $0.profile_id == me) }.sorted { $0.seat < $1.seat }
            .map { SetupDraft.Guest(name: $0.display_name, hasXIX: $0.profile_id != nil) }
        // Games by seat: the memory's rows map onto the new round's rows in order (owner first, then guests).
        let seats = ([m.players.first { $0.profile_id != nil && $0.profile_id == me }].compactMap { $0 } + m.players.filter { !($0.profile_id != nil && $0.profile_id == me) }.sorted { $0.seat < $1.seat }).map(\.id)
        draft.games = m.games.compactMap { g in
            guard let entry = GamesLibrary.entry(format: g.format) else { return nil }
            let members = m.gamePlayers.filter { $0.game_id == g.id }
            let idx = members.compactMap { gp in seats.firstIndex(of: gp.player_id) }
            var pick = SetupDraft.GamePick(entry: entry, seats: Set(idx))
            for gp in members { if let i = seats.firstIndex(of: gp.player_id), let side = gp.side { pick.sides[i] = side } }
            return pick
        }
        do {
            let id = try await draft.create(env: env)
            env.router.path.append(.setup(.group))
            env.router.replaceTop(with: .round(id))
        } catch {
            self.error = "\(error)"
        }
    }
}

