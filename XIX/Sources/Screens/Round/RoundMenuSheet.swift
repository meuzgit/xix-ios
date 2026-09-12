// The round menu (Pass 7 §1): a panel on white, plain list in the base type. Quiet mode for this
// round, Edit players and Edit games (owner), Export card, End round (owner), Leave round (non-owner).
// Snap the card and Import a screenshot arrive in step 7 and sit dimmed with the reason.
import SwiftUI
import XIXData
import XIXModels
import XIXUI

enum RoundMenuItem { case players, games, export, end, leave }

struct RoundMenuSheet: View {
    let roundID: UUID
    let isOwner: Bool
    let state: RoundSession.State?
    let onPick: (RoundMenuItem) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var quiet = false

    private var hole1Scored: Bool { state?.scores.contains { $0.hole == 1 && ($0.strokes != nil || $0.picked_up) } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("This round").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                Spacer()
                Button("Close") { dismiss() }.font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
            }
            .padding(.horizontal, 20).frame(height: 50)
            ScrollView {
                VStack(spacing: 0) {
                    ListRow("Quiet mode for this round", sub: quiet ? "On. Stickers sent to you are muted" : "Off. Overrides your default") {
                        InkToggle(on: Binding(get: { quiet }, set: { quiet = $0; env.setQuiet(roundID, $0) }))
                    }
                    if isOwner {
                        ListRow("Edit players", sub: "Rename, add a late guest, remove an unclaimed row", action: { onPick(.players) }) { chevron }
                        ListRow("Edit games", sub: hole1Scored ? "Locked. Hole 1 is scored" : "Before hole 1 is scored", dim: hole1Scored, action: { onPick(.games) }) { chevron }
                    }
                    ListRow("Snap the card", sub: "Arrives with step 7", dim: true)
                    ListRow("Import a screenshot", sub: "Arrives with step 7", dim: true)
                    ListRow("Export card", action: { onPick(.export) }) { chevron }
                    if isOwner {
                        ListRow("End round", sub: "Owner", action: { onPick(.end) }) { chevron }
                    } else {
                        ListRow("Leave round", danger: true, action: { onPick(.leave) }) { EmptyView() }
                    }
                }
            }
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
        .onAppear { quiet = env.isQuiet(roundID) }
    }

    private var chevron: some View { Text("›").font(XIXType.body(20)).foregroundStyle(XIXColor.faint) }
}
