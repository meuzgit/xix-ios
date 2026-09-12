// Tapping a sticker somebody threw at you plays it full screen (Pass 2 2e, Build Doc 3 step 2): the
// slap at poster scale on the cream ground, the sender named in ink, and one line saying they will be
// told. Closing it is a tap anywhere. The caller marks it played.
import SwiftUI

public struct PlayedStickerView: View {
    public let key: String
    public let senderName: String
    /// Quiet mode for this round: the slap still plays, the cue does not.
    public let quiet: Bool
    public let onClose: () -> Void

    @State private var settled = false

    public init(key: String, senderName: String, quiet: Bool = false, onClose: @escaping () -> Void) {
        self.key = key; self.senderName = senderName; self.quiet = quiet; self.onClose = onClose
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width * 0.72, 300)
            ZStack {
                XIXColor.cream.ignoresSafeArea()
                VStack(spacing: 18) {
                    Spacer()
                    SlapSticker(key: key, size: size, quiet: quiet) { settled = true }
                    Text("FROM \(senderName.uppercased())").trackedCaps(10, weight: .bold).foregroundStyle(XIXColor.green)
                        .opacity(settled ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: settled)
                    Spacer()
                    Text("\(senderName) is told you opened it").font(XIXType.body(12)).foregroundStyle(XIXColor.muted)
                        .accessibilityIdentifier("playedStickerCaption")
                    Text("Tap to close").trackedCaps(9).foregroundStyle(XIXColor.faint).padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture { onClose() }
        }
        // `.contain`, not a label on the container: a label here would collapse the poster into one
        // element and hide the sender line from anything reading the screen.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playedSticker")
        .environment(\.colorScheme, .light)
    }
}
