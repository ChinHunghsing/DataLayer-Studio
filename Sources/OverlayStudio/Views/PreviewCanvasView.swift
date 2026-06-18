import AppKit
import SwiftUI
import OverlayCore

struct PreviewCanvasView: View {
    @ObservedObject var model: StudioModel
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
                controlsPanel
            }
        } else {
            VStack(spacing: 0) {
                previewViewport
                controlsPanel
            }
        }
    }

    private var controlsPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                controlRow

                HStack {
                    Text("Preview \(formatTime(model.previewTime))")
                    Spacer()
                    if model.syncMode == .syncPoint, model.syncFITSeconds == 0 {
                        Text("运动开始: \(formatTime(model.syncVideoSeconds))")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    Text("\(model.outputWidth)x\(model.outputHeight)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let previewWarning = model.previewWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(previewWarning)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Preview warning")
                    .accessibilityValue(previewWarning)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private var controlRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                transportControls

                Divider()
                    .frame(height: 18)

                zoomControls
            }

            VStack(spacing: 8) {
                transportControls
                zoomControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            Button {
                model.togglePlayback()
            } label: {
                Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .disabled(model.player == nil || model.isExporting)

            Slider(
                value: Binding(
                    get: { model.previewTime },
                    set: { model.seekPreview(to: $0) }
                ),
                in: 0...max(model.outputDuration, 1)
            )
            .frame(minWidth: 140)
            .disabled(model.player == nil || model.isExporting)

            Button {
                model.markSportStart()
            } label: {
                Label("运动开始", systemImage: "figure.run.circle")
            }
            .disabled(model.player == nil || model.isExporting)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewViewport: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let fitSize = aspectFitSize(
                container: viewportSize,
                aspectRatio: CGFloat(model.outputWidth) / CGFloat(max(1, model.outputHeight))
            )
            let zoomFactor = CGFloat(clampedZoom(zoom))
            let canvasSize = CGSize(width: fitSize.width * zoomFactor, height: fitSize.height * zoomFactor)
            let overlayRenderSize = previewOverlayRenderSize(for: canvasSize)
            let visibleElements = model.layout.visibleElements
            let overflowInsets = layoutOverflowInsets(canvasSize: canvasSize, visibleElements: visibleElements)
            let minimumContentSize = CGSize(
                width: canvasSize.width + overflowInsets.left + overflowInsets.right,
                height: canvasSize.height + overflowInsets.top + overflowInsets.bottom
            )
            let contentSize = CGSize(
                width: max(viewportSize.width, minimumContentSize.width),
                height: max(viewportSize.height, minimumContentSize.height)
            )
            let extraWidth = max(0, contentSize.width - minimumContentSize.width)
            let extraHeight = max(0, contentSize.height - minimumContentSize.height)
            let displayRect = CGRect(
                x: overflowInsets.left + extraWidth / 2,
                y: overflowInsets.top + extraHeight / 2,
                width: canvasSize.width,
                height: canvasSize.height
            )

            ScrollView([.horizontal, .vertical]) {
                previewCanvas(displayRect: displayRect, contentSize: contentSize, visibleElements: visibleElements)
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

    private func previewCanvas(displayRect: CGRect, contentSize: CGSize, visibleElements: [OverlayElement]) -> some View {
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
            } else {
                PlaceholderView()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
            }

            if activeDrag != nil {
                if let baseOverlay = model.dragBaseOverlayImage {
                    overlayImage(baseOverlay, displayRect: displayRect)
                }
            } else if let overlay = model.overlayImage {
                overlayImage(overlay, displayRect: displayRect)
            }

            if let activeDrag {
                if let dragOverlay = model.dragOverlayImage {
                    Image(nsImage: dragOverlay)
                        .resizable()
                        .frame(width: displayRect.width, height: displayRect.height)
                        .position(x: displayRect.midX, y: displayRect.midY)
                        .offset(activeDrag.translation)
                        .allowsHitTesting(false)
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

            ForEach(visibleElements) { element in
                componentHandle(element: element, displayRect: displayRect)
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .coordinateSpace(name: "previewCanvas")
        .contentShape(Rectangle())
        .highPriorityGesture(
            SpatialTapGesture(coordinateSpace: .named("previewCanvas"))
                .onEnded { value in
                    selectElement(at: value.location, displayRect: displayRect, visibleElements: visibleElements)
                }
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button {
                setZoom(zoom / 1.2)
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help("Zoom out")

            Slider(
                value: Binding(
                    get: { clampedZoom(zoom) },
                    set: { setZoom($0) }
                ),
                in: PreviewZoomLimits.range
            )
            .frame(minWidth: 92, idealWidth: 118, maxWidth: 160)

            Text("\(Int((clampedZoom(zoom) * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            Button {
                setZoom(zoom * 1.2)
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help("Zoom in")

            Button {
                setZoom(1)
            } label: {
                Label("Fit", systemImage: "arrow.counterclockwise")
            }
            .labelStyle(.iconOnly)
            .help("Fit to preview")

            Button {
                onToggleFullscreen()
            } label: {
                Label(isFullscreen ? "Exit Full Screen" : "Full Screen", systemImage: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .labelStyle(.iconOnly)
            .help(isFullscreen ? "Exit full screen" : "Full screen")
        }
    }

    private func componentHandle(element: OverlayElement, displayRect: CGRect) -> some View {
        let dragTranslation = activeDrag?.id == element.id ? activeDrag?.translation ?? .zero : .zero
        let rect = componentDisplayRect(element: element, displayRect: displayRect)
            .offsetBy(dx: dragTranslation.width, dy: dragTranslation.height)
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
                        moveElement(element.id, displayRect: displayRect, translation: value.translation)
                    }
                    .onEnded { _ in
                        if let activeDrag, activeDrag.id == element.id {
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
            .accessibilityLabel(Text(element.kind.title))
            .accessibilityValue(Text(isSelected ? "Selected" : "Not selected"))
            .accessibilityHint(Text("Click to select. Drag to move."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                selectElement(element.id)
            }
    }

    private func selectElement(_ id: String) {
        if model.selectedElementID != id {
            model.selectedElementID = id
        }
    }

    private func selectElement(at location: CGPoint, displayRect: CGRect, visibleElements: [OverlayElement]) {
        guard let element = hitTestElement(at: location, displayRect: displayRect, visibleElements: visibleElements) else { return }
        selectElement(element.id)
    }

    private func hitTestElement(at location: CGPoint, displayRect: CGRect, visibleElements: [OverlayElement]) -> OverlayElement? {
        visibleElements
            .reversed()
            .first { element in
                componentHitRect(element: element, displayRect: displayRect).contains(location)
            }
    }

    private func moveElement(_ id: String, displayRect: CGRect, translation: CGSize) {
        guard !model.isExporting else { return }
        selectElement(id)

        if activeDrag?.id != id, let element = model.layout.elements.first(where: { $0.id == id }) {
            activeDrag = ComponentDragState(
                id: id,
                startX: element.frame.x,
                startY: element.frame.y,
                currentX: element.frame.x,
                currentY: element.frame.y,
                sourceRect: componentDisplayRect(element: element, displayRect: displayRect),
                sourceOverlay: model.overlayImage,
                translation: .zero
            )
            model.beginElementDrag(id: id, previewSize: dragRenderSize(for: displayRect.size))
        }
        guard var activeDrag else { return }

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
        self.activeDrag = activeDrag
    }

    private func snapped(_ value: Double, divisions: Int) -> Double {
        let divisions = max(1, divisions)
        return (value * Double(divisions)).rounded() / Double(divisions)
    }

    private func componentHitRect(element: OverlayElement, displayRect: CGRect) -> CGRect {
        componentDisplayRect(element: element, displayRect: displayRect)
            .insetBy(dx: -8, dy: -8)
    }

    private func componentDisplayRect(element: OverlayElement, displayRect: CGRect) -> CGRect {
        let unitRect = componentUnitRect(element: element)
        return CGRect(
            x: displayRect.minX + displayRect.width * unitRect.minX,
            y: displayRect.minY + displayRect.height * unitRect.minY,
            width: displayRect.width * unitRect.width,
            height: displayRect.height * unitRect.height
        )
    }

    private func componentUnitRect(element: OverlayElement) -> CGRect {
        let frame = element.frame
        let base = ComponentBaseSize.size(for: element.kind)
        let outputSize = componentOutputSize(element: element, base: base)
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

    private func layoutOverflowInsets(canvasSize: CGSize, visibleElements: [OverlayElement]) -> CanvasOverflowInsets {
        var insets = CanvasOverflowInsets()
        let hitPadding: CGFloat = 18

        for element in visibleElements {
            let rect = componentUnitRect(element: element)
            insets.left = max(insets.left, -rect.minX * canvasSize.width + hitPadding)
            insets.right = max(insets.right, (rect.maxX - 1) * canvasSize.width + hitPadding)
            insets.top = max(insets.top, -rect.minY * canvasSize.height + hitPadding)
            insets.bottom = max(insets.bottom, (rect.maxY - 1) * canvasSize.height + hitPadding)
        }

        return insets.roundedUp
    }

    private func componentOutputSize(element: OverlayElement, base: CGSize) -> CGSize {
        let scale = rendererLayoutScale() * CGFloat(element.frame.scale)
        let baseWidth = base.width * scale * CGFloat(max(0.1, element.customization.lengthScale))
        let baseHeight = base.height * scale

        switch element.kind {
        case .pace, .distance, .heartRate, .cadence:
            return metricOutputSize(element: element, baseWidth: baseWidth, baseHeight: baseHeight, scale: scale)
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
        scale: CGFloat
    ) -> CGSize {
        let textScale = scale * CGFloat(element.frame.style.textScale)
        let labelFontSize = labelSize(10, scale: textScale, element: element)
        let valueFontSize = valueSize(23, scale: textScale, element: element)
        let unitFontSize = unitSize(10, scale: textScale, element: element)
        let iconFontSize = iconSize(10 * textScale, scale: 1, element: element)
        let hasTopRow = element.customization.showsLabel || element.customization.showsIcon
        let topRowHeight = hasTopRow ? max(labelFontSize, iconFontSize) : 0
        let valueRowHeight = max(valueFontSize, element.customization.showsUnit ? unitFontSize : 0)
        let topPadding = 8 * scale
        let bottomPadding = 12 * scale
        let rowGap = hasTopRow ? max(6 * scale, valueFontSize * 0.18) : 0
        let desiredHeight = max(baseHeight, topPadding + topRowHeight + rowGap + valueRowHeight + bottomPadding)

        let text = metricText(for: element)
        let valueWidth = textWidth(text.value, size: valueFontSize, fontName: element.customization.valueFont)
        let unitWidth = element.customization.showsUnit ? textWidth(text.unit, size: unitFontSize, fontName: element.customization.unitFont) : 0
        let unitGap = element.customization.showsUnit ? 10 * scale : 0
        let labelWidth = element.customization.showsLabel ? textWidth(text.label, size: labelFontSize, fontName: element.customization.labelFont) : 0
        let iconWidth = element.customization.showsIcon ? textWidth(text.icon, size: iconFontSize, fontName: element.customization.iconFont) : 0
        let iconGap = element.customization.showsIcon ? 12 * scale : 0
        let desiredWidth = max(
            alignedMetricOutputWidth() ?? 0,
            baseWidth,
            24 * scale + valueWidth + unitGap + unitWidth + 12 * scale,
            24 * scale + labelWidth + iconGap + iconWidth + 12 * scale
        )
        return CGSize(width: desiredWidth, height: desiredHeight)
    }

    private func alignedMetricOutputWidth() -> CGFloat? {
        let widths = model.layout.visibleElements.compactMap { element -> CGFloat? in
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
        let iconFontSize = iconSize(10 * textScale, scale: 1, element: element)
        let text = metricText(for: element)
        let valueWidth = textWidth(text.value, size: valueFontSize, fontName: element.customization.valueFont)
        let unitWidth = element.customization.showsUnit ? textWidth(text.unit, size: unitFontSize, fontName: element.customization.unitFont) : 0
        let unitGap = element.customization.showsUnit ? 10 * scale : 0
        let labelWidth = element.customization.showsLabel ? textWidth(text.label, size: labelFontSize, fontName: element.customization.labelFont) : 0
        let iconWidth = element.customization.showsIcon ? textWidth(text.icon, size: iconFontSize, fontName: element.customization.iconFont) : 0
        let iconGap = element.customization.showsIcon ? 12 * scale : 0
        return max(
            baseWidth,
            24 * scale + valueWidth + unitGap + unitWidth + 12 * scale,
            24 * scale + labelWidth + iconGap + iconWidth + 12 * scale
        )
    }

    private func isMetricElement(_ element: OverlayElement) -> Bool {
        switch element.kind {
        case .pace, .distance, .heartRate, .cadence:
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
        return (
            element.customization.label(default: "TIME"),
            formatClockDuration(sample.elapsed),
            formatClockTime(sample.date),
            formatCalendarDate(sample.date),
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

    private func dragRenderSize(for displaySize: CGSize) -> CGSize {
        let maximumDimension: CGFloat = 2200
        let longestSide = max(displaySize.width, displaySize.height)
        guard longestSide > maximumDimension else { return displaySize }
        let scale = maximumDimension / longestSide
        return CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
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

    private func clampedZoom(_ value: Double) -> Double {
        PreviewZoomLimits.clamp(value)
    }

    private func setZoom(_ value: Double) {
        zoom = clampedZoom(value)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
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

    private func formatPace(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond, metersPerSecond > 0.3 else { return "--:--" }
        let secondsPerKm = Int((1000 / metersPerSecond).rounded())
        return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
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

struct PlaceholderView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.76))
            VStack(spacing: 10) {
                Image(systemName: "film")
                    .font(.system(size: 42))
                Text("Choose a video and FIT file")
                    .font(.title3.weight(.semibold))
                Text("The overlay can be dragged and resized after preview loads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
