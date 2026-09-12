// The Rive-backed sticker renderer (Build Doc 3 step 2). XIXUI draws stills and knows nothing about a
// runtime; the app installs this at launch and every sticker — grid, hole card, tray, callout banner,
// the full-screen played state — switches to its `.riv` state machine. A key with no `.riv` in the
// bundle keeps its still, so the app is correct before the assets land and correct after.
//
// The contract each `.riv` must satisfy (authored in the Rive editor from the 1024 masters):
//   artboard        any (the default artboard is used)
//   state machine   "Sticker"
//   trigger  "play"   plays the slap once, then rests in the pinned pose
//   number   "bubble" CALLED_OUT only: 0 none, 1 SIGN IT held, 2 DUCK IT held (darken + 0.96)
// The slap's timing is Pass 5's and lives in `StickerSlap`: peel in 1.4× / −34°, smack on frame 3,
// squash 0.82 × 1.18, rebound 1.08 × 0.92, settle flat at ~620 ms.
import RiveRuntime
import SwiftUI
import XIXUI

struct RiveStickerRenderer: StickerRendering {
    static let stateMachine = "Sticker"

    /// Keys with an authored `.riv` in this build, decided once.
    private let animated: Set<String>

    init() {
        animated = Set(StickerImages.animatedKeys)
    }

    func hasAnimation(for key: String) -> Bool { animated.contains(key) }

    @MainActor
    func view(key: String, size: CGFloat, state: StickerState, pressed: String?, onFinished: (() -> Void)?) -> AnyView? {
        guard animated.contains(key) else { return nil }
        return AnyView(RiveSticker(key: key, size: size, state: state, pressed: pressed, onFinished: onFinished))
    }
}

/// One sticker's state machine, held for the life of the view.
private struct RiveSticker: View {
    let key: String
    let size: CGFloat
    let state: StickerState
    let pressed: String?
    let onFinished: (() -> Void)?

    @StateObject private var model: RiveStickerModel

    init(key: String, size: CGFloat, state: StickerState, pressed: String?, onFinished: (() -> Void)?) {
        self.key = key; self.size = size; self.state = state; self.pressed = pressed; self.onFinished = onFinished
        _model = StateObject(wrappedValue: RiveStickerModel(key: key))
    }

    var body: some View {
        Group {
            if let vm = model.viewModel {
                vm.view()
            } else {
                // The file would not load: the still is always a correct sticker.
                StickerImage(key: key, size: size)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            model.apply(pressed: pressed)
            if state == .played { model.play(onFinished: onFinished) }
        }
        .onChange(of: pressed) { _, now in model.apply(pressed: now) }
        .onChange(of: state) { _, now in if now == .played { model.play(onFinished: onFinished) } }
    }
}

@MainActor
private final class RiveStickerModel: ObservableObject {
    let viewModel: RiveViewModel?
    private var finishTask: Task<Void, Never>?

    init(key: String) {
        guard let url = StickerImages.animationURL(for: key),
              let data = try? Data(contentsOf: url),
              let file = try? RiveFile(byteArray: [UInt8](data), loadCdn: false) else {
            viewModel = nil
            return
        }
        let model = RiveModel(riveFile: file)
        viewModel = RiveViewModel(model, stateMachineName: RiveStickerRenderer.stateMachine, autoPlay: false)
    }

    /// Fire the slap. `onFinished` is called on the settle, timed from `StickerSlap` so the caller does
    /// not depend on the runtime's delegate callbacks.
    func play(onFinished: (() -> Void)?) {
        guard let viewModel else { onFinished?(); return }
        viewModel.play()
        viewModel.triggerInput("play")
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(StickerSlap.duration))
            guard !Task.isCancelled, self != nil else { return }
            onFinished?()
        }
    }

    /// CALLED_OUT's held bubble: 0 none, 1 sign, 2 duck.
    func apply(pressed: String?) {
        guard let viewModel else { return }
        let value: Double = pressed == "sign" ? 1 : (pressed == "duck" ? 2 : 0)
        viewModel.setInput("bubble", value: value)
    }

    deinit { finishTask?.cancel() }
}
