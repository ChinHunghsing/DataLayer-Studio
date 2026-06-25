import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasWidth = 1440
let canvasHeight = 900
let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let inputDir = root.appendingPathComponent("assets/appstore/v0.1.1/desktop")
let outputRootDir = root.appendingPathComponent("assets/appstore/v0.1.1/framed")
let iconURL = root.appendingPathComponent("Resources/AppIcon.png")

try FileManager.default.createDirectory(at: outputRootDir, withIntermediateDirectories: true)

struct HeroCopy {
    let locale: String
    let subtitle: String
    let pills: [String]
    let sourceLabel: String
    let sourceSubhead: String
    let windowTitle: String
}

struct PageCopy {
    let fileName: String
    let source: String
    let title: String
    let subtitle: String
    let accent: CGColor
}

struct LocaleCopy {
    let hero: HeroCopy
    let pages: [PageCopy]
}

let localizedCopies: [LocaleCopy] = [
    LocaleCopy(
        hero: HeroCopy(
            locale: "en-US",
            subtitle: "Turn running data into cinematic video overlays.",
            pills: ["Transparent video export", "Custom gauges", "FIT, weather, power", "Reusable layouts"],
            sourceLabel: "Video + FIT",
            sourceSubhead: "to editor-ready overlays",
            windowTitle: "Live overlay preview"
        ),
        pages: [
            PageCopy(fileName: "02-live-preview.png", source: "01-source-preview.png", title: "Preview every overlay before export", subtitle: "Scrub the video, tune gauge positions, and verify timing against FIT data.", accent: color(96, 210, 255)),
            PageCopy(fileName: "03-layout-presets.png", source: "02-canvas-presets.png", title: "Build reusable telemetry layouts", subtitle: "Save presets, sync them with iCloud, and keep consistent visuals across edits.", accent: color(132, 255, 178)),
            PageCopy(fileName: "04-export-settings.png", source: "03-export-settings.png", title: "Export transparent overlays", subtitle: "Choose resolution, frame rate, bitrate, and alpha-friendly formats for editors.", accent: color(255, 197, 93))
        ]
    ),
    LocaleCopy(
        hero: HeroCopy(
            locale: "zh-Hans",
            subtitle: "把跑步数据做成专业视频浮层。",
            pills: ["透明视频导出", "自定义仪表", "FIT、天气、功率", "可复用布局"],
            sourceLabel: "视频 + FIT",
            sourceSubhead: "生成剪辑可用的浮层",
            windowTitle: "实时浮层预览"
        ),
        pages: [
            PageCopy(fileName: "02-live-preview.png", source: "01-source-preview.png", title: "导出前预览每一个浮层", subtitle: "拖动进度条，调整仪表位置，并用 FIT 数据校准时间。", accent: color(96, 210, 255)),
            PageCopy(fileName: "03-layout-presets.png", source: "02-canvas-presets.png", title: "建立可复用的运动数据布局", subtitle: "保存预设、通过 iCloud 同步，并让每条视频保持一致风格。", accent: color(132, 255, 178)),
            PageCopy(fileName: "04-export-settings.png", source: "03-export-settings.png", title: "导出透明背景浮层", subtitle: "选择分辨率、帧率、码率和适合剪辑软件的透明格式。", accent: color(255, 197, 93))
        ]
    ),
    LocaleCopy(
        hero: HeroCopy(
            locale: "zh-Hant",
            subtitle: "把跑步資料做成專業影片浮層。",
            pills: ["透明影片輸出", "自訂儀表", "FIT、天氣、功率", "可重用版面"],
            sourceLabel: "影片 + FIT",
            sourceSubhead: "產生剪輯可用的浮層",
            windowTitle: "即時浮層預覽"
        ),
        pages: [
            PageCopy(fileName: "02-live-preview.png", source: "01-source-preview.png", title: "輸出前預覽每一個浮層", subtitle: "拖動進度條、調整儀表位置，並用 FIT 資料校準時間。", accent: color(96, 210, 255)),
            PageCopy(fileName: "03-layout-presets.png", source: "02-canvas-presets.png", title: "建立可重用的運動資料版面", subtitle: "儲存預設、透過 iCloud 同步，讓每段影片保持一致風格。", accent: color(132, 255, 178)),
            PageCopy(fileName: "04-export-settings.png", source: "03-export-settings.png", title: "輸出透明背景浮層", subtitle: "選擇解析度、影格率、位元率和適合剪輯軟體的透明格式。", accent: color(255, 197, 93))
        ]
    ),
    LocaleCopy(
        hero: HeroCopy(
            locale: "ja",
            subtitle: "ランニングデータを映像用オーバーレイに。",
            pills: ["透明ビデオ書き出し", "カスタムゲージ", "FIT・天気・パワー", "再利用できるレイアウト"],
            sourceLabel: "動画 + FIT",
            sourceSubhead: "編集で使えるオーバーレイへ",
            windowTitle: "ライブオーバーレイプレビュー"
        ),
        pages: [
            PageCopy(fileName: "02-live-preview.png", source: "01-source-preview.png", title: "書き出し前にすべてのオーバーレイを確認", subtitle: "動画をスクラブし、ゲージ位置を調整して、FIT データとタイミングを合わせられます。", accent: color(96, 210, 255)),
            PageCopy(fileName: "03-layout-presets.png", source: "02-canvas-presets.png", title: "再利用できるテレメトリレイアウト", subtitle: "プリセットを保存し、iCloud で同期して、編集ごとの見た目をそろえられます。", accent: color(132, 255, 178)),
            PageCopy(fileName: "04-export-settings.png", source: "03-export-settings.png", title: "透明オーバーレイを書き出し", subtitle: "解像度、フレームレート、ビットレート、編集向けの透明形式を選べます。", accent: color(255, 197, 93))
        ]
    )
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func topRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasSize.height - y - height, width: width, height: height)
}

func fillRound(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

func strokeRound(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor, width: CGFloat) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: width / 2, dy: width / 2), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()
}

func drawText(
    _ ctx: CGContext,
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color textColor: NSColor = .white,
    alignment: NSTextAlignment = .left,
    lineSpacing: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineSpacing = lineSpacing
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    let rect = topRect(x, y, width, height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSString(string: text).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

func drawFittedText(
    _ ctx: CGContext,
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    size: CGFloat,
    minSize: CGFloat = 24,
    weight: NSFont.Weight = .bold,
    color textColor: NSColor = .white
) {
    var fittedSize = size
    while fittedSize > minSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fittedSize, weight: weight),
            .kern: 0
        ]
        let measured = NSString(string: text).size(withAttributes: attributes)
        if measured.width <= width {
            break
        }
        fittedSize -= 1
    }
    drawText(ctx, text, x: x, y: y, width: width, height: height, size: fittedSize, weight: weight, color: textColor)
}

func drawMonoText(
    _ ctx: CGContext,
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    size: CGFloat,
    weight: NSFont.Weight = .semibold,
    color textColor: NSColor = .white
) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .kern: 0
    ]
    let rect = topRect(x, y, width, height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSString(string: text).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
}

func drawBackground(_ ctx: CGContext, accent: CGColor = color(78, 189, 255)) {
    ctx.setFillColor(color(10, 15, 20))
    ctx.fill(CGRect(origin: .zero, size: canvasSize))

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(20, 29, 38).copy(alpha: 1)!, color(7, 12, 18).copy(alpha: 1)!] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: canvasSize.height),
        end: CGPoint(x: canvasSize.width, y: 0),
        options: []
    )

    ctx.saveGState()
    ctx.setStrokeColor(color(255, 255, 255, 0.045))
    ctx.setLineWidth(1)
    for x in stride(from: CGFloat(80), through: canvasSize.width, by: CGFloat(80)) {
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: canvasSize.height))
    }
    for y in stride(from: CGFloat(60), through: canvasSize.height, by: CGFloat(60)) {
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: canvasSize.width, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setStrokeColor(accent.copy(alpha: 0.18)!)
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 72, y: 154))
    path.addCurve(to: CGPoint(x: 346, y: 674), control1: CGPoint(x: 170, y: 820), control2: CGPoint(x: 226, y: 134))
    path.addCurve(to: CGPoint(x: 760, y: 700), control1: CGPoint(x: 470, y: 1010), control2: CGPoint(x: 594, y: 526))
    path.addCurve(to: CGPoint(x: 1290, y: 180), control1: CGPoint(x: 950, y: 900), control2: CGPoint(x: 1128, y: 170))
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()
}

func drawPill(_ ctx: CGContext, text: String, x: CGFloat, y: CGFloat, width: CGFloat) {
    fillRound(ctx, topRect(x, y, width, 42), radius: 21, color: color(255, 255, 255, 0.09))
    strokeRound(ctx, topRect(x, y, width, 42), radius: 21, color: color(255, 255, 255, 0.13), width: 1)
    drawText(ctx, text, x: x + 18, y: y + 10, width: width - 36, height: 24, size: 15, weight: .semibold, color: NSColor(calibratedWhite: 0.88, alpha: 1))
}

func drawImage(_ ctx: CGContext, url: URL, rect: CGRect, radius: CGFloat = 0) throws {
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "AppStoreAsset", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load image \(url.path)"])
    }
    ctx.saveGState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    if radius > 0 {
        let clipPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        clipPath.addClip()
    }
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

func drawImageFitted(_ ctx: CGContext, url: URL, rect: CGRect) throws {
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "AppStoreAsset", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load image \(url.path)"])
    }
    let scale = min(rect.width / image.size.width, rect.height / image.size.height)
    let fittedSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
    )
    let fittedRect = CGRect(
        x: rect.midX - fittedSize.width / 2,
        y: rect.midY - fittedSize.height / 2,
        width: fittedSize.width,
        height: fittedSize.height
    )
    ctx.saveGState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSBezierPath(roundedRect: fittedRect, xRadius: 8, yRadius: 8).addClip()
    image.draw(in: fittedRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

func drawWindow(_ ctx: CGContext, screenshotURL: URL, frame: CGRect, title: String) throws {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 46, color: color(0, 0, 0, 0.52))
    fillRound(ctx, frame, radius: 24, color: color(12, 17, 23, 0.96))
    ctx.restoreGState()

    strokeRound(ctx, frame, radius: 24, color: color(255, 255, 255, 0.14), width: 1)
    let titlebarHeight: CGFloat = 46
    let titlebar = CGRect(x: frame.minX, y: frame.maxY - titlebarHeight, width: frame.width, height: titlebarHeight)
    fillRound(ctx, titlebar, radius: 24, color: color(34, 43, 52, 0.94))
    ctx.setFillColor(color(34, 43, 52, 0.94))
    ctx.fill(CGRect(x: frame.minX, y: frame.maxY - titlebarHeight, width: frame.width, height: titlebarHeight / 2))

    let dotY = frame.maxY - 28
    for (index, dotColor) in [color(255, 95, 86), color(255, 190, 48), color(39, 201, 63)].enumerated() {
        ctx.setFillColor(dotColor)
        ctx.fillEllipse(in: CGRect(x: frame.minX + 20 + CGFloat(index) * 18, y: dotY, width: 11, height: 11))
    }
    drawText(ctx, title, x: frame.minX + 86, y: canvasSize.height - frame.maxY + 13, width: frame.width - 170, height: 20, size: 13, weight: .semibold, color: NSColor(calibratedWhite: 0.76, alpha: 1), alignment: .center)

    let content = CGRect(x: frame.minX + 10, y: frame.minY + 10, width: frame.width - 20, height: frame.height - titlebarHeight - 10)
    fillRound(ctx, content, radius: 2, color: color(31, 37, 40))
    try drawImageFitted(ctx, url: screenshotURL, rect: content)
}

func makeContext() -> CGContext {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
    return CGContext(
        data: nil,
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: canvasWidth * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
}

func save(_ ctx: CGContext, to url: URL) throws {
    guard let cgImage = ctx.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "AppStoreAsset", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG \(url.path)"])
    }
    CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "AppStoreAsset", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not write PNG \(url.path)"])
    }
}

func renderHero(_ copy: HeroCopy, outputDir: URL) throws {
    let ctx = makeContext()
    drawBackground(ctx, accent: color(96, 210, 255))

    try drawImage(ctx, url: iconURL, rect: topRect(84, 90, 66, 66), radius: 16)
    drawText(ctx, "DataLayer Studio", x: 84, y: 176, width: 330, height: 58, size: 42, weight: .bold)
    drawText(ctx, copy.subtitle, x: 86, y: 244, width: 336, height: 84, size: 21, weight: .medium, color: NSColor(calibratedWhite: 0.80, alpha: 1), lineSpacing: 5)
    for (index, pill) in copy.pills.enumerated() {
        let width = max(CGFloat(148), CGFloat(pill.count) * 15 + 42)
        drawPill(ctx, text: pill, x: 86, y: 356 + CGFloat(index) * 58, width: min(width, 300))
    }

    drawMonoText(ctx, copy.sourceLabel, x: 94, y: 678, width: 236, height: 32, size: 19, color: NSColor(calibratedRed: 0.55, green: 0.86, blue: 1.0, alpha: 1))
    drawText(ctx, copy.sourceSubhead, x: 94, y: 710, width: 286, height: 34, size: 17, weight: .semibold, color: NSColor(calibratedWhite: 0.76, alpha: 1))

    let source = inputDir.appendingPathComponent("01-source-preview.png")
    try drawWindow(ctx, screenshotURL: source, frame: topRect(410, 126, 940, 634), title: copy.windowTitle)
    try save(ctx, to: outputDir.appendingPathComponent("01-hero.png"))
}

func renderFramed(page: PageCopy, outputDir: URL) throws {
    let ctx = makeContext()
    drawBackground(ctx, accent: page.accent)
    drawFittedText(ctx, page.title, x: 92, y: 58, width: 1060, height: 52, size: 39, minSize: 30, weight: .bold)
    drawText(ctx, page.subtitle, x: 94, y: 112, width: 920, height: 48, size: 18, weight: .medium, color: NSColor(calibratedWhite: 0.72, alpha: 1))
    let screenshot = inputDir.appendingPathComponent(page.source)
    try drawWindow(ctx, screenshotURL: screenshot, frame: topRect(180, 154, 1080, 722), title: "DataLayer Studio")
    try save(ctx, to: outputDir.appendingPathComponent(page.fileName))
}

for copy in localizedCopies {
    let outputDir = outputRootDir.appendingPathComponent(copy.hero.locale)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    try renderHero(copy.hero, outputDir: outputDir)
    for page in copy.pages {
        try renderFramed(page: page, outputDir: outputDir)
    }
}

print("Generated localized framed App Store assets in \(outputRootDir.path)")
