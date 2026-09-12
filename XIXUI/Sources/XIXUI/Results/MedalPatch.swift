// Medals as riso patches (PRD 7, Pass 2 2e, Pass 6 6d): five silhouettes with text overlays, drawn in
// SwiftUI so they print crisp at every size. Static for now; the shape family is the whole identity.
import SwiftUI
import XIXScoring

public enum MedalShape: String, CaseIterable, Sendable { case shield, oval, pennant, circle, rsquare }

public struct MedalPatchModel: Equatable, Sendable, Identifiable {
    public var id: String
    public var shape: MedalShape
    public var accent: MedalAccent
    public var top: String                        // "NASSAU"
    public var bottom: String                     // "FRONT NINE"
    public var name: String                       // "Nassau Front Nine"
    public var context: String                    // "vs Dave · Fraserview · 13 Sep"
    public init(id: String, shape: MedalShape, accent: MedalAccent, top: String, bottom: String, name: String, context: String) {
        self.id = id; self.shape = shape; self.accent = accent; self.top = top; self.bottom = bottom; self.name = name; self.context = context
    }
}

/// The three patch inks Pass 6 uses, in rotation.
public enum MedalAccent: Int, CaseIterable, Sendable {
    case green, orange, red
    public var color: Color {
        switch self {
        case .green: return XIXColor.greenSoft
        case .orange: return XIXColor.accent
        case .red: return Color(hex: 0xD8332B)
        }
    }
}

extension MedalKey {
    /// Shape family and the two overlay lines for each medal.
    public var patch: (shape: MedalShape, top: String, bottom: String, name: String) {
        switch self {
        case .nassauFront: return (.shield, "NASSAU", "FRONT NINE", "Nassau Front Nine")
        case .nassauBack: return (.shield, "NASSAU", "BACK NINE", "Nassau Back Nine")
        case .nassau18: return (.shield, "NASSAU", "THE 18", "Nassau, the 18")
        case .matchplayWin: return (.shield, "MATCH", "THE MATCH", "Match Play")
        case .skinsTwo: return (.oval, "SKINS", "TWO IN A ROUND", "Two Skins in a Round")
        case .skinsFour: return (.oval, "SKINS", "FOUR IN A ROUND", "Four Skins in a Round")
        case .rabbit9: return (.oval, "RABBIT", "THE NINE", "Rabbit, the Nine")
        case .rabbit18: return (.oval, "RABBIT", "THE 18", "Rabbit, the 18")
        case .stablefordTop: return (.rsquare, "STABLEFORD", "TOP OF THE CARD", "Top of the Card")
        case .strokeLowGross: return (.rsquare, "STROKE", "LOW GROSS", "Low Gross")
        case .fivePars: return (.circle, "PARS", "FIVE PARS", "Five Pars")
        case .noBlowups: return (.circle, "BLOW-UPS", "NONE ALL ROUND", "No Blow-Ups")
        case .beatAverage: return (.circle, "AVERAGE", "BEATEN", "Beat Your Average")
        case .personalBest: return (.circle, "BEST", "PERSONAL BEST", "Personal Best")
        case .calloutCalledIt: return (.pennant, "CALLOUT", "CALLED IT", "Called It")
        case .calloutDuel: return (.pennant, "CALLOUT", "DUEL WON", "Duel Won")
        case .calloutLoneWolf: return (.pennant, "CALLOUT", "LONE WOLF", "Lone Wolf")
        case .calloutDuckedNothing: return (.pennant, "CALLOUT", "DUCKED NOTHING", "Ducked Nothing")
        }
    }

    /// A stable ink per medal so the same medal always prints the same patch.
    public var accent: MedalAccent {
        MedalAccent(rawValue: MedalKey.allCases.firstIndex(of: self)! % MedalAccent.allCases.count) ?? .green
    }
}

/// The patch: silhouette in the accent, cream ink, a cream keyline inset, text stacked in the middle.
public struct MedalPatch: View {
    public let model: MedalPatchModel
    public let size: CGFloat
    /// Empty patches (cabinet empties) draw the silhouette outline only.
    public let outlineOnly: Bool

    public init(model: MedalPatchModel, size: CGFloat = 84, outlineOnly: Bool = false) {
        self.model = model; self.size = size; self.outlineOnly = outlineOnly
    }

    public var body: some View {
        let shape = MedalSilhouette(shape: model.shape)
        ZStack {
            if outlineOnly {
                shape.stroke(XIXColor.hairline, lineWidth: 1.5)
            } else {
                shape.fill(model.accent.color)
                shape.inset(by: size * 0.07).stroke(XIXColor.cream.opacity(0.85), lineWidth: max(1, size * 0.018))
                VStack(spacing: size * 0.04) {
                    Text(model.top).trackedCaps(size * 0.11, weight: .heavy).foregroundStyle(XIXColor.cream).lineLimit(1).minimumScaleFactor(0.6)
                    Text("XIX").trackedCaps(size * 0.07, weight: .bold).foregroundStyle(XIXColor.cream.opacity(0.7))
                    Text(model.bottom).trackedCaps(size * 0.075, weight: .bold).foregroundStyle(XIXColor.cream).lineLimit(2)
                        .multilineTextAlignment(.center).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, size * 0.16)
                .offset(y: model.shape == .pennant ? -size * 0.08 : 0)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(model.name)
    }
}

/// The five silhouettes, each filling a square.
public struct MedalSilhouette: InsettableShape {
    public let shape: MedalShape
    public var insetAmount: CGFloat = 0
    public init(shape: MedalShape) { self.shape = shape }

    public func inset(by amount: CGFloat) -> MedalSilhouette { var c = self; c.insetAmount += amount; return c }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        switch shape {
        case .circle:
            p.addEllipse(in: r)
        case .oval:
            p.addEllipse(in: r.insetBy(dx: 0, dy: r.height * 0.12))
        case .rsquare:
            p.addRoundedRect(in: r.insetBy(dx: r.width * 0.04, dy: r.height * 0.04), cornerSize: CGSize(width: r.width * 0.2, height: r.width * 0.2))
        case .shield:
            let w = r.width, h = r.height
            p.move(to: CGPoint(x: r.minX + w * 0.08, y: r.minY + h * 0.06))
            p.addLine(to: CGPoint(x: r.maxX - w * 0.08, y: r.minY + h * 0.06))
            p.addLine(to: CGPoint(x: r.maxX - w * 0.08, y: r.minY + h * 0.52))
            p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY - h * 0.02), control: CGPoint(x: r.maxX - w * 0.1, y: r.maxY - h * 0.16))
            p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.08, y: r.minY + h * 0.52), control: CGPoint(x: r.minX + w * 0.1, y: r.maxY - h * 0.16))
            p.closeSubpath()
        case .pennant:
            let w = r.width, h = r.height
            p.move(to: CGPoint(x: r.minX + w * 0.12, y: r.minY + h * 0.06))
            p.addLine(to: CGPoint(x: r.maxX - w * 0.12, y: r.minY + h * 0.06))
            p.addLine(to: CGPoint(x: r.maxX - w * 0.12, y: r.minY + h * 0.66))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY - h * 0.04))
            p.addLine(to: CGPoint(x: r.minX + w * 0.12, y: r.minY + h * 0.66))
            p.closeSubpath()
        }
        return p
    }
}
