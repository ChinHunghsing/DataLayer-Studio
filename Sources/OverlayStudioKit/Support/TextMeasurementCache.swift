import CoreGraphics
import CoreText
import Foundation
import OverlayCore

package enum TextMeasurementCache {
    private static let lock = NSLock()
    private static let maximumCachedWidths = 4_096
    private static var cachedWidths: [TextMeasurementKey: CGFloat] = [:]

    package static func width(_ text: String, size: CGFloat, fontName: OverlayFontFamily) -> CGFloat {
        let normalizedSize = max(0.1, size.isFinite ? size : 12)
        let key = TextMeasurementKey(
            text: text,
            postScriptName: fontName.postScriptName,
            sizeHundredths: Int((normalizedSize * 100).rounded())
        )

        lock.lock()
        if let width = cachedWidths[key] {
            lock.unlock()
            return width
        }
        lock.unlock()

        let fontSize = CGFloat(key.sizeHundredths) / 100
        let font = CTFontCreateWithName(key.postScriptName as CFString, fontSize, nil)
        let attributedText = CFAttributedStringCreate(
            nil,
            text as CFString,
            [kCTFontAttributeName: font] as CFDictionary
        )
        let line = CTLineCreateWithAttributedString(attributedText!)
        let width = ceil(CTLineGetTypographicBounds(line, nil, nil, nil))

        lock.lock()
        if cachedWidths.count >= maximumCachedWidths {
            cachedWidths.removeAll(keepingCapacity: true)
        }
        cachedWidths[key] = width
        lock.unlock()
        return width
    }

    package static func clear() {
        lock.lock()
        cachedWidths.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    package static var cachedWidthCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cachedWidths.count
    }
}

private struct TextMeasurementKey: Hashable {
    var text: String
    var postScriptName: String
    var sizeHundredths: Int
}
