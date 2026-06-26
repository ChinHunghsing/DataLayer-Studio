import CoreGraphics
import CoreText
import CoreVideo
import Darwin
import Foundation

public final class OverlayRenderer {
    private let series: TelemetrySeries
    private let config: OverlayRenderConfig
    private let routePoints: [RoutePoint]
    private let totalDistanceMeters: Double
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let fontCacheLock = NSLock()
    private var fontCache: [TextFontKey: CTFont] = [:]
    private static let textWidthCacheLock = NSLock()
    private static let maximumCachedTextWidths = 16_384
    private static var textWidthCache: [TextWidthKey: CGFloat] = [:]

    public init(series: TelemetrySeries, config: OverlayRenderConfig) {
        self.series = series
        self.config = config
        self.totalDistanceMeters = OverlayRenderer.lastFiniteDistance(samples: series.samples) ?? 0
        self.routePoints = OverlayRenderer.makeRoutePoints(
            samples: series.samples,
            bounds: series.bounds,
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
        memset(baseAddress, 0, bytesPerRow * height)

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
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        let rawTelemetryTime = config.timeSync.rawFitElapsed(forVideoTime: videoTime)
        let telemetryTime = config.timeSync.fitElapsed(forVideoTime: videoTime)
        let sample = series.sample(at: telemetryTime)
        let absoluteDate = series.date(atElapsed: rawTelemetryTime) ?? sample.date
        let metricTileWidth = alignedMetricTileWidth(sample: sample, canvas: canvas)

        for element in config.layout.visibleElements {
            switch element.kind {
            case .topProgress:
                drawTopProgress(context: context, sample: sample, canvas: canvas, element: element)
            case .speed:
                drawSpeed(context: context, sample: sample, canvas: canvas, element: element)
            case .pace, .distance, .heartRate, .cadence, .calories, .strideLength, .power, .weather:
                if let content = metricContent(for: element, sample: sample) {
                    drawMetricComponent(
                        element,
                        label: content.label,
                        value: content.value,
                        unit: content.unit,
                        alignedWidth: metricTileWidth,
                        context: context,
                        canvas: canvas
                    )
                }
            case .route:
                drawRoute(context: context, sample: sample, canvas: canvas, element: element)
            case .timeDate:
                drawTimeDate(context: context, sample: sample, absoluteDate: absoluteDate, canvas: canvas, element: element)
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

        if element.customization.showsPanel, element.customization.panelBorderIsVisible {
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
        alignedWidth: CGFloat?,
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
            alignedWidth: alignedWidth,
            context: context,
            accent: componentAccent(element)
        )
    }

    private func metricContent(
        for element: OverlayElement,
        sample: TelemetrySample
    ) -> (label: String, value: String, unit: String)? {
        switch element.kind {
        case .pace:
            return ("PACE", formatPace(sample.speedMetersPerSecond), "/KM")
        case .distance:
            return ("DIST", formatDistance(sample.distanceMeters, element: element), config.distanceUnit.symbol)
        case .heartRate:
            return ("HR", sample.heartRate.map { "\($0)" } ?? "--", "BPM")
        case .cadence:
            return ("CAD", sample.cadence.map { "\($0)" } ?? "--", "SPM")
        case .calories:
            return ("CAL", sample.totalCalories.map { "\(Int($0.rounded()))" } ?? "--", "KCAL")
        case .strideLength:
            return ("STRIDE", formatStrideLength(sample.stepLengthMeters, precision: element.customization.valuePrecision), "m")
        case .power:
            return ("PWR", sample.powerWatts.map { "\($0)" } ?? "--", "W")
        case .weather:
            return ("WEATHER", formatWeatherTemperature(sample), formatWeatherUnit(sample))
        default:
            return nil
        }
    }

    private func drawMetricTile(
        element: OverlayElement,
        label: String,
        value: String,
        unit: String,
        rect: CGRect,
        scale: CGFloat,
        textScale: CGFloat,
        alignedWidth: CGFloat?,
        context: CGContext,
        accent: CGColor
    ) {
        let labelFontSize = labelSize(10, scale: textScale, element: element)
        let valueFontSize = valueSize(23, scale: textScale, element: element)
        let unitFontSize = unitSize(10, scale: textScale, element: element)
        let iconFontSize = metricIconFontSize(element: element, textScale: textScale)
        let drawsWeatherIconInValueRow = element.kind == .weather && element.customization.showsIcon
        let drawsTopRowIcon = element.customization.showsIcon && !drawsWeatherIconInValueRow
        let hasTopRow = element.customization.showsLabel || drawsTopRowIcon
        let topRowHeight = hasTopRow ? max(labelFontSize, iconFontSize) : 0
        let valueRowHeight = max(
            valueFontSize,
            metricUnitBlockHeight(element: element, unit: unit, unitFontSize: unitFontSize, iconFontSize: iconFontSize, scale: scale)
        )
        let horizontalPadding = 14 * scale
        let topPadding = 9 * scale
        let bottomPadding = 14 * scale
        let rowGap = hasTopRow ? max(6 * scale, valueFontSize * 0.18) : 0
        let desiredHeight = max(rect.height, topPadding + topRowHeight + rowGap + valueRowHeight + bottomPadding)

        let iconText = element.customization.icon(default: defaultIcon(for: element.kind))
        let iconWidth = drawsTopRowIcon ? textWidth(iconText, size: iconFontSize, fontName: iconFontName(element)) : 0
        let desiredWidth = max(
            alignedWidth ?? 0,
            metricTileWidth(
                element: element,
                label: label,
                value: value,
                unit: unit,
                rectWidth: rect.width,
                scale: scale,
                valueFontSize: valueFontSize,
                unitFontSize: unitFontSize,
                labelFontSize: labelFontSize,
                iconFontSize: iconFontSize
            )
        )
        let tileRect = CGRect(x: rect.minX, y: rect.maxY - desiredHeight, width: desiredWidth, height: desiredHeight)

        if element.customization.showsPanel {
            let radius = 10 * scale
            drawElevatedSurface(context, tileRect, radius: radius, fill: Colors.tile(opacity: componentPanelOpacity(element) * 0.94))
            if element.customization.panelBorderIsVisible {
                strokeRoundedRect(context, tileRect, radius: radius, color: Colors.tileStroke, lineWidth: max(0.7, 0.8 * scale))
                drawTopHighlight(context, tileRect, radius: radius, inset: 11 * scale, color: Colors.tileHighlight)
            }
        }

        let topBaselineY = tileRect.maxY - topPadding - topRowHeight * 0.78
        if element.customization.showsLabel {
            drawText(
                label,
                context: context,
                baseline: CGPoint(x: tileRect.minX + horizontalPadding, y: topBaselineY),
                size: labelFontSize,
                color: labelColor(element),
                fontName: labelFontName(element)
            )
        }
        if drawsTopRowIcon {
            drawText(
                iconText,
                context: context,
                baseline: CGPoint(x: tileRect.maxX - horizontalPadding - iconWidth, y: topBaselineY),
                size: iconFontSize,
                color: iconColor(element),
                fontName: iconFontName(element)
            )
        }

        let valueBaselineY = tileRect.minY + bottomPadding + valueRowHeight * 0.24
        drawText(
            value,
            context: context,
            baseline: CGPoint(x: tileRect.minX + horizontalPadding, y: valueBaselineY),
            size: valueFontSize,
            color: valueColor(element, fallback: accent),
            fontName: valueFontName(element)
        )
        if element.customization.showsUnit {
            drawMetricUnitBlock(
                element: element,
                unit: unit,
                context: context,
                rightX: tileRect.maxX - horizontalPadding,
                centerBaselineY: valueBaselineY,
                unitFontSize: unitFontSize,
                iconFontSize: iconFontSize,
                scale: scale
            )
        }
    }

    private func alignedMetricTileWidth(sample: TelemetrySample, canvas: CGRect) -> CGFloat? {
        let widths = config.layout.visibleElements.compactMap { element -> CGFloat? in
            guard let content = metricContent(for: element, sample: sample) else { return nil }
            let scale = componentScale(element, canvas: canvas)
            let textScale = scale * componentTextScale(element)
            let rect = componentRect(element, baseSize: baseSize(for: element.kind), canvas: canvas)
            return metricTileWidth(
                element: element,
                label: element.customization.label(default: content.label),
                value: content.value,
                unit: element.customization.unit(default: content.unit),
                rectWidth: rect.width,
                scale: scale,
                valueFontSize: valueSize(23, scale: textScale, element: element),
                unitFontSize: unitSize(10, scale: textScale, element: element),
                labelFontSize: labelSize(10, scale: textScale, element: element),
                iconFontSize: metricIconFontSize(element: element, textScale: textScale)
            )
        }
        return widths.max()
    }

    private func metricTileWidth(
        element: OverlayElement,
        label: String,
        value: String,
        unit: String,
        rectWidth: CGFloat,
        scale: CGFloat,
        valueFontSize: CGFloat,
        unitFontSize: CGFloat,
        labelFontSize: CGFloat,
        iconFontSize: CGFloat
    ) -> CGFloat {
        let valueWidth = textWidth(value, size: valueFontSize, fontName: valueFontName(element))
        let unitWidth = metricUnitBlockWidth(element: element, unit: unit, unitFontSize: unitFontSize, iconFontSize: iconFontSize)
        let horizontalPadding = 14 * scale
        let unitGap = element.customization.showsUnit ? 10 * scale : 0
        let labelWidth = element.customization.showsLabel ? textWidth(label, size: labelFontSize, fontName: labelFontName(element)) : 0
        let iconText = element.customization.icon(default: defaultIcon(for: element.kind))
        let drawsTopRowIcon = element.customization.showsIcon && element.kind != .weather
        let iconWidth = drawsTopRowIcon ? textWidth(iconText, size: iconFontSize, fontName: iconFontName(element)) : 0
        let iconGap = drawsTopRowIcon ? 12 * scale : 0
        return max(
            rectWidth,
            (horizontalPadding * 2) + valueWidth + unitGap + unitWidth,
            (horizontalPadding * 2) + labelWidth + iconGap + iconWidth
        )
    }

    private func metricUnitLines(_ unit: String) -> [String] {
        let lines = unit.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.isEmpty ? [""] : lines
    }

    private func metricIconFontSize(element: OverlayElement, textScale: CGFloat) -> CGFloat {
        let base = element.kind == .weather ? 16 * textScale : 10 * textScale
        return iconSize(base, scale: 1, element: element)
    }

    private func metricUnitBlockWidth(
        element: OverlayElement,
        unit: String,
        unitFontSize: CGFloat,
        iconFontSize: CGFloat
    ) -> CGFloat {
        guard element.customization.showsUnit else { return 0 }
        var widths = metricUnitLines(unit).map { textWidth($0, size: unitFontSize, fontName: unitFontName(element)) }
        if element.kind == .weather, element.customization.showsIcon {
            widths[0] = textWidth(weatherIconText(element: element, summary: metricUnitLines(unit).first), size: iconFontSize, fontName: iconFontName(element))
        }
        return widths.max() ?? 0
    }

    private func metricUnitBlockHeight(
        element: OverlayElement,
        unit: String,
        unitFontSize: CGFloat,
        iconFontSize: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        guard element.customization.showsUnit else { return 0 }
        let lines = metricUnitLines(unit)
        let firstLineHeight = element.kind == .weather && element.customization.showsIcon ? iconFontSize : unitFontSize
        let remainingHeight = CGFloat(max(0, lines.count - 1)) * unitFontSize
        let gaps = CGFloat(max(0, lines.count - 1)) * metricUnitLineGap(element: element, unitFontSize: unitFontSize, scale: scale)
        return firstLineHeight + remainingHeight + gaps
    }

    private func drawMetricUnitBlock(
        element: OverlayElement,
        unit: String,
        context: CGContext,
        rightX: CGFloat,
        centerBaselineY: CGFloat,
        unitFontSize: CGFloat,
        iconFontSize: CGFloat,
        scale: CGFloat
    ) {
        let lines = metricUnitLines(unit)
        let step = max(unitFontSize, iconFontSize * 0.72) + metricUnitLineGap(element: element, unitFontSize: unitFontSize, scale: scale)
        let firstBaselineY = centerBaselineY + CGFloat(lines.count - 1) * step / 2
        for (index, line) in lines.enumerated() {
            let drawsIcon = index == 0 && element.kind == .weather && element.customization.showsIcon
            let text = drawsIcon ? weatherIconText(element: element, summary: line) : line
            let size = drawsIcon ? iconFontSize : unitFontSize
            let font = drawsIcon ? iconFontName(element) : unitFontName(element)
            let color = drawsIcon ? iconColor(element) : unitColor(element)
            drawRightAlignedText(
                text,
                context: context,
                rightX: rightX,
                baselineY: firstBaselineY - CGFloat(index) * step,
                size: size,
                color: color,
                fontName: font
            )
        }
    }

    private func metricUnitLineGap(element: OverlayElement, unitFontSize: CGFloat, scale: CGFloat) -> CGFloat {
        let baseGap = max(2 * scale, unitFontSize * 0.16)
        guard element.kind == .weather else { return baseGap }
        return baseGap * CGFloat(element.customization.weatherIconSpacingScale ?? 1)
    }

    private func weatherIconText(element: OverlayElement, summary: String?) -> String {
        if let override = element.customization.iconOverride,
           let icon = OverlayWeatherIcon(rawValue: override),
           icon != .auto {
            return icon.symbol
        }
        return OverlayWeatherIcon.icon(for: summary).symbol
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

        let fitRect = routeFitRect(mapRect, bounds: bounds)

        context.setStrokeColor(valueColor(element, fallback: accent).copy(alpha: 0.16) ?? Colors.routeGlow)
        context.setLineWidth(max(1, lineWidth(element, scale: scale) * 1.8))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        strokeRoute(routePoints, in: fitRect, context: context)

        context.setStrokeColor(trackColor(element).copy(alpha: 0.62) ?? Colors.routeBase)
        context.setLineWidth(max(0.5, lineWidth(element, scale: scale) * 0.82))
        strokeRoute(routePoints, in: fitRect, context: context)

        let elapsedCount = routePointCount(through: sample.elapsed)
        if elapsedCount > 1 {
            context.setStrokeColor(valueColor(element, fallback: accent))
            context.setLineWidth(lineWidth(element, scale: scale))
            strokeRoute(routePoints.prefix(elapsedCount), in: fitRect, context: context)
        }

        if let current = point(for: sample, in: fitRect, bounds: bounds) {
            drawRouteCurrentMarker(
                at: current,
                angle: routeDirectionAngle(for: sample, in: fitRect, bounds: bounds),
                context: context,
                scale: scale,
                element: element,
                accent: accent
            )
        }
    }

    private func drawTimeDate(
        context: CGContext,
        sample: TelemetrySample,
        absoluteDate: Date?,
        canvas: CGRect,
        element: OverlayElement
    ) {
        let scale = componentScale(element, canvas: canvas)
        let textScale = scale * componentTextScale(element)
        let basePanel = componentRect(element, baseSize: baseSize(for: element.kind), canvas: canvas)
        let labelFontSize = labelSize(11, scale: textScale, element: element)
        let valueFontSize = valueSize(24, scale: textScale, element: element)
        let clockFontSize = unitSize(22, scale: textScale, element: element)
        let dateFontSize = unitSize(18, scale: textScale, element: element)
        let iconFontSize = iconSize(12 * textScale, scale: 1, element: element)
        let topPadding = 15 * scale
        let bottomPadding = 12 * scale
        let valueGap = max(8 * scale, valueFontSize * 0.28)
        let unitGap = max(8 * scale, clockFontSize * 0.28)
        let topRowHeight = (element.customization.showsLabel || element.customization.showsIcon) ? max(labelFontSize, iconFontSize) : 0
        let topRowGap = topRowHeight > 0 ? max(6 * scale, topRowHeight * 0.25) : 0
        let requiredHeight = max(
            basePanel.height,
            topPadding + topRowHeight + topRowGap + valueFontSize
                + (element.customization.showsUnit ? valueGap + clockFontSize + unitGap + dateFontSize : 0)
                + bottomPadding
        )
        let elapsed = formatClockDuration(sample.elapsed)
        let clockAndDate = formatClockAndCalendarDate(absoluteDate)
        let clock = clockAndDate.clock
        let date = clockAndDate.date
        let label = element.customization.label(default: "TIME")
        let icon = element.customization.icon(default: "TIME")
        let requiredTextWidth = max(
            textWidth(elapsed, size: valueFontSize, fontName: valueFontName(element)),
            element.customization.showsUnit ? textWidth(clock, size: clockFontSize, fontName: unitFontName(element)) : 0,
            element.customization.showsUnit ? textWidth(date, size: dateFontSize, fontName: unitFontName(element)) : 0,
            element.customization.showsLabel ? textWidth(label, size: labelFontSize, fontName: labelFontName(element)) : 0
        )
        let iconWidth = element.customization.showsIcon ? textWidth(icon, size: iconFontSize, fontName: iconFontName(element)) : 0
        let requiredWidth = max(basePanel.width, requiredTextWidth + iconWidth + 28 * scale)
        let panel = CGRect(
            x: basePanel.maxX - requiredWidth,
            y: basePanel.maxY - requiredHeight,
            width: requiredWidth,
            height: requiredHeight
        )
        let right = panel.maxX

        drawPanelBackground(context, panel, element: element, radius: 12 * scale)

        var cursorTop = panel.maxY - topPadding
        if element.customization.showsIcon {
            drawText(
                icon,
                context: context,
                baseline: CGPoint(x: panel.minX, y: cursorTop - topRowHeight * 0.78),
                size: iconFontSize,
                color: iconColor(element),
                fontName: iconFontName(element)
            )
        }

        if element.customization.showsLabel {
            drawRightAlignedText(
                label,
                context: context,
                rightX: right,
                baselineY: cursorTop - topRowHeight * 0.78,
                size: labelFontSize,
                color: labelColor(element),
                fontName: labelFontName(element)
            )
        }

        if topRowHeight > 0 {
            cursorTop -= topRowHeight + topRowGap
        }

        let elapsedBaselineY = cursorTop - valueFontSize * 0.78
        drawRightAlignedText(
            elapsed,
            context: context,
            rightX: right,
            baselineY: elapsedBaselineY,
            size: valueFontSize,
            color: valueColor(element),
            fontName: valueFontName(element)
        )

        guard element.customization.showsUnit else { return }
        cursorTop -= valueFontSize + valueGap
        let clockBaselineY = cursorTop - clockFontSize * 0.78
        drawRightAlignedText(
            clock,
            context: context,
            rightX: right,
            baselineY: clockBaselineY,
            size: clockFontSize,
            color: unitColor(element),
            fontName: unitFontName(element)
        )
        cursorTop -= clockFontSize + unitGap
        drawRightAlignedText(
            date,
            context: context,
            rightX: right,
            baselineY: cursorTop - dateFontSize * 0.78,
            size: dateFontSize,
            color: unitColor(element),
            fontName: unitFontName(element)
        )
    }

    private func drawTopProgress(context: CGContext, sample: TelemetrySample, canvas: CGRect, element: OverlayElement) {
        let scale = componentScale(element, canvas: canvas)
        let textScale = scale * componentTextScale(element)
        let rect = componentRect(element, baseSize: baseSize(for: element.kind), canvas: canvas)
        let displayedTotalDistance = max(totalDistanceMeters, sample.distanceMeters ?? 0)
        let currentDistance = max(0, min(sample.distanceMeters ?? 0, displayedTotalDistance))
        let progress = displayedTotalDistance > 0 ? min(1, max(0, currentDistance / displayedTotalDistance)) : 0
        let accent = componentAccent(element)

        let trackHeight = lineWidth(element, scale: scale)
        let startLabelSize = labelSize(15, scale: textScale, element: element)
        let currentLabelSize = valueSize(12, scale: textScale, element: element)
        let endLabelSize = unitSize(15, scale: textScale, element: element)
        let iconFontSize = iconSize(12 * textScale, scale: 1, element: element)
        let topRowHeight = max(
            element.customization.showsLabel ? startLabelSize : 0,
            element.customization.showsUnit ? endLabelSize : 0,
            element.customization.showsIcon ? iconFontSize : 0
        )
        let bottomRowHeight = element.customization.showsLabel ? currentLabelSize : 0
        let topPadding = 8 * scale
        let topGap = topRowHeight > 0 ? max(5 * scale, topRowHeight * 0.18) : 0
        let knobRadius = max(4 * scale, trackHeight * 0.82 * progressKnobScale(element))
        let outerRadius = knobRadius + max(2 * scale, knobRadius * 0.28)
        let tickRadius = showsGaugeTicks(element) ? trackHeight * 1.225 : trackHeight / 2
        let trackUpExtent = max(trackHeight / 2, outerRadius, tickRadius)
        let trackDownExtent = trackUpExtent
        let bottomGap = bottomRowHeight > 0 ? progressValueMargin(element, scale: scale, trackHeight: trackHeight) : 0
        let bottomPadding = bottomRowHeight > 0 ? 7 * scale : 0
        let trackBlockHeight = trackUpExtent + trackDownExtent
        let desiredHeight = max(rect.height, topPadding + topRowHeight + topGap + trackBlockHeight + bottomGap + bottomRowHeight + bottomPadding)
        let progressRect = CGRect(x: rect.minX, y: rect.maxY - desiredHeight, width: rect.width, height: desiredHeight)
        let hasTextRows = topRowHeight > 0 || bottomRowHeight > 0
        let trackCenterY = hasTextRows ? progressRect.maxY - topPadding - topRowHeight - topGap - trackUpExtent : progressRect.midY
        let sidePadding = min(
            progressRect.width * 0.42,
            max(0, 72 * scale * progressInsetScale(element))
        )
        let track = CGRect(
            x: progressRect.minX + sidePadding,
            y: trackCenterY - trackHeight / 2,
            width: max(1, progressRect.width - sidePadding * 2),
            height: trackHeight
        )

        if element.customization.showsPanel {
            drawPanelBackground(
                context,
                progressRect.insetBy(dx: -10 * scale, dy: -5 * scale),
                element: element,
                radius: 12 * scale
            )
        }
        fillRoundedRect(context, track, radius: trackHeight / 2, color: trackColor(element))

        var filled = track
        filled.size.width *= CGFloat(progress)
        if filled.width > 0 {
            fillRoundedRect(context, filled, radius: trackHeight / 2, color: valueColor(element, fallback: accent))
        }

        drawTopProgressTicks(context: context, track: track, scale: scale, element: element)

        let knobX = track.minX + track.width * CGFloat(progress)
        context.setFillColor(Colors.panel(opacity: 0.30))
        context.fillEllipse(in: CGRect(
            x: knobX - outerRadius,
            y: track.midY - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))
        context.setFillColor(valueColor(element, fallback: Colors.white))
        context.fillEllipse(in: CGRect(
            x: knobX - knobRadius,
            y: track.midY - knobRadius,
            width: knobRadius * 2,
            height: knobRadius * 2
        ))
        context.setStrokeColor(valueColor(element, fallback: accent))
        context.setLineWidth(max(1, trackHeight * 0.18))
        context.strokeEllipse(in: CGRect(
            x: knobX - outerRadius,
            y: track.midY - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))

        if element.customization.showsLabel {
            let startLabel = distanceLabel(0, element: element)
            let topBaselineY = progressRect.maxY - topPadding - topRowHeight * 0.78
            drawText(
                startLabel,
                context: context,
                baseline: CGPoint(x: track.minX, y: topBaselineY),
                size: startLabelSize,
                color: labelColor(element),
                fontName: labelFontName(element)
            )

            let currentLabel = distanceLabel(currentDistance, element: element)
            let currentWidth = textWidth(currentLabel, size: currentLabelSize, fontName: valueFontName(element))
            drawText(
                currentLabel,
                context: context,
                baseline: CGPoint(
                    x: min(track.maxX - currentWidth, max(track.minX, knobX - currentWidth / 2)),
                    y: trackCenterY - trackDownExtent - bottomGap - currentLabelSize * 0.78
                ),
                size: currentLabelSize,
                color: valueColor(element, fallback: accent),
                fontName: valueFontName(element)
            )
        }
        if element.customization.showsUnit {
            let endLabel = distanceLabel(displayedTotalDistance, element: element)
            let endWidth = textWidth(endLabel, size: endLabelSize, fontName: unitFontName(element))
            drawText(
                endLabel,
                context: context,
                baseline: CGPoint(x: track.maxX - endWidth, y: progressRect.maxY - topPadding - topRowHeight * 0.78),
                size: endLabelSize,
                color: unitColor(element),
                fontName: unitFontName(element)
            )
        }
        drawIconIfNeeded(
            element,
            defaultIcon: "DIST",
            context: context,
            baseline: CGPoint(x: max(progressRect.minX, track.minX - 52 * scale), y: progressRect.maxY - topPadding - topRowHeight * 0.78),
            size: 12 * textScale
        )
    }

    private func drawTopProgressTicks(context: CGContext, track: CGRect, scale: CGFloat, element: OverlayElement) {
        guard showsGaugeTicks(element) else { return }
        let tickCount = progressTickCount(element, track: track, scale: scale)
        guard tickCount > 0 else { return }

        let majorStride = max(1, tickCount / 10)
        context.saveGState()
        context.setStrokeColor(unitColor(element))
        context.setLineCap(.butt)
        for index in 0...tickCount {
            let x = track.minX + track.width * CGFloat(index) / CGFloat(tickCount)
            let isMajor = index % majorStride == 0
            let tickHeight = track.height * (isMajor ? 2.45 : 1.55)
            context.setLineWidth(max(0.75 * scale, track.height * (isMajor ? 0.12 : 0.07)))
            context.beginPath()
            context.move(to: CGPoint(x: x, y: track.midY - tickHeight / 2))
            context.addLine(to: CGPoint(x: x, y: track.midY + tickHeight / 2))
            context.strokePath()
        }
        context.restoreGState()
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

    private func routeDirectionAngle(for sample: TelemetrySample, in rect: CGRect, bounds: GeoBounds) -> CGFloat? {
        let before = point(for: series.sample(at: sample.elapsed - 2), in: rect, bounds: bounds)
        let after = point(for: series.sample(at: sample.elapsed + 2), in: rect, bounds: bounds)
        guard let before, let after else { return nil }
        return Self.routeDirectionAngle(before: before, after: after)
    }

    static func routeDirectionAngle(before: CGPoint, after: CGPoint) -> CGFloat? {
        let dx = after.x - before.x
        let dy = after.y - before.y
        guard hypot(dx, dy) > 1 else { return nil }
        return atan2(dy, dx)
    }

    private func drawRouteCurrentMarker(
        at current: CGPoint,
        angle: CGFloat?,
        context: CGContext,
        scale: CGFloat,
        element: OverlayElement,
        accent: CGColor
    ) {
        let color = valueColor(element, fallback: accent)

        context.setFillColor(color.copy(alpha: 0.92) ?? color)
        context.fillEllipse(in: CGRect(
            x: current.x - 6 * scale,
            y: current.y - 6 * scale,
            width: 12 * scale,
            height: 12 * scale
        ))
        context.setStrokeColor(color)
        context.setLineWidth(max(1, lineWidth(element, scale: scale) * 0.55))
        context.strokeEllipse(in: CGRect(
            x: current.x - 12 * scale,
            y: current.y - 12 * scale,
            width: 24 * scale,
            height: 24 * scale
        ))

        guard let angle else { return }
        let length = max(14 * scale, lineWidth(element, scale: scale) * 1.7)
        let width = length * 0.72
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)
        let tip = CGPoint(x: current.x + direction.x * length, y: current.y + direction.y * length)
        let base = CGPoint(x: current.x + direction.x * 2 * scale, y: current.y + direction.y * 2 * scale)

        context.beginPath()
        context.move(to: tip)
        context.addLine(to: CGPoint(x: base.x + perpendicular.x * width / 2, y: base.y + perpendicular.y * width / 2))
        context.addLine(to: CGPoint(x: base.x - perpendicular.x * width / 2, y: base.y - perpendicular.y * width / 2))
        context.closePath()
        context.setFillColor(color)
        context.fillPath()
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

    private func routePointCount(through elapsed: TimeInterval) -> Int {
        var lowerBound = 0
        var upperBound = routePoints.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if routePoints[middle].elapsed <= elapsed {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func strokeRoute<Points: Collection>(
        _ points: Points,
        in rect: CGRect,
        context: CGContext
    ) where Points.Element == RoutePoint {
        guard let first = points.first else { return }
        context.beginPath()
        context.move(to: first.point(in: rect))
        for point in points.dropFirst() {
            context.addLine(to: point.point(in: rect))
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
        case .weather:
            return CGSize(width: 136, height: 76)
        case .pace, .heartRate, .cadence, .calories, .strideLength, .power, .distance:
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

    private func progressInsetScale(_ element: OverlayElement) -> CGFloat {
        CGFloat(element.customization.progressInsetScale ?? 1)
    }

    private func progressKnobScale(_ element: OverlayElement) -> CGFloat {
        CGFloat(element.customization.progressKnobScale ?? 1)
    }

    private func progressValueMargin(_ element: OverlayElement, scale: CGFloat, trackHeight: CGFloat) -> CGFloat {
        let marginScale = CGFloat(element.customization.progressValueMarginScale ?? 1)
        let baseMargin = max(5 * scale, trackHeight * 0.35)
        return baseMargin * marginScale
    }

    private func progressTickCount(_ element: OverlayElement, track: CGRect, scale: CGFloat) -> Int {
        if let progressTickCount = element.customization.progressTickCount {
            return max(0, progressTickCount)
        }
        return max(8, min(80, Int((track.width / max(1, 28 * scale)).rounded())))
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
        case .calories:
            return "CAL"
        case .strideLength:
            return "STR"
        case .power:
            return "PWR"
        case .weather:
            return OverlayWeatherIcon.clouds.symbol
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
        let font = cachedFont(fontName, size: size)
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
        let fontKey = normalizedFontKey(fontName, size: size)
        let textKey = TextWidthKey(fontKey: fontKey, text: text)

        Self.textWidthCacheLock.lock()
        if let width = Self.textWidthCache[textKey] {
            Self.textWidthCacheLock.unlock()
            return width
        }
        Self.textWidthCacheLock.unlock()

        let font = cachedFont(fontName, size: size)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

        Self.textWidthCacheLock.lock()
        if Self.textWidthCache.count >= Self.maximumCachedTextWidths {
            Self.textWidthCache.removeAll(keepingCapacity: true)
        }
        Self.textWidthCache[textKey] = width
        Self.textWidthCacheLock.unlock()
        return width
    }

    private func cachedFont(_ fontName: CFString, size: CGFloat) -> CTFont {
        let key = normalizedFontKey(fontName, size: size)

        fontCacheLock.lock()
        defer { fontCacheLock.unlock() }

        if let font = fontCache[key] {
            return font
        }

        let font = CTFontCreateWithName(fontName, CGFloat(key.sizeHundredths) / 100, nil)
        fontCache[key] = font
        return font
    }

    private func normalizedFontKey(_ fontName: CFString, size: CGFloat) -> TextFontKey {
        let normalizedSize = max(0.1, size.isFinite ? size : 12)
        return TextFontKey(fontName: fontName as String, sizeHundredths: Int((normalizedSize * 100).rounded()))
    }

    static func clearTextWidthCacheForTesting() {
        textWidthCacheLock.lock()
        textWidthCache.removeAll(keepingCapacity: true)
        textWidthCacheLock.unlock()
    }

    static var textWidthCacheCountForTesting: Int {
        textWidthCacheLock.lock()
        defer { textWidthCacheLock.unlock() }
        return textWidthCache.count
    }

    private func fillRoundedRect(_ context: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
        context.setFillColor(color)
        context.addPath(roundedPath(rect: rect, radius: radius))
        context.fillPath()
    }

    private func drawElevatedSurface(_ context: CGContext, _ rect: CGRect, radius: CGFloat, fill: CGColor) {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 10, color: Colors.surfaceShadow)
        fillRoundedRect(context, rect, radius: radius, color: fill)
        context.restoreGState()
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
        drawElevatedSurface(context, rect, radius: radius, fill: Colors.panel(opacity: componentPanelOpacity(element)))
        if element.customization.panelBorderIsVisible {
            strokeRoundedRect(context, rect, radius: radius, color: Colors.panelStroke, lineWidth: 1)
        }

        if element.customization.panelBorderIsVisible {
            drawTopHighlight(context, rect, radius: radius, inset: 18, color: Colors.panelHighlight)
        }
    }

    private func drawTopHighlight(_ context: CGContext, _ rect: CGRect, radius: CGFloat, inset: CGFloat, color: CGColor) {
        let width = max(0, rect.width - inset * 2)
        guard width > 0 else { return }
        let topLine = CGRect(x: rect.minX + inset, y: rect.maxY - 1.25, width: width, height: 0.8)
        fillRoundedRect(context, topLine, radius: min(radius, 0.5), color: color)
    }

    private func roundedPath(rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let clampedRadius = min(max(0, radius), rect.width / 2, rect.height / 2)
        path.addRoundedRect(in: rect, cornerWidth: clampedRadius, cornerHeight: clampedRadius)
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

    private func formatStrideLength(_ meters: Double?, precision: Int?) -> String {
        guard let meters, meters.isFinite else { return "--" }
        let digits = min(3, max(0, precision ?? 2))
        return String(format: "%.\(digits)f", meters)
    }

    private func distanceLabel(_ meters: Double?, element: OverlayElement) -> String {
        "\(formatDistance(meters, element: element)) \(element.customization.unit(default: config.distanceUnit.symbol))"
    }

    private func formatPace(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond > 0.3 else { return "--:--" }
        let secondsPerKm = Int((1000 / metersPerSecond).rounded())
        return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
    }

    private func formatWeatherTemperature(_ sample: TelemetrySample) -> String {
        guard let temperature = sample.weatherTemperatureCelsius ?? sample.temperatureCelsius else { return "--℃" }
        return "\(temperature)℃"
    }

    private func formatWeatherUnit(_ sample: TelemetrySample) -> String {
        let summary = sample.weatherSummary ?? "Weather"
        guard let humidity = sample.weatherHumidityPercent else { return summary }
        return "\(summary)\n\(humidity)%"
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func formatClockDuration(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed.rounded()))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func formatClockAndCalendarDate(_ date: Date?) -> (clock: String, date: String) {
        guard let date else { return ("--:--:--", "----/--/--") }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return (
            String(format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0),
            String(format: "%04d/%02d/%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        )
    }

    private func formatGaugeEdge(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.01 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    static func lastFiniteDistance(samples: [TelemetrySample]) -> Double? {
        samples.reversed().first { sample in
            guard let distance = sample.distanceMeters else { return false }
            return distance.isFinite
        }?.distanceMeters
    }

    private static func makeRoutePoints(samples: [TelemetrySample], bounds: GeoBounds?, limit: Int) -> [RoutePoint] {
        guard let bounds else { return [] }
        let samples = downsample(
            samples: samples.filter { $0.latitude != nil && $0.longitude != nil },
            limit: limit
        )
        return samples.compactMap { RoutePoint(sample: $0, bounds: bounds) }
    }

    static func downsample(samples: [TelemetrySample], limit: Int) -> [TelemetrySample] {
        guard limit > 0 else { return [] }
        guard samples.count > limit else { return samples }
        guard limit > 1 else { return [samples[0]] }

        let step = Double(samples.count - 1) / Double(limit - 1)
        var usedIndices = Set<Int>()
        var result: [TelemetrySample] = []
        result.reserveCapacity(limit)

        for outputIndex in 0..<limit {
            let index = min(samples.count - 1, Int((Double(outputIndex) * step).rounded()))
            guard usedIndices.insert(index).inserted else { continue }
            result.append(samples[index])
        }

        if result.last != samples.last {
            if result.count == limit {
                result[result.count - 1] = samples[samples.count - 1]
            } else {
                result.append(samples[samples.count - 1])
            }
        }

        return result
    }
}

private struct RoutePoint {
    let elapsed: TimeInterval
    let normalizedX: CGFloat
    let normalizedY: CGFloat

    init?(sample: TelemetrySample, bounds: GeoBounds) {
        guard let latitude = sample.latitude, let longitude = sample.longitude else { return nil }
        let latSpan = max(bounds.maxLatitude - bounds.minLatitude, 0.000_001)
        let lonSpan = max(bounds.maxLongitude - bounds.minLongitude, 0.000_001)
        self.elapsed = sample.elapsed
        self.normalizedX = CGFloat((longitude - bounds.minLongitude) / lonSpan)
        self.normalizedY = CGFloat((latitude - bounds.minLatitude) / latSpan)
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + normalizedX * rect.width,
            y: rect.minY + normalizedY * rect.height
        )
    }
}

private struct TextFontKey: Hashable {
    var fontName: String
    var sizeHundredths: Int
}

private struct TextWidthKey: Hashable {
    var fontKey: TextFontKey
    var text: String
}

private enum Colors {
    static let white = CGColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.96)
    static let muted = CGColor(red: 0.66, green: 0.72, blue: 0.78, alpha: 0.82)
    static let label = CGColor(red: 0.74, green: 0.80, blue: 0.86, alpha: 0.92)
    static func panel(opacity: Double) -> CGColor {
        CGColor(red: 0.018, green: 0.022, blue: 0.026, alpha: min(0.95, max(0.12, opacity)))
    }
    static func tile(opacity: Double) -> CGColor {
        CGColor(red: 0.024, green: 0.029, blue: 0.034, alpha: min(0.92, max(0.10, opacity)))
    }
    static let panelStroke = CGColor(red: 1, green: 1, blue: 1, alpha: 0.14)
    static let panelHighlight = CGColor(red: 1, green: 1, blue: 1, alpha: 0.22)
    static let tileStroke = CGColor(red: 1, green: 1, blue: 1, alpha: 0.16)
    static let tileHighlight = CGColor(red: 1, green: 1, blue: 1, alpha: 0.18)
    static let surfaceShadow = CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
    static let track = CGColor(red: 1, green: 1, blue: 1, alpha: 0.14)
    static let gaugeTrack = CGColor(red: 1, green: 1, blue: 1, alpha: 0.17)
    static let tick = CGColor(red: 1, green: 1, blue: 1, alpha: 0.28)
    static let routeGlow = CGColor(red: 0.10, green: 0.95, blue: 0.70, alpha: 0.16)
    static let routeBase = CGColor(red: 1, green: 1, blue: 1, alpha: 0.30)
    static let cyan = CGColor(red: 0.45, green: 0.82, blue: 1.00, alpha: 0.96)
    static let red = CGColor(red: 1.00, green: 0.38, blue: 0.42, alpha: 0.96)
    static let amber = CGColor(red: 1.00, green: 0.76, blue: 0.35, alpha: 0.96)
}
