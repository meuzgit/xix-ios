// Small parts every screen in the app shares, in the Pass 5 system: the green bar with a step label,
// the two button weights, list rows, section labels, chips. No new visual ideas; these are the parts
// the grid and hole card already use, named once.
import SwiftUI
import XIXUI

/// The thin green bar: back, a tracked-caps label, a trailing slot.
struct GreenBar<Trailing: View>: View {
    let label: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(_ label: String, onBack: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.label = label; self.onBack = onBack; self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(XIXColor.onGreen)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Text("XIX").trackedCaps(11, weight: .bold).foregroundStyle(XIXColor.onGreen)
            }
            Text(label).trackedCaps(9).foregroundStyle(XIXColor.faint).lineLimit(1)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).frame(height: XIXMetric.control)
        .frame(maxWidth: .infinity)
        .background(XIXColor.green)
    }
}

struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(XIXType.body(15, weight: .semibold)).foregroundStyle(XIXColor.onGreen)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Capsule().fill(enabled ? XIXColor.green : XIXColor.faint))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var danger = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(XIXType.body(15, weight: .semibold)).foregroundStyle(danger ? Color(hex: 0xD8332B) : XIXColor.green)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Capsule().fill(XIXColor.surface))
        }
        .buttonStyle(.plain)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).trackedCaps(9, weight: .bold).foregroundStyle(XIXColor.muted)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Chip: View {
    let text: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(XIXType.body(13, weight: .semibold)).foregroundStyle(selected ? XIXColor.onGreen : XIXColor.ink)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(selected ? XIXColor.green : XIXColor.surface))
        }
        .buttonStyle(.plain)
    }
}

struct Avatar: View {
    let initials: String
    var me = false
    var size: CGFloat = 34
    var body: some View {
        Text(initials).trackedCaps(size * 0.3, weight: .bold)
            .foregroundStyle(me ? XIXColor.onGreen : XIXColor.green)
            .frame(width: size, height: size)
            .background(Circle().fill(me ? XIXColor.green : XIXColor.cream).overlay(Circle().strokeBorder(XIXColor.green, lineWidth: 1)))
    }
}

/// A plain list row in the base type: title, optional sub, trailing text or toggle, hairline on top.
struct ListRow<Trailing: View>: View {
    let title: String
    var sub: String? = nil
    var dim = false
    var danger = false
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, sub: String? = nil, dim: Bool = false, danger: Bool = false, action: (() -> Void)? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title; self.sub = sub; self.dim = dim; self.danger = danger; self.action = action; self.trailing = trailing
    }

    var body: some View {
        let row = HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(XIXType.body(15, weight: .semibold)).foregroundStyle(danger ? Color(hex: 0xD8332B) : (dim ? XIXColor.faint : XIXColor.ink))
                if let sub, !sub.isEmpty { Text(sub).font(XIXType.body(11.5)).foregroundStyle(XIXColor.muted).lineLimit(2) }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline) }
        .contentShape(Rectangle())
        if let action, !dim {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

struct InkToggle: View {
    @Binding var on: Bool
    var body: some View {
        Toggle("", isOn: $on).labelsHidden().tint(XIXColor.green)
    }
}

extension Date {
    /// "SUNDAY, 13 SEPTEMBER" for the home header, "13 Sep" for kickers.
    var homeLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"; return f.string(from: self).uppercased()
    }
    static func shortLabel(playedOn: String) -> String {
        let p = DateFormatter(); p.dateFormat = "yyyy-MM-dd"
        guard let d = p.date(from: playedOn) else { return playedOn }
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d)
    }
}
