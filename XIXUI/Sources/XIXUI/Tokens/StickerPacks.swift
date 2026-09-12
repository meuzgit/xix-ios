// Sticker packs (Build Doc 3 step 2). Every sticker carries a `pack_key`; `base` is free and is the
// only pack in V1. Entitlement is a local stub until StoreKit in step 9 — it answers from a set on the
// device, and the server enforces nothing yet, so nothing here may be treated as proof of purchase.
import Foundation

public struct StickerPack: Hashable, Sendable, Identifiable {
    public let key: String
    public let name: String
    public let stickers: [StickerKey]
    public var id: String { key }

    public init(key: String, name: String, stickers: [StickerKey]) {
        self.key = key; self.name = name; self.stickers = stickers
    }

    /// The twelve that ship with the app.
    public static let base = StickerPack(key: "base", name: "Base", stickers: StickerKey.allCases)
    public static let all: [StickerPack] = [base]

    public static func pack(for sticker: StickerKey) -> StickerPack {
        all.first { $0.stickers.contains(sticker) } ?? base
    }
}

/// Which packs this device may send from. Step 9 replaces the stub with StoreKit and a server check.
public enum StickerEntitlements {
    private static let key = "xix.packs"

    public static var owned: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []).union(["base"]) }
        set { UserDefaults.standard.set(Array(newValue.subtracting(["base"])), forKey: key) }
    }

    public static func owns(_ pack: StickerPack) -> Bool { owned.contains(pack.key) }
    public static func canSend(_ sticker: StickerKey) -> Bool { owns(StickerPack.pack(for: sticker)) }
}
