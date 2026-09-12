// The rivalry (PRD 8.18, Pass 6 6d): the grudge on record. Two names, the head-to-head, a streak line
// that is the only loud thing on the screen, the medals between the two of you, and the last five
// rounds with the stickers that were actually thrown in them. Ink and patches; a sticker appears only
// because somebody threw it.
import SwiftUI

public struct RivalryModel: Equatable, Sendable {
    public struct Round: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var course: String
        public var date: String
        public var outcome: String          // "W", "L", "H"
        public var line: String             // "78 to 84"
        public var stickers: [String]
        public init(id: UUID, course: String, date: String, outcome: String, line: String, stickers: [String]) {
            self.id = id; self.course = course; self.date = date; self.outcome = outcome; self.line = line; self.stickers = stickers
        }
    }

    public var me: String
    public var them: String
    public var myWins: Int
    public var theirWins: Int
    public var rounds: Int
    public var streak: String?              // "RAY ON A 3-ROUND STREAK"
    public var stats: [(key: String, value: String)]
    public var medals: [MedalPatchModel]
    public var lastFive: [Round]

    public init(me: String, them: String, myWins: Int, theirWins: Int, rounds: Int, streak: String?,
                stats: [(key: String, value: String)], medals: [MedalPatchModel], lastFive: [Round]) {
        self.me = me; self.them = them; self.myWins = myWins; self.theirWins = theirWins; self.rounds = rounds
        self.streak = streak; self.stats = stats; self.medals = medals; self.lastFive = lastFive
    }

    public static func == (a: RivalryModel, b: RivalryModel) -> Bool {
        a.me == b.me && a.them == b.them && a.myWins == b.myWins && a.theirWins == b.theirWins
            && a.rounds == b.rounds && a.streak == b.streak && a.medals == b.medals && a.lastFive == b.lastFive
            && a.stats.map(\.key) == b.stats.map(\.key) && a.stats.map(\.value) == b.stats.map(\.value)
    }
}

public struct RivalryScreen: View {
    public let model: RivalryModel
    public let width: CGFloat
    public let scrolls: Bool
    public let onBack: (() -> Void)?

    public init(model: RivalryModel, width: CGFloat = XIXMetric.screenWidth, scrolls: Bool = true, onBack: (() -> Void)? = nil) {
        self.model = model; self.width = width; self.scrolls = scrolls; self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if scrolls { ScrollView { content } } else { content }
        }
        .frame(width: width)
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(XIXColor.onGreen)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Back")
                } else {
                    Text("XIX").trackedCaps(11, weight: .bold).foregroundStyle(XIXColor.onGreen)
                }
                Text("RIVALRY").trackedCaps(9).foregroundStyle(XIXColor.faint)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.me).font(XIXType.body(20, weight: .bold)).foregroundStyle(XIXColor.onGreen)
                    Text("\(model.myWins)").font(.system(size: 46, weight: .black)).foregroundStyle(XIXColor.onGreen)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(model.rounds)").font(XIXType.number(15, weight: .bold)).foregroundStyle(XIXColor.faint)
                    Text("ROUNDS").trackedCaps(8).foregroundStyle(XIXColor.faint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.them).font(XIXType.body(20, weight: .bold)).foregroundStyle(XIXColor.onGreen)
                    Text("\(model.theirWins)").font(.system(size: 46, weight: .black)).foregroundStyle(XIXColor.onGreen)
                }
            }
            if let streak = model.streak {
                Text(streak).trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.accent)
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XIXColor.green)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.stats.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(model.stats.enumerated()), id: \.offset) { _, stat in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stat.value).font(XIXType.number(20, weight: .bold)).foregroundStyle(XIXColor.ink)
                            Text(stat.key).trackedCaps(8).foregroundStyle(XIXColor.muted).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20)
            }
            if !model.medals.isEmpty {
                label("Medals between you")
                ScrollViewReaderIfNeeded(scrolls: scrolls) {
                    HStack(spacing: 12) {
                        ForEach(model.medals) { m in MedalPatch(model: m, size: 72) }
                    }
                    .padding(.horizontal, 20)
                }
            }
            if !model.lastFive.isEmpty {
                label("Last five")
                ForEach(model.lastFive) { round in
                    HStack(spacing: 12) {
                        Text(round.outcome).trackedCaps(10, weight: .bold)
                            .foregroundStyle(round.outcome == "W" ? XIXColor.onGreen : XIXColor.green)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(round.outcome == "W" ? XIXColor.green : XIXColor.surface))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(round.course).font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.ink)
                            Text("\(round.date) · \(round.line)").font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: -8) {
                            ForEach(Array(round.stickers.prefix(3).enumerated()), id: \.offset) { i, key in
                                StickerImage(key: key, size: 30, tilt: .degrees(i.isMultiple(of: 2) ? -6 : 5))
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
                }
            }
            Spacer(minLength: 30)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A horizontal strip that scrolls on screen and lays flat for an offscreen render.
struct ScrollViewReaderIfNeeded<Content: View>: View {
    let scrolls: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if scrolls {
            ScrollView(.horizontal, showsIndicators: false) { content() }
        } else {
            content().frame(maxWidth: .infinity, alignment: .leading).clipped()
        }
    }
}

/// The rivalry empty state (Pass 6 6d): the shape family, and one line saying when a rival appears.
public struct RivalryEmpty: View {
    public let width: CGFloat
    public init(width: CGFloat = XIXMetric.screenWidth) { self.width = width }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RIVALS").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                .padding(.horizontal, 20).padding(.top, 24)
            Text("A rival appears after two rounds with the same person. None yet.")
                .font(XIXType.body(13)).foregroundStyle(XIXColor.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.top, 8)
        }
        .frame(width: width, alignment: .leading)
    }
}
