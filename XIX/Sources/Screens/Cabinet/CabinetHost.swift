// The cabinet, a medal's context card, the rivals list and one rivalry — each bound to the repository
// (Build Doc 3 step 5). The screens themselves are in XIXUI and know nothing about the network.
import SwiftUI
import XIXData
import XIXModels
import XIXScoring
import XIXUI

struct CabinetHost: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: CabinetModel?
    @State private var medals: [CabinetMedal] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let model {
                CabinetScreen(model: model, onTap: { entry in
                    if let medal = medals.first(where: { $0.id == entry.id }) { env.router.path.append(.medal(medal.id)) }
                }, onBack: { env.router.path.removeLast() })
            } else if let error {
                Text(error).font(XIXType.body(13)).foregroundStyle(XIXColor.muted).padding(20)
            } else {
                XIXColor.sheet
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        guard await env.requireSignIn(reason: "Sign in to see your cabinet") else { env.router.home(); return }
        do {
            medals = try await CabinetRepository(client: env.client).medals()
            model = CabinetHost.model(medals, owner: env.displayName)
        } catch {
            self.error = "Could not load the cabinet: \(error.localizedDescription)"
        }
    }

    /// Medals grouped into seasons, newest first (PRD 8.18).
    static func model(_ medals: [CabinetMedal], owner: String) -> CabinetModel {
        let bySeason = Dictionary(grouping: medals) { $0.season }
        let seasons = bySeason.keys.sorted(by: >).map { season in
            CabinetModel.Season(label: "\(season) SEASON", medals: bySeason[season]!.map(entry(for:)))
        }
        return CabinetModel(owner: owner, total: medals.count, seasons: seasons)
    }

    static func entry(for medal: CabinetMedal) -> CabinetModel.Entry {
        CabinetModel.Entry(id: medal.id, patch: patch(for: medal), when: when(for: medal))
    }

    static func patch(for medal: CabinetMedal, opponent: String? = nil) -> MedalPatchModel {
        let key = MedalKey(rawValue: medal.key)
        let p = key?.patch ?? (shape: .circle, top: "MEDAL", bottom: medal.key.uppercased(), name: medal.key.capitalized)
        var context: [String] = []
        if let opponent { context.append("vs \(opponent)") }
        if let course = medal.course { context.append(course) }
        if let date = medal.date { context.append(Date.shortLabel(playedOn: date)) }
        return MedalPatchModel(id: medal.id.uuidString, shape: p.shape, accent: key?.accent ?? .green,
                               top: p.top, bottom: p.bottom, name: p.name, context: context.joined(separator: " · "))
    }

    static func when(for medal: CabinetMedal) -> String {
        [medal.date.map(Date.shortLabel(playedOn:)), medal.course].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One medal, with the round it came from drawn by the same renderer the export uses (Pass 7 §3).
struct MedalHost: View {
    let medalID: UUID
    @Environment(AppEnvironment.self) private var env
    @State private var medal: CabinetMedal?
    @State private var scorecard: ScorecardModel?
    @State private var opponent: String?
    @State private var share: Data?

    var body: some View {
        Group {
            if let medal {
                MedalContextCard(patch: CabinetHost.patch(for: medal, opponent: opponent),
                                 how: how(medal), scorecard: scorecard,
                                 onShare: { shareCard() },
                                 onBack: { env.router.path.removeLast() })
            } else {
                XIXColor.sheet
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(item: Binding(get: { share.map { ShareBlob(data: $0) } }, set: { if $0 == nil { share = nil } })) { blob in
            ShareSheet(items: [UIImage(data: blob.data) as Any])
        }
    }

    struct ShareBlob: Identifiable { let data: Data; var id: Int { data.count } }

    private func how(_ medal: CabinetMedal) -> String {
        guard let holes = medal.holes, !holes.isEmpty else { return "" }
        let list = holes.map(String.init)
        return "Hole" + (holes.count > 1 ? "s " : " ") + ListFormatter.localizedString(byJoining: list)
    }

    private func load() async {
        let repo = CabinetRepository(client: env.client)
        guard let found = try? await repo.medals().first(where: { $0.id == medalID }) else { return }
        medal = found
        // The round it came from, drawn from the session's own state.
        if let session = try? await env.session(for: found.roundID) {
            let state = await session.currentState()
            let grid = GridScreenHost.model(from: state, nameStyle: .names, selectedPill: nil)
            scorecard = grid.scorecard
            if let opponentID = found.opponentProfileID {
                opponent = state.players.first { $0.profile_id == opponentID }?.display_name
            }
        }
    }

    @MainActor private func shareCard() {
        guard let scorecard else { return }
        share = ScorecardRenderer.pngData(model: scorecard)
    }
}

/// Who you could have a rivalry with, and the rivalry itself.
struct RivalsHost: View {
    @Environment(AppEnvironment.self) private var env
    @State private var rivals: [RivalSummary] = []
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            XIXBar(kicker: "RIVALS", title: "Rivals", onBack: { env.router.path.removeLast() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if loaded && rivals.isEmpty {
                        RivalryEmpty()
                    }
                    ForEach(rivals) { rival in
                        Button { env.router.path.append(.rivalry(rival.profileID)) } label: {
                            HStack(spacing: 14) {
                                Avatar(initials: ScorecardModel.initials(for: rival.displayName ?? "?"))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rival.displayName ?? "Someone").font(XIXType.body(16, weight: .semibold)).foregroundStyle(XIXColor.ink)
                                    Text("\(rival.rounds) round\(rival.rounds == 1 ? "" : "s") together").font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                                }
                                Spacer()
                                Text("›").font(XIXType.body(20)).foregroundStyle(XIXColor.faint)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("rival-\(rival.displayName ?? "")")
                    }
                }
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard await env.requireSignIn(reason: "Sign in to see your rivals") else { env.router.home(); return }
            rivals = (try? await CabinetRepository(client: env.client).rivals()) ?? []
            loaded = true
        }
    }
}

struct RivalryHost: View {
    let profileID: UUID
    @Environment(AppEnvironment.self) private var env
    @State private var model: RivalryModel?

    var body: some View {
        Group {
            if let model {
                RivalryScreen(model: model, onBack: { env.router.path.removeLast() })
            } else {
                XIXColor.sheet
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        guard let r = try? await CabinetRepository(client: env.client).rivalry(with: profileID) else { return }
        let them = r.them ?? "They"
        let medals = (r.myMedals + r.theirMedals).compactMap { medal -> MedalPatchModel? in
            guard let key = MedalKey(rawValue: medal.key) else { return nil }
            let p = key.patch
            return MedalPatchModel(id: "\(medal.roundID)-\(medal.key)", shape: p.shape, accent: key.accent,
                                   top: p.top, bottom: p.bottom, name: p.name, context: "vs \(them)")
        }
        model = RivalryModel(
            me: r.me ?? "You", them: them, myWins: r.myWins, theirWins: r.theirWins, rounds: r.rounds,
            streak: r.streak.map { "\($0.name.uppercased()) ON A \($0.count)-ROUND STREAK" },
            stats: [("MEDALS BETWEEN YOU", "\(r.myMedals.count + r.theirMedals.count)"),
                    ("THEY SIGNED", "\(r.theySigned)"),
                    ("THEY DUCKED", "\(r.theyDucked)")],
            medals: medals,
            lastFive: r.lastFive.map { round in
                RivalryModel.Round(id: round.roundID, course: round.course ?? "Round",
                                   date: Date.shortLabel(playedOn: round.playedOn), outcome: round.outcome,
                                   line: [round.myGross, round.theirGross].compactMap { $0 }.map(String.init).joined(separator: " to "),
                                   stickers: round.stickers)
            })
    }
}
