#if os(iOS)
import CoreGraphics
import OverlayCore
import SwiftUI

/// 预览画布：视频背景 + 数据浮层 + 触控选中/拖动。
/// 命中区域用组件基础尺寸粗估（最小 44pt 热区），精确边界由浮层渲染呈现。
struct TouchCanvasView: View {
    @ObservedObject var model: TouchStudioModel
    let localizer: TouchLocalizer

    @Environment(\.displayScale) private var displayScale
    @State private var activeDrag: ComponentDragState?

    private struct ComponentDragState {
        var id: String
        var startX: Double
        var startY: Double
    }

    var body: some View {
        GeometryReader { proxy in
            let displayRect = aspectFitRect(container: proxy.size)

            ZStack {
                Color.black

                if model.videoURL != nil {
                    TouchPlayerSurface(player: model.player)
                        .frame(width: displayRect.width, height: displayRect.height)
                        .position(x: displayRect.midX, y: displayRect.midY)
                        .allowsHitTesting(false)
                }

                if let overlayImage = model.overlayImage {
                    Image(decorative: overlayImage, scale: 1, orientation: .up)
                        .resizable()
                        .frame(width: displayRect.width, height: displayRect.height)
                        .position(x: displayRect.midX, y: displayRect.midY)
                        .allowsHitTesting(false)
                }

                if model.series == nil, model.videoURL == nil {
                    emptyState
                }

                if model.series != nil {
                    componentHandles(displayRect: displayRect)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectElement(nil)
            }
            .onChange(of: displayRect.size, initial: true) { _, newSize in
                model.updatePreviewOverlayRenderSize(
                    CGSize(width: newSize.width * displayScale, height: newSize.height * displayScale)
                )
            }
        }
        .clipped()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.3.layers.3d.down.right")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(localizer.string("canvas.emptyTitle"))
                .font(.title3.weight(.semibold))
            Text(localizer.string("canvas.emptyMessage"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(24)
    }

    private func componentHandles(displayRect: CGRect) -> some View {
        ForEach(model.layout.elements.filter { $0.frame.isVisible }) { element in
            componentHandle(element: element, displayRect: displayRect)
        }
    }

    private func componentHandle(element: OverlayElement, displayRect: CGRect) -> some View {
        let rect = componentDisplayRect(element: element, displayRect: displayRect)
        let hitWidth = max(44, rect.width)
        let hitHeight = max(44, rect.height)
        let isSelected = model.selectedElementID == element.id

        return Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: hitWidth, height: hitHeight)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: max(24, rect.width), height: max(24, rect.height))
                }
            }
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectElement(element.id)
            }
            .gesture(dragGesture(element: element, displayRect: displayRect))
            .zIndex(isSelected ? 10 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(localizer.string(element.kind.localizationKey)))
            .accessibilityAddTraits(.isButton)
    }

    private func dragGesture(element: OverlayElement, displayRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !model.isExporting else { return }
                model.beginDragInteraction()

                if activeDrag?.id != element.id {
                    model.selectElement(element.id)
                    guard let current = model.layout.elements.first(where: { $0.id == element.id }) else { return }
                    activeDrag = ComponentDragState(id: element.id, startX: current.frame.x, startY: current.frame.y)
                }
                guard let drag = activeDrag else { return }

                let nextX = TouchLayoutLimits.clampPosition(drag.startX + Double(value.translation.width / max(1, displayRect.width)))
                let nextY = TouchLayoutLimits.clampPosition(drag.startY + Double(value.translation.height / max(1, displayRect.height)))
                model.updateElement(drag.id, recordUndo: false) { element in
                    element.frame.x = nextX
                    element.frame.y = nextY
                }
            }
            .onEnded { _ in
                activeDrag = nil
                model.endDragInteraction()
            }
    }

    private func componentDisplayRect(element: OverlayElement, displayRect: CGRect) -> CGRect {
        let base = TouchComponentBaseSize.size(for: element.kind)
        let rendererScale = max(0.28, min(CGFloat(model.outputWidth) / 1920, CGFloat(model.outputHeight) / 1080))
        let scale = rendererScale * CGFloat(element.frame.scale)
        let widthScale = element.kind == .altitudeProfile
            ? CGFloat(element.customization.resolvedAltitudeWidthScale)
            : CGFloat(max(0.1, element.customization.lengthScale))
        let heightScale = element.kind == .altitudeProfile
            ? CGFloat(element.customization.resolvedAltitudeHeightScale)
            : 1
        let width = base.width * scale * widthScale
        let height = base.height * scale * heightScale
        let unitWidth = width / CGFloat(max(1, model.outputWidth))
        let unitHeight = height / CGFloat(max(1, model.outputHeight))
        return CGRect(
            x: displayRect.minX + displayRect.width * CGFloat(element.frame.x),
            y: displayRect.minY + displayRect.height * CGFloat(element.frame.y),
            width: displayRect.width * unitWidth,
            height: displayRect.height * unitHeight
        )
    }

    private func aspectFitRect(container: CGSize) -> CGRect {
        let aspect = CGFloat(model.outputWidth) / CGFloat(max(1, model.outputHeight))
        let containerAspect = container.width / max(1, container.height)
        let size: CGSize
        if containerAspect > aspect {
            size = CGSize(width: container.height * aspect, height: container.height)
        } else {
            size = CGSize(width: container.width, height: container.width / max(0.1, aspect))
        }
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// 时间轴：播放/暂停、帧步进、scrub 滑杆与时间显示。
struct TouchTimelineBar: View {
    @ObservedObject var model: TouchStudioModel
    let localizer: TouchLocalizer

    var body: some View {
        HStack(spacing: 14) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24)
            }
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(Text(localizer.string(model.isPlaying ? "timeline.pause" : "timeline.play")))
            .disabled(model.player == nil || model.isExporting)

            Button {
                model.stepPreviewFrame(by: -1)
            } label: {
                Image(systemName: "backward.frame.fill")
            }
            .accessibilityLabel(Text(localizer.string("timeline.stepBack")))
            .disabled(model.previewDuration <= 0 || model.isExporting)

            Button {
                model.stepPreviewFrame(by: 1)
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            .accessibilityLabel(Text(localizer.string("timeline.stepForward")))
            .disabled(model.previewDuration <= 0 || model.isExporting)

            Text(TouchStudioModel.formatSeconds(model.previewTime))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { model.previewTime },
                    set: { model.scrubPreview(to: $0) }
                ),
                in: sliderRange
            ) { editing in
                if editing {
                    model.pausePlayback()
                }
            }
            .disabled(model.previewDuration <= 0 || model.isExporting)

            Text(TouchStudioModel.formatSeconds(model.previewTimeRange.upperBound))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var sliderRange: ClosedRange<TimeInterval> {
        let range = model.previewTimeRange
        guard range.upperBound > range.lowerBound else { return 0...1 }
        return range
    }
}
#endif
