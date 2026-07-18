import CoreGraphics
import Foundation
import OverlayCore
import OverlayStudioKit

/// Shared canvas geometry: computes each element's normalized unit rect the same way the
/// preview canvas draws it, so drag hit-testing, smart guides, and the arrange commands
/// (align/distribute) all agree on element bounds.
@MainActor
struct CanvasElementGeometry {
    let model: StudioModel

    /// Shared metric width at element scale 1; callers reapply each gauge's own scale.
    func alignedMetricOutputWidth(for visibleElements: [OverlayElement]) -> CGFloat? {
        let widths = visibleElements.compactMap { element -> CGFloat? in
            guard isMetricElement(element) else { return nil }
            let base = ComponentBaseSize.size(for: element.kind)
            let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
            let baseWidth = base.width * scale * CGFloat(max(0.1, element.customization.lengthScale))
            return metricDesiredOutputWidth(element: element, baseWidth: baseWidth, scale: scale)
                / max(0.1, CGFloat(element.frame.scale))
        }
        return widths.max()
    }

    func unitRect(element: OverlayElement, alignedMetricWidth: CGFloat?) -> CGRect {
        let frame = element.frame
        let base = ComponentBaseSize.size(for: element.kind)
        let outputSize = componentOutputSize(element: element, base: base, alignedMetricWidth: alignedMetricWidth)
        let width = outputSize.width / CGFloat(max(1, model.outputWidth))
        let height = outputSize.height / CGFloat(max(1, model.outputHeight))
        let horizontalOffset = componentHorizontalOffset(element: element, base: base, outputWidth: outputSize.width)
        let verticalOffset = componentVerticalOffset(element: element, base: base, outputHeight: outputSize.height)
        return CGRect(
            x: CGFloat(frame.x) + horizontalOffset / CGFloat(max(1, model.outputWidth)),
            y: CGFloat(frame.y) + verticalOffset / CGFloat(max(1, model.outputHeight)),
            width: width,
            height: height
        )
    }

    /// Part hit/highlight zones in unit-rect space (same normalized coordinates as
    /// `unitRect`). Zones are row-accurate (real font metrics) with left/right splits for
    /// label/icon and value/unit, which is precise enough for click targeting.
    func partRects(element: OverlayElement, alignedMetricWidth: CGFloat?) -> [OverlayElementPart: CGRect] {
        let availableParts = OverlayElementPart.availableParts(for: element)
        guard !availableParts.isEmpty else { return [:] }
        let container = unitRect(element: element, alignedMetricWidth: alignedMetricWidth)
        let base = ComponentBaseSize.size(for: element.kind)
        let outputSize = componentOutputSize(element: element, base: base, alignedMetricWidth: alignedMetricWidth)
        guard outputSize.width > 0, outputSize.height > 0 else { return [:] }

        let fractionRects: [OverlayElementPart: CGRect]
        switch element.kind {
        case .pace, .distance, .heartRate, .cadence, .calories, .ascent, .strideLength, .power,
             .verticalOscillation, .groundContactTime, .groundContactTimePercent,
             .groundContactTimeBalance, .verticalRatio, .respirationRate,
             .stepSpeedLoss, .formPower, .airPower, .legSpringStiffness, .weather:
            fractionRects = metricPartFractions(element: element, outputSize: outputSize)
        case .timeDate:
            fractionRects = timeDatePartFractions(element: element, outputSize: outputSize)
        case .topProgress:
            fractionRects = progressPartFractions(element: element)
        case .speed:
            fractionRects = [.value: CGRect(x: 0, y: 0, width: 1, height: 1)]
        case .route:
            fractionRects = [:]
        }

        var rects: [OverlayElementPart: CGRect] = [:]
        for part in availableParts {
            guard let fraction = fractionRects[part] else { continue }
            rects[part] = CGRect(
                x: container.minX + container.width * fraction.minX,
                y: container.minY + container.height * fraction.minY,
                width: container.width * fraction.width,
                height: container.height * fraction.height
            )
        }
        return rects
    }

    /// Finds the part zone containing a normalized canvas point, preferring the smallest
    /// matching zone so overlapping rows resolve to the more specific part.
    func part(at point: CGPoint, element: OverlayElement, alignedMetricWidth: CGFloat?) -> OverlayElementPart? {
        partRects(element: element, alignedMetricWidth: alignedMetricWidth)
            .filter { $0.value.contains(point) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?
            .key
    }

    private func metricPartFractions(element: OverlayElement, outputSize: CGSize) -> [OverlayElementPart: CGRect] {
        let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let textScale = scale * CGFloat(element.frame.style.textScale)
        let labelFontSize = labelSize(10, scale: textScale, element: element)
        let valueFontSize = valueSize(23, scale: textScale, element: element)
        let iconFontSize = metricIconFontSize(element: element, textScale: textScale)
        let drawsTopRowIcon = element.customization.showsIcon && element.kind != .weather
        let hasTopRow = element.customization.showsLabel || drawsTopRowIcon
        let topRowHeight = hasTopRow ? max(labelFontSize, iconFontSize) : 0
        let topPadding = 9 * scale
        let rowGap = hasTopRow ? max(6 * scale, valueFontSize * 0.18) : 0

        let topBandEnd = min(1, (topPadding + topRowHeight + rowGap / 2) / outputSize.height)
        var rects: [OverlayElementPart: CGRect] = [:]
        if hasTopRow {
            let topBand = CGRect(x: 0, y: 0, width: 1, height: topBandEnd)
            if element.customization.showsLabel, drawsTopRowIcon {
                rects[.label] = CGRect(x: 0, y: 0, width: 0.55, height: topBand.height)
                rects[.icon] = CGRect(x: 0.55, y: 0, width: 0.45, height: topBand.height)
            } else if element.customization.showsLabel {
                rects[.label] = topBand
            } else {
                rects[.icon] = topBand
            }
        }
        let valueBand = CGRect(x: 0, y: topBandEnd, width: 1, height: max(0, 1 - topBandEnd))
        if element.customization.showsUnit {
            rects[.value] = CGRect(x: 0, y: valueBand.minY, width: 0.6, height: valueBand.height)
            rects[.unit] = CGRect(x: 0.6, y: valueBand.minY, width: 0.4, height: valueBand.height)
        } else {
            rects[.value] = valueBand
        }
        return rects
    }

    private func timeDatePartFractions(element: OverlayElement, outputSize: CGSize) -> [OverlayElementPart: CGRect] {
        let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let textScale = scale * CGFloat(element.frame.style.textScale)
        let labelFontSize = labelSize(11, scale: textScale, element: element)
        let valueFontSize = valueSize(24, scale: textScale, element: element)
        let iconFontSize = iconSize(12 * textScale, scale: 1, element: element)
        let topPadding = 15 * scale
        let hasTopRow = element.customization.showsLabel || element.customization.showsIcon
        let topRowHeight = hasTopRow ? max(labelFontSize, iconFontSize) : 0
        let topRowGap = topRowHeight > 0 ? max(6 * scale, topRowHeight * 0.25) : 0
        let valueGap = max(8 * scale, valueFontSize * 0.28)

        let topBandEnd = min(1, (topPadding + topRowHeight + topRowGap / 2) / outputSize.height)
        let valueBandEnd = min(1, (topPadding + topRowHeight + topRowGap + valueFontSize + valueGap / 2) / outputSize.height)

        var rects: [OverlayElementPart: CGRect] = [:]
        if hasTopRow {
            if element.customization.showsLabel, element.customization.showsIcon {
                rects[.label] = CGRect(x: 0, y: 0, width: 0.55, height: topBandEnd)
                rects[.icon] = CGRect(x: 0.55, y: 0, width: 0.45, height: topBandEnd)
            } else if element.customization.showsLabel {
                rects[.label] = CGRect(x: 0, y: 0, width: 1, height: topBandEnd)
            } else {
                rects[.icon] = CGRect(x: 0, y: 0, width: 1, height: topBandEnd)
            }
        }
        if element.customization.showsUnit {
            rects[.value] = CGRect(x: 0, y: topBandEnd, width: 1, height: max(0, valueBandEnd - topBandEnd))
            rects[.unit] = CGRect(x: 0, y: valueBandEnd, width: 1, height: max(0, 1 - valueBandEnd))
        } else {
            rects[.value] = CGRect(x: 0, y: topBandEnd, width: 1, height: max(0, 1 - topBandEnd))
        }
        return rects
    }

    private func progressPartFractions(element: OverlayElement) -> [OverlayElementPart: CGRect] {
        // Top row carries start (label), icon, and end (unit); the current readout (value)
        // sits under the track. Half-height bands are a good enough click approximation.
        var rects: [OverlayElementPart: CGRect] = [:]
        let showsIcon = element.customization.showsIcon
        if element.customization.showsLabel, element.customization.showsUnit {
            rects[.label] = CGRect(x: 0, y: 0, width: showsIcon ? 0.35 : 0.5, height: 0.5)
            rects[.unit] = CGRect(x: showsIcon ? 0.65 : 0.5, y: 0, width: showsIcon ? 0.35 : 0.5, height: 0.5)
            if showsIcon {
                rects[.icon] = CGRect(x: 0.35, y: 0, width: 0.3, height: 0.5)
            }
        } else if element.customization.showsLabel {
            rects[.label] = CGRect(x: 0, y: 0, width: showsIcon ? 0.5 : 1, height: 0.5)
            if showsIcon {
                rects[.icon] = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
            }
        } else if element.customization.showsUnit {
            rects[.unit] = CGRect(x: showsIcon ? 0.5 : 0, y: 0, width: showsIcon ? 0.5 : 1, height: 0.5)
            if showsIcon {
                rects[.icon] = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
            }
        } else if showsIcon {
            rects[.icon] = CGRect(x: 0, y: 0, width: 1, height: 0.5)
        }
        if element.customization.showsLabel {
            rects[.value] = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        }
        return rects
    }

    private func componentOutputSize(element: OverlayElement, base: CGSize, alignedMetricWidth: CGFloat?) -> CGSize {
        let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let baseWidth = base.width * scale * CGFloat(max(0.1, element.customization.lengthScale))
        let baseHeight = base.height * scale

        switch element.kind {
        case .pace, .distance, .heartRate, .cadence, .calories, .ascent, .strideLength, .power,
             .verticalOscillation, .groundContactTime, .groundContactTimePercent,
             .groundContactTimeBalance, .verticalRatio, .respirationRate,
             .stepSpeedLoss, .formPower, .airPower, .legSpringStiffness, .weather:
            return metricOutputSize(
                element: element,
                baseWidth: baseWidth,
                baseHeight: baseHeight,
                scale: scale,
                alignedMetricWidth: alignedMetricWidth
            )
        case .topProgress:
            return progressOutputSize(element: element, baseWidth: baseWidth, baseHeight: baseHeight, scale: scale)
        case .timeDate:
            return timeDateOutputSize(element: element, baseWidth: baseWidth, baseHeight: baseHeight, scale: scale)
        case .speed, .route:
            return CGSize(width: baseWidth, height: baseHeight)
        }
    }

    private func componentHorizontalOffset(element: OverlayElement, base: CGSize, outputWidth: CGFloat) -> CGFloat {
        guard element.kind == .timeDate else { return 0 }
        let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let baseWidth = base.width * scale * CGFloat(max(0.1, element.customization.lengthScale))
        return min(0, baseWidth - outputWidth)
    }

    private func componentVerticalOffset(element: OverlayElement, base: CGSize, outputHeight: CGFloat) -> CGFloat {
        let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let baseHeight = base.height * scale
        return min(0, baseHeight - outputHeight)
    }

    private func metricOutputSize(
        element: OverlayElement,
        baseWidth: CGFloat,
        baseHeight: CGFloat,
        scale: CGFloat,
        alignedMetricWidth: CGFloat?
    ) -> CGSize {
        let textScale = scale * CGFloat(element.frame.style.textScale)
        let labelFontSize = labelSize(10, scale: textScale, element: element)
        let valueFontSize = valueSize(23, scale: textScale, element: element)
        let unitFontSize = unitSize(10, scale: textScale, element: element)
        let iconFontSize = metricIconFontSize(element: element, textScale: textScale)
        let drawsTopRowIcon = element.customization.showsIcon && element.kind != .weather
        let hasTopRow = element.customization.showsLabel || drawsTopRowIcon
        let topRowHeight = hasTopRow ? max(labelFontSize, iconFontSize) : 0
        let text = metricText(for: element)
        let valueRowHeight = max(
            valueFontSize,
            metricUnitBlockHeight(element: element, unit: text.unit, unitFontSize: unitFontSize, iconFontSize: iconFontSize, scale: scale)
        )
        let horizontalPadding = 14 * scale
        let topPadding = 9 * scale
        let bottomPadding = 14 * scale
        let rowGap = hasTopRow ? max(6 * scale, valueFontSize * 0.18) : 0
        let desiredHeight = max(baseHeight, topPadding + topRowHeight + rowGap + valueRowHeight + bottomPadding)

        let valueWidth = textWidth(text.value, size: valueFontSize, fontName: element.customization.valueFont)
        let unitWidth = metricUnitBlockWidth(element: element, unit: text.unit, unitFontSize: unitFontSize, iconFontSize: iconFontSize)
        let unitGap = element.customization.showsUnit ? 10 * scale : 0
        let labelWidth = element.customization.showsLabel ? textWidth(text.label, size: labelFontSize, fontName: element.customization.labelFont) : 0
        let iconWidth = drawsTopRowIcon ? textWidth(text.icon, size: iconFontSize, fontName: element.customization.iconFont) : 0
        let iconGap = drawsTopRowIcon ? 12 * scale : 0
        let desiredWidth = max(
            (alignedMetricWidth ?? 0) * max(0.1, CGFloat(element.frame.scale)),
            baseWidth,
            (horizontalPadding * 2) + valueWidth + unitGap + unitWidth,
            (horizontalPadding * 2) + labelWidth + iconGap + iconWidth
        )
        return CGSize(width: desiredWidth, height: desiredHeight)
    }

    private func metricDesiredOutputWidth(
        element: OverlayElement,
        baseWidth: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        let textScale = scale * CGFloat(element.frame.style.textScale)
        let labelFontSize = labelSize(10, scale: textScale, element: element)
        let valueFontSize = valueSize(23, scale: textScale, element: element)
        let unitFontSize = unitSize(10, scale: textScale, element: element)
        let iconFontSize = metricIconFontSize(element: element, textScale: textScale)
        let text = metricText(for: element)
        let valueWidth = textWidth(text.value, size: valueFontSize, fontName: element.customization.valueFont)
        let unitWidth = metricUnitBlockWidth(element: element, unit: text.unit, unitFontSize: unitFontSize, iconFontSize: iconFontSize)
        let horizontalPadding = 14 * scale
        let unitGap = element.customization.showsUnit ? 10 * scale : 0
        let labelWidth = element.customization.showsLabel ? textWidth(text.label, size: labelFontSize, fontName: element.customization.labelFont) : 0
        let drawsTopRowIcon = element.customization.showsIcon && element.kind != .weather
        let iconWidth = drawsTopRowIcon ? textWidth(text.icon, size: iconFontSize, fontName: element.customization.iconFont) : 0
        let iconGap = drawsTopRowIcon ? 12 * scale : 0
        return max(
            baseWidth,
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
        var widths = metricUnitLines(unit).map { textWidth($0, size: unitFontSize, fontName: element.customization.unitFont) }
        if element.kind == .weather, element.customization.showsIcon {
            widths[0] = textWidth(weatherIconText(element: element, summary: metricUnitLines(unit).first), size: iconFontSize, fontName: element.customization.iconFont)
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

    private func isMetricElement(_ element: OverlayElement) -> Bool {
        switch element.kind {
        case .pace, .distance, .heartRate, .cadence, .calories, .ascent, .strideLength, .power,
             .verticalOscillation, .groundContactTime, .groundContactTimePercent,
             .groundContactTimeBalance, .verticalRatio, .respirationRate,
             .stepSpeedLoss, .formPower, .airPower, .legSpringStiffness, .weather:
            return true
        case .speed, .route, .topProgress, .timeDate:
            return false
        }
    }

    private func progressOutputSize(
        element: OverlayElement,
        baseWidth: CGFloat,
        baseHeight: CGFloat,
        scale: CGFloat
    ) -> CGSize {
        let textScale = scale * CGFloat(element.frame.style.textScale)
        let startLabelSize = labelSize(15, scale: textScale, element: element)
        let currentLabelSize = valueSize(12, scale: textScale, element: element)
        let endLabelSize = unitSize(15, scale: textScale, element: element)
        let iconFontSize = iconSize(12 * textScale, scale: 1, element: element)
        let trackHeight = lineWidth(element, scale: scale)
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
        let tickRadius = showsProgressTicks(element) ? trackHeight * 1.225 : trackHeight / 2
        let trackExtent = max(trackHeight / 2, outerRadius, tickRadius)
        let trackBlockHeight = trackExtent * 2
        let bottomGap = bottomRowHeight > 0 ? progressValueMargin(element, scale: scale, trackHeight: trackHeight) : 0
        let bottomPadding = bottomRowHeight > 0 ? 7 * scale : 0
        let desiredHeight = max(baseHeight, topPadding + topRowHeight + topGap + trackBlockHeight + bottomGap + bottomRowHeight + bottomPadding)
        return CGSize(width: baseWidth, height: desiredHeight)
    }

    private func showsProgressTicks(_ element: OverlayElement) -> Bool {
        element.customization.showGaugeTicks ?? model.layout.style.showGaugeTicks
    }

    private func progressKnobScale(_ element: OverlayElement) -> CGFloat {
        CGFloat(element.customization.progressKnobScale ?? 1)
    }

    private func progressValueMargin(_ element: OverlayElement, scale: CGFloat, trackHeight: CGFloat) -> CGFloat {
        let marginScale = CGFloat(element.customization.progressValueMarginScale ?? 1)
        return max(5 * scale, trackHeight * 0.35) * marginScale
    }

    private func lineWidth(_ element: OverlayElement, scale: CGFloat) -> CGFloat {
        max(0.25, CGFloat(element.customization.lineWidth) * scale)
    }

    private func timeDateOutputSize(
        element: OverlayElement,
        baseWidth: CGFloat,
        baseHeight: CGFloat,
        scale: CGFloat
    ) -> CGSize {
        let textScale = scale * CGFloat(element.frame.style.textScale)
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
        let desiredHeight = max(
            baseHeight,
            topPadding + topRowHeight + topRowGap + valueFontSize
                + (element.customization.showsUnit ? valueGap + clockFontSize + unitGap + dateFontSize : 0)
                + bottomPadding
        )

        let text = timeDateText(for: element)
        let textWidth = max(
            self.textWidth(text.elapsed, size: valueFontSize, fontName: element.customization.valueFont),
            element.customization.showsUnit ? self.textWidth(text.clock, size: clockFontSize, fontName: element.customization.unitFont) : 0,
            element.customization.showsUnit ? self.textWidth(text.date, size: dateFontSize, fontName: element.customization.unitFont) : 0,
            element.customization.showsLabel ? self.textWidth(text.label, size: labelFontSize, fontName: element.customization.labelFont) : 0
        )
        let iconWidth = element.customization.showsIcon ? self.textWidth(text.icon, size: iconFontSize, fontName: element.customization.iconFont) : 0
        let desiredWidth = max(baseWidth, textWidth + iconWidth + 28 * scale)
        return CGSize(width: desiredWidth, height: desiredHeight)
    }

    private func currentTelemetrySample() -> TelemetrySample {
        model.displayTelemetrySample(forVideoTime: model.previewTime)
    }

    private func metricText(for element: OverlayElement) -> (label: String, value: String, unit: String, icon: String) {
        let sample = currentTelemetrySample()
        switch element.kind {
        case .pace:
            return (
                element.customization.label(default: "PACE"),
                formatPace(sample.speedMetersPerSecond),
                element.customization.unit(default: "/KM"),
                element.customization.icon(default: "PACE")
            )
        case .distance:
            return (
                element.customization.label(default: "DIST"),
                formatDistance(sample.distanceMeters, element: element),
                element.customization.unit(default: model.distanceUnit.symbol),
                element.customization.icon(default: "DIST")
            )
        case .heartRate:
            return (
                element.customization.label(default: "HR"),
                sample.heartRate.map { "\($0)" } ?? "--",
                element.customization.unit(default: "BPM"),
                element.customization.icon(default: "HR")
            )
        case .cadence:
            return (
                element.customization.label(default: "CAD"),
                sample.cadence.map { "\($0)" } ?? "--",
                element.customization.unit(default: "SPM"),
                element.customization.icon(default: "CAD")
            )
        case .calories:
            return (
                element.customization.label(default: "CAL"),
                sample.totalCalories.map { "\(Int($0.rounded()))" } ?? "--",
                element.customization.unit(default: "KCAL"),
                element.customization.icon(default: "CAL")
            )
        case .ascent:
            return (
                element.customization.label(default: "ASC"),
                formatDecimal(sample.totalAscentMeters, precision: element.customization.valuePrecision ?? 0),
                element.customization.unit(default: "m"),
                element.customization.icon(default: "ASC")
            )
        case .strideLength:
            return (
                element.customization.label(default: "STRIDE"),
                formatStrideLength(sample.stepLengthMeters, precision: element.customization.valuePrecision),
                element.customization.unit(default: "m"),
                element.customization.icon(default: "STR")
            )
        case .power:
            return (
                element.customization.label(default: "PWR"),
                sample.powerWatts.map { "\($0)" } ?? "--",
                element.customization.unit(default: "W"),
                element.customization.icon(default: "PWR")
            )
        case .verticalOscillation:
            return (
                element.customization.label(default: "VERT"),
                formatDecimal(sample.verticalOscillationCentimeters, precision: element.customization.valuePrecision ?? 1),
                element.customization.unit(default: "CM"),
                element.customization.icon(default: "VERT")
            )
        case .groundContactTime:
            return (
                element.customization.label(default: "GCT"),
                formatDecimal(sample.groundContactTimeMilliseconds, precision: element.customization.valuePrecision ?? 0),
                element.customization.unit(default: "MS"),
                element.customization.icon(default: "GCT")
            )
        case .groundContactTimePercent:
            return (
                element.customization.label(default: "GCT %"),
                formatDecimal(sample.groundContactTimePercent, precision: element.customization.valuePrecision ?? 1),
                element.customization.unit(default: "%"),
                element.customization.icon(default: "GCT%")
            )
        case .groundContactTimeBalance:
            return (
                element.customization.label(default: "GCT BAL"),
                formatDecimal(sample.groundContactTimeBalancePercent, precision: element.customization.valuePrecision ?? 1),
                element.customization.unit(default: "%"),
                element.customization.icon(default: "BAL")
            )
        case .verticalRatio:
            return (
                element.customization.label(default: "VERT R"),
                formatDecimal(sample.verticalRatioPercent, precision: element.customization.valuePrecision ?? 1),
                element.customization.unit(default: "%"),
                element.customization.icon(default: "VR")
            )
        case .respirationRate:
            return (
                element.customization.label(default: "RESP"),
                formatDecimal(sample.respirationRateBreathsPerMinute, precision: element.customization.valuePrecision ?? 1),
                element.customization.unit(default: "BR/MIN"),
                element.customization.icon(default: "RESP")
            )
        case .stepSpeedLoss:
            return (
                element.customization.label(default: "SSL"),
                formatDecimal(sample.stepSpeedLossPercent, precision: element.customization.valuePrecision ?? 1),
                element.customization.unit(default: "%"),
                element.customization.icon(default: "SSL")
            )
        case .formPower:
            return (
                element.customization.label(default: "FORM"),
                sample.formPowerWatts.map { "\($0)" } ?? "--",
                element.customization.unit(default: "W"),
                element.customization.icon(default: "FORM")
            )
        case .airPower:
            return (
                element.customization.label(default: "AIR"),
                sample.airPowerWatts.map { "\($0)" } ?? "--",
                element.customization.unit(default: "W"),
                element.customization.icon(default: "AIR")
            )
        case .legSpringStiffness:
            return (
                element.customization.label(default: "LSS"),
                formatDecimal(sample.legSpringStiffnessKilonewtonsPerMeter, precision: element.customization.valuePrecision ?? 1),
                element.customization.unit(default: "kN/m"),
                element.customization.icon(default: "LSS")
            )
        case .weather:
            return (
                element.customization.label(default: "WEATHER"),
                formatWeatherTemperature(sample, element: element),
                element.customization.unit(default: formatWeatherUnit(sample, element: element)),
                element.customization.icon(default: OverlayWeatherIcon.clouds.symbol)
            )
        default:
            return (
                element.customization.label(default: element.kind.title),
                "--",
                element.customization.unit(default: ""),
                element.customization.icon(default: element.kind.title)
            )
        }
    }

    private func timeDateText(for element: OverlayElement) -> (label: String, elapsed: String, clock: String, date: String, icon: String) {
        let sample = currentTelemetrySample()
        let absoluteDate = model.absoluteActivityDate(forVideoTime: model.previewTime) ?? sample.date
        return (
            element.customization.label(default: "TIME"),
            formatClockDuration(sample.elapsed),
            formatClockTime(absoluteDate),
            formatCalendarDate(absoluteDate),
            element.customization.icon(default: "TIME")
        )
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

    private func textWidth(_ text: String, size: CGFloat, fontName: OverlayFontFamily) -> CGFloat {
        TextMeasurementCache.width(text, size: size, fontName: fontName)
    }

    private func rendererLayoutScale() -> CGFloat {
        max(0.28, min(CGFloat(model.outputWidth) / 1920, CGFloat(model.outputHeight) / 1080))
    }

    private func formatDistance(_ meters: Double?, element: OverlayElement) -> String {
        guard let meters, meters.isFinite else { return "--" }
        if let valuePrecision = element.customization.valuePrecision {
            let digits = min(3, max(0, valuePrecision))
            switch model.distanceUnit {
            case .meters:
                return String(format: "%.\(digits)f", meters)
            case .kilometers:
                return String(format: "%.\(digits)f", meters / 1000)
            }
        }
        return model.distanceUnit.format(meters: meters)
    }

    private func formatStrideLength(_ meters: Double?, precision: Int?) -> String {
        guard let meters, meters.isFinite else { return "--" }
        let digits = min(3, max(0, precision ?? 2))
        return String(format: "%.\(digits)f", meters)
    }

    private func formatDecimal(_ value: Double?, precision: Int) -> String {
        guard let value, value.isFinite else { return "--" }
        let digits = min(3, max(0, precision))
        return String(format: "%.\(digits)f", value)
    }

    private func formatPace(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond > 0.3 else { return "--:--" }
        let secondsPerKm = Int((1000 / metersPerSecond).rounded())
        return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
    }

    private func formatWeatherTemperature(_ sample: TelemetrySample, element: OverlayElement) -> String {
        guard let temperature = element.customization.resolvedWeatherTemperatureCelsius(
            apiValue: sample.weatherTemperatureCelsius,
            activityValue: sample.temperatureCelsius
        ) else { return "--℃" }
        return "\(temperature)℃"
    }

    private func formatWeatherUnit(_ sample: TelemetrySample, element: OverlayElement) -> String {
        element.customization.weatherUnitText(
            summary: sample.weatherSummary,
            apiHumidityPercent: sample.weatherHumidityPercent
        )
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
}
