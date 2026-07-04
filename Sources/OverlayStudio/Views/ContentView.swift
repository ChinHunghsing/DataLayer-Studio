import OverlayCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @SceneStorage("previewZoom") private var previewZoom = 1.0
    @State private var isPreviewFullscreen = false
    @State private var isDebugConsolePresented = false
    @State private var isExportSheetPresented = false
    @State private var isCancelExportConfirmationPresented = false

    var body: some View {
        Group {
            if isPreviewFullscreen {
                fullscreenPreview
            } else {
                editorLayout
            }
        }
        .onChange(of: previewInvalidationState) { _ in model.refreshOverlayOrPreview() }
        .onAppear {
            model.setResolvedLanguage(localization.resolvedLanguage)
        }
        .onChange(of: localization.selection) { _ in
            model.setResolvedLanguage(localization.resolvedLanguage)
        }
        .onChange(of: model.isExporting) { isExporting in
            if isExporting {
                isExportSheetPresented = true
            }
        }
        .onChange(of: model.hasExportResult) { hasExportResult in
            if hasExportResult {
                isExportSheetPresented = true
            }
        }
        .onDisappear {
            model.shutdown()
        }
        .sheet(isPresented: $isDebugConsolePresented) {
            DebugConsoleView(model: model)
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
        }
        .sheet(isPresented: $isExportSheetPresented, onDismiss: clearDismissedExportResult) {
            ExportStatusSheet(
                model: model,
                isCancelExportConfirmationPresented: $isCancelExportConfirmationPresented
            )
            .environmentObject(localization)
            .environment(\.locale, localization.locale)
        }
        .focusedSceneValue(\.studioCommandActions, studioCommandActions)
        .focusedSceneValue(\.previewCommandActions, previewCommandActions)
    }

    private var editorLayout: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 330)
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
            debugLogCount: model.debugLogEntries.count,
            canMarkSportStart: model.player != nil && !model.isExporting,
            canMoveSelectionForward: canMoveSelectedElementForward,
            canMoveSelectionBackward: canMoveSelectedElementBackward,
            chooseVideo: model.chooseVideo,
            chooseFIT: model.chooseFIT,
            export: model.export,
            cancelExport: requestExportCancellation,
            refreshPreview: model.refreshOverlayOrPreview,
            togglePlayback: model.togglePlayback,
            markSportStart: model.markSportStart,
            moveSelectionForward: model.moveSelectedElementForward,
            moveSelectionBackward: model.moveSelectedElementBackward,
            showDebugConsole: { isDebugConsolePresented = true },
            copyDebugLog: model.copyDebugLog,
            clearDebugLog: model.clearDebugLog
        )
    }

    private func requestExportCancellation() {
        guard model.isExporting else { return }
        isExportSheetPresented = true
        isCancelExportConfirmationPresented = true
    }

    private func clearDismissedExportResult() {
        if !model.isExporting {
            model.clearExportResult()
        }
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

private struct ExportStatusSheet: View {
    @ObservedObject var model: StudioModel
    @Binding var isCancelExportConfirmationPresented: Bool
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.isExporting {
                exportingContent
            } else {
                resultContent
            }
        }
        .padding(24)
        .frame(width: 430, alignment: .leading)
        .interactiveDismissDisabled(model.isExporting)
        .alert(localization.string("exportDialog.cancelTitle"), isPresented: $isCancelExportConfirmationPresented) {
            Button(localization.string("exportDialog.confirmCancel"), role: .destructive) {
                model.cancelExport()
            }
            Button(localization.string("common.cancel"), role: .cancel) { }
        } message: {
            Text(localization.string("exportDialog.cancelMessage"))
        }
    }

    private var exportingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                localization.string(model.exportMode == .video ? "sidebar.exportingVideo" : "sidebar.exportingOverlay"),
                systemImage: "paperplane.fill"
            )
            .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: clampedExportProgress)

                HStack {
                    Text(clampedExportProgress.percentString)
                        .monospacedDigit()
                    Spacer()
                    if let etaSeconds = model.exportETASeconds {
                        Text(localization.string("sidebar.exportETA", formatDuration(etaSeconds)))
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(localization.string("sidebar.exportProgress"))
            .accessibilityValue(clampedExportProgress.percentString)

            Button(role: .destructive) {
                isCancelExportConfirmationPresented = true
            } label: {
                Label(localization.string("toolbar.cancelExport"), systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            resultHeader

            if let lastExportedURL = model.lastExportedURL {
                Text(lastExportedURL.lastPathComponent)
                    .font(.body)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } else if let errorMessage = model.lastExportErrorMessage {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if let elapsed = model.lastExportElapsedSeconds {
                Label(localization.string("exportDialog.elapsed", formatDuration(elapsed)), systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ViewThatFits {
                HStack(spacing: 8) {
                    resultButtons
                }
                VStack(spacing: 8) {
                    resultButtons
                }
            }
            .controlSize(.large)
        }
    }

    private var resultHeader: some View {
        Label(resultTitle, systemImage: resultSystemImage)
            .font(.headline)
            .foregroundStyle(resultColor)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var resultButtons: some View {
        if model.lastExportedURL != nil {
            Button {
                model.revealLastExportInFinder()
            } label: {
                Label(localization.string("sidebar.revealInFinder"), systemImage: "folder")
            }

            Button {
                model.openLastExport()
            } label: {
                Label(localization.string("exportDialog.openFile"), systemImage: "play.circle")
            }
        }

        Button {
            model.clearExportResult()
            dismiss()
        } label: {
            Label(localization.string("common.done"), systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
    }

    private var resultTitle: String {
        if model.lastExportedURL != nil {
            return localization.string("sidebar.exportDone")
        }
        if model.lastExportWasCancelled {
            return localization.string("exportDialog.cancelled")
        }
        return localization.string("exportDialog.failed")
    }

    private var resultSystemImage: String {
        if model.lastExportedURL != nil {
            return "checkmark.circle.fill"
        }
        if model.lastExportWasCancelled {
            return "xmark.circle.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    private var resultColor: Color {
        if model.lastExportedURL != nil {
            return .green
        }
        if model.lastExportWasCancelled {
            return .secondary
        }
        return .red
    }

    private var clampedExportProgress: Double {
        guard model.exportProgress.isFinite else { return 0 }
        return min(1, max(0, model.exportProgress))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
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
