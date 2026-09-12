// Layer 2, the hole card (PRD 8.3, Build Doc 2 D.4): one hole per screen, white edge to edge, the
// green chrome as a thin header. Rows carry the game standing under the name and a large score box;
// stickers pin on the score side and never over names or digits. Panels rise on white; nothing dims.
import SwiftUI

public struct HoleCardView: View {
    public var model: HoleCardModel
    public let width: CGFloat
    public let actions: HoleCardActions
    /// Offscreen renders (snapshots, exports) skip scroll views; pass false to lay the body out flat.
    public let scrolls: Bool
    /// A control the app places in the header before the menu (the grid/card switch).
    public let headerAccessory: AnyView?
    @State private var lifted: UUID? = nil

    public init(model: HoleCardModel, width: CGFloat = XIXMetric.screenWidth, actions: HoleCardActions = .none, scrolls: Bool = true,
                headerAccessory: AnyView? = nil) {
        self.model = model; self.width = width; self.actions = actions; self.scrolls = scrolls; self.headerAccessory = headerAccessory
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if scrolls {
                ScrollView { sheet }
            } else {
                sheet
                Spacer(minLength: 0)
            }
            panel
            holeStrip
        }
        .frame(width: width)
        .background(XIXColor.sheet)
        .overlay(alignment: .top) { if let n = model.notice { NoticeToast(text: n).padding(.top, 52) } }
        .environment(\.colorScheme, .light)
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            inPlayStrip
            rows
            if !model.events.isEmpty { inkLine }
            if let callout = model.callout {
                CalloutBanner(callout: callout, width: min(260, width - 80),
                              onSign: { actions.respond(callout.id, .signed) }, onDuck: { actions.respond(callout.id, .ducked) })
                    .padding(.top, 14)
            }
            if let nudge = model.nudge { nudgeLine(nudge) }
            calloutStub
            Spacer(minLength: 12)
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("HOLE").trackedCaps(9).foregroundStyle(XIXColor.faint)
            Text("\(model.hole)").font(XIXType.number(24, weight: .bold)).foregroundStyle(XIXColor.onGreen)
            if let par = model.par { Text("PAR \(par)").trackedCaps(9).foregroundStyle(XIXColor.onGreen) }
            if let si = model.strokeIndex { Text("SI \(si)").trackedCaps(9).foregroundStyle(XIXColor.faint) }
            if let y = model.yards { Text("\(y) YDS").trackedCaps(9).foregroundStyle(XIXColor.faint) }
            Spacer()
            if let headerAccessory { headerAccessory } else { Text("\(model.hole) OF \(model.holes)").trackedCaps(9).foregroundStyle(XIXColor.faint) }
            if let menu = actions.menu { MenuDots(action: menu) }
        }
        .padding(.horizontal, 16).frame(height: XIXMetric.control)
        .background(XIXColor.green)
    }

    private var inPlayStrip: some View {
        HStack {
            if model.inPlay.isEmpty {
                Text("No games on this hole").trackedCaps(9).foregroundStyle(XIXColor.muted)
            } else {
                Rectangle().fill(XIXColor.accent).frame(width: 3, height: 12)
                Text(model.inPlay).trackedCaps(9).foregroundStyle(XIXColor.ink).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16).frame(height: 30)
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(model.rows) { row in
                HStack(spacing: 12) {
                    avatar(row.initials, me: row.isMe)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name).font(XIXType.body(17, weight: .semibold)).foregroundStyle(XIXColor.ink).lineLimit(1)
                        // The standing line is the sacrificial element under stickers.
                        Text(row.standing.isEmpty ? " " : row.standing).trackedCaps(9).foregroundStyle(XIXColor.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    stickerZone(row)
                    scoreBox(row)
                }
                .padding(.horizontal, 16)
                .frame(height: 76)
                .overlay(alignment: .bottom) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline).padding(.leading, 60) }
            }
        }
    }

    private func avatar(_ initials: String, me: Bool) -> some View {
        Text(initials).trackedCaps(10, weight: .bold)
            .foregroundStyle(me ? XIXColor.onGreen : XIXColor.green)
            .frame(width: 32, height: 32)
            .background(Circle().fill(me ? XIXColor.green : XIXColor.cream).overlay(Circle().strokeBorder(XIXColor.green, lineWidth: 1)))
    }

    /// Stickers at 60–72pt on the score side, overlapping each other, never the name or the digits.
    private func stickerZone(_ row: HoleCardModel.Row) -> some View {
        let size: CGFloat = 66
        return ZStack(alignment: .trailing) {
            ForEach(Array(row.stickers.enumerated()), id: \.element.id) { i, s in
                ZStack(alignment: .bottomLeading) {
                    StickerImage(key: s.key, size: size, tilt: .degrees(i.isMultiple(of: 2) ? 3 : -2))
                    Text(s.senderInitials)
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(XIXColor.onGreen)
                        .frame(width: 18, height: 16).background(Capsule().fill(XIXColor.green))
                        .offset(x: -2, y: 2)
                }
                .scaleEffect(lifted == s.id ? 1.3 : 1)
                .zIndex(lifted == s.id ? 10 : Double(i))
                .offset(x: -CGFloat(row.stickers.count - 1 - i) * 22)
                .onLongPressGesture(minimumDuration: 0.3) { withAnimation(.spring(duration: 0.25)) { lifted = lifted == s.id ? nil : s.id } }
            }
        }
        .frame(width: row.stickers.isEmpty ? 0 : size + CGFloat(max(0, row.stickers.count - 1)) * 22, height: size)
        .frame(maxHeight: .infinity, alignment: .top)
        .offset(y: -6)
    }

    private func scoreBox(_ row: HoleCardModel.Row) -> some View {
        Button { if row.canEdit { actions.openPad(row.id) } } label: {
            ZStack {
                InkMark(mark: row.mark).frame(width: 40, height: 40)
                Text(row.score).font(XIXType.number(28, weight: .bold)).foregroundStyle(XIXColor.ink)
            }
            .frame(width: 56, height: XIXMetric.control + 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(XIXColor.sheet)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(row.canEdit ? XIXColor.green : XIXColor.hairline, lineWidth: 1)))
        }
        .buttonStyle(.plain)
        .disabled(!row.canEdit)
        .accessibilityIdentifier("score-\(row.name)")
    }

    // MARK: Lines and stubs

    private var inkLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.events, id: \.self) { e in
                Text(e).font(XIXType.body(13, weight: .medium)).foregroundStyle(XIXColor.green)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nudgeLine(_ text: String) -> some View {
        HStack {
            Text(text).font(XIXType.body(13)).foregroundStyle(XIXColor.ink)
            Spacer()
            Button { actions.openTray(model.rows.first { Int($0.score).map { s in model.par.map { s >= $0 + 2 } ?? false } ?? ($0.score == "X") }?.id ?? model.rows.first?.id ?? UUID(), .blowUp) } label: {
                Text("Stickers").trackedCaps(10, weight: .bold).foregroundStyle(XIXColor.green)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Capsule().strokeBorder(XIXColor.green, lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var calloutStub: some View {
        Group {
            if model.callout == nil && !model.isComplete {
                Button { actions.composeCallout() } label: {
                    Text("Call someone out").trackedCaps(10, weight: .bold).foregroundStyle(XIXColor.green)
                        .frame(height: XIXMetric.control)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder private var panel: some View {
        switch model.panel {
        case .none: EmptyView()
        case .pad(let pad):
            ScorePad(pad: pad, par: model.par,
                     onTap: { actions.padTap($0) }, onPickUp: { actions.padPickUp() }, onClear: { actions.padClear() }, onSave: { actions.padSave() })
        case .tray(let target, let context):
            StickerTray(context: context, targetName: model.rows.first { $0.id == target }?.name ?? "",
                        onSend: { actions.sendSticker(target, $0) }, onClose: { actions.closePanel() })
        }
    }

    /// The hole selector strip: a cell per hole, filled as scores land, the current hole in green.
    private var holeStrip: some View {
        HStack(spacing: 3) {
            ForEach(model.strip) { item in
                let current = item.hole == model.hole
                let full = item.total > 0 && item.filled == item.total
                Button { actions.go(item.hole) } label: {
                    Text("\(item.hole)")
                        .font(XIXType.number(9, weight: current ? .bold : .semibold))
                        .foregroundStyle(current ? XIXColor.onGreen : (full ? XIXColor.ink : XIXColor.muted))
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 4).fill(current ? XIXColor.green : (full ? XIXColor.surface : XIXColor.sheet))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(item.filled > 0 && !full && !current ? XIXColor.green : XIXColor.hairline, lineWidth: 1)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hole-\(item.hole)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(XIXColor.sheet)
        .overlay(Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline), alignment: .top)
    }
}

/// Everything the card can ask the host to do.
public struct HoleCardActions {
    public var openPad: (UUID) -> Void
    public var padTap: (Int) -> Void
    public var padPickUp: () -> Void
    public var padClear: () -> Void
    public var padSave: () -> Void
    public var openTray: (UUID, StickerContext) -> Void
    public var sendSticker: (UUID, StickerKey) -> Void
    public var closePanel: () -> Void
    public var respond: (UUID, HoleCardResponse) -> Void
    public var composeCallout: () -> Void
    public var go: (Int) -> Void
    /// The round menu ("···" in the header); nil hides the control.
    public var menu: (() -> Void)?

    public init(openPad: @escaping (UUID) -> Void, padTap: @escaping (Int) -> Void, padPickUp: @escaping () -> Void, padClear: @escaping () -> Void,
                padSave: @escaping () -> Void, openTray: @escaping (UUID, StickerContext) -> Void, sendSticker: @escaping (UUID, StickerKey) -> Void,
                closePanel: @escaping () -> Void, respond: @escaping (UUID, HoleCardResponse) -> Void, composeCallout: @escaping () -> Void, go: @escaping (Int) -> Void,
                menu: (() -> Void)? = nil) {
        self.openPad = openPad; self.padTap = padTap; self.padPickUp = padPickUp; self.padClear = padClear; self.padSave = padSave
        self.openTray = openTray; self.sendSticker = sendSticker; self.closePanel = closePanel; self.respond = respond; self.composeCallout = composeCallout; self.go = go
        self.menu = menu
    }

    public static let none = HoleCardActions(openPad: { _ in }, padTap: { _ in }, padPickUp: {}, padClear: {}, padSave: {}, openTray: { _, _ in },
                                             sendSticker: { _, _ in }, closePanel: {}, respond: { _, _ in }, composeCallout: {}, go: { _ in })
}

public enum HoleCardResponse: String, Sendable { case signed, ducked }
