import SwiftUI
import OverlayCore

struct PreviewCanvasView: View {
    @ObservedObject var model: StudioModel
    @State private var activeDrag: ComponentDragState?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let displayRect = aspectFitRect(
                    container: CGRect(origin: .zero, size: proxy.size),
                    aspectRatio: CGFloat(model.outputWidth) / CGFloat(max(1, model.outputHeight))
                )

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

                    if let overlay = model.overlayImage {
                        Image(nsImage: overlay)
                            .resizable()
                            .frame(width: displayRect.width, height: displayRect.height)
                            .position(x: displayRect.midX, y: displayRect.midY)
                            .allowsHitTesting(false)
                    }

                    if let dragOverlay = model.dragOverlayImage, let activeDrag {
                        Image(nsImage: dragOverlay)
                            .resizable()
                            .frame(width: displayRect.width, height: displayRect.height)
                            .position(x: displayRect.midX, y: displayRect.midY)
                            .offset(activeDrag.translation)
                            .allowsHitTesting(false)
                    }

                    if model.showGrid {
                        PreviewGridOverlay(columns: model.gridColumns, rows: model.gridRows)
                            .stroke(Color.white.opacity(0.34), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .frame(width: displayRect.width, height: displayRect.height)
                            .position(x: displayRect.midX, y: displayRect.midY)
                            .allowsHitTesting(false)
                    }

                    ForEach(model.layout.visibleElements) { element in
                        componentHandle(element: element, displayRect: displayRect)
                    }
                }
                .coordinateSpace(name: "previewCanvas")
                .contentShape(Rectangle())
                .highPriorityGesture(
                    SpatialTapGesture(coordinateSpace: .named("previewCanvas"))
                        .onEnded { value in
                            selectElement(at: value.location, displayRect: displayRect)
                        }
                )
            }

            VStack(spacing: 8) {
                HStack {
                    Button {
                        model.togglePlayback()
                    } label: {
                        Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .disabled(model.player == nil)

                    Slider(
                        value: Binding(
                            get: { model.previewTime },
                            set: { model.seekPreview(to: $0) }
                        ),
                        in: 0...max(model.outputDuration, 1)
                    )

                    Button {
                        model.markSportStart()
                    } label: {
                        Label("运动开始", systemImage: "figure.run.circle")
                    }
                    .disabled(model.player == nil)
                }

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
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func componentHandle(element: OverlayElement, displayRect: CGRect) -> some View {
        let rect = componentDisplayRect(element: element, displayRect: displayRect)
        let isSelected = model.selectedElementID == element.id

        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .overlay {
                if element.customization.showsPanel {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.45), lineWidth: isSelected ? 2 : 1)
                }
            }
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
                        activeDrag = nil
                        model.endElementDrag()
                    }
            )
            .zIndex(isSelected ? 10 : 1)
            .accessibilityLabel(Text(element.kind.title))
    }

    private func selectElement(_ id: String) {
        if model.selectedElementID != id {
            model.selectedElementID = id
        }
    }

    private func selectElement(at location: CGPoint, displayRect: CGRect) {
        guard displayRect.contains(location) else { return }
        guard let element = hitTestElement(at: location, displayRect: displayRect) else { return }
        selectElement(element.id)
    }

    private func hitTestElement(at location: CGPoint, displayRect: CGRect) -> OverlayElement? {
        model.layout.visibleElements
            .reversed()
            .first { element in
                componentHitRect(element: element, displayRect: displayRect).contains(location)
            }
    }

    private func moveElement(_ id: String, displayRect: CGRect, translation: CGSize) {
        selectElement(id)

        if activeDrag?.id != id, let element = model.layout.elements.first(where: { $0.id == id }) {
            activeDrag = ComponentDragState(id: id, startX: element.frame.x, startY: element.frame.y, translation: .zero)
            model.beginElementDrag(id: id, previewSize: displayRect.size)
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
        self.activeDrag = activeDrag

        model.updateElement(id, refreshPreview: false) { element in
            element.frame.x = nextX
            element.frame.y = nextY
        }
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
        let frame = element.frame
        let base = ComponentBaseSize.size(for: element.kind)
        let scale = rendererLayoutScale() * CGFloat(frame.scale)
        let width = displayRect.width * base.width * scale * CGFloat(max(0.1, element.customization.lengthScale)) / CGFloat(max(1, model.outputWidth))
        let height = displayRect.height * base.height * scale / CGFloat(max(1, model.outputHeight))
        return CGRect(
            x: displayRect.minX + displayRect.width * CGFloat(frame.x),
            y: displayRect.minY + displayRect.height * CGFloat(frame.y),
            width: width,
            height: height
        )
    }

    private func rendererLayoutScale() -> CGFloat {
        max(0.28, min(CGFloat(model.outputWidth) / 1920, CGFloat(model.outputHeight) / 1080))
    }

    private func aspectFitRect(container: CGRect, aspectRatio: CGFloat) -> CGRect {
        let containerAspect = container.width / max(1, container.height)
        if containerAspect > aspectRatio {
            let width = container.height * aspectRatio
            return CGRect(x: container.midX - width / 2, y: container.minY, width: width, height: container.height)
        }
        let height = container.width / max(0.1, aspectRatio)
        return CGRect(x: container.minX, y: container.midY - height / 2, width: container.width, height: height)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ComponentDragState {
    let id: String
    let startX: Double
    let startY: Double
    var translation: CGSize
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
