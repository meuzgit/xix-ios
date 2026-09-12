// Round setup, five screens (PRD 8.16, Pass 6 6a/6b): Course → Par → Players → Games → Share. Solo
// skips players and games. The round is created when Games finishes (Share needs the code), and Play
// hole 1 opens the round on the hole card.
import SwiftUI
import XIXData
import XIXModels
import XIXUI

struct SetupFlow: View {
    let mode: SetupMode
    @Environment(AppEnvironment.self) private var env
    @State private var draft = SetupDraft()
    @State private var step = 0
    @State private var creating = false
    @State private var createdRoundID: UUID?
    @State private var joinCode = ""
    @State private var error: String?

    private var steps: [String] { mode == .solo ? ["Course", "Par"] : ["Course", "Par", "Players", "Games", "Share the round"] }

    var body: some View {
        VStack(spacing: 0) {
            GreenBar("\(mode == .solo ? "SOLO ROUND" : "NEW ROUND") · \(step + 1) OF \(steps.count)", onBack: back)
            Group {
                switch (mode, step) {
                case (_, 0): CourseStep(draft: $draft, onNext: next)
                case (_, 1): ParStep(draft: $draft, onNext: next)
                case (.group, 2): PlayersStep(draft: $draft, onNext: next)
                case (.group, 3): GamesStep(draft: $draft, title: "Games", locked: false, onNext: next)
                default: ShareStep(joinCode: joinCode, creating: creating, onPlay: play)
                }
            }
            if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(12) }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func back() {
        if step == 0 || createdRoundID != nil { env.router.path.removeLast() } else { step -= 1 }
    }

    private func next() {
        error = nil
        let last = steps.count - 1
        if mode == .solo && step == 1 { Task { await createAndPlay() }; return }
        if mode == .group && step == 3 { Task { await create() }; return }
        if step < last { step += 1 }
    }

    /// Group: create the round now so the share screen has its code.
    private func create() async {
        guard await env.requireSignIn(reason: "Sign in to start a round") else { return }
        creating = true; step = 4
        defer { creating = false }
        do {
            let id = try await draft.create(env: env)
            createdRoundID = id
            let bundle = try await env.rounds.fetchBundle(roundID: id)
            joinCode = bundle.round.joinCode
        } catch {
            self.error = "Could not create the round: \(error.localizedDescription)"
            step = 3
        }
    }

    private func createAndPlay() async {
        guard await env.requireSignIn(reason: "Sign in to start a round") else { return }
        creating = true; defer { creating = false }
        do {
            let id = try await draft.create(env: env)
            env.router.replaceTop(with: .round(id))
        } catch {
            self.error = "Could not create the round: \(error.localizedDescription)"
        }
    }

    private func play() {
        guard let id = createdRoundID else { return }
        env.router.replaceTop(with: .round(id))
    }
}

// MARK: - 1 · Course

struct CourseStep: View {
    @Binding var draft: SetupDraft
    let onNext: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""
    @State private var matches: [CourseRow] = []
    @State private var recents: [String] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Course").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(20)
                    TextField("Search or type any name", text: $query)
                        .accessibilityIdentifier("courseField")
                        .font(XIXType.body(17)).padding(.horizontal, 16).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(.horizontal, 12)
                        .focused($focused).autocorrectionDisabled().submitLabel(.next)
                        .onSubmit { if !trimmed.isEmpty { choose(trimmed, region: nil) } }
                        .onChange(of: query) { Task { await search() } }
                    if trimmed.isEmpty {
                        if !recents.isEmpty {
                            SectionLabel(text: "Recent")
                            ForEach(recents, id: \.self) { name in
                                ListRow(name, sub: "Played here before", action: { choose(name, region: nil) }) { tag("RECENT") }
                            }
                        }
                    } else {
                        ForEach(matches, id: \.id) { c in
                            ListRow(c.name, sub: [c.region, "par known"].compactMap { $0 }.joined(separator: " · "), action: { choose(c.name, region: c.region) })
                        }
                        ListRow("Use “\(trimmed)” as a new course", sub: "No match needed. Type anything.", action: { choose(trimmed, region: nil) }) { tag("NEW", filled: true) }
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach([9, 18], id: \.self) { n in Chip(text: "\(n) holes", selected: draft.holes == n) { setHoles(n) } }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
            PrimaryButton(title: "Next", enabled: draft.isValid) { onNext() }.padding(.horizontal, 12).padding(.bottom, 16)
        }
        .task {
            recents = env.client.store.recentCourses()
            query = draft.courseName
            if draft.courseName.isEmpty { focused = true }
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private func tag(_ text: String, filled: Bool = false) -> some View {
        Text(text).trackedCaps(8, weight: .bold).foregroundStyle(filled ? XIXColor.onGreen : XIXColor.muted)
            .padding(.horizontal, 7).frame(height: 20).background(RoundedRectangle(cornerRadius: 4).fill(filled ? XIXColor.green : XIXColor.surface))
    }

    private func choose(_ name: String, region: String?) {
        draft.courseName = name; draft.region = region; query = name
        focused = false
        onNext()
    }

    private func setHoles(_ n: Int) {
        draft.holes = n
        draft.par = Array(repeating: 4, count: n); draft.strokeIndex = Array(repeating: nil, count: n); draft.yards = Array(repeating: nil, count: n)
    }

    private func search() async {
        let q = trimmed
        draft.courseName = q
        guard env.isSignedIn, q.count >= 2 else { matches = []; return }
        matches = (try? await env.rounds.searchCourses(q)) ?? []
    }
}

// MARK: - 2 · Par

struct ParStep: View {
    @Binding var draft: SetupDraft
    let onNext: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 9)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Par").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(.horizontal, 20).padding(.top, 20)
                    Text("Optional. Tap a chip to change it: 3, 4 or 5.").font(XIXType.body(13)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20).padding(.top, 4)
                    SectionLabel(text: "Par · optional")
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(0..<draft.holes, id: \.self) { i in
                            Button {
                                draft.parSkipped = false
                                draft.par[i] = draft.par[i] == 3 ? 4 : (draft.par[i] == 4 ? 5 : 3)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(i + 1)").trackedCaps(7).foregroundStyle(draft.parSkipped ? XIXColor.faint : XIXColor.muted)
                                    Text("\(draft.par[i])").font(XIXType.number(15, weight: .semibold)).foregroundStyle(draft.parSkipped ? XIXColor.faint : XIXColor.ink)
                                }
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(RoundedRectangle(cornerRadius: 8).fill(draft.parSkipped ? XIXColor.sheet : XIXColor.surface))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(draft.parSkipped ? XIXColor.hairline : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("par-\(i + 1)")
                        }
                    }
                    .padding(.horizontal, 12)
                    HStack {
                        Text("Total par \(draft.par.prefix(draft.holes).reduce(0, +))").trackedCaps(9).foregroundStyle(draft.parSkipped ? XIXColor.faint : XIXColor.ink)
                        Spacer()
                        Chip(text: draft.parSkipped ? "Par skipped" : "Skip par", selected: draft.parSkipped) { draft.parSkipped.toggle() }
                    }
                    .padding(.horizontal, 20).padding(.top, 14)
                    Text("Skipping greys Stableford, Bogey Golf, Most Pars and Fewest Blow-Ups until par is added.")
                        .font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20).padding(.top, 10)
                }
            }
            PrimaryButton(title: "Next") { onNext() }.padding(.horizontal, 12).padding(.bottom, 16)
        }
    }
}

// MARK: - 3 · Players

struct PlayersStep: View {
    @Binding var draft: SetupDraft
    let onNext: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var newName = ""
    @State private var recents: [(name: String, hasXIX: Bool)] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Players").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(20)
                    playerRow(initials: initials(env.displayName), name: env.displayName, sub: "You · owner", remove: nil)
                    ForEach(draft.guests) { g in
                        playerRow(initials: initials(g.name), name: g.name, sub: g.hasXIX ? "Has XIX" : "By name") { draft.guests.removeAll { $0.id == g.id } }
                    }
                    if draft.guests.count < 3 {
                        HStack(spacing: 10) {
                            TextField("Add a player", text: $newName).accessibilityIdentifier("playerField").font(XIXType.body(15)).focused($focused).autocorrectionDisabled()
                                .submitLabel(.done).onSubmit(add)
                            Button("Add", action: add).font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 16).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(XIXColor.surface)).padding(.horizontal, 12).padding(.top, 10)
                    } else {
                        Text("Four is the card. Remove a row to add someone else.").font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(20)
                    }
                    let available = recents.filter { r in !draft.guests.contains { $0.name == r.name } }
                    if !available.isEmpty {
                        SectionLabel(text: "Recent")
                        FlowChips(items: available.map(\.name)) { name in
                            guard draft.guests.count < 3 else { return }
                            draft.guests.append(.init(name: name, hasXIX: available.first { $0.name == name }?.hasXIX ?? false))
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            PrimaryButton(title: "Next") { onNext() }.padding(.horizontal, 12).padding(.bottom, 16)
        }
        .task { recents = env.client.store.recentPeople(profileID: env.userID) }
    }

    private func initials(_ n: String) -> String { ScorecardModel.initials(for: n) }

    private func add() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, draft.guests.count < 3 else { return }
        draft.guests.append(.init(name: n, hasXIX: false)); newName = ""
    }

    private func playerRow(initials: String, name: String, sub: String, remove: (() -> Void)?) -> some View {
        HStack(spacing: 14) {
            Avatar(initials: initials, me: remove == nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(XIXType.body(16, weight: .semibold)).foregroundStyle(XIXColor.ink)
                Text(sub).font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
            }
            Spacer()
            if let remove {
                Button(action: remove) { Text("×").font(XIXType.body(20)).foregroundStyle(XIXColor.muted).frame(width: 32, height: 32) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
    }
}

/// Chips that wrap.
struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in Chip(text: item) { tap(item) } }
        }
    }
}

// MARK: - 4 · Games

struct GamesStep: View {
    @Binding var draft: SetupDraft
    let title: String
    /// Read-only once hole 1 has a score (round menu).
    let locked: Bool
    let onNext: () -> Void
    @State private var thirdGame: GameEntry?

    private var seatNames: [String] {
        ["You"] + draft.guests.map(\.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink)
                        Spacer()
                        let active = draft.activeGames.map { $0.entry.name.uppercased() }
                        Text(active.isEmpty ? "NO GAMES" : active.joined(separator: " · ")).trackedCaps(8).foregroundStyle(XIXColor.muted).lineLimit(1)
                    }
                    .padding(20)
                    if locked {
                        Text("Locked. Hole 1 is scored, so the games stay as they are.").font(XIXType.body(12)).foregroundStyle(Color(hex: 0xB77B12)).padding(.horizontal, 20)
                    }
                    if let third = thirdGame { thirdGameLine(third) }
                    ForEach(GamesLibrary.groups, id: \.label) { group in
                        SectionLabel(text: group.label)
                        ForEach(group.games) { entry in gameRow(entry) }
                    }
                    Text(footer).font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted).padding(20)
                }
            }
            if !locked { PrimaryButton(title: "Next") { onNext() }.padding(.horizontal, 12).padding(.bottom, 16) }
        }
    }

    private var footer: String {
        "\(min(draft.activeGames.count, GamesLibrary.freeLimit)) of \(GamesLibrary.freeLimit) games on free · the rest need Full"
    }

    private func pick(_ entry: GameEntry) -> SetupDraft.GamePick? { draft.games.first { $0.entry == entry } }

    private func gameRow(_ entry: GameEntry) -> some View {
        let parBlocked = entry.needsPar && draft.parSkipped
        let tooFew = entry.minPlayers > draft.seatCount
        let dim = parBlocked || tooFew || entry.full
        let current = pick(entry)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.name).font(XIXType.body(15, weight: .semibold)).foregroundStyle(dim ? XIXColor.faint : XIXColor.ink)
                    if entry.full { tag("FULL", filled: true) } else if parBlocked { tag("ADD PAR") }
                }
                Text(parBlocked ? "Needs par · add it on the par screen" : (tooFew ? "Needs \(entry.minPlayers) players" : entry.rule))
                    .font(XIXType.body(11.5)).foregroundStyle(parBlocked ? Color(hex: 0xB77B12) : XIXColor.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(0..<draft.seatCount, id: \.self) { seat in
                    let on = current?.seats.contains(seat) ?? false
                    Button { toggle(entry, seat: seat) } label: {
                        Text(ScorecardModel.initials(for: seatNames[seat])).trackedCaps(8, weight: .bold)
                            .foregroundStyle(on ? XIXColor.onGreen : (dim ? XIXColor.faint : XIXColor.green))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(on ? XIXColor.green : XIXColor.sheet).overlay(Circle().strokeBorder(dim ? XIXColor.hairline : XIXColor.green, lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                    .disabled(dim || locked)
                    .accessibilityIdentifier("game-\(entry.format.rawValue)-\(seat)")
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(dim ? Color(hex: 0xFCFCFB) : XIXColor.sheet)
        .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
    }

    private func tag(_ text: String, filled: Bool = false) -> some View {
        Text(text).trackedCaps(7, weight: .bold).foregroundStyle(filled ? XIXColor.onGreen : Color(hex: 0xB77B12))
            .padding(.horizontal, 6).frame(height: 18).background(RoundedRectangle(cornerRadius: 4).fill(filled ? XIXColor.green : Color(hex: 0xFFF1DA)))
    }

    private func toggle(_ entry: GameEntry, seat: Int) {
        thirdGame = nil
        if let i = draft.games.firstIndex(where: { $0.entry == entry }) {
            if draft.games[i].seats.contains(seat) { draft.games[i].seats.remove(seat) } else {
                draft.games[i].seats.insert(seat)
                if entry.sided { draft.games[i].sides[seat] = draft.games[i].sides[seat] ?? (draft.games[i].seats.count - 1) % 2 }
            }
            if draft.games[i].seats.isEmpty { draft.games.remove(at: i) }
        } else {
            // The free limit: a third game with players is the paywall's first entry point (step 9); here it just says so.
            if draft.activeGames.count >= GamesLibrary.freeLimit && entry.minPlayers <= 1 { thirdGame = entry; return }
            if draft.activeGames.count >= GamesLibrary.freeLimit && draft.games.filter({ $0.seats.count + 1 >= $0.entry.minPlayers }).count >= GamesLibrary.freeLimit {
                thirdGame = entry; return
            }
            var p = SetupDraft.GamePick(entry: entry, seats: [seat])
            if entry.sided { p.sides[seat] = 0 }
            draft.games.append(p)
        }
    }

    private func thirdGameLine(_ entry: GameEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Third game").trackedCaps(8, weight: .bold).foregroundStyle(XIXColor.muted)
            Text("Free rounds run two games").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.ink)
            let names = draft.activeGames.map { $0.entry.name }.joined(separator: " and ")
            Text("\(names) are in. \(entry.name) needs Full, or swap it for one of the two.").font(XIXType.body(12)).foregroundStyle(XIXColor.muted)
            HStack {
                Chip(text: "Swap a game") { if let first = draft.activeGames.first { draft.games.removeAll { $0.id == first.id } }; thirdGame = nil }
                Chip(text: "Not now") { thirdGame = nil }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(XIXColor.surface))
        .padding(.horizontal, 12)
    }
}

// MARK: - 5 · Share

struct ShareStep: View {
    let joinCode: String
    let creating: Bool
    let onPlay: () -> Void

    private var link: String { "xix.golf/r/\(joinCode)" }
    private var url: URL { URL(string: "https://\(link)")! }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Share the round").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(20)
                    if creating {
                        Text("Setting the round up…").font(XIXType.body(14)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 14) {
                            QRCodeView(text: "https://\(link)", size: 180)
                            Text(link).font(XIXType.number(20, weight: .bold)).foregroundStyle(XIXColor.ink)
                            Text("Anyone with the link lands on the live hole.").font(XIXType.body(12)).foregroundStyle(XIXColor.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                        .background(RoundedRectangle(cornerRadius: XIXMetric.cardRadius).fill(XIXColor.cream)).padding(.horizontal, 12)
                        ShareLink(item: url, subject: Text("Play a round on XIX"), message: Text("Join the round: \(link)")) {
                            Text("Share link").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.green)
                                .frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(XIXColor.surface))
                        }
                        .padding(.horizontal, 12).padding(.top, 12)
                    }
                    Text("Guests who join later land on the current hole. The owner can fill their earlier holes.")
                        .font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(20)
                }
            }
            PrimaryButton(title: "Play hole 1", enabled: !creating && !joinCode.isEmpty, action: onPlay).padding(.horizontal, 12).padding(.bottom, 16)
        }
    }
}
