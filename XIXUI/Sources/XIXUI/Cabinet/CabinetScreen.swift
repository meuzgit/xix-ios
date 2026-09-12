// The cabinet (PRD 8.18, Pass 6 6d): riso patches on white, newest season first, a season rule between
// them. Tapping one opens its context card. The empty state draws the silhouettes so the shape family
// reads before anything has been won.
import SwiftUI
import XIXScoring

public struct CabinetModel: Equatable, Sendable {
    public struct Season: Equatable, Sendable, Identifiable {
        public var label: String            // "2026 SEASON"
        public var medals: [Entry]
        public var id: String { label }
        public init(label: String, medals: [Entry]) { self.label = label; self.medals = medals }
    }
    public struct Entry: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var patch: MedalPatchModel
        public var when: String             // "9 Sep · vs Dave"
        public init(id: UUID, patch: MedalPatchModel, when: String) { self.id = id; self.patch = patch; self.when = when }
    }

    public var owner: String
    public var total: Int
    public var seasons: [Season]
    public init(owner: String, total: Int, seasons: [Season]) { self.owner = owner; self.total = total; self.seasons = seasons }
    public var isEmpty: Bool { seasons.allSatisfy { $0.medals.isEmpty } }
}

public struct CabinetScreen: View {
    public let model: CabinetModel
    public let width: CGFloat
    public let onTap: (CabinetModel.Entry) -> Void
    public let onBack: (() -> Void)?
    public let scrolls: Bool

    public init(model: CabinetModel, width: CGFloat = XIXMetric.screenWidth, scrolls: Bool = true,
                onTap: @escaping (CabinetModel.Entry) -> Void = { _ in }, onBack: (() -> Void)? = nil) {
        self.model = model; self.width = width; self.scrolls = scrolls; self.onTap = onTap; self.onBack = onBack
    }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 14), count: 3) }

    public var body: some View {
        VStack(spacing: 0) {
            XIXBar(kicker: model.isEmpty ? "\(model.owner.uppercased()) · NO MEDALS YET" : "\(model.owner.uppercased()) · \(model.total) MEDAL\(model.total == 1 ? "" : "S")",
                   title: "Cabinet", onBack: onBack)
            if scrolls { ScrollView { content } } else { content }
        }
        .frame(width: width)
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder private var content: some View {
        if model.isEmpty { empty } else { seasons }
    }

    private var seasons: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.seasons) { season in
                HStack {
                    Text(season.label).trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                    Spacer()
                    Text("\(season.medals.count) medal\(season.medals.count == 1 ? "" : "s")").trackedCaps(9).foregroundStyle(XIXColor.faint)
                }
                .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline).padding(.horizontal, 20) }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(season.medals) { entry in
                        Button { onTap(entry) } label: {
                            VStack(spacing: 6) {
                                MedalPatch(model: entry.patch, size: 88)
                                Text(entry.when).font(XIXType.body(10)).foregroundStyle(XIXColor.muted).lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("medal-\(entry.patch.name)")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16)
            }
            Spacer(minLength: 30)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The silhouettes, so the shape family reads before anything is won.
            HStack(spacing: 14) {
                ForEach(MedalShape.allCases, id: \.rawValue) { shape in
                    MedalSilhouette(shape: shape).stroke(XIXColor.hairline, lineWidth: 1.5).frame(width: 56, height: 56)
                }
            }
            .padding(.horizontal, 20).padding(.top, 30)
            Text("Nothing in here yet").font(XIXType.body(17, weight: .semibold)).foregroundStyle(XIXColor.ink)
                .padding(.horizontal, 20).padding(.top, 26)
            Text("Medals come out of games and callouts. Play a round with someone and the first one lands on the results screen.")
                .font(XIXType.body(13)).foregroundStyle(XIXColor.muted).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.top, 6)
            Spacer(minLength: 40)
        }
    }
}

/// The medal context card (Pass 7 §3): the patch large, its name, one context line, and the round it
/// came from drawn by the same renderer the export uses — so a medal is never an abstraction.
public struct MedalContextCard: View {
    public let patch: MedalPatchModel
    public let how: String                   // "Holes 6 and 14 · Fraserview · 13 Sep"
    public let scorecard: ScorecardModel?
    public let width: CGFloat
    public let scrolls: Bool
    public let onShare: () -> Void
    public let onBack: (() -> Void)?

    public init(patch: MedalPatchModel, how: String, scorecard: ScorecardModel?, width: CGFloat = XIXMetric.screenWidth,
                scrolls: Bool = true, onShare: @escaping () -> Void = {}, onBack: (() -> Void)? = nil) {
        self.patch = patch; self.how = how; self.scorecard = scorecard; self.width = width
        self.scrolls = scrolls; self.onShare = onShare; self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            XIXBar(kicker: "CABINET", title: nil, onBack: onBack)
            if scrolls { ScrollView { content } } else { content }
        }
        .frame(width: width)
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    private var content: some View {
        VStack(spacing: 0) {
            MedalPatch(model: patch, size: 132).padding(.top, 26)
            Text(patch.name).font(XIXType.body(22, weight: .bold)).foregroundStyle(XIXColor.ink).padding(.top, 16)
            Text(patch.context).trackedCaps(9).foregroundStyle(XIXColor.muted).padding(.top, 6)
                .multilineTextAlignment(.center)
            if !how.isEmpty {
                Text(how).font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(.horizontal, 30).padding(.top, 10)
                    .multilineTextAlignment(.center)
            }
            if let scorecard {
                Text("THE ROUND").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 10)
                ScorecardView(model: scorecard, width: min(width - 24, XIXMetric.chatWidth))
                    .background(RoundedRectangle(cornerRadius: 16).fill(XIXColor.sheet))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(XIXColor.hairline, lineWidth: 1))
                    .padding(.horizontal, 12)
            }
            Button(action: onShare) {
                Text("Share").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.onGreen)
                    .frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(XIXColor.green))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.top, 24).padding(.bottom, 24)
            .accessibilityIdentifier("shareMedal")
        }
    }
}

/// The green bar these screens share: a kicker, an optional big title, an optional back chevron.
public struct XIXBar: View {
    public let kicker: String
    public let title: String?
    public let onBack: (() -> Void)?

    public init(kicker: String, title: String?, onBack: (() -> Void)? = nil) {
        self.kicker = kicker; self.title = title; self.onBack = onBack
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(XIXColor.onGreen)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                } else {
                    Text("XIX").trackedCaps(11, weight: .bold).foregroundStyle(XIXColor.onGreen)
                }
                Text(kicker).trackedCaps(9).foregroundStyle(XIXColor.faint).lineLimit(1)
                Spacer()
            }
            if let title {
                Text(title).font(.system(size: 30, weight: .black)).foregroundStyle(XIXColor.onGreen)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, title == nil ? 12 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XIXColor.green)
    }
}
