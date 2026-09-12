// Sharing a rendered card or results image through the system share sheet.
import CoreTransferable
import SwiftUI
import UIKit

struct ShareImage: Transferable {
    let image: UIImage
    let title: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.image.pngData() ?? Data() }
    }
}
