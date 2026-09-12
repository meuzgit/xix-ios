// The results screen (PRD 8.9, Pass 2 2e, Pass 6 6c): green header with the headline, then medals as
// patches, games, callouts, highlights, stickers received and Rival Points in straight broadcast type.
// Share and Back are the app's; the screen only draws.
import SwiftUI

public struct ResultsActions {
    public var share: () -> Void
    public var back: () -> Void
    public var confirm: () -> Void
    public init(share: @escaping () -> Void, back: @escaping () -> Void, confirm: @escaping () -> Void) {
        self.share = share; self.back = back; self.confirm = confirm
    }
    public static let none = ResultsActions(share: {}, back: {}, confirm: {})
}

public struct ResultsScreen: View {
    public let model: ResultsModel
    public let width: CGFloat
    public let actions: ResultsActions
    public let scrolls: Bool

    public init(model: ResultsModel, width: CGFloat = XIXMetric.screenWidth, actions: ResultsActions = .none, scrolls: Bool = true) {
        self.model = model; self.width = width; self.actions = actions; self.scrolls = scrolls
    }

    public var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }
        .frame(width: width)
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            if let c = model.confirm { confirmCard(c) }
            if !model.medals.isEmpty { medals }
            if !model.games.isEmpty { games }
            if !model.callouts.isEmpty { callouts }
            if !model.highlights.isEmpty { highlights }
            stickersLine
            buttons
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("XIX").trackedCaps(11, weight: .bold).foregroundStyle(XIXColor.onGreen)
                Spacer()
                Text(model.kicker).trackedCaps(9).foregroundStyle(XIXColor.faint).lineLimit(1)
            }
            Text(model.title).font(.system(size: 34, weight: .black)).foregroundStyle(XIXColor.onGreen).padding(.top, 8)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(model.headline).font(XIXType.hero).foregroundStyle(XIXColor.onGreen)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.headlineSub).trackedCaps(10, weight: .bold).foregroundStyle(XIXColor.onGreen)
                    if !model.gamesLine.isEmpty { Text(model.gamesLine).trackedCaps(9).foregroundStyle(XIXColor.faint).lineLimit(2) }
                }
            }
            if model.pending {
                HStack(spacing: 8) {
                    Rectangle().fill(XIXColor.accent).frame(width: 3, height: 12)
                    Text("Waiting for the final result").trackedCaps(9).foregroundStyle(XIXColor.faint)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XIXColor.green)
    }

    private func confirmCard(_ c: ResultsModel.ConfirmCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(c.label).trackedCaps(9, weight: .bold).foregroundStyle(c.done ? XIXColor.cream : XIXColor.faint)
            Text(c.title).font(XIXType.body(20, weight: .bold)).foregroundStyle(XIXColor.onGreen)
            Text(c.body).font(XIXType.body(13)).foregroundStyle(XIXColor.onGreen.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            Button(action: actions.confirm) {
                Text(c.button).font(XIXType.body(15, weight: .bold))
                    .foregroundStyle(c.done ? XIXColor.onGreen : XIXColor.green)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(c.done ? Color.white.opacity(0.16) : XIXColor.cream))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Text(c.foot).font(XIXType.body(11)).foregroundStyle(XIXColor.onGreen.opacity(0.5))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: XIXMetric.cardRadius).fill(c.done ? XIXColor.greenSoft : XIXColor.green))
        .padding(.horizontal, 12).padding(.top, 12)
    }

    // MARK: Sections

    private func sectionLabel(_ text: String) -> some View {
        Text(text).trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medals: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Medals unlocked")
            if scrolls {
                ScrollView(.horizontal, showsIndicators: false) { medalRow }
            } else {
                medalRow.frame(width: width, alignment: .leading).clipped()
            }
        }
    }

    private var medalRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(model.medals) { m in
                VStack(spacing: 6) {
                    MedalPatch(model: m, size: 92)
                    Text(m.name).font(XIXType.body(11.5, weight: .semibold)).foregroundStyle(XIXColor.ink).lineLimit(2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(m.context).font(XIXType.body(10)).foregroundStyle(XIXColor.muted).lineLimit(2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 104)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var games: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Games")
            ForEach(model.games) { g in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(g.name).font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.ink)
                        Text(g.who).font(XIXType.body(12)).foregroundStyle(XIXColor.muted).lineLimit(2)
                    }
                    Spacer()
                    if !g.tag.isEmpty { Text(g.tag).trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.green) }
                }
                .padding(.horizontal, 20).padding(.vertical, 11)
                .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
            }
        }
    }

    private var callouts: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Callouts")
            ForEach(model.callouts) { c in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.title).font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.ink)
                        Text(c.sub).font(XIXType.body(12)).foregroundStyle(XIXColor.muted)
                    }
                    Spacer()
                    Text(c.mark).trackedCaps(9, weight: .bold).foregroundStyle(c.mark.hasPrefix("DUCKED") ? XIXColor.muted : XIXColor.green)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 20).padding(.vertical, 11)
                .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
            }
        }
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Highlights")
            HStack(alignment: .top, spacing: 0) {
                ForEach(model.highlights.prefix(4)) { h in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.key).trackedCaps(8).foregroundStyle(XIXColor.muted)
                        Text(h.value).font(XIXType.number(15, weight: .bold)).foregroundStyle(XIXColor.ink).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var stickersLine: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Stickers received").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                Spacer()
                if let rp = model.rivalPoints { Text("Rival Points \(rp >= 0 ? "+" : "")\(rp)").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.accent) }
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)
            if model.stickersReceived.isEmpty {
                Text("None thrown your way").font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
            } else {
                HStack(spacing: -10) {
                    ForEach(Array(model.stickersReceived.enumerated()), id: \.offset) { i, key in
                        StickerImage(key: key, size: 52, tilt: .degrees(i.isMultiple(of: 2) ? -8 : 7))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            Button(action: actions.share) {
                Text("Share results").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.onGreen)
                    .frame(maxWidth: .infinity).frame(height: XIXMetric.control).background(Capsule().fill(XIXColor.green))
            }
            .buttonStyle(.plain)
            Button(action: actions.back) {
                Text("Back to card").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.green)
                    .frame(maxWidth: .infinity).frame(height: XIXMetric.control).background(Capsule().strokeBorder(XIXColor.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.top, 24).padding(.bottom, 20)
    }
}
