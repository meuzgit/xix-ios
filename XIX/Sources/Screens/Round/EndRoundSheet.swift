// End the round (Pass 7 §1): every cell in, or exactly which holes are open, with End anyway. Nothing
// is filled with par on anyone's behalf.
import SwiftUI
import XIXData
import XIXModels
import XIXUI

struct EndRoundSheet: View {
    let state: RoundSession.State
    let onEnd: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ending = false

    private struct RowGap { let player: LocalPlayer; let missing: [Int] }

    private var rows: [RowGap] {
        state.players.filter { $0.left_at == nil }.sorted { $0.seat < $1.seat }.map { p in
            RowGap(player: p, missing: (1...max(1, state.round.holes)).filter { h in state.score(player: p.id, hole: h).map { $0.strokes == nil && !$0.picked_up } ?? true })
        }
    }
    private var complete: Bool { rows.allSatisfy { $0.missing.isEmpty } }
    private var cells: Int { rows.count * state.round.holes }

    var body: some View {
        VStack(spacing: 0) {
            GreenBar("\(state.round.course_name?.uppercased() ?? "ROUND") · \(state.round.holes) HOLES", onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("End the round?").font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.ink).padding(20)
                    banner
                    ForEach(rows, id: \.player.id) { r in
                        HStack(spacing: 14) {
                            Avatar(initials: ScorecardModel.initials(for: r.player.display_name))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.player.display_name).font(XIXType.body(16, weight: .semibold)).foregroundStyle(XIXColor.ink)
                                Text(r.missing.isEmpty ? "\(state.round.holes) of \(state.round.holes)" : "Hole" + (r.missing.count > 1 ? "s " : " ") + r.missing.map(String.init).joined(separator: ", "))
                                    .font(XIXType.body(11.5)).foregroundStyle(r.missing.isEmpty ? XIXColor.muted : Color(hex: 0xB77B12))
                            }
                            Spacer()
                            Text(r.missing.isEmpty ? "IN" : "\(r.missing.count) OPEN").trackedCaps(8, weight: .bold).foregroundStyle(r.missing.isEmpty ? XIXColor.green : Color(hex: 0xB77B12))
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
                    }
                    Text(complete ? "Results are shared with everyone in the round and count for rankings once one other player confirms."
                                  : "Blank holes are left blank. Nothing gets filled with par on your behalf.")
                        .font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(20)
                }
            }
            VStack(spacing: 8) {
                if complete {
                    PrimaryButton(title: ending ? "Ending…" : "End round and see results", enabled: !ending) { Task { ending = true; await onEnd(); ending = false } }
                    SecondaryButton(title: "Not yet") { dismiss() }
                } else {
                    PrimaryButton(title: "Fill the missing holes") { dismiss() }
                    SecondaryButton(title: ending ? "Ending…" : "End anyway") { Task { ending = true; await onEnd(); ending = false } }
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 16)
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    private var banner: some View {
        let open = rows.reduce(0) { $0 + $1.missing.count }
        let names = rows.filter { !$0.missing.isEmpty }.map(\.player.display_name)
        return VStack(alignment: .leading, spacing: 6) {
            Text(complete ? "ALL \(cells) CELLS IN" : "\(open) CELL\(open == 1 ? "" : "S") STILL EMPTY").trackedCaps(9, weight: .bold)
                .foregroundStyle(complete ? XIXColor.faint : Color(hex: 0xFFD79A))
            Text(complete ? "Every player has a score on every hole. Ending now takes everyone in the round to the results."
                          : "\(names.joined(separator: ", ")) still ha\(names.count == 1 ? "s" : "ve") open holes. You can fill them, or end anyway and those holes stay blank in every game.")
                .font(XIXType.body(13)).foregroundStyle(XIXColor.onGreen.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(complete ? XIXColor.green : XIXColor.greenSoft))
        .padding(.horizontal, 12).padding(.bottom, 12)
    }
}
