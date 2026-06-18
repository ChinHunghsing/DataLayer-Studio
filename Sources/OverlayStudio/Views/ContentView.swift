import OverlayCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: StudioModel
    @SceneStorage("previewZoom") private var previewZoom = 1.0
    @State private var isPreviewFullscreen = false

    var body: some View {
        Group {
            if isPreviewFullscreen {
                fullscreenPreview
            } else {
                editorLayout
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.refreshPreview()
                } label: {
                    Label("Refresh Preview", systemImage: "arrow.clockwise")
                }
                .disabled(model.isExporting)

                Button {
                    model.markSportStart()
                } label: {
                    Label("运动开始", systemImage: "figure.run.circle")
                }
                .disabled(model.player == nil || model.isExporting)

                Button {
                    model.chooseOutput()
                } label: {
                    Label("Output", systemImage: "square.and.arrow.down")
                }
                .disabled(model.isExporting)

                Button {
                    if model.isExporting {
                        model.cancelExport()
                    } else {
                        model.export()
                    }
                } label: {
                    Label(model.isExporting ? "Cancel Export" : "Export", systemImage: model.isExporting ? "xmark.circle.fill" : "play.fill")
                }
                .disabled(!model.isExporting && !model.canExport)
                .help(model.isExporting ? "Cancel export" : (model.exportReadinessMessage ?? "Export transparent overlay video"))
            }
        }
        .toolbar(isPreviewFullscreen ? .hidden : .automatic, for: .windowToolbar)
        .onChange(of: previewInvalidationState) { _ in model.refreshOverlayOrPreview() }
        .onDisappear {
            model.shutdown()
        }
        .focusedSceneValue(\.studioCommandActions, studioCommandActions)
        .focusedSceneValue(\.previewCommandActions, previewCommandActions)
    }

    private var editorLayout: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 380)
                .background(.bar)

            Divider()

            PreviewCanvasView(
                model: model,
                zoom: $previewZoom,
                isFullscreen: false,
                onToggleFullscreen: { isPreviewFullscreen = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            InspectorView(model: model)
                .frame(width: 390)
                .background(.bar)
        }
    }

    private var fullscreenPreview: some View {
        PreviewCanvasView(
            model: model,
            zoom: $previewZoom,
            isFullscreen: true,
            onToggleFullscreen: { isPreviewFullscreen = false }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .onExitCommand {
            isPreviewFullscreen = false
        }
    }

    private var studioCommandActions: StudioCommandActions {
        StudioCommandActions(
            isExporting: model.isExporting,
            canExport: model.canExport,
            canPlayPreview: model.player != nil && !model.isExporting,
            isPlayingPreview: model.isPlaying,
            canMarkSportStart: model.player != nil && !model.isExporting,
            canMoveSelectionForward: canMoveSelectedElementForward,
            canMoveSelectionBackward: canMoveSelectedElementBackward,
            chooseVideo: model.chooseVideo,
            chooseFIT: model.chooseFIT,
            export: model.export,
            cancelExport: model.cancelExport,
            refreshPreview: model.refreshOverlayOrPreview,
            togglePlayback: model.togglePlayback,
            markSportStart: model.markSportStart,
            moveSelectionForward: model.moveSelectedElementForward,
            moveSelectionBackward: model.moveSelectedElementBackward
        )
    }

    private var previewCommandActions: PreviewCommandActions {
        PreviewCommandActions(
            isFullscreen: isPreviewFullscreen,
            zoomIn: { setPreviewZoom(previewZoom * 1.2) },
            zoomOut: { setPreviewZoom(previewZoom / 1.2) },
            resetZoom: { setPreviewZoom(1) },
            toggleFullscreen: { isPreviewFullscreen.toggle() }
        )
    }

    private var previewInvalidationState: PreviewInvalidationState {
        PreviewInvalidationState(
            outputWidth: model.outputWidth,
            outputHeight: model.outputHeight,
            syncMode: model.syncMode,
            offsetSeconds: model.offsetSeconds,
            fitStartSeconds: model.fitStartSeconds,
            syncVideoSeconds: model.syncVideoSeconds,
            syncFITSeconds: model.syncFITSeconds,
            distanceUnit: model.distanceUnit
        )
    }

    private func setPreviewZoom(_ value: Double) {
        previewZoom = PreviewZoomLimits.clamp(value)
    }

    private var selectedElementIndex: Int? {
        guard let selectedElementID = model.selectedElementID else { return nil }
        return model.layout.elements.firstIndex { $0.id == selectedElementID }
    }

    private var canMoveSelectedElementForward: Bool {
        guard !model.isExporting, let selectedElementIndex else { return false }
        return selectedElementIndex < model.layout.elements.count - 1
    }

    private var canMoveSelectedElementBackward: Bool {
        guard !model.isExporting, let selectedElementIndex else { return false }
        return selectedElementIndex > 0
    }
}

private struct PreviewInvalidationState: Equatable {
    var outputWidth: Int
    var outputHeight: Int
    var syncMode: SyncMode
    var offsetSeconds: Double
    var fitStartSeconds: Double
    var syncVideoSeconds: Double
    var syncFITSeconds: Double
    var distanceUnit: OverlayDistanceUnit
}
