// The base sticker pack: twelve die-cuts, bundled at 512² (the 1024 masters live in `masters/stickers`
// and are never shipped; `scripts/build-sticker-bundle.py` writes the bundle). A sticker draws through
// the environment's renderer when one is installed — the app installs the Rive-backed one — and falls
// back to the still PNG, which is what the snapshots and the exported card always use.
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

public enum StickerKey: String, CaseIterable, Sendable {
    case choke = "CHOKE"
    case sandbagger = "SANDBAGGER"
    case clutch = "CLUTCH"
    case duckIt = "DUCK_IT"
    case noWitnesses = "NO_WITNESSES"
    case snake = "SNAKE"
    case calledOut = "CALLED_OUT"
    case signed = "SIGNED"
    case yikes = "YIKES"
    case wasted = "WASTED"
    case hahaha = "HAHAHA"
    case bail = "BAIL"
}

public enum StickerImages {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    /// The still for a sticker key, decoded once. Nil for keys outside the base pack.
    public static func image(for key: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard let url = Bundle.module.url(forResource: key, withExtension: "png", subdirectory: "Stickers"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else { return nil }
        cache[key] = image
        return image
    }

    public static func image(for key: StickerKey) -> CGImage? { image(for: key.rawValue) }

    /// The `.riv` for a sticker key, when the animated asset has been authored and bundled
    /// (`scripts/build-sticker-bundle.py` copies them in beside the stills). Nil means the still is all
    /// there is, and every sticker surface falls back to it.
    public static func animationURL(for key: String) -> URL? {
        Bundle.module.url(forResource: key, withExtension: "riv", subdirectory: "Stickers")
            ?? Bundle.module.url(forResource: key, withExtension: "riv")
    }

    /// The package's resource bundle, for runtimes that load by bundle rather than by URL.
    public static var resourceBundle: Bundle { Bundle.module }

    /// The keys that have an animated asset in this build.
    public static var animatedKeys: [String] { StickerKey.allCases.map(\.rawValue).filter { animationURL(for: $0) != nil } }
}

/// A sticker at a given size. Placed flat (0–4°), never scattered (PRD 7). `state` is `.pinned` on the
/// card; the played slap is `SlapSticker` and the full-screen overlay.
public struct StickerImage: View {
    let key: String
    let size: CGFloat
    let tilt: Angle
    let state: StickerState
    /// For CALLED_OUT: which bubble is held down ("sign" / "duck"), so the Rive state machine can darken it.
    let pressed: String?
    @Environment(\.stickerRenderer) private var renderer

    public init(key: String, size: CGFloat, tilt: Angle = .degrees(0), state: StickerState = .pinned, pressed: String? = nil) {
        self.key = key
        self.size = size
        self.tilt = tilt
        self.state = state
        self.pressed = pressed
    }

    public var body: some View {
        Group {
            if let animated = renderer.view(key: key, size: size, state: state, pressed: pressed, onFinished: nil) {
                animated
            } else {
                still
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(tilt)
    }

    /// The still PNG. The export renderer and the snapshots always take this path.
    @ViewBuilder private var still: some View {
        Group {
            if let cg = StickerImages.image(for: key) {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.2).fill(XIXColor.cream)
                    .overlay(Text(key).trackedCaps(size * 0.18).foregroundStyle(XIXColor.green).minimumScaleFactor(0.5).padding(2))
            }
        }
    }
}

/// One sticker playing its slap (Build Doc 3 step 2). With a Rive renderer installed this is the `.riv`
/// state machine's `played` state; without one the still plays the same curve from `StickerSlap`, so
/// the timing is identical either way. The cue fires on the contact frame unless `quiet`.
public struct SlapSticker: View {
    public let key: String
    public let size: CGFloat
    public let quiet: Bool
    public let onFinished: (() -> Void)?
    @Environment(\.stickerRenderer) private var renderer
    @State private var started = Date()
    @State private var cued = false
    @State private var finished = false
    @State private var timing: Task<Void, Never>?

    public init(key: String, size: CGFloat, quiet: Bool = false, onFinished: (() -> Void)? = nil) {
        self.key = key; self.size = size; self.quiet = quiet; self.onFinished = onFinished
    }

    public var body: some View {
        Group {
            if let animated = renderer.view(key: key, size: size, state: .played, pressed: nil, onFinished: finish) {
                animated
                    .onAppear { cue() }
            } else {
                // One stable image, transformed by the render server: the slap costs no view rebuilds.
                KeyframeAnimator(initialValue: StickerSlap.Pose(), trigger: started) { pose in
                    StickerImage(key: key, size: size)
                        .scaleEffect(x: pose.scaleX, y: pose.scaleY)
                        .rotationEffect(.degrees(pose.rotation))
                        .opacity(pose.opacity)
                } keyframes: { _ in
                    StickerSlap.track(\.scaleX)
                    StickerSlap.track(\.scaleY)
                    StickerSlap.track(\.rotation)
                    StickerSlap.track(\.opacity)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { start() }
        .onDisappear { timing?.cancel() }
    }

    /// The cue on the contact frame and the settle at the end are timed, not tied to a frame count.
    private func start() {
        started = Date()
        cued = false; finished = false
        timing?.cancel()
        timing = Task {
            try? await Task.sleep(for: .seconds(StickerSlap.contact))
            guard !Task.isCancelled else { return }
            cue()
            try? await Task.sleep(for: .seconds(StickerSlap.duration - StickerSlap.contact))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func cue() {
        guard !cued else { return }
        cued = true
        if !quiet { SlapCue.play() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished?()
    }
}
