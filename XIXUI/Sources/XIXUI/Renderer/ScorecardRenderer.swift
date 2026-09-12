// The one scorecard renderer (Build Doc 2 D.2): the same view tree on screen, in the export, on the
// results screen and on the medal context card. Width is a parameter; 322pt is a chat bubble.
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import ImageIO
import UniformTypeIdentifiers

public struct ScorecardView: View {
    public let model: ScorecardModel
    public let width: CGFloat

    public init(model: ScorecardModel, width: CGFloat = XIXMetric.screenWidth) {
        self.model = model
        self.width = width
    }

    private var metrics: GridMetrics { GridMetrics(width: width, nameStyle: model.nameStyle) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if model.holes > 9 {
                block(range: 0..<9, label: "OUT", showTotal: false)
                Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline)
                block(range: 9..<model.holes, label: "IN", showTotal: true)
            } else {
                block(range: 0..<model.holes, label: "TOT", showTotal: false)
            }
            footer
        }
        .frame(width: width)
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
    }

    // MARK: Header (broadcast green)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("XIX").trackedCaps(11, weight: .bold).foregroundStyle(XIXColor.onGreen)
                Spacer()
                Text(model.dateLabel).trackedCaps(9).foregroundStyle(XIXColor.faint)
            }
            Text(model.courseName)
                .font(XIXType.body(metrics.titleSize, weight: .semibold))
                .foregroundStyle(XIXColor.onGreen)
                .lineLimit(1)
            if let strap = model.strapline {
                Text(strap).trackedCaps(9).foregroundStyle(XIXColor.faint).lineLimit(1)
            }
        }
        .padding(.horizontal, metrics.margin)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XIXColor.green)
    }

    // MARK: A nine-hole block

    private func block(range: Range<Int>, label: String, showTotal: Bool) -> some View {
        let m = metrics
        let columns = Array(range)
        return VStack(spacing: XIXMetric.gap) {
            // Hole numbers, with the live callout mark on its header.
            row(leading: Text("HOLE").trackedCaps(m.capsSize).foregroundStyle(XIXColor.muted),
                cells: columns.map { h in
                    AnyView(ZStack {
                        if model.liveCalloutHole == h + 1 {
                            Circle().strokeBorder(XIXColor.green, lineWidth: 1).frame(width: m.cell - 4, height: m.cell - 4)
                        }
                        Text("\(h + 1)").font(XIXType.number(m.capsSize, weight: .semibold)).foregroundStyle(XIXColor.muted)
                    })
                },
                trailing: [Text(label).trackedCaps(m.capsSize).foregroundStyle(XIXColor.muted)] + (showTotal ? [Text("TOT").trackedCaps(m.capsSize).foregroundStyle(XIXColor.muted)] : []),
                height: m.headerRow, background: XIXColor.sheet)

            // Par row.
            row(leading: Text("PAR").trackedCaps(m.capsSize).foregroundStyle(XIXColor.muted),
                cells: columns.map { h in AnyView(Text(model.par[safe: h].flatMap { $0 }.map(String.init) ?? "–").font(XIXType.number(m.capsSize)).foregroundStyle(XIXColor.muted)) },
                trailing: [Text(model.parTotal(range).map(String.init) ?? "–").font(XIXType.number(m.capsSize)).foregroundStyle(XIXColor.muted)]
                    + (showTotal ? [Text(model.parTotal(0..<model.holes).map(String.init) ?? "–").font(XIXType.number(m.capsSize)).foregroundStyle(XIXColor.muted)] : []),
                height: m.parRow, background: XIXColor.surface)

            // Player rows.
            ForEach(Array(model.players.enumerated()), id: \.element.id) { index, player in
                row(leading: nameCell(player),
                    cells: columns.map { h in AnyView(scoreCell(model.cells[safe: index]?[safe: h] ?? .empty)) },
                    trailing: [totalText(model.blockTotal(player: index, holes: range))]
                        + (showTotal ? [totalText(model.totals[safe: index].flatMap { $0 }, strong: true)] : []),
                    height: m.playerRow, background: XIXColor.sheet)
            }
        }
        .padding(.horizontal, m.margin)
        .padding(.vertical, 8)
    }

    private func row(leading: some View, cells: [AnyView], trailing: [some View], height: CGFloat, background: Color) -> some View {
        let m = metrics
        return HStack(spacing: XIXMetric.gap) {
            leading.frame(width: m.nameColumn, height: height, alignment: .leading).padding(.leading, 4)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                cell.frame(width: m.cell, height: height)
            }
            ForEach(Array(trailing.enumerated()), id: \.offset) { _, t in
                t.frame(width: m.totalColumn, height: height, alignment: .trailing).padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private func nameCell(_ player: ScorecardModel.Player) -> some View {
        Group {
            switch model.nameStyle {
            case .names:
                Text(player.name).font(XIXType.body(metrics.nameSize, weight: .semibold)).foregroundStyle(XIXColor.ink).lineLimit(1).minimumScaleFactor(0.8)
            case .initials:
                Text(player.initials).trackedCaps(metrics.nameSize, weight: .bold).foregroundStyle(XIXColor.ink)
            }
        }
    }

    private func totalText(_ value: Int?, strong: Bool = false) -> some View {
        Text(value.map(String.init) ?? "")
            .font(XIXType.number(metrics.numberSize, weight: strong ? .bold : .semibold))
            .foregroundStyle(XIXColor.ink)
    }

    // MARK: A score cell: number, ink mark, sticker

    private func scoreCell(_ cell: ScorecardModel.Cell) -> some View {
        let m = metrics
        return ZStack(alignment: .topTrailing) {
            ZStack {
                InkMark(mark: cell.mark).frame(width: m.markSize, height: m.markSize)
                Text(cell.text).font(XIXType.number(m.numberSize)).foregroundStyle(XIXColor.ink)
            }
            .frame(width: m.cell, height: m.playerRow)
            if let pin = cell.sticker {
                StickerPinView(pin: pin, size: m.sticker)
                    .offset(x: m.sticker * 0.45, y: -m.sticker * 0.45)   // overhangs into the row and column gaps; covers at most a third of the digit
            }
        }
    }

    private var footer: some View {
        HStack {
            if let link = model.joinLink {
                Text(link).trackedCaps(8).foregroundStyle(XIXColor.muted)
            }
            Spacer()
            Text("\(model.holes) holes").trackedCaps(8).foregroundStyle(XIXColor.faint)
        }
        .padding(.horizontal, metrics.margin)
        .padding(.bottom, 10)
    }
}

/// Column widths from the available width and name style. At 322pt with names a cell is ~24pt.
struct GridMetrics {
    let width: CGFloat
    let nameStyle: ScorecardModel.NameStyle

    var margin: CGFloat { width <= XIXMetric.chatWidth ? 8 : 12 }
    var nameColumn: CGFloat { nameStyle == .names ? (width <= XIXMetric.chatWidth ? 54 : 72) : 30 }
    var totalColumn: CGFloat { width <= XIXMetric.chatWidth ? 30 : 36 }
    var cell: CGFloat {
        let fixed = margin * 2 + nameColumn + totalColumn * 2 + XIXMetric.gap * 11
        return floor((width - fixed) / 9)
    }
    var playerRow: CGFloat { max(28, cell + 6) }
    var headerRow: CGFloat { 18 }
    var parRow: CGFloat { 20 }
    var capsSize: CGFloat { width <= XIXMetric.chatWidth ? 8 : 9 }
    var numberSize: CGFloat { width <= XIXMetric.chatWidth ? 13 : 15 }
    var nameSize: CGFloat { width <= XIXMetric.chatWidth ? 11 : 13 }
    var titleSize: CGFloat { width <= XIXMetric.chatWidth ? 15 : 17 }
    var markSize: CGFloat { cell - 6 }
    var sticker: CGFloat { width <= XIXMetric.chatWidth ? 22 : XIXMetric.stickerOnGrid }
}

/// Printed-card ink: thin green line only, never a die-cut.
struct InkMark: View {
    let mark: ScorecardModel.Mark
    var body: some View {
        switch mark {
        case .none: EmptyView()
        case .circle: Circle().strokeBorder(XIXColor.green, lineWidth: 1)
        case .square: Rectangle().strokeBorder(XIXColor.green, lineWidth: 1)
        case .filled: Rectangle().strokeBorder(XIXColor.green, lineWidth: 1).background(Rectangle().fill(XIXColor.green.opacity(0.12)))
        case .x: Rectangle().strokeBorder(XIXColor.green, lineWidth: 1).background(Rectangle().fill(XIXColor.green.opacity(0.12)))
        }
    }
}

/// A sticker on a cell with its sender chip welded to the edge and a "×n" tab for stacks.
struct StickerPinView: View {
    let pin: ScorecardModel.StickerPin
    let size: CGFloat
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            StickerImage(key: pin.key, size: size, tilt: .degrees(2))
            Text(pin.senderInitials)
                .font(.system(size: max(5, size * 0.24), weight: .bold))
                .foregroundStyle(XIXColor.onGreen)
                .padding(.horizontal, 2).frame(height: max(8, size * 0.36))
                .background(Capsule().fill(XIXColor.green))
                .offset(x: -2, y: 2)
            if pin.count > 1 {
                Text("×\(pin.count)")
                    .font(.system(size: max(5, size * 0.24), weight: .bold))
                    .foregroundStyle(XIXColor.ink)
                    .padding(.horizontal, 2).frame(height: max(8, size * 0.36))
                    .background(Capsule().fill(XIXColor.cream))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: 2, y: -2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Export

public enum ScorecardRenderer {
    /// The same view tree as `ScorecardView`, rasterised. `scale` 2 for a crisp chat image.
    @MainActor
    public static func image(model: ScorecardModel, width: CGFloat = XIXMetric.chatWidth, scale: CGFloat = 2) -> CGImage? {
        let renderer = ImageRenderer(content: ScorecardView(model: model, width: width))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.cgImage
    }

    @MainActor
    public static func pngData(model: ScorecardModel, width: CGFloat = XIXMetric.chatWidth, scale: CGFloat = 2) -> Data? {
        guard let cg = image(model: model, width: width, scale: scale) else { return nil }
        return pngData(cg)
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
