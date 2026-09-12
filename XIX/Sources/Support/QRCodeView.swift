// The join QR for the share screen (Pass 6 6a): CoreImage, ink on white, no logo.
import CoreImage.CIFilterBuiltins
import SwiftUI
import XIXUI

struct QRCodeView: View {
    let text: String
    let size: CGFloat

    var body: some View {
        Group {
            if let img = QRCodeView.image(for: text) {
                Image(decorative: img, scale: 1).interpolation(.none).resizable().frame(width: size, height: size)
            } else {
                Rectangle().fill(XIXColor.surface).frame(width: size, height: size)
            }
        }
        .accessibilityLabel("Join code \(text)")
    }

    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
