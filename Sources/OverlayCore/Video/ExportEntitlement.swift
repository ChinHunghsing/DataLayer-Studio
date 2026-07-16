import CoreGraphics
import CoreText
import CoreVideo
import Foundation

/// 导出授权层级。App Store 购买校验通过的构建为 `full`；
/// GitHub 直下版、自编译版和 CLI 为 `free`，导出统一叠加水印并把分辨率钳制到 1080p 以内。
public enum ExportEntitlement: Equatable, Sendable {
    case full
    case free

    public static let freeWatermarkText = "Made with DataLayer Studio"
    public static let freeMaxLongEdge = 1920
    public static let freeMaxShortEdge = 1080

    public var watermarkText: String? {
        self == .free ? Self.freeWatermarkText : nil
    }

    /// free 层把输出尺寸等比缩放到 1920x1080（横）/ 1080x1920（竖）以内，并保持偶数像素。
    public func clampedExportSize(width: Int, height: Int) -> (width: Int, height: Int) {
        guard self == .free, width > 0, height > 0 else { return (width, height) }
        let longEdge = Double(max(width, height))
        let shortEdge = Double(min(width, height))
        let scale = min(
            Double(Self.freeMaxLongEdge) / longEdge,
            Double(Self.freeMaxShortEdge) / shortEdge
        )
        guard scale < 1 else { return (width, height) }
        return (
            width: Self.evenDimension(Double(width) * scale),
            height: Self.evenDimension(Double(height) * scale)
        )
    }

    private static func evenDimension(_ value: Double) -> Int {
        max(2, Int((value / 2).rounded()) * 2)
    }
}

/// 在导出帧的覆盖层上绘制免费层水印（右下角胶囊）。
/// 与组件同一 premultiplied alpha 绘制路径，透明与合成导出共用。
enum ExportWatermarkRenderer {
    private static let fontName = "HelveticaNeue-Medium" as CFString
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    static func drawIfNeeded(_ entitlement: ExportEntitlement, into pixelBuffer: CVPixelBuffer) {
        guard let text = entitlement.watermarkText else { return }
        draw(text: text, into: pixelBuffer)
    }

    static func draw(text: String, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return
        }
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        let shortEdge = CGFloat(min(width, height))
        let fontSize = max(10, shortEdge * 0.022)
        let font = CTFontCreateWithName(fontName, fontSize, nil)
        let textColor = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.85])
            ?? CGColor(gray: 1, alpha: 0.85)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))

        let margin = max(8, shortEdge * 0.018)
        let paddingX = fontSize * 0.65
        let paddingY = fontSize * 0.38
        let pillWidth = textWidth + paddingX * 2
        let pillHeight = ascent + descent + paddingY * 2
        let pillRect = CGRect(
            x: CGFloat(width) - margin - pillWidth,
            y: margin,
            width: pillWidth,
            height: pillHeight
        )

        let pillColor = CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.32])
            ?? CGColor(gray: 0, alpha: 0.32)
        context.addPath(CGPath(
            roundedRect: pillRect,
            cornerWidth: pillHeight / 2,
            cornerHeight: pillHeight / 2,
            transform: nil
        ))
        context.setFillColor(pillColor)
        context.fillPath()

        context.textPosition = CGPoint(
            x: pillRect.minX + paddingX,
            y: pillRect.minY + paddingY + descent
        )
        CTLineDraw(line, context)
    }
}
