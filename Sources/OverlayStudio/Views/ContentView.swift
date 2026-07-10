import AppKit
import OverlayCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @SceneStorage("previewZoom") private var previewZoom = 1.0
    @SceneStorage("bottomWorkspaceHeight") private var bottomWorkspaceHeight = 240.0
    @State private var resizeStartHeight: Double?
    @State private var isPreviewFullscreen = false
    @State private var isDebugConsolePresented = false
    @State private var isExportSheetPresented = false
    @State private var isCancelExportConfirmationPresented = false
    @State private var isStartupSourcePromptPresented = false
    @State private var didPresentStartupSourcePrompt = false
    @State private var suppressStartupSourcePrompt = false
    @State private var sourceContinuationPrompt: SourceContinuationPrompt?

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
            presentStartupSourcePromptIfNeeded()
        }
        .onChange(of: localization.selection) { _ in
            model.setResolvedLanguage(localization.resolvedLanguage)
        }
        .onChange(of: model.videoURL) { url in
            if url != nil { focusPreviewForPlayback() }
            guard url != nil, model.fitURL == nil else { return }
            sourceContinuationPrompt = .activityAfterVideo
        }
        .onChange(of: model.fitURL) { url in
            if url != nil { focusPreviewForPlayback() }
            guard url != nil, model.videoURL == nil else { return }
            sourceContinuationPrompt = .videoAfterActivity
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
        .sheet(isPresented: $isExportSheetPresented) {
            ExportStatusSheet(
                model: model,
                isCancelExportConfirmationPresented: $isCancelExportConfirmationPresented
            )
            .environmentObject(localization)
            .environment(\.locale, localization.locale)
        }
        .sheet(isPresented: $isStartupSourcePromptPresented) {
            StartupSourcePromptView(
                chooseVideo: { dismissStartupSourcePromptAndRun(model.chooseVideo) },
                chooseActivity: { dismissStartupSourcePromptAndRun(model.chooseFIT) }
            )
            .environmentObject(localization)
            .environment(\.locale, localization.locale)
        }
        .alert(
            sourceContinuationPrompt.map { localization.string($0.titleKey) } ?? "",
            isPresented: sourceContinuationPromptBinding
        ) {
            if let prompt = sourceContinuationPrompt {
                Button(localization.string(prompt.primaryActionKey)) {
                    continueSourceSelection(from: prompt)
                }

                Button(localization.string("sourceContinuation.later"), role: .cancel) { }
            }
        } message: {
            if let prompt = sourceContinuationPrompt {
                Text(localization.string(prompt.messageKey))
            }
        }
        .alert(
            model.pendingTimelineActionTitle,
            isPresented: pendingTimelineActionBinding
        ) {
            Button(model.pendingTimelineActionConfirmationTitle, role: .destructive) {
                model.confirmPendingTimelineAction()
            }
            Button(localization.string("common.cancel"), role: .cancel) {
                model.cancelPendingTimelineAction()
            }
        } message: {
            Text(model.pendingTimelineActionMessage)
        }
        .alert(
            localization.string("exportWeatherWarning.title"),
            isPresented: weatherExportConfirmationBinding
        ) {
            Button(localization.string("exportWeatherWarning.continue")) {
                model.confirmWeatherExport()
            }
            Button(localization.string("common.cancel"), role: .cancel) {
                model.cancelWeatherExportConfirmation()
            }
        } message: {
            Text(localization.string("exportWeatherWarning.message"))
        }
        .focusedSceneValue(\.studioCommandActions, studioCommandActions)
        .focusedSceneValue(\.previewCommandActions, previewCommandActions)
        .onOpenURL(perform: openActivityFile)
    }

    private var editorLayout: some View {
        VStack(spacing: 0) {
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
            .frame(maxHeight: .infinity)

            bottomResizeHandle

            // 参考 DaVinci：下半部分贯穿左右，两侧面板不够高时各自滚动，高度可拖拽
            BottomWorkspaceView(model: model)
                .frame(height: bottomWorkspaceHeight)
        }
    }

    private var bottomResizeHandle: some View {
        ZStack {
            Divider()
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 42, height: 4)
        }
        .frame(height: 11)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if resizeStartHeight == nil { resizeStartHeight = bottomWorkspaceHeight }
                    let base = resizeStartHeight ?? bottomWorkspaceHeight
                    bottomWorkspaceHeight = min(560, max(150, base - value.translation.height))
                }
                .onEnded { _ in resizeStartHeight = nil }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .accessibilityHidden(true)
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
            canPlayPreview: (model.player != nil || model.series != nil) && !model.isExporting,
            isPlayingPreview: model.isPlaying,
            debugLogCount: model.debugLogEntries.count,
            canMarkSportStart: model.player != nil && !model.isExporting,
            canMoveSelectionForward: canMoveSelectedElementForward,
            canMoveSelectionBackward: canMoveSelectedElementBackward,
            chooseVideo: model.chooseVideo,
            chooseFIT: model.chooseFIT,
            openTimelineProject: model.openTimelineProject,
            saveTimelineProject: model.saveTimelineProject,
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

    /// 载入视频/数据后，清掉文本框（如预设名称）的键盘焦点，让空格直接命中预览播放/暂停命令。
    private func focusPreviewForPlayback() {
        DispatchQueue.main.async {
            (NSApp.keyWindow ?? NSApp.mainWindow)?.makeFirstResponder(nil)
        }
    }

    private func requestExportCancellation() {
        guard model.isExporting else { return }
        isExportSheetPresented = true
        isCancelExportConfirmationPresented = true
    }

    private func presentStartupSourcePromptIfNeeded() {
        guard !didPresentStartupSourcePrompt,
              !suppressStartupSourcePrompt,
              model.videoURL == nil,
              model.fitURL == nil
        else { return }

        didPresentStartupSourcePrompt = true
        DispatchQueue.main.async {
            guard !suppressStartupSourcePrompt,
                  model.videoURL == nil,
                  model.fitURL == nil else { return }
            isStartupSourcePromptPresented = true
        }
    }

    private func dismissStartupSourcePromptAndRun(_ action: @escaping () -> Void) {
        isStartupSourcePromptPresented = false
        DispatchQueue.main.async {
            action()
        }
    }

    private var sourceContinuationPromptBinding: Binding<Bool> {
        Binding(
            get: { sourceContinuationPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    sourceContinuationPrompt = nil
                }
            }
        )
    }

    private var pendingTimelineActionBinding: Binding<Bool> {
        Binding(
            get: { model.pendingTimelineAction != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelPendingTimelineAction()
                }
            }
        )
    }

    private var weatherExportConfirmationBinding: Binding<Bool> {
        Binding(
            get: { model.isWeatherExportConfirmationPresented },
            set: { isPresented in
                if !isPresented {
                    model.cancelWeatherExportConfirmation()
                }
            }
        )
    }

    private func continueSourceSelection(from prompt: SourceContinuationPrompt) {
        sourceContinuationPrompt = nil
        DispatchQueue.main.async {
            switch prompt {
            case .activityAfterVideo:
                model.chooseFIT()
            case .videoAfterActivity:
                model.chooseVideo()
            }
        }
    }

    private func openActivityFile(_ url: URL) {
        suppressStartupSourcePrompt = true
        didPresentStartupSourcePrompt = true
        isStartupSourcePromptPresented = false
        sourceContinuationPrompt = nil
        model.openActivityFile(url)
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
            distanceUnit: model.distanceUnit,
            activityTrim: model.currentActivityTrim
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

private enum SourceContinuationPrompt {
    case activityAfterVideo
    case videoAfterActivity

    var titleKey: String {
        switch self {
        case .activityAfterVideo:
            return "sourceContinuation.activityTitle"
        case .videoAfterActivity:
            return "sourceContinuation.videoTitle"
        }
    }

    var messageKey: String {
        switch self {
        case .activityAfterVideo:
            return "sourceContinuation.activityMessage"
        case .videoAfterActivity:
            return "sourceContinuation.videoMessage"
        }
    }

    var primaryActionKey: String {
        switch self {
        case .activityAfterVideo:
            return "startupPrompt.chooseActivity"
        case .videoAfterActivity:
            return "startupPrompt.chooseVideo"
        }
    }
}

private struct StartupSourcePromptView: View {
    var chooseVideo: () -> Void
    var chooseActivity: () -> Void

    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 6) {
                    Text(localization.string("startupPrompt.title"))
                        .font(.title3.weight(.semibold))

                    Text(localization.string("startupPrompt.message"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(action: chooseVideo) {
                    Label(localization.string("startupPrompt.chooseVideo"), systemImage: "film")
                }

                Button(action: chooseActivity) {
                    Label(localization.string("startupPrompt.chooseActivity"), systemImage: "figure.run")
                }

                Spacer()

                Button(localization.string("startupPrompt.close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
    }
}

private struct ExportStatusSheet: View {
    @ObservedObject var model: StudioModel
    @Binding var isCancelExportConfirmationPresented: Bool
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if model.isExporting {
                exportingContent
            } else {
                resultContent
            }
        }
        .padding(24)
        .frame(width: 480, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                statusGlyph(systemImage: "paperplane.fill", color: .accentColor)

                Text(localization.string(model.exportMode == .video ? "sidebar.exportingVideo" : "sidebar.exportingOverlay"))
                    .font(.title3.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
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

            HStack {
                Spacer()

                Button(role: .destructive) {
                    isCancelExportConfirmationPresented = true
                } label: {
                    Label(localization.string("toolbar.cancelExport"), systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            resultHeader
            resultDetail
            Divider()
            resultActions
        }
    }

    private var resultHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            statusGlyph(systemImage: resultSystemImage, color: resultColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(resultTitle)
                    .font(.title3.weight(.semibold))

                if let elapsed = model.lastExportElapsedSeconds {
                    Label(localization.string("exportDialog.elapsed", formatDuration(elapsed)), systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var resultDetail: some View {
        if let lastExportedURL = model.lastExportedURL {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                Text(lastExportedURL.lastPathComponent)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        } else if let errorMessage = model.lastExportErrorMessage {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var resultActions: some View {
        HStack(spacing: 10) {
            if model.lastExportedURL != nil {
                Button {
                    model.revealLastExportInFinder()
                } label: {
                    Label(localization.string("sidebar.revealInFinder"), systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    model.openLastExport()
                } label: {
                    Label(localization.string("exportDialog.openFile"), systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Label(localization.string("common.done"), systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }

    private func statusGlyph(systemImage: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))

            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 48, height: 48)
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
            return "checkmark"
        }
        if model.lastExportWasCancelled {
            return "xmark"
        }
        return "exclamationmark"
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
    var activityTrim: ActivityTrim
}
