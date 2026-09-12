// The boards and crews (Pass 6 6e, Pass 7 §4), bound to the repository.
import SwiftUI
import XIXData
import XIXModels
import XIXUI

struct RankingsHost: View {
    @Environment(AppEnvironment.self) private var env
    @State private var metric: RankingMetric = .stablefordVsLevel
    @State private var isCrew = false
    @State private var crews: [CrewSummary] = []
    @State private var crewIndex = 0
    @State private var rows: [RankingRow] = []
    @State private var pending: [PendingRound] = []
    @State private var busy = false
    @State private var error: String?

    private var crew: CrewSummary? { crews.indices.contains(crewIndex) ? crews[crewIndex] : nil }

    var body: some View {
        RankingsScreen(model: model, metrics: RankingMetric.allCases.map(\.title),
                       actions: RankingsActions(
                        pickTab: { crew in isCrew = crew; Task { await reload() } },
                        pickMetric: { title in
                            metric = RankingMetric.allCases.first { $0.title == title } ?? metric
                            Task { await reload() }
                        },
                        confirm: { id in Task { await answer(id, .confirm) } },
                        object: { id in Task { await answer(id, .object) } },
                        openRound: { id in env.router.path.append(.results(id)) },
                        invite: { invite() },
                        newCrew: { env.router.path.append(.crewNew) }),
                       onBack: { env.router.path.removeLast() })
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(item: Binding(get: { inviteLink.map { InviteLink(url: $0) } }, set: { if $0 == nil { inviteLink = nil } })) { link in
            ShareSheet(items: [link.url])
        }
    }

    @State private var inviteLink: URL?
    struct InviteLink: Identifiable { let url: URL; var id: String { url.absoluteString } }

    private var model: RankingsModel {
        RankingsModel(
            scope: isCrew ? (crew?.name ?? "No crew yet") : "Everyone",
            isCrew: isCrew,
            crewPrivateNote: isCrew,
            metric: metric.title,
            period: metric.window == "month" ? "THIS MONTH" : "ALL TIME",
            rows: rows.map { row in
                RankingsModel.Row(
                    id: row.profileID, rank: row.rank ?? 0, name: row.displayName ?? "Someone",
                    initials: ScorecardModel.initials(for: row.displayName ?? "?"),
                    sub: [row.rounds == 1 ? "1 round" : "\(row.rounds) rounds",
                          row.level.map { "Level \(String(format: "%.0f", $0))" }].compactMap { $0 }.joined(separator: " · "),
                    value: value(row.value), movement: row.movement, isMe: row.isMe)
            },
            pending: pending.map { p in
                RankingsModel.Pending(
                    id: p.roundID,
                    line: [p.course, Date.shortLabel(playedOn: p.playedOn), p.gross.map { "you \($0)" }].compactMap { $0 }.joined(separator: " · "),
                    waiting: p.objected
                        ? "This result is on hold. Both of you get the card to re-check; whoever fixes a cell, the other confirms."
                        : (p.confirmed
                           ? "You have confirmed it. Counts automatically in \(Int(p.hoursLeft.rounded())) hours."
                           : "Waiting on one other player. Counts automatically in \(Int(p.hoursLeft.rounded())) hours."),
                    frozen: p.objected)
            },
            footnote: error ?? "Results count once another player in the round confirms them, or after 48 hours.")
    }

    private func value(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func load() async {
        guard await env.requireSignIn(reason: "Sign in to see the boards") else { env.router.home(); return }
        crews = (try? await CabinetRepository(client: env.client).crews()) ?? []
        await reload()
    }

    private func reload() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let repo = CabinetRepository(client: env.client)
        do {
            rows = try await repo.rankings(metric, crewID: isCrew ? crew?.id : nil)
            pending = try await repo.pendingRounds()
            error = nil
        } catch {
            rows = []
            self.error = "Could not load the board: \(error.localizedDescription)"
        }
    }

    private func answer(_ roundID: UUID, _ action: ConfirmationAction) async {
        _ = try? await env.rounds.confirmRound(roundID: roundID, action: action)
        await reload()
    }

    private func invite() {
        guard let crew else { env.router.path.append(.crewNew); return }
        inviteLink = URL(string: "https://xix.golf/c/\(crew.joinCode)")
    }
}

/// Crew creation: name it, add people you have played with, done (Pass 7 §4).
struct CrewFlow: View {
    @Environment(AppEnvironment.self) private var env
    @State private var step = 0
    @State private var name = ""
    @State private var added: [CrewPeopleStep.Person] = []
    @State private var recent: [CrewPeopleStep.Person] = []
    @State private var crew: CrewSummary?
    @State private var error: String?

    var body: some View {
        Group {
            if step == 0 {
                CrewNameStep(name: $name, suggestions: suggestions, onNext: { Task { await create() } },
                             onBack: { env.router.path.removeLast() })
            } else {
                CrewPeopleStep(crewName: crew?.name ?? name, added: added, recent: recent,
                               link: "xix.golf/c/\(crew?.joinCode ?? "")",
                               onAdd: { person in Task { await add(person) } },
                               onRemove: { person in added.removeAll { $0.id == person.id } },
                               onDone: { env.router.replaceTop(with: .rankings) },
                               onBack: { step = 0 })
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadRecents() }
        .overlay(alignment: .bottom) {
            if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(12) }
        }
    }

    private var suggestions: [String] {
        var out = ["Sunday Foursome", "The Regulars"]
        if let course = env.client.store.recentCourses().first { out.insert("\(course) Regulars", at: 0) }
        return out
    }

    private func loadRecents() async {
        let rivals = (try? await CabinetRepository(client: env.client).rivals()) ?? []
        recent = rivals.map { .init(id: $0.profileID, name: $0.displayName ?? "Someone",
                                    sub: "\($0.rounds) round\($0.rounds == 1 ? "" : "s") together") }
    }

    private func create() async {
        guard await env.requireSignIn(reason: "Sign in to start a crew") else { return }
        do {
            crew = try await CabinetRepository(client: env.client).createCrew(name: name)
            step = 1
        } catch {
            self.error = "Could not create the crew: \(error.localizedDescription)"
        }
    }

    private func add(_ person: CrewPeopleStep.Person) async {
        guard let crew else { return }
        do {
            try await CabinetRepository(client: env.client).addToCrew(crewID: crew.id, profileID: person.id)
            added.append(person)
        } catch {
            self.error = "Could not add \(person.name): \(error.localizedDescription)"
        }
    }
}
