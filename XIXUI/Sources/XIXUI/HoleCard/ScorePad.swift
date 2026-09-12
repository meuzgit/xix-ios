// The number pad panel (PRD 8.4): 1–9, then 10+ and Picked up on their own row; the par key is largest.
// Rises as a panel on white; nothing behind it dims.
import SwiftUI

public struct ScorePad: View {
    public let pad: HoleCardModel.Pad
    public let par: Int?
    public let onTap: (Int) -> Void
    public let onPickUp: () -> Void
    public let onClear: () -> Void
    public let onSave: () -> Void

    public init(pad: HoleCardModel.Pad, par: Int?, onTap: @escaping (Int) -> Void, onPickUp: @escaping () -> Void,
                onClear: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.pad = pad; self.par = par; self.onTap = onTap; self.onPickUp = onPickUp; self.onClear = onClear; self.onSave = onSave
    }

    private var entry: String { pad.pickedUp ? "Picked up" : pad.entered.map(String.init) ?? "–" }

    public var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pad.playerName).font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.ink)
                Spacer()
                Text(entry).font(pad.pickedUp ? XIXType.body(15, weight: .semibold) : XIXType.number(28, weight: .bold)).foregroundStyle(XIXColor.ink)
            }
            .padding(.horizontal, 4)
            ForEach([[1, 2, 3, 4, 5], [6, 7, 8, 9]], id: \.self) { keys in
                HStack(spacing: 6) {
                    ForEach(keys, id: \.self) { n in key("\(n)", big: n == par, selected: !pad.pickedUp && pad.entered == n) { onTap(n) } }
                }
            }
            HStack(spacing: 6) {
                // 10+: first tap enters 10, each further tap adds one (to 15).
                key("10+", big: false, selected: !pad.pickedUp && (pad.entered ?? 0) >= 10) { onTap((pad.entered ?? 0) >= 10 ? min(15, pad.entered! + 1) : 10) }
                key("Picked up", big: false, selected: pad.pickedUp, wide: true) { onPickUp() }
            }
            HStack(spacing: 6) {
                Button(action: onClear) {
                    Text("Clear").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.green)
                        .frame(maxWidth: .infinity).frame(height: XIXMetric.control)
                        .background(Capsule().strokeBorder(XIXColor.green, lineWidth: 1))
                }.buttonStyle(.plain)
                Button(action: onSave) {
                    Text("Save").font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.onGreen)
                        .frame(maxWidth: .infinity).frame(height: XIXMetric.control)
                        .background(Capsule().fill(XIXColor.green))
                }.buttonStyle(.plain).disabled(pad.entered == nil && !pad.pickedUp)
            }
        }
        .padding(12)
        .background(XIXColor.sheet)
        .overlay(Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline), alignment: .top)
    }

    private func key(_ label: String, big: Bool, selected: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(label.count > 3 ? XIXType.body(14, weight: .semibold) : XIXType.number(big ? 26 : 20, weight: big ? .bold : .semibold))
                .foregroundStyle(selected ? XIXColor.onGreen : XIXColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: big ? XIXMetric.control + 12 : XIXMetric.control)
                .background(RoundedRectangle(cornerRadius: 12).fill(selected ? XIXColor.green : XIXColor.surface))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: wide ? .infinity : nil)
    }
}
