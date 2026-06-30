import AppKit
import AVFoundation
import SwiftUI
import OverlayCore

struct PreviewCanvasView: View {
    static let componentDragMinimumDistance: CGFloat = 1

    let model: StudioModel
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
        let canvasState = PreviewCanvasState(model: model)
        let controlsState = PreviewControlsState(model: model)

        if isFullscreen {
            ZStack(alignment: .bottom) {
                previewViewport(state: canvasState)
                PreviewControlsPanel(
                    model: model,
                    state: controlsState,
                    zoom: $zoom,
                    isFullscreen: isFullscreen,
                    onToggleFullscreen: onToggleFullscreen
                )
            }
        } else {
            VStack(spacing: 0) {
                previewViewport(state: canvasState)
                PreviewControlsPanel(
                    model: model,
                    state: controlsState,
                    zoom: $zoom,
                    isFullscreen: isFullscreen,
                    onToggleFullscreen: onToggleFullscreen
                )
            }
        }
    }

    private func previewViewport(state: PreviewCanvasState) -> some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let stageInsets = previewStageInsets(for: viewportSize)
            let stageSize = CGSize(
                width: max(1, viewportSize.width - stageInsets.leading - stageInsets.trailing),
                height: max(1, viewportSize.height - stageInsets.top - stageInsets.bottom)
            )
            let fitSize = aspectFitSize(
                container: stageSize,
                aspectRatio: CGFloat(state.outputWidth) / CGFloat(max(1, state.outputHeight))
            )
            let zoomFactor = CGFloat(clampedZoom(zoom))
            let canvasSize = CGSize(width: fitSize.width * zoomFactor, height: fitSize.height * zoomFactor)
            let overlayRenderSize = previewOverlayRenderSize(for: canvasSize)
            let dragState = activeDrag
            let visibleElements = dragState?.visibleElements ?? state.layout.visibleElements
            let alignedMetricWidth = dragState?.alignedMetricWidth ?? alignedMetricOutputWidth(for: visibleElements)
            let overflowInsets = dragState?.overflowInsets ?? layoutOverflowInsets(
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
            let computedContentSize = CGSize(
                width: max(viewportSize.width, displayRect.maxX + overflowInsets.right + stageInsets.trailing),
                height: max(viewportSize.height, displayRect.maxY + overflowInsets.bottom + stageInsets.bottom)
            )
            let contentSize = dragState?.contentSize ?? computedContentSize

            ScrollView([.horizontal, .vertical]) {
                previewCanvas(
                    displayRect: displayRect,
                    contentSize: contentSize,
                    visibleElements: visibleElements,
                    alignedMetricWidth: alignedMetricWidth,
                    state: state
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
        alignedMetricWidth: CGFloat?,
        state: PreviewCanvasState
    ) -> some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let player = state.player {
                PlayerSurfaceView(player: player)
                    .frame(width: displayRect.width, height: displayRect.height)
                    .clipped()
                    .position(x: displayRect.midX, y: displayRect.midY)
                    .allowsHitTesting(false)
            } else if let background = state.backgroundImage {
                Image(nsImage: background)
                    .resizable()
                    .scaledToFill()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .clipped()
                    .position(x: displayRect.midX, y: displayRect.midY)
            } else if state.hasSeries {
                FitOnlyPreviewBackground()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
            } else {
                PlaceholderView()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
            }

            if let activeDrag {
                if let baseOverlay = state.dragBaseOverlayImage {
                    overlayImage(baseOverlay, displayRect: displayRect)
                } else if !activeDrag.baseSnapshots.isEmpty {
                    dragBaseSnapshotSlices(activeDrag.baseSnapshots)
                } else if let sourceOverlay = activeDrag.sourceOverlay {
                    dragBaseSnapshotOverlay(
                        sourceOverlay,
                        excluding: activeDrag.sourceRect,
                        displayRect: displayRect
                    )
                }
            } else if let overlay = state.overlayImage {
                overlayImage(overlay, displayRect: displayRect)
            }

            if let activeDrag {
                if let sourceElementSnapshot = activeDrag.sourceElementSnapshot {
                    dragSnapshotImage(
                        sourceElementSnapshot,
                        sourceRect: activeDrag.sourceRect,
                        translation: activeDrag.translation
                    )
                } else if let dragOverlay = state.dragOverlayImage {
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

            if state.isScrubbingPreview, state.hasSeries, activeDrag == nil {
                liveScrubOverlay(
                    displayRect: displayRect,
                    visibleElements: visibleElements,
                    alignedMetricWidth: alignedMetricWidth
                )
                .allowsHitTesting(false)
            }

            if state.showGrid {
                PreviewGridOverlay(columns: state.gridColumns, rows: state.gridRows)
                    .stroke(Color.white.opacity(0.34), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
                    .allowsHitTesting(false)
            }

            ForEach(interactiveElements(visibleElements)) { element in
                componentHandle(
                    element: element,
                    displayRect: displayRect,
                    contentSize: contentSize,
                    visibleElements: visibleElements,
                    alignedMetricWidth: alignedMetricWidth,
                    state: state
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
        contentSize: CGSize,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?,
        state: PreviewCanvasState
    ) -> some View {
        let dragState = activeDrag?.id == element.id ? activeDrag : nil
        let rect = dragState.map {
            $0.sourceRect.offsetBy(dx: $0.translation.width, dy: $0.translation.height)
        } ?? componentDisplayRect(element: element, displayRect: displayRect, alignedMetricWidth: alignedMetricWidth)
        let isSelected = state.selectedElementID == element.id

        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onTapGesture {
                selectElement(element.id)
            }
            .gesture(
                DragGesture(minimumDistance: Self.componentDragMinimumDistance, coordinateSpace: .named("previewCanvas"))
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
                            contentSize: contentSize,
                            translation: value.translation,
                            visibleElements: visibleElements,
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
        contentSize: CGSize,
        translation: CGSize,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) {
        guard !model.isExporting else { return }

        var dragState = activeDrag
        if activeDrag?.id != id, let element = model.layout.elements.first(where: { $0.id == id }) {
            selectElement(id)
            let sourceRect = componentDisplayRect(
                element: element,
                displayRect: displayRect,
                alignedMetricWidth: alignedMetricWidth
            )
            let sourceOverlay = model.overlayImage
            let sourceElementSnapshot = sourceOverlay.flatMap {
                PreviewSnapshotSlicer.sliceImage($0, cropRect: sourceRect, displayRect: displayRect)
            }
            let baseSnapshotRects = dragBaseSnapshotRects(displayRect: displayRect, excluding: sourceRect)
            let baseSnapshots = sourceOverlay.map { overlay in
                baseSnapshotRects.compactMap { rect in
                    PreviewSnapshotSlicer.slice(
                        image: overlay,
                        cropRect: rect,
                        displayRect: displayRect
                    )
                }
            } ?? []
            let initialDragState = ComponentDragState(
                id: id,
                startX: element.frame.x,
                startY: element.frame.y,
                currentX: element.frame.x,
                currentY: element.frame.y,
                sourceRect: sourceRect,
                sourceOverlay: sourceOverlay,
                sourceElementSnapshot: sourceElementSnapshot,
                baseSnapshots: baseSnapshots,
                visibleElements: [element],
                alignedMetricWidth: alignedMetricWidth,
                overflowInsets: layoutOverflowInsets(
                    canvasSize: displayRect.size,
                    visibleElements: visibleElements,
                    alignedMetricWidth: alignedMetricWidth
                ),
                contentSize: contentSize,
                translation: .zero
            )
            dragState = initialDragState
            self.activeDrag = initialDragState
            model.beginElementDrag(
                id: id,
                previewSize: previewOverlayRenderSize(for: displayRect.size),
                renderFallbackSnapshots: sourceElementSnapshot == nil || baseSnapshots.count != baseSnapshotRects.count
            )
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

    private func dragSnapshotImage(
        _ image: NSImage,
        sourceRect: CGRect,
        translation: CGSize
    ) -> some View {
        Image(nsImage: image)
            .resizable()
            .frame(width: sourceRect.width, height: sourceRect.height)
            .position(x: sourceRect.midX, y: sourceRect.midY)
            .offset(translation)
            .allowsHitTesting(false)
    }

    private func dragBaseSnapshotSlices(_ slices: [DragSnapshotSlice]) -> some View {
        ZStack {
            ForEach(slices.indices, id: \.self) { index in
                let slice = slices[index]
                Image(nsImage: slice.image)
                    .resizable()
                    .frame(width: slice.rect.width, height: slice.rect.height)
                    .position(x: slice.rect.midX, y: slice.rect.midY)
            }
        }
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

    private func liveScrubOverlay(
        displayRect: CGRect,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) -> some View {
        ZStack {
            ForEach(visibleElements) { element in
                let rect = componentDisplayRect(
                    element: element,
                    displayRect: displayRect,
                    alignedMetricWidth: alignedMetricWidth
                )
                switch element.kind {
                case .pace, .distance, .heartRate, .cadence, .calories, .strideLength, .power, .weather:
                    liveMetricOverlay(element: element, rect: rect, displayRect: displayRect)
                case .topProgress:
                    liveTopProgressOverlay(element: element, rect: rect, displayRect: displayRect)
                case .timeDate:
                    liveTimeDateOverlay(element: element, rect: rect, displayRect: displayRect)
                case .route:
                    liveRouteMarkerOverlay(element: element, rect: rect, displayRect: displayRect)
                case .speed:
                    EmptyView()
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func liveMetricOverlay(element: OverlayElement, rect: CGRect, displayRect: CGRect) -> some View {
        let text = metricText(for: element)
        let outputScale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let textScale = outputScale * CGFloat(element.frame.style.textScale)
        let displayScale = displayScale(for: displayRect)
        let labelFontSize = labelSize(10, scale: textScale, element: element) * displayScale
        let valueFontSize = valueSize(23, scale: textScale, element: element) * displayScale
        let unitFontSize = unitSize(10, scale: textScale, element: element) * displayScale
        let iconFontSize = metricIconFontSize(element: element, textScale: textScale) * displayScale
        let horizontalPadding = 14 * outputScale * displayScale
        let verticalPadding = 9 * outputScale * displayScale
        let cornerRadius = max(6, 12 * outputScale * displayScale)
        let labelColor = (element.customization.labelColor ?? .label).swiftUIColor
        let valueColor = (element.customization.valueColor ?? (element.frame.style.accentColor ?? model.layout.style.accentColor).overlayColor).swiftUIColor
        let unitColor = (element.customization.unitColor ?? .muted).swiftUIColor
        let iconColor = (element.customization.iconColor ?? element.customization.labelColor ?? .label).swiftUIColor
        let unitLines = metricUnitLines(text.unit)

        return ZStack {
            if element.customization.showsPanel {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(componentPanelOpacity(element)))
                    .overlay {
                        if element.customization.panelBorderIsVisible {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: max(0.5, displayScale))
                        }
                    }
            }

            VStack(alignment: .leading, spacing: max(2, 5 * outputScale * displayScale)) {
                if element.customization.showsLabel || (element.customization.showsIcon && element.kind != .weather) {
                    HStack(spacing: max(3, 8 * outputScale * displayScale)) {
                        if element.customization.showsLabel {
                            Text(text.label)
                                .font(liveFont(element.customization.labelFont, size: labelFontSize))
                                .foregroundStyle(labelColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                        Spacer(minLength: 0)
                        if element.customization.showsIcon, element.kind != .weather {
                            Text(text.icon)
                                .font(liveFont(element.customization.iconFont, size: iconFontSize))
                                .foregroundStyle(iconColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: max(4, 10 * outputScale * displayScale)) {
                    Text(text.value)
                        .font(liveFont(element.customization.valueFont, size: valueFontSize))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    Spacer(minLength: 0)

                    if element.customization.showsUnit {
                        VStack(alignment: .trailing, spacing: max(1, metricUnitLineGap(element: element, unitFontSize: unitFontSize / max(displayScale, 0.001), scale: outputScale) * displayScale)) {
                            ForEach(unitLines.indices, id: \.self) { index in
                                if element.kind == .weather, index == 0, element.customization.showsIcon {
                                    Text(weatherIconText(element: element, summary: unitLines.first))
                                        .font(liveFont(element.customization.iconFont, size: iconFontSize))
                                        .foregroundStyle(iconColor)
                                        .lineLimit(1)
                                } else {
                                    Text(unitLines[index])
                                        .font(liveFont(element.customization.unitFont, size: unitFontSize))
                                        .foregroundStyle(unitColor)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.55)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func liveTimeDateOverlay(element: OverlayElement, rect: CGRect, displayRect: CGRect) -> some View {
        let text = timeDateText(for: element)
        let outputScale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let textScale = outputScale * CGFloat(element.frame.style.textScale)
        let displayScale = displayScale(for: displayRect)
        let labelFontSize = labelSize(11, scale: textScale, element: element) * displayScale
        let valueFontSize = valueSize(24, scale: textScale, element: element) * displayScale
        let unitFontSize = unitSize(18, scale: textScale, element: element) * displayScale
        let labelColor = (element.customization.labelColor ?? .label).swiftUIColor
        let valueColor = (element.customization.valueColor ?? (element.frame.style.accentColor ?? model.layout.style.accentColor).overlayColor).swiftUIColor
        let unitColor = (element.customization.unitColor ?? .muted).swiftUIColor
        let cornerRadius = max(5, 10 * outputScale * displayScale)

        return ZStack {
            if element.customization.showsPanel {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(componentPanelOpacity(element)))
            }

            VStack(alignment: .trailing, spacing: max(2, 5 * outputScale * displayScale)) {
                if element.customization.showsLabel {
                    Text(text.label)
                        .font(liveFont(element.customization.labelFont, size: labelFontSize))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                }
                Text(text.elapsed)
                    .font(liveFont(element.customization.valueFont, size: valueFontSize))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                if element.customization.showsUnit {
                    Text(text.clock)
                        .font(liveFont(element.customization.unitFont, size: unitFontSize))
                        .foregroundStyle(unitColor)
                        .lineLimit(1)
                    Text(text.date)
                        .font(liveFont(element.customization.unitFont, size: unitFontSize * 0.82))
                        .foregroundStyle(unitColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(max(2, 10 * outputScale * displayScale))
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func liveTopProgressOverlay(element: OverlayElement, rect: CGRect, displayRect: CGRect) -> some View {
        let sample = currentTelemetrySample()
        let outputScale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let displayScale = displayScale(for: displayRect)
        let trackHeight = max(1, lineWidth(element, scale: outputScale) * displayScale)
        let sidePadding = min(
            rect.width * 0.42,
            max(0, 72 * outputScale * CGFloat(element.customization.progressInsetScale ?? 1) * displayScale)
        )
        let topInset = max(3, 18 * outputScale * displayScale)
        let trackWidth = max(1, rect.width - sidePadding * 2)
        let trackRect = CGRect(
            x: rect.minX + sidePadding,
            y: rect.minY + topInset,
            width: trackWidth,
            height: trackHeight
        )
        let totalDistance = max(totalDistanceMeters(), sample.distanceMeters ?? 0)
        let progress = totalDistance > 0 ? min(1, max(0, (sample.distanceMeters ?? 0) / totalDistance)) : 0
        let knobRadius = max(4, trackHeight * 0.82 * progressKnobScale(element))
        let knobX = trackRect.minX + trackRect.width * CGFloat(progress)
        let textScale = outputScale * CGFloat(element.frame.style.textScale)
        let labelFontSize = labelSize(15, scale: textScale, element: element) * displayScale
        let currentFontSize = valueSize(12, scale: textScale, element: element) * displayScale
        let trackColor = (element.customization.trackColor ?? .track).swiftUIColor
        let progressColor = (element.customization.progressBarColor ?? element.customization.valueColor ?? (element.frame.style.accentColor ?? model.layout.style.accentColor).overlayColor).swiftUIColor
        let startColor = (element.customization.progressStartColor ?? element.customization.labelColor ?? .label).swiftUIColor
        let currentColor = (element.customization.progressCurrentColor ?? element.customization.valueColor ?? (element.frame.style.accentColor ?? model.layout.style.accentColor).overlayColor).swiftUIColor
        let endColor = (element.customization.progressEndColor ?? element.customization.unitColor ?? .muted).swiftUIColor

        return ZStack(alignment: .topLeading) {
            if element.customization.showsPanel {
                RoundedRectangle(cornerRadius: max(5, 12 * outputScale * displayScale), style: .continuous)
                    .fill(Color.black.opacity(componentPanelOpacity(element)))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            if element.customization.showsLabel {
                Text(distanceLabel(0, element: element))
                    .font(liveFont(element.customization.progressStartFont ?? element.customization.labelFont, size: labelFontSize))
                    .foregroundStyle(startColor)
                    .position(x: trackRect.minX, y: rect.minY + max(6, labelFontSize * 0.5))
                    .fixedSize()
                Text(distanceLabel(sample.distanceMeters, element: element))
                    .font(liveFont(element.customization.progressCurrentFont ?? element.customization.valueFont, size: currentFontSize))
                    .foregroundStyle(currentColor)
                    .position(x: knobX, y: trackRect.maxY + max(5, progressValueMargin(element, scale: outputScale, trackHeight: trackHeight / max(displayScale, 0.001)) * displayScale))
                    .fixedSize()
            }

            if element.customization.showsUnit {
                Text(distanceLabel(totalDistance, element: element))
                    .font(liveFont(element.customization.progressEndFont ?? element.customization.unitFont, size: labelFontSize))
                    .foregroundStyle(endColor)
                    .position(x: trackRect.maxX, y: rect.minY + max(6, labelFontSize * 0.5))
                    .fixedSize()
            }

            Capsule()
                .fill(trackColor)
                .frame(width: trackRect.width, height: trackRect.height)
                .position(x: trackRect.midX, y: trackRect.midY)
            Capsule()
                .fill(progressColor)
                .frame(width: max(0, trackRect.width * CGFloat(progress)), height: trackRect.height)
                .position(
                    x: trackRect.minX + max(0, trackRect.width * CGFloat(progress)) / 2,
                    y: trackRect.midY
                )
            Circle()
                .fill(progressColor)
                .overlay(Circle().stroke(progressColor.opacity(0.72), lineWidth: max(1, trackHeight * 0.18)))
                .shadow(color: .black.opacity(0.28), radius: max(1, knobRadius * 0.28))
                .frame(width: knobRadius * 2, height: knobRadius * 2)
                .position(x: knobX, y: trackRect.midY)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func liveRouteMarkerOverlay(element: OverlayElement, rect: CGRect, displayRect: CGRect) -> some View {
        let outputScale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let displayScale = displayScale(for: displayRect)
        let mapRect = routeFitDisplayRect(rect, element: element, outputScale: outputScale, displayScale: displayScale)
        let marker = routeMarkerPoint(in: mapRect)
        let before = routeMarkerPoint(in: mapRect, elapsedOffset: -2)
        let after = routeMarkerPoint(in: mapRect, elapsedOffset: 2)
        let angle = routeDirectionAngle(before: before, after: after)
        let color = (element.customization.valueColor ?? (element.frame.style.accentColor ?? model.layout.style.accentColor).overlayColor).swiftUIColor
        let radius = max(3, 6 * outputScale * displayScale)

        return ZStack {
            if let marker {
                Circle()
                    .fill(color.opacity(0.92))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: marker.x, y: marker.y)
                Circle()
                    .stroke(color, lineWidth: max(1, 2 * outputScale * displayScale))
                    .frame(width: radius * 4, height: radius * 4)
                    .position(x: marker.x, y: marker.y)
                if let angle {
                    RouteArrowShape(angle: angle)
                        .fill(color)
                        .frame(width: radius * 4.4, height: radius * 4.4)
                        .position(x: marker.x, y: marker.y)
                }
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }

    private func displayScale(for displayRect: CGRect) -> CGFloat {
        displayRect.width / CGFloat(max(1, model.outputWidth))
    }

    private func componentPanelOpacity(_ element: OverlayElement) -> Double {
        element.frame.style.panelOpacity ?? model.layout.style.panelOpacity
    }

    private func liveFont(_ family: OverlayFontFamily, size: CGFloat) -> Font {
        .custom(family.postScriptName, size: max(4, size))
    }

    private func distanceLabel(_ meters: Double?, element: OverlayElement) -> String {
        "\(formatDistance(meters, element: element)) \(element.customization.unit(default: model.distanceUnit.symbol))"
    }

    private func totalDistanceMeters() -> Double {
        model.series?.samples.reversed().first { sample in
            guard let distance = sample.distanceMeters else { return false }
            return distance.isFinite
        }?.distanceMeters ?? 0
    }

    private func routeFitDisplayRect(
        _ rect: CGRect,
        element: OverlayElement,
        outputScale: CGFloat,
        displayScale: CGFloat
    ) -> CGRect {
        let insetX = 26 * outputScale * displayScale
        let insetY = 34 * outputScale * displayScale
        let mapRect = rect.insetBy(dx: min(rect.width * 0.42, insetX), dy: min(rect.height * 0.42, insetY))
        guard let bounds = model.series?.bounds else { return mapRect }
        return routeFitRect(mapRect, bounds: bounds)
    }

    private func routeFitRect(_ rect: CGRect, bounds: GeoBounds) -> CGRect {
        let latSpan = max(bounds.maxLatitude - bounds.minLatitude, 0.000_001)
        let lonSpan = max(bounds.maxLongitude - bounds.minLongitude, 0.000_001)
        let routeAspect = CGFloat(lonSpan / latSpan)
        let rectAspect = rect.width / max(1, rect.height)
        if routeAspect > rectAspect {
            let height = rect.width / max(routeAspect, 0.000_001)
            return CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        }
        let width = rect.height * routeAspect
        return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
    }

    private func routeMarkerPoint(in rect: CGRect, elapsedOffset: TimeInterval = 0) -> CGPoint? {
        guard let series = model.series, let bounds = series.bounds else { return nil }
        let elapsed = model.timeSync.fitElapsed(forVideoTime: model.previewTime) + elapsedOffset
        let sample = series.sample(at: elapsed)
        guard let latitude = sample.latitude, let longitude = sample.longitude else { return nil }
        let latSpan = max(bounds.maxLatitude - bounds.minLatitude, 0.000_001)
        let lonSpan = max(bounds.maxLongitude - bounds.minLongitude, 0.000_001)
        return CGPoint(
            x: rect.minX + CGFloat((longitude - bounds.minLongitude) / lonSpan) * rect.width,
            y: rect.minY + CGFloat((latitude - bounds.minLatitude) / latSpan) * rect.height
        )
    }

    private func routeDirectionAngle(before: CGPoint?, after: CGPoint?) -> Angle? {
        guard let before, let after else { return nil }
        let dx = after.x - before.x
        let dy = after.y - before.y
        guard hypot(dx, dy) > 1 else { return nil }
        return Angle(radians: Double(atan2(dy, dx)))
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

private struct RouteArrowShape: Shape {
    var angle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length = min(rect.width, rect.height) * 0.48
        let width = length * 0.72
        let direction = CGPoint(x: cos(angle.radians), y: sin(angle.radians))
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)
        let tip = CGPoint(x: center.x + direction.x * length, y: center.y + direction.y * length)
        let base = CGPoint(x: center.x + direction.x * length * 0.10, y: center.y + direction.y * length * 0.10)

        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + perpendicular.x * width / 2, y: base.y + perpendicular.y * width / 2))
        path.addLine(to: CGPoint(x: base.x - perpendicular.x * width / 2, y: base.y - perpendicular.y * width / 2))
        path.closeSubpath()
        return path
    }
}

enum PreviewZoomLimits {
    static let range: ClosedRange<Double> = 0.25...4.0

    static func clamp(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : 1))
    }
}

struct PreviewCanvasState: Equatable {
    var player: AVPlayer?
    var backgroundImage: NSImage?
    var overlayImage: NSImage?
    var dragBaseOverlayImage: NSImage?
    var dragOverlayImage: NSImage?
    var layout: OverlayLayout
    var selectedElementID: String?
    var showGrid: Bool
    var gridColumns: Int
    var gridRows: Int
    var hasSeries: Bool
    var outputWidth: Int
    var outputHeight: Int
    var previewTime: TimeInterval
    var isScrubbingPreview: Bool

    @MainActor
    init(model: StudioModel) {
        player = model.player
        backgroundImage = model.backgroundImage
        overlayImage = model.overlayImage
        dragBaseOverlayImage = model.dragBaseOverlayImage
        dragOverlayImage = model.dragOverlayImage
        layout = model.layout
        selectedElementID = model.selectedElementID
        showGrid = model.showGrid
        gridColumns = model.gridColumns
        gridRows = model.gridRows
        hasSeries = model.series != nil
        outputWidth = model.outputWidth
        outputHeight = model.outputHeight
        previewTime = model.previewTime
        isScrubbingPreview = model.isScrubbingPreview
    }

    static func == (lhs: PreviewCanvasState, rhs: PreviewCanvasState) -> Bool {
        lhs.player === rhs.player
            && lhs.backgroundImage === rhs.backgroundImage
            && lhs.overlayImage === rhs.overlayImage
            && lhs.dragBaseOverlayImage === rhs.dragBaseOverlayImage
            && lhs.dragOverlayImage === rhs.dragOverlayImage
            && lhs.layout == rhs.layout
            && lhs.selectedElementID == rhs.selectedElementID
            && lhs.showGrid == rhs.showGrid
            && lhs.gridColumns == rhs.gridColumns
            && lhs.gridRows == rhs.gridRows
            && lhs.hasSeries == rhs.hasSeries
            && lhs.outputWidth == rhs.outputWidth
            && lhs.outputHeight == rhs.outputHeight
            && lhs.previewTime == rhs.previewTime
            && lhs.isScrubbingPreview == rhs.isScrubbingPreview
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
    let sourceElementSnapshot: NSImage?
    let baseSnapshots: [DragSnapshotSlice]
    let visibleElements: [OverlayElement]
    let alignedMetricWidth: CGFloat?
    let overflowInsets: CanvasOverflowInsets
    let contentSize: CGSize
    var translation: CGSize
}

struct DragSnapshotSlice {
    let rect: CGRect
    let image: NSImage
}

enum PreviewSnapshotSlicer {
    static func slice(
        image: NSImage,
        cropRect: CGRect,
        displayRect: CGRect
    ) -> DragSnapshotSlice? {
        guard let slicedImage = sliceImage(image, cropRect: cropRect, displayRect: displayRect) else {
            return nil
        }
        return DragSnapshotSlice(rect: cropRect, image: slicedImage)
    }

    static func sliceImage(
        _ image: NSImage,
        cropRect: CGRect,
        displayRect: CGRect
    ) -> NSImage? {
        guard cropRect.width > 0,
              cropRect.height > 0,
              displayRect.width > 0,
              displayRect.height > 0,
              image.size.width > 0,
              image.size.height > 0 else {
            return nil
        }

        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scaleX = imageSize.width / displayRect.width
        let scaleY = imageSize.height / displayRect.height
        let sourceRect = CGRect(
            x: (cropRect.minX - displayRect.minX) * scaleX,
            y: (cropRect.minY - displayRect.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let clippedSourceRect = sourceRect.integral.intersection(imageBounds)
        guard !clippedSourceRect.isNull,
              clippedSourceRect.width > 0,
              clippedSourceRect.height > 0,
              let croppedImage = cgImage.cropping(to: clippedSourceRect) else {
            return nil
        }

        let outputSize = CGSize(
            width: clippedSourceRect.width / scaleX,
            height: clippedSourceRect.height / scaleY
        )
        return NSImage(cgImage: croppedImage, size: outputSize)
    }
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
