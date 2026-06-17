import AppKit
import OverlayCore

enum TextMeasurementCache {
    private static let lock = NSLock()
    private static let maximumCachedWidths = 4_096
    private static var cachedWidths: [TextMeasurementKey: CGFloat] = [:]

    static func width(_ text: String, size: CGFloat, fontName: OverlayFontFamily) -> CGFloat {
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
        let font = NSFont(name: key.postScriptName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)

        lock.lock()
        if cachedWidths.count >= maximumCachedWidths {
            cachedWidths.removeAll(keepingCapacity: true)
        }
        cachedWidths[key] = width
        lock.unlock()
        return width
    }

    static func clear() {
        lock.lock()
        cachedWidths.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    static var cachedWidthCount: Int {
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
