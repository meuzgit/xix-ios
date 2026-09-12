// Layer 1, the grid (Build Doc 2 D.3): green header with the leaderboard strip, the two nine-hole
// blocks from the shared renderer, "Play hole N", and a one-line toast for merge notices.
import SwiftUI

public struct GridScreen: View {
    public var model: GridScreenModel
    @Binding public var selectedPill: String?
    public let width: CGFloat
    public let onOpenHole: (Int) -> Void

    public init(model: GridScreenModel, selectedPill: Binding<String?>, width: CGFloat = XIXMetric.screenWidth, onOpenHole: @escaping (Int) -> Void) {
        self.model = model
        self._selectedPill = selectedPill
        self.width = width
        self.onOpenHole = onOpenHole
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                GridScreenContent(model: model, selectedPill: $selectedPill, width: width, onOpenHole: onOpenHole)
            }
            .background(XIXColor.sheet)
            if let notice = model.notice {
                NoticeToast(text: notice).padding(.top, 8)
            }
        }
        .frame(width: width)
        .environment(\.colorScheme, .light)
    }
}

/// The grid screen without its scroller: header, strip, sheet and the play button. Snapshots render this.
public struct GridScreenContent: View {
    public var model: GridScreenModel
    @Binding public var selectedPill: String?
    public let width: CGFloat
    public let onOpenHole: (Int) -> Void

    public init(model: GridScreenModel, selectedPill: Binding<String?>, width: CGFloat = XIXMetric.screenWidth, onOpenHole: @escaping (Int) -> Void) {
        self.model = model
        self._selectedPill = selectedPill
        self.width = width
        self.onOpenHole = onOpenHole
    }

    public var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                ScorecardView(model: model.scorecard, width: width, showsHeader: false, onTapHole: onOpenHole)
                playHole
            }
            if let notice = model.notice {
                NoticeToast(text: notice).padding(.top, 8)
            }
        }
        .frame(width: width)
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("XIX").trackedCaps(11, weight: .bold).foregroundStyle(XIXColor.onGreen)
                Spacer()
                Text(model.scorecard.dateLabel).trackedCaps(9).foregroundStyle(XIXColor.faint)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(model.scorecard.courseName).font(XIXType.body(17, weight: .semibold)).foregroundStyle(XIXColor.onGreen).lineLimit(1)
                Spacer()
                if model.currentHole != nil {
                    Text("LIVE").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.accent)
                }
            }
            LeaderboardStripView(pills: model.pills, selected: $selectedPill)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XIXColor.green)
    }

    private var playHole: some View {
        Group {
            if let hole = model.currentHole {
                Button { onOpenHole(hole) } label: {
                    Text("Play hole \(hole)")
                        .font(XIXType.body(15, weight: .semibold))
                        .foregroundStyle(XIXColor.onGreen)
                        .frame(maxWidth: .infinity)
                        .frame(height: XIXMetric.control)
                        .background(Capsule().fill(XIXColor.green))
                }
                .buttonStyle(.plain)
            } else {
                Text("Every hole is in").trackedCaps(9).foregroundStyle(XIXColor.muted).frame(height: XIXMetric.control)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

/// One quiet line of ink for a merge notice ("Dave changed hole 6"). Green line on cream, no die-cut.
public struct NoticeToast: View {
    public let text: String
    public init(text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(XIXType.body(12, weight: .medium))
            .foregroundStyle(XIXColor.green)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(XIXColor.cream).overlay(Capsule().strokeBorder(XIXColor.green, lineWidth: 1)))
    }
}
