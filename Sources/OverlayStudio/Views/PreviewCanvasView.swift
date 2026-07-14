import AppKit
import AVFoundation
import SwiftUI
import OverlayCore
import OverlayStudioKit
import UniformTypeIdentifiers

struct PreviewCanvasView: View {
    static let componentDragMinimumDistance: CGFloat = 1
    /// Pixel radius inside which smart guides magnetically capture a dragged element.
    static let alignmentSnapRadius: CGFloat = 6

    let model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @Binding private var zoom: Double
    let isFullscreen: Bool
    let onToggleFullscreen: () -> Void
    @State private var activeDrag: ComponentDragState?
    @State private var activeAlignmentGuides: [CanvasAlignmentGuide] = []
    @State private var marquee: MarqueeState?
    @State private var magnificationStartZoom: Double?
    @FocusState private var focusedElementID: String?

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
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
            let visibleElements = state.layout.visibleElements
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
            let computedContentSize = CGSize(
                width: max(viewportSize.width, displayRect.maxX + overflowInsets.right + stageInsets.trailing),
                height: max(viewportSize.height, displayRect.maxY + overflowInsets.bottom + stageInsets.bottom)
            )

            ScrollView([.horizontal, .vertical]) {
                previewCanvas(
                    displayRect: displayRect,
                    contentSize: computedContentSize,
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
                Image(decorative: background, scale: 1, orientation: .up)
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

            if let overlay = state.overlayImage {
                overlayImage(overlay, displayRect: displayRect)
            }

            if state.showGrid {
                PreviewGridOverlay(columns: PreviewGridOverlay.defaultColumns, rows: PreviewGridOverlay.defaultRows)
                    .stroke(Color.white.opacity(0.34), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
                    .allowsHitTesting(false)
            }

            ForEach(activeAlignmentGuides, id: \.self) { guide in
                alignmentGuideLine(guide, displayRect: displayRect)
            }

            if let marquee {
                let rect = marquee.rect
                Rectangle()
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(Rectangle().stroke(Color.accentColor.opacity(0.8), lineWidth: 1))
                    .frame(width: max(1, rect.width), height: max(1, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            ForEach(visibleElements) { element in
                componentHandle(
                    element: element,
                    displayRect: displayRect,
                    visibleElements: visibleElements,
                    alignedMetricWidth: alignedMetricWidth,
                    state: state
                )
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .coordinateSpace(name: "previewCanvas")
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], isTargeted: nil) { providers, location in
            handleComponentDrop(providers, at: location, displayRect: displayRect)
        }
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
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("previewCanvas"))
                .onChanged { value in
                    if marquee == nil {
                        // Only start a marquee from empty canvas; element drags own their rects.
                        guard hitTestElement(
                            at: value.startLocation,
                            displayRect: displayRect,
                            visibleElements: visibleElements,
                            alignedMetricWidth: alignedMetricWidth
                        ) == nil else { return }
                        marquee = MarqueeState(start: value.startLocation, current: value.location)
                    } else {
                        marquee?.current = value.location
                    }
                    guard let marquee else { return }
                    let selectedIDs = visibleElements
                        .filter { element in
                            componentDisplayRect(
                                element: element,
                                displayRect: displayRect,
                                alignedMetricWidth: alignedMetricWidth
                            ).intersects(marquee.rect)
                        }
                        .map(\.id)
                    model.setElementSelection(Set(selectedIDs))
                }
                .onEnded { _ in
                    marquee = nil
                }
        )
        .onExitCommand {
            model.escapeCanvasSelection()
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onChange(of: focusedElementID) { elementID in
            if let elementID {
                selectElement(elementID)
            }
        }
        .onDisappear {
            activeDrag = nil
            activeAlignmentGuides = []
            model.endGaugeDragInteraction()
        }
    }

    private func componentHandle(
        element: OverlayElement,
        displayRect: CGRect,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?,
        state: PreviewCanvasState
    ) -> some View {
        let rect = componentDisplayRect(element: element, displayRect: displayRect, alignedMetricWidth: alignedMetricWidth)
        let isSelected = state.selectedElementIDs.contains(element.id) || state.selectedElementID == element.id

        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .focusable()
            .focused($focusedElementID, equals: element.id)
            .previewFocusEffectHidden()
            .onMoveCommand { direction in
                nudgeElement(element.id, direction: direction)
            }
            .onExitCommand {
                model.escapeCanvasSelection()
            }
            .onTapGesture {
                handleElementTap(element.id)
            }
            .contextMenu {
                elementContextMenu(element: element)
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
                            translation: value.translation,
                            visibleElements: visibleElements,
                            alignedMetricWidth: alignedMetricWidth
                        )
                    }
                    .onEnded { _ in
                        activeDrag = nil
                        activeAlignmentGuides = []
                        model.endGaugeDragInteraction()
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

    private func handleComponentDrop(
        _ providers: [NSItemProvider],
        at location: CGPoint,
        displayRect: CGRect
    ) -> Bool {
        guard displayRect.contains(location),
              let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        let outputWidth = model.outputWidth
        let outputHeight = model.outputHeight
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let rawValue = value as? String,
                  let component = ComponentDragPayload.component(from: rawValue) else { return }
            let baseSize = ComponentBaseSize.size(for: component)
            let position = CGPoint(
                x: (location.x - displayRect.minX) / max(1, displayRect.width)
                    - baseSize.width / CGFloat(max(1, outputWidth)) / 2,
                y: (location.y - displayRect.minY) / max(1, displayRect.height)
                    - baseSize.height / CGFloat(max(1, outputHeight)) / 2
            )
            Task { @MainActor in
                model.addElement(kind: component, atNormalizedPosition: position)
            }
        }
        return true
    }

    private func selectElement(_ id: String) {
        model.selectElement(id: id)
    }

    private func handleElementTap(_ id: String) {
        if NSEvent.modifierFlags.contains(.shift) {
            model.toggleElementInSelection(id: id)
        } else {
            selectElement(id)
        }
    }

    /// Runs a context-menu action against the clicked element: if it is already part of the
    /// selection the action applies to the whole selection, otherwise it becomes the selection.
    private func withElementSelected(_ id: String, _ action: () -> Void) {
        if !model.isElementSelected(id: id) {
            selectElement(id)
        }
        action()
    }

    @ViewBuilder
    private func elementContextMenu(element: OverlayElement) -> some View {
        Button(localization.string("menu.copyStyle")) {
            model.copyElementStyle(id: element.id)
        }
        Button(localization.string("menu.pasteStyle")) {
            withElementSelected(element.id) {
                model.pasteCopiedElementStyle()
            }
        }
        .disabled(!model.canPasteElementStyle && !model.isElementSelected(id: element.id))

        Divider()

        Menu(localization.string("menu.align")) {
            Button(localization.string("menu.alignLeft")) {
                withElementSelected(element.id) { model.alignSelectedElements(.left) }
            }
            Button(localization.string("menu.alignHorizontalCenter")) {
                withElementSelected(element.id) { model.alignSelectedElements(.horizontalCenter) }
            }
            Button(localization.string("menu.alignRight")) {
                withElementSelected(element.id) { model.alignSelectedElements(.right) }
            }
            Divider()
            Button(localization.string("menu.alignTop")) {
                withElementSelected(element.id) { model.alignSelectedElements(.top) }
            }
            Button(localization.string("menu.alignVerticalCenter")) {
                withElementSelected(element.id) { model.alignSelectedElements(.verticalCenter) }
            }
            Button(localization.string("menu.alignBottom")) {
                withElementSelected(element.id) { model.alignSelectedElements(.bottom) }
            }
            Divider()
            Button(localization.string("menu.distributeHorizontally")) {
                withElementSelected(element.id) { model.distributeSelectedElements(.horizontal) }
            }
            .disabled(!model.canDistributeSelectedElements)
            Button(localization.string("menu.distributeVertically")) {
                withElementSelected(element.id) { model.distributeSelectedElements(.vertical) }
            }
            .disabled(!model.canDistributeSelectedElements)
        }
        .disabled(!model.canAlignSelectedElements)

        Divider()

        Button(localization.string("menu.bringToFront")) {
            withElementSelected(element.id) { model.bringSelectedElementToFront() }
        }
        Button(localization.string("menu.bringForward")) {
            withElementSelected(element.id) { model.moveSelectedElementForward() }
        }
        Button(localization.string("menu.sendBackward")) {
            withElementSelected(element.id) { model.moveSelectedElementBackward() }
        }
        Button(localization.string("menu.sendToBack")) {
            withElementSelected(element.id) { model.sendSelectedElementToBack() }
        }

        Divider()

        Button(localization.string("menu.deleteElement"), role: .destructive) {
            withElementSelected(element.id) { model.deleteSelectedElement() }
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
        if NSEvent.modifierFlags.contains(.shift) {
            model.toggleElementInSelection(id: element.id)
            return
        }
        let unitPoint = CGPoint(
            x: (location.x - displayRect.minX) / max(1, displayRect.width),
            y: (location.y - displayRect.minY) / max(1, displayRect.height)
        )
        let part = geometry.part(at: unitPoint, element: element, alignedMetricWidth: alignedMetricWidth)
        model.handleCanvasElementTap(id: element.id, part: part)
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
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) {
        guard !model.isExporting else { return }
        model.beginGaugeDragInteraction()

        var dragState = activeDrag
        if activeDrag?.id != id, let element = model.layout.elements.first(where: { $0.id == id }) {
            // Dragging an element that is already part of a multi-selection moves the group;
            // selecting it here would collapse that selection.
            if !model.isElementSelected(id: id) {
                selectElement(id)
            }
            var groupStartPositions: [String: (x: Double, y: Double)] = [:]
            if model.selectedElementIDs.count > 1, model.isElementSelected(id: id) {
                for other in model.layout.elements
                where other.id != id && model.selectedElementIDs.contains(other.id) {
                    groupStartPositions[other.id] = (other.frame.x, other.frame.y)
                }
            }
            let initialDragState = ComponentDragState(
                id: id,
                startX: element.frame.x,
                startY: element.frame.y,
                currentX: element.frame.x,
                currentY: element.frame.y,
                groupStartPositions: groupStartPositions
            )
            dragState = initialDragState
            self.activeDrag = initialDragState
        }
        guard var activeDrag = dragState else { return }

        let deltaX = Double(translation.width / max(1, displayRect.width))
        let deltaY = Double(translation.height / max(1, displayRect.height))
        var nextX = activeDrag.startX + deltaX
        var nextY = activeDrag.startY + deltaY
        let alignment = alignmentSolution(
            forElementID: id,
            proposedX: nextX,
            proposedY: nextY,
            displayRect: displayRect,
            visibleElements: visibleElements,
            alignedMetricWidth: alignedMetricWidth
        )
        nextX += Double(alignment.offset.dx)
        nextY += Double(alignment.offset.dy)
        if activeAlignmentGuides != alignment.guides {
            activeAlignmentGuides = alignment.guides
        }
        nextX = PreviewLayoutLimits.clampPosition(nextX)
        nextY = PreviewLayoutLimits.clampPosition(nextY)
        let pixelDeltaX = (nextX - activeDrag.currentX) * Double(displayRect.width)
        let pixelDeltaY = (nextY - activeDrag.currentY) * Double(displayRect.height)
        guard abs(pixelDeltaX) >= 0.25 || abs(pixelDeltaY) >= 0.25 else { return }
        activeDrag.currentX = nextX
        activeDrag.currentY = nextY
        self.activeDrag = activeDrag
        if activeDrag.groupStartPositions.isEmpty {
            model.updateElement(activeDrag.id, refreshPreview: false) { element in
                element.frame.x = nextX
                element.frame.y = nextY
            }
        } else {
            let groupDeltaX = nextX - activeDrag.startX
            let groupDeltaY = nextY - activeDrag.startY
            var positions: [String: (x: Double, y: Double)] = [activeDrag.id: (nextX, nextY)]
            for (otherID, start) in activeDrag.groupStartPositions {
                positions[otherID] = (
                    PreviewLayoutLimits.clampPosition(start.x + groupDeltaX),
                    PreviewLayoutLimits.clampPosition(start.y + groupDeltaY)
                )
            }
            model.setElementPositions(positions, refreshPreview: false)
        }
        model.refreshOverlayOnly(coalesceIfBusy: true, displayIntermediateResults: true)
    }

    private func nudgeElement(_ id: String, direction: MoveCommandDirection) {
        let stepX = 1.0 / Double(max(1, model.outputWidth))
        let stepY = 1.0 / Double(max(1, model.outputHeight))
        switch direction {
        case .left:
            model.nudgeElement(id, deltaX: -stepX, deltaY: 0)
        case .right:
            model.nudgeElement(id, deltaX: stepX, deltaY: 0)
        case .up:
            model.nudgeElement(id, deltaX: 0, deltaY: -stepY)
        case .down:
            model.nudgeElement(id, deltaX: 0, deltaY: stepY)
        @unknown default:
            break
        }
    }

    private func alignmentSolution(
        forElementID id: String,
        proposedX: Double,
        proposedY: Double,
        displayRect: CGRect,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) -> CanvasAlignmentSolution {
        guard let element = model.layout.elements.first(where: { $0.id == id }) else {
            return CanvasAlignmentSolution()
        }
        let currentRect = componentUnitRect(element: element, alignedMetricWidth: alignedMetricWidth)
        let movingRect = currentRect.offsetBy(
            dx: CGFloat(proposedX - element.frame.x),
            dy: CGFloat(proposedY - element.frame.y)
        )
        // A group drag must not snap against elements that move along with the pointer.
        let excludedIDs: Set<String> = model.isElementSelected(id: id) && model.selectedElementIDs.count > 1
            ? model.selectedElementIDs.union([id])
            : [id]
        let neighborRects = visibleElements
            .filter { !excludedIDs.contains($0.id) }
            .map { componentUnitRect(element: $0, alignedMetricWidth: alignedMetricWidth) }
        return CanvasAlignmentSolver.solve(
            movingRect: movingRect,
            neighborRects: neighborRects,
            configuration: CanvasAlignmentSolver.Configuration(
                tolerance: CGSize(
                    width: Self.alignmentSnapRadius / max(1, displayRect.width),
                    height: Self.alignmentSnapRadius / max(1, displayRect.height)
                ),
                safeAreaInset: CGFloat(model.canvasSafeAreaInsetPercent) / 100
            )
        )
    }

    private func alignmentGuideLine(_ guide: CanvasAlignmentGuide, displayRect: CGRect) -> some View {
        let lineColor = Color.yellow.opacity(0.9)
        return Group {
            switch guide.axis {
            case .vertical:
                Rectangle()
                    .fill(lineColor)
                    .frame(width: 1, height: displayRect.height)
                    .position(
                        x: displayRect.minX + displayRect.width * guide.position,
                        y: displayRect.midY
                    )
            case .horizontal:
                Rectangle()
                    .fill(lineColor)
                    .frame(width: displayRect.width, height: 1)
                    .position(
                        x: displayRect.midX,
                        y: displayRect.minY + displayRect.height * guide.position
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func componentHitRect(element: OverlayElement, displayRect: CGRect, alignedMetricWidth: CGFloat?) -> CGRect {
        componentDisplayRect(element: element, displayRect: displayRect, alignedMetricWidth: alignedMetricWidth)
            .insetBy(dx: -8, dy: -8)
    }

    private var geometry: CanvasElementGeometry {
        CanvasElementGeometry(model: model)
    }

    private func componentUnitRect(element: OverlayElement, alignedMetricWidth: CGFloat?) -> CGRect {
        geometry.unitRect(element: element, alignedMetricWidth: alignedMetricWidth)
    }

    private func alignedMetricOutputWidth(for visibleElements: [OverlayElement]) -> CGFloat? {
        geometry.alignedMetricOutputWidth(for: visibleElements)
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

    private func layoutOverflowInsets(
        canvasSize: CGSize,
        visibleElements: [OverlayElement],
        alignedMetricWidth: CGFloat?
    ) -> CanvasOverflowInsets {
        var insets = CanvasOverflowInsets()
        let hitPadding: CGFloat = 18

        // Only elements that actually extend past the canvas grow the scrollable content
        // (plus padding so their drag handles stay reachable). Elements merely near an edge
        // must not create scroll bars when nothing is clipped.
        for element in visibleElements {
            let rect = componentUnitRect(element: element, alignedMetricWidth: alignedMetricWidth)
            if rect.minX < 0 {
                insets.left = max(insets.left, -rect.minX * canvasSize.width + hitPadding)
            }
            if rect.maxX > 1 {
                insets.right = max(insets.right, (rect.maxX - 1) * canvasSize.width + hitPadding)
            }
            if rect.minY < 0 {
                insets.top = max(insets.top, -rect.minY * canvasSize.height + hitPadding)
            }
            if rect.maxY > 1 {
                insets.bottom = max(insets.bottom, (rect.maxY - 1) * canvasSize.height + hitPadding)
            }
        }

        return insets.roundedUp
    }

    private func previewOverlayRenderSize(for displaySize: CGSize) -> CGSize {
        let maximumDimension: CGFloat = 3200
        let longestSide = max(displaySize.width, displaySize.height)
        guard longestSide > maximumDimension else { return displaySize }
        let scale = maximumDimension / longestSide
        return CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
    }

    private func overlayImage(_ image: CGImage, displayRect: CGRect) -> some View {
        Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .frame(width: displayRect.width, height: displayRect.height)
            .position(x: displayRect.midX, y: displayRect.midY)
            .allowsHitTesting(false)
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

}

enum PreviewZoomLimits {
    static let range: ClosedRange<Double> = 0.25...4.0

    static func clamp(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : 1))
    }
}

struct PreviewCanvasState: Equatable {
    var player: AVPlayer?
    var backgroundImage: CGImage?
    var overlayImage: CGImage?
    var layout: OverlayLayout
    var selectedElementID: String?
    var selectedElementIDs: Set<String>
    var showGrid: Bool
    var hasSeries: Bool
    var outputWidth: Int
    var outputHeight: Int

    @MainActor
    init(model: StudioModel) {
        player = model.player
        backgroundImage = model.backgroundImage
        overlayImage = model.overlayImage
        layout = model.layout
        selectedElementID = model.selectedElementID
        selectedElementIDs = model.selectedElementIDs
        showGrid = model.showGrid
        hasSeries = model.series != nil || model.usesCustomTimelinePreview
        outputWidth = model.outputWidth
        outputHeight = model.outputHeight
    }

    static func == (lhs: PreviewCanvasState, rhs: PreviewCanvasState) -> Bool {
        lhs.player === rhs.player
            && lhs.backgroundImage === rhs.backgroundImage
            && lhs.overlayImage === rhs.overlayImage
            && lhs.layout == rhs.layout
            && lhs.selectedElementID == rhs.selectedElementID
            && lhs.selectedElementIDs == rhs.selectedElementIDs
            && lhs.showGrid == rhs.showGrid
            && lhs.hasSeries == rhs.hasSeries
            && lhs.outputWidth == rhs.outputWidth
            && lhs.outputHeight == rhs.outputHeight
    }
}

private struct ComponentDragState {
    let id: String
    let startX: Double
    let startY: Double
    var currentX: Double
    var currentY: Double
    /// Start positions of the other selected elements when dragging a multi-selection.
    var groupStartPositions: [String: (x: Double, y: Double)] = [:]
}

private struct MarqueeState {
    let start: CGPoint
    var current: CGPoint

    var rect: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
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

private extension View {
    @ViewBuilder
    func previewFocusEffectHidden() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}

private struct PreviewGridOverlay: Shape {
    // The grid is a fixed visual aid now that snapping goes through smart guides.
    static let defaultColumns = 12
    static let defaultRows = 8

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
            .fill(.black)
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
