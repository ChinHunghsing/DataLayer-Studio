import AppKit
import XCTest
@testable import OverlayStudio

final class PreviewSnapshotSlicerTests: XCTestCase {
    func testSliceUsesPreviewTopLeftCoordinates() throws {
        let image = NSImage(size: CGSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: 2, height: 2)).fill()
        NSColor.green.setFill()
        NSBezierPath(rect: CGRect(x: 2, y: 0, width: 2, height: 2)).fill()
        NSColor.red.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 2, width: 2, height: 2)).fill()
        NSColor.yellow.setFill()
        NSBezierPath(rect: CGRect(x: 2, y: 2, width: 2, height: 2)).fill()
        image.unlockFocus()

        let slice = try XCTUnwrap(PreviewSnapshotSlicer.sliceImage(
            image,
            cropRect: CGRect(x: 0, y: 0, width: 2, height: 2),
            displayRect: CGRect(x: 0, y: 0, width: 4, height: 4)
        ))
        let cgImage = try XCTUnwrap(slice.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let pixel = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).colorAt(x: 1, y: 1))

        XCTAssertGreaterThan(pixel.redComponent, 0.8)
        XCTAssertLessThan(pixel.greenComponent, 0.25)
        XCTAssertLessThan(pixel.blueComponent, 0.25)
    }
}
