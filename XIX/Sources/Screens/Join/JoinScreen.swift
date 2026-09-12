// Join by link (PRD 8.17, Pass 6 6c): the code resolves to the join screen; with a row already yours
// you go straight in; a claimable row is claimed with one tap and lands on the current hole; an ended
// round goes to results with the confirm card. Identity is asked for here, since a join needs one.
import SwiftUI
import XIXData
import XIXModels
import XIXUI

struct JoinScreen: View {
    let code: String
    @Environment(AppEnvironment.self) private var env
    @State private var screen: JoinScreen_?
    @State private var error: String?
    @State private var claiming = false
    @State private var resultLink: (row: UUID, owner: String)?

    typealias JoinScreen_ = XIXData.JoinScreen

    var body: some View {
        Group {
            if let r = resultLink {
                ResultsHost(roundID: screen!.round.id, claimRow: r.row, ownerName: r.owner)
            } else {
                VStack(spacing: 0) {
                    GreenBar("JOINING", onBack: { env.router.home() })
                    if let screen { content(screen) } else if let error { failed(error) } else { Text("Finding the round…").font(XIXType.body(14)).foregroundStyle(XIXColor.muted).padding(30) }
                    Spacer()
                }
            }
        }
        .background(XIXColor.sheet)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        guard await env.requireSignIn(reason: "Sign in to join the round") else { env.router.home(); return }
        do {
            let s = try await env.rounds.joinScreen(code: code)
            screen = s
            if let mine = s.players.first(where: { $0.mine }) {
                _ = mine
                env.router.replaceTop(with: s.round.status == "ended" ? .results(s.round.id) : .round(s.round.id))
            }
        } catch {
            self.error = "No round for \(code). The link may be old, or the round was deleted."
        }
    }

    private func content(_ s: JoinScreen_) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(s.round.owner ?? "Someone") asked you\nto play").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(20)
            Text("\(s.round.course ?? "A round") · \(Date.shortLabel(playedOn: s.round.playedOn))\(s.round.status == "ended" ? " · ended" : "")")
                .font(XIXType.body(14)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
            ForEach(s.players, id: \.id) { p in
                HStack(spacing: 14) {
                    Avatar(initials: ScorecardModel.initials(for: p.displayName))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.displayName).font(XIXType.body(16, weight: .semibold)).foregroundStyle(XIXColor.ink)
                        Text(p.claimable ? "Open row · by name" : "Has XIX").font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
            }
            .padding(.top, 8)
            if s.claimable.isEmpty {
                Text("Every row is taken. Ask \(s.round.owner ?? "the owner") to add you from the round menu.").font(XIXType.body(13)).foregroundStyle(XIXColor.muted).padding(20)
            } else {
                claimCard(s)
            }
            if let error { Text(error).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xD8332B)).padding(.horizontal, 20) }
        }
    }

    private func claimCard(_ s: JoinScreen_) -> some View {
        let owner = s.round.owner ?? "The owner"
        let ended = s.round.status == "ended"
        return VStack(alignment: .leading, spacing: 8) {
            let rows = s.claimable
            if rows.count == 1, let r = rows.first {
                Text("\(owner.uppercased()) PUT YOU IN AS “\(r.displayName.uppercased())”").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.green)
                Text(ended ? "The round has ended. Claim the row and the scores \(owner) kept are yours to confirm."
                           : "Claim the row and you score it yourself from here. Holes already scored stay as \(owner) entered them.")
                    .font(XIXType.body(13)).foregroundStyle(XIXColor.ink)
                PrimaryButton(title: claiming ? "Claiming…" : (ended ? "See my scores" : "Claim this row"), enabled: !claiming) { Task { await claim(r, s) } }.padding(.top, 6)
            } else {
                Text("WHICH ROW IS YOURS?").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.green)
                ForEach(rows, id: \.id) { r in
                    SecondaryButton(title: r.displayName) { Task { await claim(r, s) } }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(XIXColor.cream))
        .padding(12)
    }

    private func failed(_ e: String) -> some View {
        VStack(spacing: 12) {
            Text(e).font(XIXType.body(14)).foregroundStyle(XIXColor.muted).padding(20)
            SecondaryButton(title: "Back") { env.router.home() }.padding(.horizontal, 12)
        }
    }

    private func claim(_ r: JoinScreen_.Player, _ s: JoinScreen_) async {
        claiming = true; defer { claiming = false }
        if s.round.status == "ended" {
            // Result link: the claim happens with the confirm.
            resultLink = (r.id, s.round.owner ?? "the owner")
            return
        }
        do {
            _ = try await env.rounds.claimRow(roundID: s.round.id, playerID: r.id)
            env.router.replaceTop(with: .round(s.round.id))
        } catch {
            self.error = "Could not claim the row: \(error.localizedDescription)"
        }
    }
}
