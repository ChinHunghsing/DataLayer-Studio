import AppKit
import SwiftUI
import OverlayCore

struct PreviewCanvasView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @Binding private var zoom: Double
    let isFullscreen: Bool
    let onToggleFullscreen: () -> Void
    @State private var activeDrag: ComponentDragState?
    @State private var magnificationStartZoom: Double?

    init(
        model: StudioModel,
        zoom: Binding<Double>,
        isFullscreen: Bool = false,
        onToggleFullscreen: @escaping () -> Void = {}
    ) {
        self.model = model
        self._zoom = zoom
        self.isFullscreen = isFullscreen
        self.onToggleFullscreen = onToggleFullscreen
    }

    var body: some View {
        if isFullscreen {
            ZStack(alignment: .bottom) {
                previewViewport
                PreviewControlsPanel(
                    model: model,
                    zoom: $zoom,
                    isFullscreen: isFullscreen,
                    onToggleFullscreen: onToggleFullscreen
                )
            }
        } else {
            VStack(spacing: 0) {
                previewViewport
                PreviewControlsPanel(
                    model: model,
                    zoom: $zoom,
                    isFullscreen: isFullscreen,
                    onToggleFullscreen: onToggleFullscreen
                )
            }
        }
    }

    private var previewViewport: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let stageInsets = previewStageInsets(for: viewportSize)
            let stageSize = CGSize(
                width: max(1, viewportSize.width - stageInsets.leading - stageInsets.trailing),
                height: max(1, viewportSize.height - stageInsets.top - stageInsets.bottom)
            )
            let fitSize = aspectFitSize(
                container: stageSize,
                aspectRatio: CGFloat(model.outputWidth) / CGFloat(max(1, model.outputHeight))
            )
            let zoomFactor = CGFloat(clampedZoom(zoom))
            let canvasSize = CGSize(width: fitSize.width * zoomFactor, height: fitSize.height * zoomFactor)
            let overlayRenderSize = previewOverlayRenderSize(for: canvasSize)
            let visibleElements = model.layout.visibleElements
            let alignedMetricWidth = alignedMetricOutputWidth(for: visibleElements)
            let overflowInsets = layoutOverflowInsets(
                canvasSize: canvasSize,
                visibleElements: visibleElements,
                alignedMetricWidth: alignedMetricWidth
            )
            let horizontalSlack = max(0, stageSize.width - canvasSize.width)
            let verticalSlack = max(0, stageSize.height - canvasSize.height)
            let displayRect = CGRect(
                x: stageInsets.leading + horizontalSlack / 2,
                y: stageInsets.top + verticalPreviewSlackOffset(verticalSlack),
                width: canvasSize.width,
                height: canvasSize.height
            )
            let contentSize = CGSize(
                width: max(viewportSize.width, displayRect.maxX + overflowInsets.right + stageInsets.trailing),
                height: max(viewportSize.height, displayRect.maxY + overflowInsets.bottom + stageInsets.bottom)
            )

            ScrollView([.horizontal, .vertical]) {
                previewCanvas(
                    displayRect: displayRect,
                    contentSize: contentSize,
                    visibleElements: visibleElements,
                    alignedMetricWidth: alignedMetricWidth
                )
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .onAppear {
                model.updatePreviewOverlayRenderSize(overlayRenderSize)
            }
            .onChange(of: overlayRenderSize) { newValue in
                model.updatePreviewOverlayRenderSize(newValue)
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if magnificationStartZoom == nil {
                            magnificationStartZoom = zoom
                        }
                        setZoom((magnificationStartZoom ?? zoom) * Double(value))
                    }
                    .onEnded { _ in
                        magnificationStartZoom = nil
                    }
            )
        }
    }

    private func previewCanvas(
        displayRect: CGRect,
        contentSize: CGSize,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) -> some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let player = model.player {
                PlayerSurfaceView(player: player)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .clipped()
                    .position(x: displayRect.midX, y: displayRect.midY)
                    .allowsHitTesting(false)
            } else if let background = model.backgroundImage {
                Image(nsImage: background)
                    .resizable()
                    .scaledToFill()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .clipped()
                    .position(x: displayRect.midX, y: displayRect.midY)
            } else if model.series != nil {
                FitOnlyPreviewBackground()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
            } else {
                PlaceholderView()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
            }

            if let activeDrag {
                if let baseOverlay = model.dragBaseOverlayImage {
                    overlayImage(baseOverlay, displayRect: displayRect)
                } else if let sourceOverlay = activeDrag.sourceOverlay {
                    dragBaseSnapshotOverlay(
                        sourceOverlay,
                        excluding: activeDrag.sourceRect,
                        displayRect: displayRect
                    )
                }
            } else if let overlay = model.overlayImage {
                overlayImage(overlay, displayRect: displayRect)
            }

            if let activeDrag {
                if let dragOverlay = model.dragOverlayImage {
                    dragSnapshotOverlay(
                        dragOverlay,
                        sourceRect: activeDrag.sourceRect,
                        displayRect: displayRect,
                        translation: activeDrag.translation
                    )
                } else if let sourceOverlay = activeDrag.sourceOverlay {
                    dragSnapshotOverlay(
                        sourceOverlay,
                        sourceRect: activeDrag.sourceRect,
                        displayRect: displayRect,
                        translation: activeDrag.translation
                    )
                }
            }

            if model.showGrid {
                PreviewGridOverlay(columns: model.gridColumns, rows: model.gridRows)
                    .stroke(Color.white.opacity(0.34), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
                    .allowsHitTesting(false)
            }

            ForEach(interactiveElements(visibleElements)) { element in
                componentHandle(
                    element: element,
                    displayRect: displayRect,
                    visibleElements: visibleElements,
                    alignedMetricWidth: alignedMetricWidth
                )
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .coordinateSpace(name: "previewCanvas")
        .contentShape(Rectangle())
        .highPriorityGesture(
            SpatialTapGesture(coordinateSpace: .named("previewCanvas"))
                .onEnded { value in
                    selectElement(
                        at: value.location,
                        displayRect: displayRect,
                        visibleElements: visibleElements,
                        alignedMetricWidth: alignedMetricWidth
                    )
                }
        )
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func componentHandle(
        element: OverlayElement,
        displayRect: CGRect,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) -> some View {
        let dragState = activeDrag?.id == element.id ? activeDrag : nil
        let rect = dragState.map {
            $0.sourceRect.offsetBy(dx: $0.translation.width, dy: $0.translation.height)
        } ?? componentDisplayRect(element: element, displayRect: displayRect, alignedMetricWidth: alignedMetricWidth)
        let isSelected = model.selectedElementID == element.id

        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onTapGesture {
                selectElement(element.id)
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("previewCanvas"))
                    .onChanged { value in
                        let targetID = activeDrag?.id ?? hitTestElement(
                            at: value.startLocation,
                            displayRect: displayRect,
                            visibleElements: visibleElements,
                            alignedMetricWidth: alignedMetricWidth
                        )?.id ?? element.id
                        moveElement(
                            targetID,
                            displayRect: displayRect,
                            translation: value.translation,
                            alignedMetricWidth: alignedMetricWidth
                        )
                    }
                    .onEnded { _ in
                        if let activeDrag {
                            model.updateElement(activeDrag.id, refreshPreview: false) { element in
                                element.frame.x = activeDrag.currentX
                                element.frame.y = activeDrag.currentY
                            }
                        }
                        activeDrag = nil
                        model.endElementDrag()
                    }
            )
            .zIndex(isSelected ? 10 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(localization.string(element.kind.localizationKey)))
            .accessibilityValue(Text(isSelected ? localization.string("preview.selected") : localization.string("preview.notSelected")))
            .accessibilityHint(Text(localization.string("preview.elementHint")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                selectElement(element.id)
            }
    }

    private func interactiveElements(_ visibleElements: [OverlayElement]) -> [OverlayElement] {
        guard let activeDrag else { return visibleElements }
        guard let element = visibleElements.first(where: { $0.id == activeDrag.id }) else { return [] }
        return [element]
    }

    private func selectElement(_ id: String) {
        if model.selectedElementID != id {
            model.selectedElementID = id
        }
    }

    private func selectElement(
        at location: CGPoint,
        displayRect: CGRect,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) {
        guard let element = hitTestElement(
            at: location,
            displayRect: displayRect,
            visibleElements: visibleElements,
            alignedMetricWidth: alignedMetricWidth
        ) else { return }
        selectElement(element.id)
    }

    private func hitTestElement(
        at location: CGPoint,
        displayRect: CGRect,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) -> OverlayElement? {
        visibleElements
            .reversed()
            .first { element in
                componentDisplayRect(
                    element: element,
                    displayRect: displayRect,
                    alignedMetricWidth: alignedMetricWidth
                ).contains(location)
            } ?? visibleElements
            .reversed()
            .first { element in
                componentHitRect(
                    element: element,
                    displayRect: displayRect,
                    alignedMetricWidth: alignedMetricWidth
                ).contains(location)
            }
    }

    private func moveElement(
        _ id: String,
        displayRect: CGRect,
        translation: CGSize,
        alignedMetricWidth: CGFloat?
    ) {
        guard !model.isExporting else { return }

        var dragState = activeDrag
        if activeDrag?.id != id, let element = model.layout.elements.first(where: { $0.id == id }) {
            selectElement(id)
            let initialDragState = ComponentDragState(
                id: id,
                startX: element.frame.x,
                startY: element.frame.y,
                currentX: element.frame.x,
                currentY: element.frame.y,
                sourceRect: componentDisplayRect(
                    element: element,
                    displayRect: displayRect,
                    alignedMetricWidth: alignedMetricWidth
                ),
                sourceOverlay: model.overlayImage,
                translation: .zero
            )
            dragState = initialDragState
            self.activeDrag = initialDragState
            model.beginElementDrag(id: id, previewSize: previewOverlayRenderSize(for: displayRect.size))
        }
        guard var activeDrag = dragState else { return }

        let deltaX = Double(translation.width / max(1, displayRect.width))
        let deltaY = Double(translation.height / max(1, displayRect.height))
        var nextX = activeDrag.startX + deltaX
        var nextY = activeDrag.startY + deltaY
        if model.snapGaugeToGrid {
            nextX = snapped(nextX, divisions: model.gridColumns)
            nextY = snapped(nextY, divisions: model.gridRows)
        }
        nextX = PreviewLayoutLimits.clampPosition(nextX)
        nextY = PreviewLayoutLimits.clampPosition(nextY)
        activeDrag.translation = CGSize(
            width: (nextX - activeDrag.startX) * displayRect.width,
            height: (nextY - activeDrag.startY) * displayRect.height
        )
        activeDrag.currentX = nextX
        activeDrag.currentY = nextY
        if let previousDrag = self.activeDrag,
           previousDrag.id == activeDrag.id,
           abs(previousDrag.translation.width - activeDrag.translation.width) < 0.25,
           abs(previousDrag.translation.height - activeDrag.translation.height) < 0.25 {
            return
        }
        self.activeDrag = activeDrag
    }

    private func snapped(_ value: Double, divisions: Int) -> Double {
        let divisions = max(1, divisions)
        return (value * Double(divisions)).rounded() / Double(divisions)
    }

    private func componentHitRect(element: OverlayElement, displayRect: CGRect, alignedMetricWidth: CGFloat?) -> CGRect {
        componentDisplayRect(element: element, displayRect: displayRect, alignedMetricWidth: alignedMetricWidth)
            .insetBy(dx: -8, dy: -8)
    }

    private func componentDisplayRect(element: OverlayElement, displayRect: CGRect, alignedMetricWidth: CGFloat?) -> CGRect {
        let unitRect = componentUnitRect(element: element, alignedMetricWidth: alignedMetricWidth)
        return CGRect(
            x: displayRect.minX + displayRect.width * unitRect.minX,
            y: displayRect.minY + displayRect.height * unitRect.minY,
            width: displayRect.width * unitRect.width,
            height: displayRect.height * unitRect.height
        )
    }

    private func componentUnitRect(element: OverlayElement, alignedMetricWidth: CGFloat?) -> CGRect {
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

    private func layoutOverflowInsets(
        canvasSize: CGSize,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) -> CanvasOverflowInsets {
        var insets = CanvasOverflowInsets()
        let hitPadding: CGFloat = 18

        for element in visibleElements {
            let rect = componentUnitRect(element: element, alignedMetricWidth: alignedMetricWidth)
            insets.left = max(insets.left, -rect.minX * canvasSize.width + hitPadding)
            insets.right = max(insets.right, (rect.maxX - 1) * canvasSize.width + hitPadding)
            insets.top = max(insets.top, -rect.minY * canvasSize.height + hitPadding)
            insets.bottom = max(insets.bottom, (rect.maxY - 1) * canvasSize.height + hitPadding)
        }

        return insets.roundedUp
    }

    private func componentOutputSize(element: OverlayElement, base: CGSize, alignedMetricWidth: CGFloat?) -> CGSize {
        let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let baseWidth = base.width * scale * CGFloat(max(0.1, element.customization.lengthScale))
        let baseHeight = base.height * scale

        switch element.kind {
        case .pace, .distance, .heartRate, .cadence, .calories, .strideLength, .power, .weather:
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
            alignedMetricWidth ?? 0,
            baseWidth,
            (horizontalPadding * 2) + valueWidth + unitGap + unitWidth,
            (horizontalPadding * 2) + labelWidth + iconGap + iconWidth
        )
        return CGSize(width: desiredWidth, height: desiredHeight)
    }

    private func alignedMetricOutputWidth(for visibleElements: [OverlayElement]) -> CGFloat? {
        let widths = visibleElements.compactMap { element -> CGFloat? in
            guard isMetricElement(element) else { return nil }
            let base = ComponentBaseSize.size(for: element.kind)
            let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
            let baseWidth = base.width * scale * CGFloat(max(0.1, element.customization.lengthScale))
            return metricDesiredOutputWidth(element: element, baseWidth: baseWidth, scale: scale)
        }
        return widths.max()
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
        case .pace, .distance, .heartRate, .cadence, .calories, .strideLength, .power, .weather:
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
        let elapsed = model.timeSync.fitElapsed(forVideoTime: model.previewTime)
        return model.series?.sample(at: elapsed) ?? TelemetrySample(elapsed: elapsed)
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
        case .weather:
            return (
                element.customization.label(default: "WEATHER"),
                formatWeatherTemperature(sample),
                element.customization.unit(default: formatWeatherUnit(sample)),
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
        let rawElapsed = model.timeSync.rawFitElapsed(forVideoTime: model.previewTime)
        let absoluteDate = model.series?.date(atElapsed: rawElapsed) ?? sample.date
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

    private func previewOverlayRenderSize(for displaySize: CGSize) -> CGSize {
        let maximumDimension: CGFloat = 3200
        let longestSide = max(displaySize.width, displaySize.height)
        guard longestSide > maximumDimension else { return displaySize }
        let scale = maximumDimension / longestSide
        return CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
    }

    private func dragSnapshotOverlay(
        _ image: NSImage,
        sourceRect: CGRect,
        displayRect: CGRect,
        translation: CGSize
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: displayRect.width, height: displayRect.height)
                .offset(
                    x: displayRect.minX - sourceRect.minX,
                    y: displayRect.minY - sourceRect.minY
                )
        }
        .frame(width: sourceRect.width, height: sourceRect.height, alignment: .topLeading)
        .clipped()
        .position(x: sourceRect.midX, y: sourceRect.midY)
        .offset(translation)
        .allowsHitTesting(false)
    }

    private func dragBaseSnapshotOverlay(
        _ image: NSImage,
        excluding sourceRect: CGRect,
        displayRect: CGRect
    ) -> some View {
        let cropRects = dragBaseSnapshotRects(displayRect: displayRect, excluding: sourceRect)
        return ZStack {
            ForEach(cropRects.indices, id: \.self) { index in
                croppedOverlayImage(image, cropRect: cropRects[index], displayRect: displayRect)
            }
        }
        .allowsHitTesting(false)
    }

    private func croppedOverlayImage(_ image: NSImage, cropRect: CGRect, displayRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .frame(width: displayRect.width, height: displayRect.height)
                .offset(
                    x: displayRect.minX - cropRect.minX,
                    y: displayRect.minY - cropRect.minY
                )
        }
        .frame(width: cropRect.width, height: cropRect.height, alignment: .topLeading)
        .clipped()
        .position(x: cropRect.midX, y: cropRect.midY)
    }

    private func dragBaseSnapshotRects(displayRect: CGRect, excluding sourceRect: CGRect) -> [CGRect] {
        let excluded = sourceRect.intersection(displayRect)
        guard !excluded.isNull, !excluded.isEmpty else { return [displayRect] }

        var rects: [CGRect] = []
        appendSnapshotRect(
            CGRect(x: displayRect.minX, y: displayRect.minY, width: displayRect.width, height: excluded.minY - displayRect.minY),
            to: &rects
        )
        appendSnapshotRect(
            CGRect(x: displayRect.minX, y: excluded.maxY, width: displayRect.width, height: displayRect.maxY - excluded.maxY),
            to: &rects
        )
        appendSnapshotRect(
            CGRect(x: displayRect.minX, y: excluded.minY, width: excluded.minX - displayRect.minX, height: excluded.height),
            to: &rects
        )
        appendSnapshotRect(
            CGRect(x: excluded.maxX, y: excluded.minY, width: displayRect.maxX - excluded.maxX, height: excluded.height),
            to: &rects
        )
        return rects
    }

    private func appendSnapshotRect(_ rect: CGRect, to rects: inout [CGRect]) {
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        rects.append(rect)
    }

    private func overlayImage(_ image: NSImage, displayRect: CGRect) -> some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: displayRect.width, height: displayRect.height)
            .position(x: displayRect.midX, y: displayRect.midY)
            .allowsHitTesting(false)
    }

    private func rendererLayoutScale() -> CGFloat {
        max(0.28, min(CGFloat(model.outputWidth) / 1920, CGFloat(model.outputHeight) / 1080))
    }

    private func aspectFitSize(container: CGSize, aspectRatio: CGFloat) -> CGSize {
        let containerAspect = container.width / max(1, container.height)
        if containerAspect > aspectRatio {
            return CGSize(width: container.height * aspectRatio, height: container.height)
        }
        return CGSize(width: container.width, height: container.width / max(0.1, aspectRatio))
    }

    private func previewStageInsets(for viewportSize: CGSize) -> EdgeInsets {
        let horizontalPadding: CGFloat = viewportSize.width < 760 ? 16 : 24
        return EdgeInsets(
            top: isFullscreen ? 24 : 28,
            leading: horizontalPadding,
            bottom: isFullscreen ? 24 : 20,
            trailing: horizontalPadding
        )
    }

    private func verticalPreviewSlackOffset(_ slack: CGFloat) -> CGFloat {
        guard slack > 0 else { return 0 }
        if isFullscreen {
            return slack / 2
        }
        guard slack > 96 else {
            return slack / 2
        }
        return min(slack / 2, max(32, slack * 0.16))
    }

    private func clampedZoom(_ value: Double) -> Double {
        PreviewZoomLimits.clamp(value)
    }

    private func setZoom(_ value: Double) {
        zoom = clampedZoom(value)
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

enum PreviewZoomLimits {
    static let range: ClosedRange<Double> = 0.25...4.0

    static func clamp(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : 1))
    }
}

private struct ComponentDragState {
    let id: String
    let startX: Double
    let startY: Double
    var currentX: Double
    var currentY: Double
    let sourceRect: CGRect
    let sourceOverlay: NSImage?
    var translation: CGSize
}

private struct CanvasOverflowInsets {
    var left: CGFloat = 0
    var right: CGFloat = 0
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    var roundedUp: CanvasOverflowInsets {
        CanvasOverflowInsets(
            left: max(0, ceil(left)),
            right: max(0, ceil(right)),
            top: max(0, ceil(top)),
            bottom: max(0, ceil(bottom))
        )
    }
}

private struct PreviewGridOverlay: Shape {
    var columns: Int
    var rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = max(1, columns)
        let rows = max(1, rows)

        if columns > 1 {
            for index in 1..<columns {
                let x = rect.minX + rect.width * CGFloat(index) / CGFloat(columns)
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }

        if rows > 1 {
            for index in 1..<rows {
                let y = rect.minY + rect.height * CGFloat(index) / CGFloat(rows)
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }

        return path
    }
}

private struct FitOnlyPreviewBackground: View {
    var body: some View {
        Rectangle()
            .fill(.black.opacity(0.76))
    }
}

struct PlaceholderView: View {
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.76))
            VStack(spacing: 10) {
                Image(systemName: "film")
                    .font(.system(size: 42))
                Text(localization.string("preview.placeholder.title"))
                    .font(.title3.weight(.semibold))
                Text(localization.string("preview.placeholder.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
