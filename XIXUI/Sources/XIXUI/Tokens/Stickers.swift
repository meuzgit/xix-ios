// The base sticker pack: twelve die-cut PNGs named by sticker key, bundled as static images.
// Rive animation arrives in Build Doc 3; the renderer only needs the still.
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
}

/// A sticker still at a given size. Placed flat (0–4°), never scattered (PRD 7).
public struct StickerImage: View {
    let key: String
    let size: CGFloat
    let tilt: Angle

    public init(key: String, size: CGFloat, tilt: Angle = .degrees(0)) {
        self.key = key
        self.size = size
        self.tilt = tilt
    }

    public var body: some View {
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
        .frame(width: size, height: size)
        .rotationEffect(tilt)
    }
}
