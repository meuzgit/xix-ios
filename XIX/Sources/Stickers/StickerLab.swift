// Debug only: the twelve slaps, one after another, with the frame rate measured while they play
// (Build Doc 3 step 2's acceptance). Never in a Release build.
#if DEBUG
import QuartzCore
import SwiftUI
import XIXUI

struct StickerLab: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.stickerRenderer) private var renderer
    @State private var index = 0
    @State private var run = UUID()
    @State private var playing = false
    @State private var meter = FrameMeter()
    @State private var results: [String: Double] = [:]

    private let keys = StickerKey.allCases

    var body: some View {
        VStack(spacing: 0) {
            GreenBar("STICKER LAB", onBack: { dismiss() })
            ScrollView {
                VStack(spacing: 14) {
                    Text(keys[index].rawValue).trackedCaps(11, weight: .bold).foregroundStyle(XIXColor.green).padding(.top, 16)
                    ZStack {
                        RoundedRectangle(cornerRadius: XIXMetric.cardRadius).fill(XIXColor.cream).frame(height: 260)
                        SlapSticker(key: keys[index].rawValue, size: 200, quiet: false) { finished() }
                            .id(run)
                    }
                    .padding(.horizontal, 12)
                    Text(renderer.hasAnimation(for: keys[index].rawValue) ? "RIVE STATE MACHINE" : "STILL · SLAP CURVE FROM StickerSlap")
                        .trackedCaps(8).foregroundStyle(XIXColor.muted)
                    HStack(spacing: 8) {
                        SecondaryButton(title: "Again") { replay() }
                        PrimaryButton(title: playing ? "Playing…" : "Play all twelve", enabled: !playing) { playAll() }
                    }
                    .padding(.horizontal, 12)
                    measured
                }
            }
        }
        .background(XIXColor.sheet)
        .environment(\.colorScheme, .light)
        .onAppear { replay() }
    }

    private var measured: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Measured while playing")
            ForEach(keys, id: \.rawValue) { key in
                ListRow(key.rawValue, sub: results[key.rawValue].map { String(format: "%.1f fps", $0) } ?? "not played yet") {
                    if let fps = results[key.rawValue] {
                        Text(fps >= 58 ? "60" : String(format: "%.0f", fps)).trackedCaps(9, weight: .bold)
                            .foregroundStyle(fps >= 58 ? XIXColor.green : Color(hex: 0xB77B12))
                    }
                }
            }
            if results.count == keys.count {
                let worst = results.values.min() ?? 0
                Text(String(format: "All twelve played. Slowest: %.1f fps.", worst))
                    .font(XIXType.body(12)).foregroundStyle(XIXColor.muted).padding(20)
                    .accessibilityIdentifier("labSummary")
            }
        }
    }

    private func replay() {
        meter.start()
        run = UUID()
    }

    private func playAll() {
        playing = true
        index = 0
        replay()
    }

    private func finished() {
        results[keys[index].rawValue] = meter.stop()
        guard playing else { return }
        if index + 1 < keys.count {
            index += 1
            replay()
        } else {
            playing = false
        }
    }
}

/// Frames per second over one slap, from the display link: the honest number for "does it hold 60".
@MainActor
final class FrameMeter {
    private var link: CADisplayLink?
    private var frames = 0
    private var began: CFTimeInterval = 0

    func start() {
        stopLink()
        frames = 0
        began = CACurrentMediaTime()
        let link = CADisplayLink(target: Proxy { [weak self] in self?.frames += 1 }, selector: #selector(Proxy.tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @discardableResult
    func stop() -> Double {
        let elapsed = CACurrentMediaTime() - began
        let fps = elapsed > 0 ? Double(frames) / elapsed : 0
        stopLink()
        return fps
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    private final class Proxy: NSObject {
        let onTick: () -> Void
        init(_ onTick: @escaping () -> Void) { self.onTick = onTick }
        @objc func tick() { onTick() }
    }
}
#endif
