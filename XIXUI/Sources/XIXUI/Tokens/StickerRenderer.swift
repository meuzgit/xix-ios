// How a sticker draws. The package itself only ever draws the still PNG, which keeps XIXUI free of an
// animation runtime and keeps the snapshots stable. The app installs a Rive-backed renderer at launch
// (`\.stickerRenderer`), and every sticker on the grid, the hole card, the tray and the callout banner
// switches to the `.riv` state machine with no change at the call sites.
import SwiftUI

/// The two states a sticker is ever in (Build Doc 3 step 2): pinned, and the slap.
public enum StickerState: Equatable, Sendable {
    /// Still, as it sits on the card.
    case pinned
    /// Playing the slap; `onFinished` fires when it settles.
    case played
}

public protocol StickerRendering: Sendable {
    /// True when this renderer has an animated asset for the key; false falls back to the still.
    func hasAnimation(for key: String) -> Bool
    /// The animated sticker, or nil to use the still.
    @MainActor func view(key: String, size: CGFloat, state: StickerState, pressed: String?, onFinished: (() -> Void)?) -> AnyView?
}

/// The default: no animation runtime, every sticker is its still PNG.
public struct StillStickerRenderer: StickerRendering {
    public init() {}
    public func hasAnimation(for key: String) -> Bool { false }
    @MainActor public func view(key: String, size: CGFloat, state: StickerState, pressed: String?, onFinished: (() -> Void)?) -> AnyView? { nil }
}

private struct StickerRendererKey: EnvironmentKey {
    static let defaultValue: any StickerRendering = StillStickerRenderer()
}

extension EnvironmentValues {
    public var stickerRenderer: any StickerRendering {
        get { self[StickerRendererKey.self] }
        set { self[StickerRendererKey.self] = newValue }
    }
}
