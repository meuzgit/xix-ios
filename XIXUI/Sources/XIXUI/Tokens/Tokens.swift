// Design tokens from Claude Design Pass 5 (Stickers Are Speech). Broadcast base: deep forest green
// header, white sheet, tracked caps, right-aligned tabular numbers, hairline rules. The accent orange
// appears only where Pass 5 uses it: LIVE, the in-play accent line, streaks. MMM yellow is not a token here.
import SwiftUI

public enum XIXColor {
    /// Header and ink line. Pass 5 #0A3A2A.
    public static let green = Color(hex: 0x0A3A2A)
    /// Body text on the sheet. Pass 5 #0A1A14.
    public static let ink = Color(hex: 0x0A1A14)
    /// Secondary green (pills on the header, pressed states). Pass 5 #1C4F2E.
    public static let greenSoft = Color(hex: 0x1C4F2E)
    /// The white sheet.
    public static let sheet = Color.white
    /// Sticker and medal ground. Pass 5 #FAF2DE.
    public static let cream = Color(hex: 0xFAF2DE)
    /// Hairline rules. Pass 5 #E8E8E4.
    public static let hairline = Color(hex: 0xE8E8E4)
    /// Quiet surfaces (par row, totals). Pass 5 #F1F1EE.
    public static let surface = Color(hex: 0xF1F1EE)
    /// Muted text. Pass 5 #8B8B85.
    public static let muted = Color(hex: 0x8B8B85)
    /// Faint text and dividers on green. Pass 5 #C7C7C2.
    public static let faint = Color(hex: 0xC7C7C2)
    /// Safety orange, Pass 5 #E8571F: LIVE, the in-play accent line, streaks. Nowhere else.
    public static let accent = Color(hex: 0xE8571F)
    /// Text on the green header.
    public static let onGreen = Color.white
}

public enum XIXMetric {
    /// Cards and sheets. Pass 5 `border-radius: 24px`.
    public static let cardRadius: CGFloat = 24
    /// Chips and pills.
    public static let pillRadius: CGFloat = 999
    /// The lattice gap between cells. Pass 5 `gap: 3px`.
    public static let gap: CGFloat = 3
    /// Every tappable control. Pass 5 `height: 44px`.
    public static let control: CGFloat = 44
    /// Stickers on the grid, anchored top-right of a cell (PRD 8.3).
    public static let stickerOnGrid: CGFloat = 26
    /// Stickers on the hole card (PRD 8.3).
    public static let stickerOnCard: CGFloat = 66
    /// Export width: a chat bubble (PRD 8.12).
    public static let chatWidth: CGFloat = 322
    /// A phone screen for the on-screen grid.
    public static let screenWidth: CGFloat = 390
    public static let hairline: CGFloat = 0.5
}

public enum XIXType {
    /// Tracked caps: SF Pro Text semibold with Pass 5's 0.14em tracking, uppercase.
    public static func trackedCaps(_ size: CGFloat, weight: Font.Weight = .semibold) -> TrackedCaps {
        TrackedCaps(size: size, weight: weight, tracking: size * 0.14)
    }

    /// Numbers: tabular figures so columns line up; callers right-align.
    public static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .default).monospacedDigit()
    }

    public static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }

    /// The hero numeral: 900 weight, tight leading. Pass 5 `font: 900 50px/.82`.
    public static let hero = Font.system(size: 50, weight: .black)
}

public struct TrackedCaps: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat

    public func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .textCase(.uppercase)
    }
}

extension View {
    public func trackedCaps(_ size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        modifier(XIXType.trackedCaps(size, weight: weight))
    }
}

extension Color {
    public init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
