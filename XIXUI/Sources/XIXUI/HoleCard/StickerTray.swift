// The sticker tray (PRD 8.7): a panel on white, contextual stickers first then the whole pack.
// Opens only on a tap; one tap sends.
import SwiftUI

public struct StickerTray: View {
    public let context: StickerContext
    public let targetName: String
    public let onSend: (StickerKey) -> Void
    public let onClose: () -> Void

    public init(context: StickerContext, targetName: String, onSend: @escaping (StickerKey) -> Void, onClose: @escaping () -> Void) {
        self.context = context; self.targetName = targetName; self.onSend = onSend; self.onClose = onClose
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sticker for \(targetName)").trackedCaps(10).foregroundStyle(XIXColor.muted)
                Spacer()
                Button(action: onClose) { Text("Close").trackedCaps(10, weight: .bold).foregroundStyle(XIXColor.green).frame(height: XIXMetric.control) }.buttonStyle(.plain)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(context.ordered, id: \.rawValue) { key in
                    Button { onSend(key) } label: {
                        StickerImage(key: key.rawValue, size: 72)
                            .frame(maxWidth: .infinity)
                            .frame(height: 78)
                            .background(RoundedRectangle(cornerRadius: 12).fill(context.suggested.contains(key) ? XIXColor.cream : XIXColor.sheet))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(XIXColor.sheet)
        .overlay(Rectangle().fill(XIXColor.hairline).frame(height: XIXMetric.hairline), alignment: .top)
    }
}
