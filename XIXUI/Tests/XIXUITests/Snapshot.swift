// A small snapshot harness: render to PNG, compare pixels with a reference in __Snapshots__.
// Set RECORD_SNAPSHOTS=1 to (re)record. A missing reference is recorded and reported as a failure.
import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import XIXUI

enum Snapshot {
    static let record = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil
    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
    }

    /// Fails when more than `tolerance` of pixels differ by more than 8/255 on any channel.
    static func assert(_ image: CGImage, named name: String, tolerance: Double = 0.005,
                       file: StaticString = #filePath, line: UInt = #line) {
        let url = directory.appendingPathComponent("\(name).png")
        guard let png = ScorecardRenderer.pngData(image) else { return XCTFail("could not encode \(name)", file: file, line: line) }
        if record || !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: url)
            XCTFail("recorded \(name).png (\(image.width)×\(image.height)); run again to compare", file: file, line: line)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let reference = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("cannot read reference \(name).png", file: file, line: line)
        }
        guard reference.width == image.width, reference.height == image.height else {
            return XCTFail("\(name): size \(image.width)×\(image.height) differs from reference \(reference.width)×\(reference.height)", file: file, line: line)
        }
        let a = pixels(reference), b = pixels(image)
        var differing = 0
        var i = 0
        while i < a.count {
            if abs(Int(a[i]) - Int(b[i])) > 8 || abs(Int(a[i+1]) - Int(b[i+1])) > 8 || abs(Int(a[i+2]) - Int(b[i+2])) > 8 { differing += 1 }
            i += 4
        }
        let fraction = Double(differing) / Double(a.count / 4)
        if fraction > tolerance {
            let failed = directory.appendingPathComponent("\(name).failed.png")
            try? png.write(to: failed)
            XCTFail("\(name): \(String(format: "%.2f", fraction * 100))% of pixels differ; see \(failed.lastPathComponent)", file: file, line: line)
        }
    }

    private static func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { ptr in
            if let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        return data
    }
}
