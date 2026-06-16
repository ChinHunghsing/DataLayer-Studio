import CoreGraphics
import CoreText
import CoreVideo
import Foundation

public final class OverlayRenderer {
    private let series: TelemetrySeries
    private let config: OverlayRenderConfig
    private let routePoints: [TelemetrySample]

    public init(series: TelemetrySeries, config: OverlayRenderConfig) {
        self.series = series
        self.config = config
        self.routePoints = OverlayRenderer.downsample(
            samples: series.samples.filter { $0.latitude != nil && $0.longitude != nil },
            limit: config.routePointLimit
        )
    }

    public func render(videoTime: TimeInterval, into pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw OverlayVideoError.cannotCreateBitmapContext
        }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(canvas)
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        let telemetryTime = config.timeSync.fitElapsed(forVideoTime: videoTime)
        let sample = series.sample(at: telemetryTime)

        for element in config.layout.visibleElements {
            switch element.kind {
            case .topProgress:
                drawTopProgress(context: context, sample: sample, canvas: canvas, element: element)
            case .speed:
                drawSpeed(context: context, sample: sample, canvas: canvas, element: element)
            case .pace:
                drawMetricComponent(
                    element,
                    label: "PACE",
                    value: formatPace(sample.speedMetersPerSecond),
                    unit: "/KM",
                    context: context,
                    canvas: canvas
                )
            case .distance:
                drawMetricComponent(
                    element,
                    label: "DIST",
                    value: formatDistance(sample.distanceMeters, element: element),
                    unit: config.distanceUnit.symbol,
                    context: context,
                    canvas: canvas
                )
            case .heartRate:
                drawMetricComponent(
                    element,
                    label: "HR",
                    value: sample.heartRate.map { "\($0)" } ?? "--",
                    unit: "BPM",
                    context: context,
                    canvas: canvas
                )
            case .cadence:
                drawMetricComponent(
                    element,
                    label: "CAD",
                    value: sample.cadence.map { "\($0)" } ?? "--",
                    unit: "SPM",
                    context: context,
                    canvas: canvas
                )
            case .route:
                drawRoute(context: context, sample: sample, canvas: canvas, element: element)
            case .timeDate:
                drawTimeDate(context: context, sample: sample, canvas: canvas, element: element)
            }
        }
    }

    private func drawSpeed(context: CGContext, sample: TelemetrySample, canvas: CGRect, element: OverlayElement) {
        let scale = componentScale(element, canvas: canvas)
        let textScale = scale * componentTextScale(element)
        let panel = componentRect(element, baseSize: baseSize(for: element.kind), canvas: canvas)
        let accent = componentAccent(element)

        drawPanelBackground(context, panel, element: element, radius: 20 * scale)

        if element.customization.showsLabel {
            drawText(
                element.customization.label(default: "RUN"),
                context: context,
                baseline: CGPoint(x: panel.minX + 30 * scale, y: panel.maxY - 32 * scale),
                size: labelSize(15, scale: scale, element: element),
                color: labelColor(element),
                fontName: labelFontName(element)
            )
        }

        drawText(
            formatElapsed(sample.elapsed),
            context: context,
            baseline: CGPoint(x: panel.minX + 30 * scale, y: panel.maxY - 62 * scale),
            size: unitSize(24, scale: textScale, element: element),
            color: unitColor(element),
            fontName: unitFontName(element)
        )

        drawIconIfNeeded(element, defaultIcon: "SPD", context: context, baseline: CGPoint(x: panel.maxX - 68 * scale, y: panel.maxY - 32 * scale), size: 13 * scale)

        let speedKmh = max(0, sample.speedMetersPerSecond ?? 0) * 3.6
        let center = CGPoint(x: panel.minX + 154 * scale, y: panel.minY + 100 * scale)
        let gaugeMinimum = element.customization.gaugeMinimum ?? 0
        let gaugeMaximum = max(gaugeMinimum + 1, element.customization.gaugeMaximum ?? 24)
        drawGauge(
            context: context,
            center: center,
            radius: 76 * scale,
            progress: min(1, max(0, (speedKmh - gaugeMinimum) / (gaugeMaximum - gaugeMinimum))),
            scale: scale,
            accent: accent,
            label: element.customization.label(default: "SPEED"),
            minimum: gaugeMinimum,
            maximum: gaugeMaximum,
            showsLabels: element.customization.showsLabel,
            element: element
        )

        drawText(
            formatSpeed(sample.speedMetersPerSecond, precision: element.customization.valuePrecision),
            context: context,
            baseline: CGPoint(x: panel.minX + 196 * scale, y: panel.minY + 122 * scale),
            size: valueSize(76, scale: textScale, element: element),
            color: valueColor(element),
            fontName: valueFontName(element)
        )

        if element.customization.showsUnit {
            drawText(
                element.customization.unit(default: "KM/H"),
                context: context,
                baseline: CGPoint(x: panel.minX + 252 * scale, y: panel.minY + 67 * scale),
                size: unitSize(17, scale: textScale, element: element),
                color: unitColor(element),
                fontName: unitFontName(element)
            )
        }

        if showsGaugeTicks(element) {
            drawNeedleTicks(context: context, center: center, radius: 91 * scale, scale: scale, element: element)
        }
    }

    private func drawGauge(
        context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        progress: Double,
        scale: CGFloat,
        accent: CGColor,
        label: String,
        minimum: Double,
        maximum: Double,
        showsLabels: Bool,
        element: OverlayElement
    ) {
        let start = degreesToRadians(224)
        let end = degreesToRadians(-44)
        context.setLineCap(.round)
        context.setLineWidth(lineWidth(element, scale: scale))
        context.setStrokeColor(trackColor(element))
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        context.strokePath()

        let progressAngle = start + ((end - start) * CGFloat(progress))
        context.setStrokeColor(accent)
        context.addArc(center: center, radius: radius, startAngle: start, endAngle: progressAngle, clockwise: true)
        context.strokePath()

        if element.customization.showsPanel {
            context.setLineWidth(max(0.5, lineWidth(element, scale: scale) * 0.12))
            context.setStrokeColor(Colors.panelStroke)
            context.strokeEllipse(in: CGRect(
                x: center.x - (radius - 22 * scale),
                y: center.y - (radius - 22 * scale),
                width: (radius - 22 * scale) * 2,
                height: (radius - 22 * scale) * 2
            ))
        }

        if showsLabels {
            drawText(
                label,
                context: context,
                baseline: CGPoint(x: center.x - 32 * scale, y: center.y + 8 * scale),
                size: labelSize(12, scale: scale, element: element),
                color: labelColor(element),
                fontName: labelFontName(element)
            )

            let rangeLabel = "\(formatGaugeEdge(minimum))        \(formatGaugeEdge(maximum))"
            drawText(
                rangeLabel,
                context: context,
                baseline: CGPoint(x: center.x - 58 * scale, y: center.y - 30 * scale),
                size: unitSize(12, scale: scale, element: element),
                color: unitColor(element),
                fontName: unitFontName(element)
            )
        }
    }

    private func drawNeedleTicks(context: CGContext, center: CGPoint, radius: CGFloat, scale: CGFloat, element: OverlayElement) {
        context.setStrokeColor(unitColor(element).copy(alpha: 0.42) ?? Colors.tick)
        context.setLineWidth(max(0.8, lineWidth(element, scale: scale) * 0.12))
        for index in 0...12 {
            let ratio = CGFloat(index) / 12
            let angle = degreesToRadians(224 - (268 * ratio))
            let inner = CGPoint(
                x: center.x + cos(angle) * (radius - 12 * scale),
                y: center.y + sin(angle) * (radius - 12 * scale)
            )
            let outer = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            context.move(to: inner)
            context.addLine(to: outer)
        }
        context.strokePath()
    }

    private func drawMetricComponent(
        _ element: OverlayElement,
        label: String,
        value: String,
        unit: String,
        context: CGContext,
        canvas: CGRect
    ) {
        let scale = componentScale(element, canvas: canvas)
        let textScale = scale * componentTextScale(element)
        let rect = componentRect(element, baseSize: baseSize(for: element.kind), canvas: canvas)
        drawMetricTile(
            element: element,
            label: element.customization.label(default: label),
            value: value,
            unit: element.customization.unit(default: unit),
            rect: rect,
            scale: scale,
            textScale: textScale,
            context: context,
            accent: componentAccent(element)
        )
    }

    private func drawMetricTile(
        element: OverlayElement,
        label: String,
        value: String,
        unit: String,
        rect: CGRect,
        scale: CGFloat,
        textScale: CGFloat,
        context: CGContext,
        accent: CGColor
    ) {
        if element.customization.showsPanel {
            fillRoundedRect(context, rect, radius: 13 * scale, color: Colors.tile(opacity: componentPanelOpacity(element) * 0.88))
            strokeRoundedRect(context, rect, radius: 13 * scale, color: Colors.tileStroke, lineWidth: 1 * scale)
        }

        if element.customization.showsLabel {
            drawText(
                label,
                context: context,
                baseline: CGPoint(x: rect.minX + 12 * scale, y: rect.maxY - 17 * scale),
                size: labelSize(10, scale: textScale, element: element),
                color: labelColor(element),
                fontName: labelFontName(element)
            )
        }
        drawIconIfNeeded(element, defaultIcon: defaultIcon(for: element.kind), context: context, baseline: CGPoint(x: rect.maxX - 36 * scale, y: rect.maxY - 17 * scale), size: 10 * textScale)

        drawText(
            value,
            context: context,
            baseline: CGPoint(x: rect.minX + 12 * scale, y: rect.minY + 18 * scale),
            size: valueSize(23, scale: textScale, element: element),
            color: valueColor(element, fallback: accent),
            fontName: valueFontName(element)
        )
        if element.customization.showsUnit {
            let size = unitSize(10, scale: textScale, element: element)
            let unitWidth = textWidth(unit, size: size, fontName: unitFontName(element))
            drawText(
                unit,
                context: context,
                baseline: CGPoint(x: rect.maxX - 12 * scale - unitWidth, y: rect.minY + 18 * scale),
                size: size,
                color: unitColor(element),
                fontName: unitFontName(element)
            )
        }
    }

    private func drawRoute(context: CGContext, sample: TelemetrySample, canvas: CGRect, element: OverlayElement) {
        guard let bounds = series.bounds, routePoints.count > 1 else { return }

        let scale = componentScale(element, canvas: canvas)
        let panel = componentRect(element, baseSize: baseSize(for: element.kind), canvas: canvas)
        let mapRect = panel.insetBy(dx: 26 * scale, dy: 34 * scale)
        let accent = componentAccent(element)

        drawPanelBackground(context, panel, element: element, radius: 20 * scale)
        if element.customization.showsLabel {
            drawText(
                element.customization.label(default: "GPS ROUTE"),
                context: context,
                baseline: CGPoint(x: panel.minX + 24 * scale, y: panel.maxY - 26 * scale),
                size: labelSize(13, scale: scale, element: element),
                color: labelColor(element),
                fontName: labelFontName(element)
            )
        }
        drawIconIfNeeded(element, defaultIcon: "GPS", context: context, baseline: CGPoint(x: panel.maxX - 70 * scale, y: panel.maxY - 26 * scale), size: 12 * scale)
        if element.customization.showsUnit {
            drawRouteDistance(context: context, panel: panel, sample: sample, scale: scale, element: element)
        }

        let points = routePoints.compactMap { point(for: $0, in: routeFitRect(mapRect, bounds: bounds), bounds: bounds) }
        guard points.count > 1 else { return }

        context.setStrokeColor(valueColor(element, fallback: accent).copy(alpha: 0.16) ?? Colors.routeGlow)
        context.setLineWidth(max(1, lineWidth(element, scale: scale) * 1.8))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        strokePolyline(points, context: context)

        context.setStrokeColor(trackColor(element).copy(alpha: 0.62) ?? Colors.routeBase)
        context.setLineWidth(max(0.5, lineWidth(element, scale: scale) * 0.82))
        strokePolyline(points, context: context)

        let elapsedPoints = routePoints.filter { $0.elapsed <= sample.elapsed }
            .compactMap { point(for: $0, in: routeFitRect(mapRect, bounds: bounds), bounds: bounds) }
        if elapsedPoints.count > 1 {
            context.setStrokeColor(valueColor(element, fallback: accent))
            context.setLineWidth(lineWidth(element, scale: scale))
            strokePolyline(elapsedPoints, context: context)
        }

        if let current = point(for: sample, in: routeFitRect(mapRect, bounds: bounds), bounds: bounds) {
            context.setFillColor(valueColor(element, fallback: Colors.white))
            context.fillEllipse(in: CGRect(
                x: current.x - 6 * scale,
                y: current.y - 6 * scale,
                width: 12 * scale,
                height: 12 * scale
            ))
            context.setStrokeColor(valueColor(element, fallback: accent))
            context.setLineWidth(max(1, lineWidth(element, scale: scale) * 0.55))
            context.strokeEllipse(in: CGRect(
                x: current.x - 12 * scale,
                y: current.y - 12 * scale,
                width: 24 * scale,
                height: 24 * scale
            ))
        }
    }

    private func drawTimeDate(context: CGContext, sample: TelemetrySample, canvas: CGRect, element: OverlayElement) {
        let scale = componentScale(element, canvas: canvas)
        let textScale = scale * componentTextScale(element)
        let panel = componentRect(element, baseSize: baseSize(for: element.kind), canvas: canvas)
        let right = panel.maxX

        drawPanelBackground(context, panel, element: element, radius: 12 * scale)

        if element.customization.showsIcon {
            drawIconIfNeeded(
                element,
                defaultIcon: "TIME",
                context: context,
                baseline: CGPoint(x: panel.minX, y: panel.maxY - 28 * scale),
                size: 12 * textScale
            )
        }

        if element.customization.showsLabel {
            drawRightAlignedText(
                element.customization.label(default: "TIME"),
                context: context,
                rightX: right,
                baselineY: panel.maxY - 10 * scale,
                size: labelSize(11, scale: textScale, element: element),
                color: labelColor(element),
                fontName: labelFontName(element)
            )
        }

        drawRightAlignedText(
            formatClockDuration(sample.elapsed),
            context: context,
            rightX: right,
            baselineY: panel.maxY - 34 * scale,
            size: valueSize(24, scale: textScale, element: element),
            color: valueColor(element),
            fontName: valueFontName(element)
        )

        guard element.customization.showsUnit else { return }
        drawRightAlignedText(
            formatClockTime(sample.date),
            context: context,
            rightX: right,
            baselineY: panel.maxY - 66 * scale,
            size: unitSize(22, scale: textScale, element: element),
            color: unitColor(element),
            fontName: unitFontName(element)
        )
        drawRightAlignedText(
            formatCalendarDate(sample.date),
            context: context,
            rightX: right,
            baselineY: panel.maxY - 96 * scale,
            size: unitSize(18, scale: textScale, element: element),
            color: unitColor(element),
            fontName: unitFontName(element)
        )
    }

    private func drawTopProgress(context: CGContext, sample: TelemetrySample, canvas: CGRect, element: OverlayElement) {
        let scale = componentScale(element, canvas: canvas)
        let textScale = scale * componentTextScale(element)
        let rect = componentRect(element, baseSize: baseSize(for: element.kind), canvas: canvas)
        let displayedTotalDistance = max(totalDistanceMeters(), sample.distanceMeters ?? 0)
        let currentDistance = max(0, min(sample.distanceMeters ?? 0, displayedTotalDistance))
        let progress = displayedTotalDistance > 0 ? min(1, max(0, currentDistance / displayedTotalDistance)) : 0
        let accent = componentAccent(element)

        let trackHeight = lineWidth(element, scale: scale)
        let track = CGRect(
            x: rect.minX + 72 * scale,
            y: rect.midY - trackHeight / 2,
            width: max(1, rect.width - 144 * scale),
            height: trackHeight
        )

        if element.customization.showsPanel {
            fillRoundedRect(context, track.insetBy(dx: -2 * scale, dy: -2 * scale), radius: 6 * scale, color: Colors.panel(opacity: componentPanelOpacity(element) * 0.55))
        }
        fillRoundedRect(context, track, radius: trackHeight / 2, color: trackColor(element))

        var filled = track
        filled.size.width *= CGFloat(progress)
        fillRoundedRect(context, filled, radius: trackHeight / 2, color: valueColor(element, fallback: accent))

        let knobX = track.minX + track.width * CGFloat(progress)
        let knobRadius = max(4 * scale, trackHeight * 0.82)
        context.setFillColor(valueColor(element, fallback: Colors.white))
        context.fillEllipse(in: CGRect(
            x: knobX - knobRadius,
            y: track.midY - knobRadius,
            width: knobRadius * 2,
            height: knobRadius * 2
        ))
        context.setStrokeColor(valueColor(element, fallback: accent))
        context.setLineWidth(max(1, trackHeight * 0.22))
        context.strokeEllipse(in: CGRect(
            x: knobX - knobRadius - 4 * scale,
            y: track.midY - knobRadius - 4 * scale,
            width: (knobRadius + 4 * scale) * 2,
            height: (knobRadius + 4 * scale) * 2
        ))

        if element.customization.showsLabel {
            let startLabel = distanceLabel(0, element: element)
            drawText(
                startLabel,
                context: context,
                baseline: CGPoint(x: rect.minX, y: rect.midY + 4 * scale),
                size: labelSize(15, scale: textScale, element: element),
                color: labelColor(element),
                fontName: labelFontName(element)
            )

            let currentLabel = distanceLabel(currentDistance, element: element)
            let currentSize = labelSize(12, scale: textScale, element: element)
            let currentWidth = textWidth(currentLabel, size: currentSize, fontName: labelFontName(element))
            drawText(
                currentLabel,
                context: context,
                baseline: CGPoint(x: min(track.maxX - currentWidth, max(track.minX, knobX - currentWidth / 2)), y: track.minY - 10 * scale),
                size: currentSize,
                color: labelColor(element),
                fontName: labelFontName(element)
            )
        }
        if element.customization.showsUnit {
            let endLabel = distanceLabel(displayedTotalDistance, element: element)
            let size = unitSize(15, scale: textScale, element: element)
            let endWidth = textWidth(endLabel, size: size, fontName: unitFontName(element))
            drawText(
                endLabel,
                context: context,
                baseline: CGPoint(x: rect.maxX - endWidth, y: rect.midY + 4 * scale),
                size: size,
                color: unitColor(element),
                fontName: unitFontName(element)
            )
        }
        drawIconIfNeeded(element, defaultIcon: "DIST", context: context, baseline: CGPoint(x: track.minX - 52 * scale, y: rect.midY + 4 * scale), size: 12 * textScale)
    }

    private func drawRouteDistance(context: CGContext, panel: CGRect, sample: TelemetrySample, scale: CGFloat, element: OverlayElement) {
        let value = formatDistance(sample.distanceMeters, element: element)
        let unit = element.customization.unit(default: config.distanceUnit.symbol)
        let unitSize = unitSize(10, scale: scale, element: element)
        let valueSize = valueSize(18, scale: scale, element: element)
        let unitWidth = textWidth(unit, size: unitSize, fontName: unitFontName(element))
        let valueWidth = textWidth(value, size: valueSize, fontName: valueFontName(element))
        let unitX = panel.maxX - 24 * scale - unitWidth
        let valueX = unitX - 7 * scale - valueWidth
        let baselineY = panel.maxY - 27 * scale

        drawText(
            value,
            context: context,
            baseline: CGPoint(x: valueX, y: baselineY),
            size: valueSize,
            color: valueColor(element),
            fontName: valueFontName(element)
        )
        drawText(
            unit,
            context: context,
            baseline: CGPoint(x: unitX, y: baselineY),
            size: unitSize,
            color: unitColor(element),
            fontName: unitFontName(element)
        )
    }

    private func point(for sample: TelemetrySample, in rect: CGRect, bounds: GeoBounds) -> CGPoint? {
        guard let latitude = sample.latitude, let longitude = sample.longitude else { return nil }
        let latSpan = max(bounds.maxLatitude - bounds.minLatitude, 0.000_001)
        let lonSpan = max(bounds.maxLongitude - bounds.minLongitude, 0.000_001)
        let x = rect.minX + CGFloat((longitude - bounds.minLongitude) / lonSpan) * rect.width
        let y = rect.minY + CGFloat((latitude - bounds.minLatitude) / latSpan) * rect.height
        return CGPoint(x: x, y: y)
    }

    private func routeFitRect(_ rect: CGRect, bounds: GeoBounds) -> CGRect {
        let latSpan = max(bounds.maxLatitude - bounds.minLatitude, 0.000_001)
        let lonSpan = max(bounds.maxLongitude - bounds.minLongitude, 0.000_001)
        let routeAspect = CGFloat(lonSpan / latSpan)
        let rectAspect = rect.width / rect.height
        if routeAspect > rectAspect {
            let height = rect.width / routeAspect
            return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        }
        let width = rect.height * routeAspect
        return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
    }

    private func strokePolyline(_ points: [CGPoint], context: CGContext) {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private func layoutScale(_ canvas: CGRect) -> CGFloat {
        max(0.28, min(canvas.width / 1920, canvas.height / 1080))
    }

    private func componentScale(_ element: OverlayElement, canvas: CGRect) -> CGFloat {
        layoutScale(canvas) * CGFloat(element.frame.scale)
    }

    private func componentTextScale(_ element: OverlayElement) -> CGFloat {
        CGFloat(element.frame.style.textScale)
    }

    private func componentAccent(_ element: OverlayElement) -> CGColor {
        if let valueColor = element.customization.valueColor {
            return valueColor.cgColor
        }
        return (element.frame.style.accentColor ?? config.layout.style.accentColor).cgColor
    }

    private func componentPanelOpacity(_ element: OverlayElement) -> Double {
        element.frame.style.panelOpacity ?? config.layout.style.panelOpacity
    }

    private func componentRect(_ element: OverlayElement, baseSize: CGSize, canvas: CGRect) -> CGRect {
        let frame = element.frame
        let scale = componentScale(element, canvas: canvas)
        let width = baseSize.width * scale * componentLengthScale(element)
        let height = baseSize.height * scale
        let topLeftX = canvas.minX + canvas.width * CGFloat(frame.x)
        let topLeftY = canvas.minY + canvas.height * CGFloat(frame.y)
        return CGRect(
            x: topLeftX,
            y: canvas.maxY - topLeftY - height,
            width: width,
            height: height
        )
    }

    private func baseSize(for kind: OverlayComponentID) -> CGSize {
        switch kind {
        case .speed:
            return CGSize(width: 420, height: 238)
        case .pace, .heartRate, .cadence, .distance:
            return CGSize(width: 160, height: 74)
        case .route:
            return CGSize(width: 382, height: 238)
        case .topProgress:
            return CGSize(width: 1650, height: 58)
        case .timeDate:
            return CGSize(width: 300, height: 118)
        }
    }

    private func showsGaugeTicks(_ element: OverlayElement) -> Bool {
        element.customization.showGaugeTicks ?? config.layout.style.showGaugeTicks
    }

    private func componentLengthScale(_ element: OverlayElement) -> CGFloat {
        CGFloat(max(0.1, element.customization.lengthScale))
    }

    private func lineWidth(_ element: OverlayElement, scale: CGFloat) -> CGFloat {
        max(0.25, CGFloat(element.customization.lineWidth) * scale)
    }

    private func labelColor(_ element: OverlayElement) -> CGColor {
        (element.customization.labelColor ?? .label).cgColor
    }

    private func valueColor(_ element: OverlayElement, fallback: CGColor? = nil) -> CGColor {
        element.customization.valueColor?.cgColor ?? fallback ?? componentAccent(element)
    }

    private func unitColor(_ element: OverlayElement) -> CGColor {
        (element.customization.unitColor ?? .muted).cgColor
    }

    private func iconColor(_ element: OverlayElement) -> CGColor {
        (element.customization.iconColor ?? element.customization.labelColor ?? .label).cgColor
    }

    private func trackColor(_ element: OverlayElement) -> CGColor {
        (element.customization.trackColor ?? .track).cgColor
    }

    private func labelFontName(_ element: OverlayElement) -> CFString {
        element.customization.labelFont.postScriptName as CFString
    }

    private func valueFontName(_ element: OverlayElement) -> CFString {
        element.customization.valueFont.postScriptName as CFString
    }

    private func unitFontName(_ element: OverlayElement) -> CFString {
        element.customization.unitFont.postScriptName as CFString
    }

    private func iconFontName(_ element: OverlayElement) -> CFString {
        element.customization.iconFont.postScriptName as CFString
    }

    private func labelSize(_ base: CGFloat, scale: CGFloat, element: OverlayElement) -> CGFloat {
        base * scale * CGFloat(element.customization.labelScale)
    }

    private func valueSize(_ base: CGFloat, scale: CGFloat, element: OverlayElement) -> CGFloat {
        base * scale * CGFloat(element.customization.valueScale)
    }

    private func unitSize(_ base: CGFloat, scale: CGFloat, element: OverlayElement) -> CGFloat {
        base * scale * CGFloat(element.customization.unitScale)
    }

    private func iconSize(_ base: CGFloat, scale: CGFloat, element: OverlayElement) -> CGFloat {
        base * scale * CGFloat(element.customization.iconScale)
    }

    private func drawIconIfNeeded(
        _ element: OverlayElement,
        defaultIcon: String,
        context: CGContext,
        baseline: CGPoint,
        size: CGFloat
    ) {
        guard element.customization.showsIcon else { return }
        drawText(
            element.customization.icon(default: defaultIcon),
            context: context,
            baseline: baseline,
            size: iconSize(size, scale: 1, element: element),
            color: iconColor(element),
            fontName: iconFontName(element)
        )
    }

    private func defaultIcon(for kind: OverlayComponentID) -> String {
        switch kind {
        case .speed:
            return "SPD"
        case .pace:
            return "PACE"
        case .heartRate:
            return "HR"
        case .cadence:
            return "CAD"
        case .distance:
            return "DIST"
        case .route:
            return "GPS"
        case .topProgress:
            return "DIST"
        case .timeDate:
            return "TIME"
        }
    }

    private func drawText(
        _ text: String,
        context: CGContext,
        baseline: CGPoint,
        size: CGFloat,
        color: CGColor,
        fontName: CFString
    ) {
        let font = CTFontCreateWithName(fontName, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = baseline
        CTLineDraw(line, context)
    }

    private func drawRightAlignedText(
        _ text: String,
        context: CGContext,
        rightX: CGFloat,
        baselineY: CGFloat,
        size: CGFloat,
        color: CGColor,
        fontName: CFString
    ) {
        let width = textWidth(text, size: size, fontName: fontName)
        drawText(
            text,
            context: context,
            baseline: CGPoint(x: rightX - width, y: baselineY),
            size: size,
            color: color,
            fontName: fontName
        )
    }

    private func textWidth(_ text: String, size: CGFloat, fontName: CFString) -> CGFloat {
        let font = CTFontCreateWithName(fontName, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func fillRoundedRect(_ context: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
        context.setFillColor(color)
        context.addPath(roundedPath(rect: rect, radius: radius))
        context.fillPath()
    }

    private func strokeRoundedRect(
        _ context: CGContext,
        _ rect: CGRect,
        radius: CGFloat,
        color: CGColor,
        lineWidth: CGFloat
    ) {
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.addPath(roundedPath(rect: rect, radius: radius))
        context.strokePath()
    }

    private func drawPanelBackground(_ context: CGContext, _ rect: CGRect, element: OverlayElement, radius: CGFloat) {
        guard element.customization.showsPanel else { return }
        fillRoundedRect(context, rect, radius: radius, color: Colors.panel(opacity: componentPanelOpacity(element)))
        strokeRoundedRect(context, rect, radius: radius, color: Colors.panelStroke, lineWidth: 1.4)

        let topLine = CGRect(x: rect.minX + 18, y: rect.maxY - 1.5, width: rect.width - 36, height: 1)
        fillRoundedRect(context, topLine, radius: 0.5, color: Colors.panelHighlight)
    }

    private func roundedPath(rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        return path
    }

    private func degreesToRadians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    private func formatSpeed(_ metersPerSecond: Double?, precision: Int? = nil) -> String {
        guard let metersPerSecond, metersPerSecond.isFinite else { return "--.-" }
        let digits = min(2, max(0, precision ?? 1))
        return String(format: "%0\(digits + 3).\(digits)f", metersPerSecond * 3.6)
    }

    private func formatDistance(_ meters: Double?, element: OverlayElement) -> String {
        guard let meters, meters.isFinite else { return "--" }
        if let valuePrecision = element.customization.valuePrecision {
            let digits = min(3, max(0, valuePrecision))
            switch config.distanceUnit {
            case .meters:
                return String(format: "%.\(digits)f", meters)
            case .kilometers:
                return String(format: "%.\(digits)f", meters / 1000)
            }
        }
        return config.distanceUnit.format(meters: meters)
    }

    private func distanceLabel(_ meters: Double?, element: OverlayElement) -> String {
        "\(formatDistance(meters, element: element)) \(element.customization.unit(default: config.distanceUnit.symbol))"
    }

    private func totalDistanceMeters() -> Double {
        samplesLastDistance() ?? 0
    }

    private func samplesLastDistance() -> Double? {
        series.samples.reversed().first { sample in
            guard let distance = sample.distanceMeters else { return false }
            return distance.isFinite
        }?.distanceMeters
    }

    private func formatPace(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond > 0.3 else { return "--:--" }
        let secondsPerKm = Int((1000 / metersPerSecond).rounded())
        return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func formatClockDuration(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed.rounded()))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func formatClockTime(_ date: Date?) -> String {
        guard let date else { return "--:--:--" }
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
    }

    private func formatCalendarDate(_ date: Date?) -> String {
        guard let date else { return "----/--/--" }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func formatGaugeEdge(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private static func downsample(samples: [TelemetrySample], limit: Int) -> [TelemetrySample] {
        guard limit > 0, samples.count > limit else { return samples }
        let stride = max(1, samples.count / limit)
        return samples.enumerated().compactMap { index, sample in
            index % stride == 0 || index == samples.count - 1 ? sample : nil
        }
    }
}

private enum Colors {
    static let white = CGColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.96)
    static let muted = CGColor(red: 0.66, green: 0.72, blue: 0.78, alpha: 0.82)
    static let label = CGColor(red: 0.74, green: 0.80, blue: 0.86, alpha: 0.92)
    static func panel(opacity: Double) -> CGColor {
        CGColor(red: 0.015, green: 0.017, blue: 0.020, alpha: min(0.95, max(0.12, opacity)))
    }
    static func tile(opacity: Double) -> CGColor {
        CGColor(red: 0.035, green: 0.041, blue: 0.048, alpha: min(0.90, max(0.10, opacity)))
    }
    static let panelStroke = CGColor(red: 1, green: 1, blue: 1, alpha: 0.20)
    static let panelHighlight = CGColor(red: 1, green: 1, blue: 1, alpha: 0.30)
    static let tileStroke = CGColor(red: 1, green: 1, blue: 1, alpha: 0.12)
    static let track = CGColor(red: 1, green: 1, blue: 1, alpha: 0.14)
    static let gaugeTrack = CGColor(red: 1, green: 1, blue: 1, alpha: 0.17)
    static let tick = CGColor(red: 1, green: 1, blue: 1, alpha: 0.28)
    static let routeGlow = CGColor(red: 0.10, green: 0.95, blue: 0.70, alpha: 0.16)
    static let routeBase = CGColor(red: 1, green: 1, blue: 1, alpha: 0.30)
    static let cyan = CGColor(red: 0.45, green: 0.82, blue: 1.00, alpha: 0.96)
    static let red = CGColor(red: 1.00, green: 0.38, blue: 0.42, alpha: 0.96)
    static let amber = CGColor(red: 1.00, green: 0.76, blue: 0.35, alpha: 0.96)
}
