// The callout composer (PRD 8.6, Build Doc 3 step 3): kind, targets, and the one extra each kind needs
// — a goal for Target, a partner for Partner, a game for Double. The CALLED OUT banner previews itself
// as you choose, because the banner is what the others will see. Send hands the draft to `create_callout`.
//
// Every rule here is the server's rule, checked twice on purpose: the composer will not offer a draft
// the RPC would refuse, and the RPC refuses it anyway if it somehow arrives.
import Foundation
import SwiftUI
import XIXScoring

public struct CalloutDraft: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case target, duel, partner, multiplier
        public var id: String { rawValue }
        /// What the player calls it (PRD 8.6: Double, not multiplier).
        public var title: String {
            switch self {
            case .target: return "Target"
            case .duel: return "Duel"
            case .partner: return "Partner"
            case .multiplier: return "Double"
            }
        }
        public var rule: String {
            switch self {
            case .target: return "Name a number they have to beat on this hole"
            case .duel: return "You against one of them, low score on this hole"
            case .partner: return "Pick a partner, best ball against the rest"
            case .multiplier: return "This hole counts double in one of the games"
            }
        }
    }

    public enum Goal: Equatable, Sendable {
        case par, birdie, strokes(Int)
        public var label: String {
            switch self {
            case .par: return "Par"
            case .birdie: return "Birdie"
            case .strokes(let n): return "\(n) or better"
            }
        }
    }

    public var kind: Kind = .target
    public var targets: Set<UUID> = []
    public var goal: Goal = .par
    /// Partner callouts only; nil is the lone wolf.
    public var partner: UUID?
    /// Double only: the game this hole counts double in.
    public var game: UUID?

    public init() {}
}

/// Everything the composer needs to know about the round, built by the host from session state.
public struct CalloutComposerModel: Equatable, Sendable {
    public struct Player: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var initials: String
        public init(id: UUID, name: String, initials: String) { self.id = id; self.name = name; self.initials = initials }
    }
    public struct Game: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public init(id: UUID, name: String) { self.id = id; self.name = name }
    }

    public var hole: Int
    public var par: Int?
    /// Everyone still in the round, the caller included.
    public var players: [Player]
    public var games: [Game]
    public var callerID: UUID
    /// Players who already have a score on this hole: a callout with any of them is refused by the server.
    public var scored: Set<UUID>

    public init(hole: Int, par: Int?, players: [Player], games: [Game], callerID: UUID, scored: Set<UUID> = []) {
        self.hole = hole; self.par = par; self.players = players; self.games = games; self.callerID = callerID; self.scored = scored
    }

    public var caller: Player? { players.first { $0.id == callerID } }
    /// Everyone the caller can aim at. The caller is never a target (B.8.10).
    public var others: [Player] { players.filter { $0.id != callerID } }

    // MARK: The server's rules, before the round trip

    /// Why this draft cannot be sent yet, in the words the player would use. Nil means it is ready.
    public func problem(with draft: CalloutDraft) -> String? {
        let targets = draft.targets.subtracting([callerID])
        if targets.isEmpty { return "Pick who you are calling out." }
        if draft.kind == .duel && targets.count != 1 { return "A duel is one on one. Pick one player." }
        if draft.kind == .multiplier && draft.game == nil { return games.isEmpty ? "Doubling needs a game in this round." : "Pick the game this hole doubles." }
        if draft.kind == .partner, let partner = draft.partner, targets.contains(partner) {
            return "Your partner cannot be on the other side."
        }
        if case .strokes(let n) = draft.goal, draft.kind == .target, n < 1 { return "That is not a score." }
        // The hole closes to callouts the moment anyone in it has a score.
        let participants = targets.union([callerID])
        let already = participants.intersection(scored)
        if !already.isEmpty {
            let names = already.compactMap { id in players.first { $0.id == id }?.name }.sorted()
            return names.count == 1 ? "\(names[0]) has already scored this hole." : "\(names.joined(separator: " and ")) have already scored this hole."
        }
        return nil
    }

    public func canSend(_ draft: CalloutDraft) -> Bool { problem(with: draft) == nil }

    /// The params `create_callout` takes. Ids are lowercased because the engine compares them against
    /// the ids Postgres renders, which are lowercase.
    public func params(for draft: CalloutDraft) -> [String: String] {
        var out: [String: String] = [:]
        switch draft.kind {
        case .target:
            switch draft.goal {
            case .par: out["goal"] = "par"
            case .birdie: out["goal"] = "birdie"
            case .strokes(let n): out["goal"] = String(n)
            }
        case .partner:
            if let partner = draft.partner { out["partner_id"] = partner.uuidString.lowercased() }
        case .multiplier:
            // `factor` is left out on purpose: the engine's default is 2, which is what "Double" means.
            if let game = draft.game { out["game_id"] = game.uuidString.lowercased() }
        case .duel:
            break
        }
        return out
    }

    /// The banner the others will see, built from the draft so the preview is the real thing.
    public func preview(_ draft: CalloutDraft) -> HoleCardModel.Callout {
        let targets = draft.targets.subtracting([callerID]).compactMap { id in players.first { $0.id == id } }.sorted { $0.name < $1.name }
        let what: String
        switch draft.kind {
        case .target:
            switch draft.goal {
            case .par: what = "BEAT PAR ON \(hole)"
            case .birdie: what = "BIRDIE ON \(hole)"
            case .strokes(let n): what = "UNDER \(n + 1) ON \(hole)"
            }
        case .duel: what = "DUEL ON \(hole)"
        case .partner:
            let name = draft.partner.flatMap { id in players.first { $0.id == id }?.name }
            what = name.map { "PARTNER PICK ON \(hole) · WITH \($0.uppercased())" } ?? "ON MY OWN ON \(hole)"
        case .multiplier:
            let game = draft.game.flatMap { id in games.first { $0.id == id }?.name }
            what = game.map { "\($0.uppercased()) DOUBLE ON \(hole)" } ?? "DOUBLE ON \(hole)"
        }
        let callerName = caller?.name ?? "You"
        let who = "\(callerName) → \(targets.map(\.name).joined(separator: ", "))"
        return HoleCardModel.Callout(
            id: UUID(),
            detail: "\(what) · \(who) · EXPIRES ON SCORE".uppercased(),
            callerInitials: caller?.initials ?? "?",
            targets: targets.map { .init(id: $0.id, initials: $0.initials, state: .pending) },
            canRespond: false)
    }
}

public struct CalloutComposer: View {
    public let model: CalloutComposerModel
    public let onSend: (CalloutDraft) -> Void
    public let onClose: () -> Void
    /// Offscreen renders (snapshots) skip scroll views; pass false to lay the body out flat.
    public let scrolls: Bool
    @State private var draft = CalloutDraft()
    @State private var strokes = 4

    public init(model: CalloutComposerModel, onSend: @escaping (CalloutDraft) -> Void, onClose: @escaping () -> Void, scrolls: Bool = true) {
        self.model = model; self.onSend = onSend; self.onClose = onClose; self.scrolls = scrolls
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if scrolls {
                ScrollView { content }
            } else {
                content
                Spacer(minLength: 0)
            }
            footer
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
        .onAppear { if case .strokes(let n) = draft.goal { strokes = n } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            kinds
            targets
            extra
            preview
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CALL SOMEONE OUT").trackedCaps(10, weight: .bold).foregroundStyle(XIXColor.onGreen)
            Spacer()
            Text("HOLE \(model.hole)").trackedCaps(9).foregroundStyle(XIXColor.faint)
            Button(action: onClose) { Text("Close").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.cream) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composerClose")
        }
        .padding(.horizontal, 16).frame(height: XIXMetric.control)
        .frame(maxWidth: .infinity)
        .background(XIXColor.green)
    }

    private var kinds: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("What kind")
            ForEach(CalloutDraft.Kind.allCases) { kind in
                let blocked = kind == .multiplier && model.games.isEmpty
                Button {
                    draft.kind = kind
                    if kind == .duel, draft.targets.count > 1 { draft.targets = Set(draft.targets.prefix(1)) }
                    if kind == .multiplier, draft.game == nil { draft.game = model.games.first?.id }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.title).font(XIXType.body(15, weight: .semibold)).foregroundStyle(blocked ? XIXColor.faint : XIXColor.ink)
                            Text(blocked ? "No games in this round" : kind.rule).font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted)
                        }
                        Spacer()
                        if draft.kind == kind { Text("ON").trackedCaps(8, weight: .bold).foregroundStyle(XIXColor.green) }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
                }
                .buttonStyle(.plain)
                .disabled(blocked)
                .accessibilityIdentifier("kind-\(kind.rawValue)")
            }
        }
    }

    private var targets: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(draft.kind == .duel ? "Against" : "Who")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(model.others) { p in
                    let on = draft.targets.contains(p.id)
                    let isPartner = draft.kind == .partner && draft.partner == p.id
                    SelectChip(text: p.name, selected: on) {
                        if draft.kind == .duel {
                            draft.targets = on ? [] : [p.id]
                        } else if on {
                            draft.targets.remove(p.id)
                        } else {
                            draft.targets.insert(p.id)
                            if isPartner { draft.partner = nil }
                        }
                    }
                    .opacity(isPartner ? 0.4 : 1)
                    .accessibilityIdentifier("target-\(p.name)")
                }
            }
            .padding(.horizontal, 20)
            if draft.kind != .duel && model.others.count > 1 {
                Button {
                    draft.targets = Set(model.others.map(\.id)).subtracting([draft.partner].compactMap { $0 })
                } label: {
                    Text("Everyone").trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.green)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("target-everyone")
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private var extra: some View {
        switch draft.kind {
        case .target:
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("They have to make")
                HStack(spacing: 6) {
                    SelectChip(text: "Par", selected: draft.goal == .par) { draft.goal = .par }
                        .accessibilityIdentifier("goal-par")
                    SelectChip(text: "Birdie", selected: draft.goal == .birdie) { draft.goal = .birdie }
                        .accessibilityIdentifier("goal-birdie")
                    SelectChip(text: "\(strokes) or better", selected: isNumberGoal) { draft.goal = .strokes(strokes) }
                        .accessibilityIdentifier("goal-number")
                    if isNumberGoal {
                        Stepper("", value: $strokes, in: 1...12)
                            .labelsHidden()
                            .onChange(of: strokes) { _, n in draft.goal = .strokes(n) }
                    }
                }
                .padding(.horizontal, 20)
                if let par = model.par {
                    Text("Par is \(par) on this hole.").font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
                } else {
                    Text("Par is not set for this hole, so par and birdie cannot be judged. A number can.")
                        .font(XIXType.body(11.5)).foregroundStyle(Color(hex: 0xB77B12)).padding(.horizontal, 20)
                }
            }
        case .partner:
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Your partner")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                    SelectChip(text: "On my own", selected: draft.partner == nil) { draft.partner = nil }
                        .accessibilityIdentifier("partner-none")
                    ForEach(model.others) { p in
                        SelectChip(text: p.name, selected: draft.partner == p.id) {
                            draft.partner = p.id
                            draft.targets.remove(p.id)
                        }
                        .accessibilityIdentifier("partner-\(p.name)")
                    }
                }
                .padding(.horizontal, 20)
                Text(draft.partner == nil ? "On your own, the whole hole is yours to win." : "Best ball: your two against theirs.")
                    .font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
            }
        case .multiplier:
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Which game doubles")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(model.games) { g in
                        SelectChip(text: g.name, selected: draft.game == g.id) { draft.game = g.id }
                            .accessibilityIdentifier("game-\(g.name)")
                    }
                }
                .padding(.horizontal, 20)
                Text("Everyone you call has to sign it, or the hole counts once.")
                    .font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20)
            }
        case .duel:
            Text("Low score on this hole takes it. A tie is halved.")
                .font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted).padding(.horizontal, 20).padding(.top, 6)
        }
    }

    private var isNumberGoal: Bool { if case .strokes = draft.goal { return true } else { return false } }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("They will see")
            CalloutBanner(callout: model.preview(draft), width: 240, onSign: {}, onDuck: {})
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .padding(.bottom, 10)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let problem = model.problem(with: draft) {
                Text(problem).font(XIXType.body(12)).foregroundStyle(Color(hex: 0xB77B12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("composerProblem")
            }
            Button { onSend(draft) } label: {
                Text("Send it").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.onGreen)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(model.canSend(draft) ? XIXColor.green : XIXColor.faint))
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend(draft))
            .accessibilityIdentifier("composerSend")
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 18)
        .background(XIXColor.sheet)
        .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The contextual gate at the first callout attempt (Pass 6 6g, entry 2). The paywall itself is step 9;
/// this names what still works without paying and gets out of the way.
public struct CalloutGate: View {
    public let onClose: () -> Void
    public let onSeeFull: () -> Void

    public init(onClose: @escaping () -> Void, onSeeFull: @escaping () -> Void) {
        self.onClose = onClose; self.onSeeFull = onSeeFull
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CALLOUT").trackedCaps(8, weight: .bold).foregroundStyle(XIXColor.muted)
            Text("Calling someone out needs Full").font(XIXType.body(17, weight: .bold)).foregroundStyle(XIXColor.ink)
            Text("You can still receive one, sign it and duck it. Throwing the first one is the part that needs Full.")
                .font(XIXType.body(12.5)).foregroundStyle(XIXColor.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecondaryCapsule(title: "Not now", action: onClose)
                PrimaryCapsule(title: "See XIX Full", action: onSeeFull)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }
}

/// A pill that is either on or off. The composer's only control besides the kind list.
public struct SelectChip: View {
    public let text: String
    public var selected: Bool
    public let action: () -> Void

    public init(text: String, selected: Bool = false, action: @escaping () -> Void) {
        self.text = text; self.selected = selected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text).font(XIXType.body(13, weight: .semibold)).foregroundStyle(selected ? XIXColor.onGreen : XIXColor.ink)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(selected ? XIXColor.green : XIXColor.surface))
        }
        .buttonStyle(.plain)
    }
}

/// The two button weights, so the gate does not depend on the app target's chrome.
struct PrimaryCapsule: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.onGreen)
                .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(XIXColor.green))
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryCapsule: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(XIXType.body(14, weight: .semibold)).foregroundStyle(XIXColor.green)
                .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(XIXColor.surface))
        }
        .buttonStyle(.plain)
    }
}
