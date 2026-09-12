// Rankings (PRD 8.19, Pass 6 6e): the same leaderboard as the round strip, at full height. Global and
// Crew as two tabs, a metric pill row, and rows of rank, person, "rounds · Level", a movement caret in
// ink and the metric right-aligned. The pending row is the only warm surface in the app, and it is
// there because a result waiting on somebody is the one thing worth interrupting for.
import SwiftUI

public struct RankingsModel: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var rank: Int
        public var name: String
        public var initials: String
        public var sub: String              // "11 rounds · Level 5"
        public var value: String
        public var movement: Int            // + up, − down, 0 level
        public var isMe: Bool
        public init(id: UUID, rank: Int, name: String, initials: String, sub: String, value: String, movement: Int, isMe: Bool) {
            self.id = id; self.rank = rank; self.name = name; self.initials = initials
            self.sub = sub; self.value = value; self.movement = movement; self.isMe = isMe
        }
    }
    public struct Pending: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var line: String             // "Fraserview · 13 Sep · Mo 88"
        public var waiting: String          // "Waiting on one other player. Counts automatically in 41 hours."
        public var frozen: Bool             // somebody objected
        public init(id: UUID, line: String, waiting: String, frozen: Bool) {
            self.id = id; self.line = line; self.waiting = waiting; self.frozen = frozen
        }
    }

    public var scope: String                // "GLOBAL" or the crew's name
    public var isCrew: Bool
    public var crewPrivateNote: Bool
    public var metric: String
    public var period: String               // "ALL TIME" / "THIS MONTH"
    public var rows: [Row]
    public var pending: [Pending]
    public var footnote: String

    public init(scope: String, isCrew: Bool, crewPrivateNote: Bool = false, metric: String, period: String,
                rows: [Row], pending: [Pending], footnote: String) {
        self.scope = scope; self.isCrew = isCrew; self.crewPrivateNote = crewPrivateNote
        self.metric = metric; self.period = period; self.rows = rows; self.pending = pending; self.footnote = footnote
    }
}

public struct RankingsActions {
    public var pickTab: (Bool) -> Void       // true = crew
    public var pickMetric: (String) -> Void
    public var confirm: (UUID) -> Void
    public var object: (UUID) -> Void
    public var openRound: (UUID) -> Void
    public var invite: () -> Void
    public var newCrew: () -> Void

    public init(pickTab: @escaping (Bool) -> Void = { _ in }, pickMetric: @escaping (String) -> Void = { _ in },
                confirm: @escaping (UUID) -> Void = { _ in }, object: @escaping (UUID) -> Void = { _ in },
                openRound: @escaping (UUID) -> Void = { _ in }, invite: @escaping () -> Void = {},
                newCrew: @escaping () -> Void = {}) {
        self.pickTab = pickTab; self.pickMetric = pickMetric; self.confirm = confirm; self.object = object
        self.openRound = openRound; self.invite = invite; self.newCrew = newCrew
    }
    public static let none = RankingsActions()
}

public struct RankingsScreen: View {
    public let model: RankingsModel
    public let metrics: [String]
    public let width: CGFloat
    public let scrolls: Bool
    public let actions: RankingsActions
    public let onBack: (() -> Void)?

    public init(model: RankingsModel, metrics: [String], width: CGFloat = XIXMetric.screenWidth, scrolls: Bool = true,
                actions: RankingsActions = .none, onBack: (() -> Void)? = nil) {
        self.model = model; self.metrics = metrics; self.width = width; self.scrolls = scrolls
        self.actions = actions; self.onBack = onBack
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
                Spacer()
                Text(model.period).trackedCaps(9).foregroundStyle(XIXColor.faint)
            }
            HStack(spacing: 6) {
                tab("Global", on: !model.isCrew) { actions.pickTab(false) }
                tab("Crew", on: model.isCrew) { actions.pickTab(true) }
            }
            Text(model.isCrew ? "CREW · PRIVATE" : "GLOBAL").trackedCaps(9).foregroundStyle(XIXColor.faint)
            Text(model.scope).font(.system(size: 26, weight: .black)).foregroundStyle(XIXColor.onGreen).lineLimit(1)
            if scrolls {
                ScrollView(.horizontal, showsIndicators: false) { pills }
            } else {
                pills
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XIXColor.green)
    }

    private var pills: some View {
        HStack(spacing: 6) {
            ForEach(metrics, id: \.self) { metric in
                Button { actions.pickMetric(metric) } label: {
                    Text(metric).trackedCaps(9, weight: .bold)
                        .foregroundStyle(metric == model.metric ? XIXColor.green : XIXColor.onGreen)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Capsule().fill(metric == model.metric ? XIXColor.cream : XIXColor.greenSoft))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("metric-\(metric)")
            }
        }
    }

    private func tab(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).trackedCaps(9, weight: .bold).foregroundStyle(on ? XIXColor.green : XIXColor.onGreen)
                .padding(.horizontal, 14).frame(height: 28)
                .background(Capsule().fill(on ? XIXColor.cream : XIXColor.greenSoft))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(title)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.pending) { pending in pendingRow(pending) }
            if model.rows.isEmpty {
                Text(model.isCrew ? "Nothing to rank yet" : "No rounds have counted yet")
                    .trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
                    .padding(.horizontal, 20).padding(.top, 24)
                Text(model.isCrew
                     ? "Numbers appear as each person plays a round. No round of yours is needed to start the board."
                     : "A round counts once another player in it confirms, or after 48 hours.")
                    .font(XIXType.body(12.5)).foregroundStyle(XIXColor.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20).padding(.top, 6)
            }
            ForEach(model.rows) { row in rankRow(row) }
            if model.isCrew {
                VStack(spacing: 8) {
                    Button(action: actions.invite) {
                        Text("Invite to this crew").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.onGreen)
                            .frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(XIXColor.green))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("inviteToCrew")
                    Button(action: actions.newCrew) {
                        Text("New crew").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.green)
                            .frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(XIXColor.surface))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("newCrew")
                }
                .padding(.horizontal, 12).padding(.top, 24)
                if model.crewPrivateNote {
                    Text("Nobody has to play the same course or the same day. A round anywhere counts here.")
                        .font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                        .padding(.horizontal, 20).padding(.top, 12)
                }
            }
            // The empty state already says how a round comes to count; saying it twice reads as a stutter.
            if !model.rows.isEmpty || model.isCrew {
                Text(model.footnote).font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 30)
            } else {
                Spacer(minLength: 30)
            }
        }
    }

    private func rankRow(_ row: RankingsModel.Row) -> some View {
        HStack(spacing: 12) {
            Text("\(row.rank)").font(XIXType.number(13, weight: .bold)).foregroundStyle(XIXColor.muted)
                .frame(width: 22, alignment: .trailing)
            Text(row.initials).trackedCaps(9, weight: .bold)
                .foregroundStyle(row.isMe ? XIXColor.onGreen : XIXColor.green)
                .frame(width: 30, height: 30)
                .background(Circle().fill(row.isMe ? XIXColor.green : XIXColor.cream).overlay(Circle().strokeBorder(XIXColor.green, lineWidth: 1)))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(XIXType.body(15, weight: row.isMe ? .bold : .semibold)).foregroundStyle(XIXColor.ink).lineLimit(1)
                Text(row.sub).font(XIXType.body(11)).foregroundStyle(XIXColor.muted)
            }
            Spacer(minLength: 0)
            if row.movement != 0 {
                Text(row.movement > 0 ? "▲" : "▼").font(.system(size: 9)).foregroundStyle(XIXColor.ink)
            }
            Text(row.value).font(XIXType.number(17, weight: .bold)).foregroundStyle(XIXColor.ink)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(row.isMe ? XIXColor.surface : XIXColor.sheet)
        .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
        .accessibilityIdentifier("rank-\(row.name)")
    }

    private func pendingRow(_ pending: RankingsModel.Pending) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pending.frozen ? "FROZEN" : "PENDING · NOT COUNTED YET").trackedCaps(8, weight: .bold)
                .foregroundStyle(Color(hex: 0xB77B12))
            Text(pending.line).font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.ink)
            Text(pending.waiting).font(XIXType.body(12)).foregroundStyle(XIXColor.muted).fixedSize(horizontal: false, vertical: true)
            if pending.frozen {
                Button { actions.openRound(pending.id) } label: {
                    Text("Open the card").font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                        .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(XIXColor.sheet))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Button { actions.confirm(pending.id) } label: {
                        Text("Confirm").font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.onGreen)
                            .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(XIXColor.green))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("confirmRound")
                    Button { actions.object(pending.id) } label: {
                        Text("I object").font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                            .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(XIXColor.sheet))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("objectRound")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: 0xFFF6E6)))
        .padding(.horizontal, 12).padding(.top, 14)
    }
}
