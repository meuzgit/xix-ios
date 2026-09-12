// The callout banner (PRD 8.6): the CALLED OUT die-cut on the white sheet, no container. Its two drawn
// bubbles are the controls: SIGN IT and DUCK IT, ≥44pt hit areas, pressed = bubble darkens and the
// sticker squashes to 0.96. With the Rive renderer installed the pressed state lives in the CALLED_OUT
// state machine (the same darken and 0.96) and the drawn overlay steps aside; the hit areas never move.
// One tracked-caps detail line; per-target chips on the banner's edge; the caller's chip welded to the corner.
import SwiftUI

public struct CalloutBanner: View {
    public let callout: HoleCardModel.Callout
    public let width: CGFloat
    public let onSign: () -> Void
    public let onDuck: () -> Void
    @State private var pressed: Bubble? = nil
    @Environment(\.stickerRenderer) private var renderer

    public enum Bubble: String { case sign, duck }

    public init(callout: HoleCardModel.Callout, width: CGFloat = 260, onSign: @escaping () -> Void, onDuck: @escaping () -> Void) {
        self.callout = callout; self.width = width; self.onSign = onSign; self.onDuck = onDuck
    }

    // Bubble positions as fractions of the die-cut (measured on CALLED_OUT.png).
    private let signCenter = CGPoint(x: 0.27, y: 0.74)
    private let duckCenter = CGPoint(x: 0.75, y: 0.74)
    private let bubbleSize = CGSize(width: 0.34, height: 0.20)

    public var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                StickerImage(key: StickerKey.calledOut.rawValue, size: width, tilt: .degrees(-1.5), pressed: pressed?.rawValue)
                    .scaleEffect(drawsPressedState && pressed != nil ? 0.96 : 1)
                    .overlay(bubbleShade(signCenter, visible: drawsPressedState && pressed == .sign))
                    .overlay(bubbleShade(duckCenter, visible: drawsPressedState && pressed == .duck))
                    .overlay(hitArea(signCenter, bubble: .sign, action: onSign))
                    .overlay(hitArea(duckCenter, bubble: .duck, action: onDuck))
                    .animation(.easeOut(duration: 0.08), value: pressed)
                chip(callout.callerInitials, filled: true).offset(x: 6, y: width * 0.14)
                VStack(spacing: 4) {
                    ForEach(callout.targets) { t in
                        chip(t.initials, filled: t.state == .signed, ducked: t.state == .ducked)
                    }
                }
                .frame(width: width, alignment: .trailing)
                .offset(x: 4, y: width * 0.14)
            }
            .frame(width: width, height: width)
            Text(callout.detail).trackedCaps(9).foregroundStyle(XIXColor.green).multilineTextAlignment(.center).lineLimit(2)
        }
        .opacity(callout.canRespond ? 1 : 0.92)
    }

    /// True while the still is on screen: the pressed look is drawn here. With a Rive asset for
    /// CALLED_OUT the state machine draws it instead and this stays out of the way.
    private var drawsPressedState: Bool { !renderer.hasAnimation(for: StickerKey.calledOut.rawValue) }

    private func bubbleShade(_ center: CGPoint, visible: Bool) -> some View {
        Ellipse().fill(XIXColor.green.opacity(visible ? 0.28 : 0))
            .frame(width: width * bubbleSize.width, height: width * bubbleSize.height)
            .position(x: width * center.x, y: width * center.y)
    }

    private func hitArea(_ center: CGPoint, bubble: Bubble, action: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: max(XIXMetric.control, width * bubbleSize.width), height: max(XIXMetric.control, width * bubbleSize.height))
            .position(x: width * center.x, y: width * center.y)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if callout.canRespond { pressed = bubble } }
                .onEnded { _ in if callout.canRespond { pressed = nil; action() } })
            .allowsHitTesting(callout.canRespond)
    }

    /// A ~16pt sender chip, welded to the die-cut edge. Signed fills green; ducked is crossed out.
    private func chip(_ initials: String, filled: Bool, ducked: Bool = false) -> some View {
        Text(initials)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(filled ? XIXColor.onGreen : XIXColor.green)
            .frame(width: 18, height: 16)
            .background(Capsule().fill(filled ? XIXColor.green : XIXColor.cream).overlay(Capsule().strokeBorder(XIXColor.green, lineWidth: 1)))
            .overlay(ducked ? Rectangle().fill(XIXColor.green).frame(height: 1).rotationEffect(.degrees(-20)) : nil)
    }
}
