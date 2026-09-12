// The live leaderboard strip on the green (PRD 8.3): the active game by default, Gross as a pill the
// user switches to. Never shows "+16" next to a casual player unless Gross is selected.
import SwiftUI

public struct LeaderboardStripView: View {
    public let pills: [GridScreenModel.Pill]
    @Binding public var selected: String?

    public init(pills: [GridScreenModel.Pill], selected: Binding<String?>) {
        self.pills = pills
        self._selected = selected
    }

    private var current: GridScreenModel.Pill? { pills.first { $0.id == selected } ?? pills.first }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A plain row: four pills fit a phone width, and offscreen renders skip scroll views.
            HStack(spacing: 6) {
                ForEach(pills) { pill in
                    Button { selected = pill.id } label: {
                        Text(pill.label)
                            .trackedCaps(9, weight: .bold)
                            .foregroundStyle(pill.id == current?.id ? XIXColor.green : XIXColor.onGreen)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(pill.id == current?.id ? XIXColor.onGreen : XIXColor.greenSoft))
                    }
                        .buttonStyle(.plain)
                }
            }
            if let pill = current {
                VStack(spacing: 3) {
                    ForEach(pill.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            if let rank = row.rank {
                                Text("\(rank)").font(XIXType.number(10)).foregroundStyle(XIXColor.faint).frame(width: 12, alignment: .trailing)
                            }
                            Text(row.name).font(XIXType.body(13, weight: .semibold)).foregroundStyle(XIXColor.onGreen).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(row.value).font(XIXType.number(13, weight: .bold)).foregroundStyle(XIXColor.onGreen).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
    }
}
