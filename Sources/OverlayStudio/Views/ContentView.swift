import AppKit
import OverlayCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.openURL) private var openURL
    @SceneStorage("previewZoom") private var previewZoom = 1.0
    @SceneStorage("bottomWorkspaceHeight") private var bottomWorkspaceHeight = StudioWorkspaceDefaults.timelineHeight
    @AppStorage("workspace.didIncreaseDefaultTimelineHeight") private var didIncreaseDefaultTimelineHeight = false
    @SceneStorage("workspace.libraryWidth") private var libraryPanelWidth = 330.0
    @SceneStorage("workspace.inspectorWidth") private var inspectorPanelWidth = 390.0
    @SceneStorage("workspace.showsLibrary") private var showsLibrary = true
    @SceneStorage("workspace.showsTimeline") private var showsTimeline = true
    @SceneStorage("workspace.showsInspector") private var showsInspector = true
    @State private var resizeStartHeight: Double?
    @State private var isPreviewFullscreen = false
    @State private var isDebugConsolePresented = false
    @State private var isExportSheetPresented = false
    @State private var isCancelExportConfirmationPresented = false
    @State private var sourceContinuationPrompt: SourceContinuationPrompt?
    @State private var isEditingText = false

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
            sourceContinuationPrompt = .forSources(
                hasVideo: model.videoURL != nil,
                hasActivity: model.fitURL != nil
            )
            if !didIncreaseDefaultTimelineHeight {
                bottomWorkspaceHeight = StudioWorkspaceDefaults.migratedTimelineHeight(bottomWorkspaceHeight)
                didIncreaseDefaultTimelineHeight = true
            }
        }
        .onChange(of: localization.selection) { _ in
            model.setResolvedLanguage(localization.resolvedLanguage)
        }
        .onChange(of: model.videoURL) { url in
            if url != nil { focusPreviewForPlayback() }
            guard url != nil else { return }
            sourceContinuationPrompt = .forSources(hasVideo: true, hasActivity: model.fitURL != nil)
        }
        .onChange(of: model.fitURL) { url in
            if url != nil { focusPreviewForPlayback() }
            guard url != nil else { return }
            sourceContinuationPrompt = .forSources(hasVideo: model.videoURL != nil, hasActivity: true)
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
        .alert(
            localization.string("weatherKeyPrompt.title"),
            isPresented: weatherAPIKeyPromptBinding
        ) {
            Button(localization.string("weatherKeyPrompt.openKeyPage")) {
                model.dismissWeatherAPIKeyPrompt()
                openURL(OpenWeatherService.apiKeyPageURL)
            }
            Button(localization.string("weatherKeyPrompt.later"), role: .cancel) {
                model.dismissWeatherAPIKeyPrompt()
            }
        } message: {
            Text(localization.string("weatherKeyPrompt.message"))
        }
        .focusedSceneValue(\.studioCommandActions, studioCommandActions)
        .focusedSceneValue(\.previewCommandActions, previewCommandActions)
        .toolbar { studioToolbar }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didBeginEditingNotification)) { _ in
            isEditingText = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didEndEditingNotification)) { _ in
            isEditingText = false
        }
        .onOpenURL(perform: openExternalFile)
    }

    private var editorLayout: some View {
        GeometryReader { proxy in
            let widths = StudioWorkspacePaneWidths.resolve(
                totalWidth: proxy.size.width,
                requestedLibrary: libraryPanelWidth,
                requestedInspector: inspectorPanelWidth,
                showsLibrary: showsLibrary,
                showsInspector: showsInspector
            )

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if showsLibrary {
                        LibraryPanelView(model: model)
                            .frame(width: widths.library)
                            .background(.bar)

                        HorizontalPaneResizeHandle(
                            edge: .trailing,
                            width: $libraryPanelWidth,
                            range: 260...420
                        )
                    }

                    PreviewCanvasView(
                        model: model,
                        zoom: $previewZoom,
                        isFullscreen: false,
                        onToggleFullscreen: { isPreviewFullscreen = true }
                    )
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                    if showsInspector {
                        HorizontalPaneResizeHandle(
                            edge: .leading,
                            width: $inspectorPanelWidth,
                            range: 320...480
                        )

                        InspectorView(model: model)
                            .frame(width: widths.inspector)
                            .background(.bar)
                    }
                }
                .frame(maxHeight: .infinity)

                if showsTimeline {
                    bottomResizeHandle

                    BottomWorkspaceView(model: model)
                        .frame(height: bottomWorkspaceHeight)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var studioToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            panelToggleButton(
                isPresented: showsLibrary,
                titleKey: "workspace.library",
                systemImage: "sidebar.left",
                action: { showsLibrary.toggle() }
            )
            panelToggleButton(
                isPresented: showsTimeline,
                titleKey: "workspace.timeline",
                systemImage: "rectangle.bottomthird.inset.filled",
                action: { showsTimeline.toggle() }
            )
            panelToggleButton(
                isPresented: showsInspector,
                titleKey: "workspace.inspector",
                systemImage: "sidebar.right",
                action: { showsInspector.toggle() }
            )
        }

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                OutputToolbarButton(model: model)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                OutputToolbarButton(model: model)
            }
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            OutputToolbarButton(model: model)
        }
        #endif
    }

    private func panelToggleButton(
        isPresented: Bool,
        titleKey: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(localization.string(titleKey), systemImage: systemImage)
                .labelStyle(.iconOnly)
                .foregroundStyle(isPresented ? Color.accentColor : Color.secondary)
        }
        .help(localization.string(titleKey))
        .accessibilityLabel(localization.string(titleKey))
        .accessibilityValue(localization.string(isPresented ? "workspace.visible" : "workspace.hidden"))
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
            canPlayPreview: model.canPlayPreview,
            isPlayingPreview: model.isPlaying,
            debugLogCount: model.debugLogEntries.count,
            canMarkSportStart: model.player != nil && !model.isExporting,
            canMoveSelectionForward: canMoveSelectedElementForward,
            canMoveSelectionBackward: canMoveSelectedElementBackward,
            canSplitTimelineClips: model.canSplitTimelineClipsAtPlayhead,
            canToggleTimelineClips: model.canToggleSelectedTimelineClipsEnabled && !isEditingText,
            canDeleteTimelineClip: model.selectedTimelineClipIsEditable,
            canJumpToTimelineEditPoints: model.canJumpToTimelineEditPoints,
            canUndo: model.canPerformUndo,
            canRedo: model.canPerformRedo,
            showsLibrary: showsLibrary,
            showsTimeline: showsTimeline,
            showsInspector: showsInspector,
            showsGrid: model.showGrid,
            recentTimelineProjects: model.recentTimelineProjects,
            chooseVideo: model.chooseVideo,
            chooseFIT: model.chooseFIT,
            openTimelineProject: model.openTimelineProject,
            openRecentTimelineProject: model.openRecentTimelineProject,
            saveTimelineProject: model.saveTimelineProject,
            saveTimelineProjectAs: model.saveTimelineProjectAs,
            export: model.export,
            cancelExport: requestExportCancellation,
            refreshPreview: model.refreshOverlayOrPreview,
            togglePlayback: model.togglePlayback,
            markSportStart: model.markSportStart,
            moveSelectionForward: model.moveSelectedElementForward,
            moveSelectionBackward: model.moveSelectedElementBackward,
            splitTimelineClips: model.splitTimelineClipsAtPlayhead,
            toggleTimelineClips: model.toggleSelectedTimelineClipsEnabled,
            deleteTimelineClip: { model.deleteSelectedTimelineClip(ripple: false) },
            rippleDeleteTimelineClip: { model.deleteSelectedTimelineClip(ripple: true) },
            jumpToPreviousEditPoint: model.jumpToPreviousTimelineEditPoint,
            jumpToNextEditPoint: model.jumpToNextTimelineEditPoint,
            undo: model.performUndo,
            redo: model.performRedo,
            toggleLibrary: { showsLibrary.toggle() },
            toggleTimeline: { showsTimeline.toggle() },
            toggleInspector: { showsInspector.toggle() },
            toggleGrid: { model.showGrid.toggle() },
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

    private var weatherAPIKeyPromptBinding: Binding<Bool> {
        Binding(
            get: { model.isWeatherAPIKeyPromptPresented },
            set: { isPresented in
                if !isPresented {
                    model.dismissWeatherAPIKeyPrompt()
                }
            }
        )
    }

    private func openExternalFile(_ url: URL) {
        _ = model.openExternalFiles([url])
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

enum SourceContinuationPrompt: Equatable {
    case activityAfterVideo
    case videoAfterActivity

    static func forSources(hasVideo: Bool, hasActivity: Bool) -> Self? {
        guard hasVideo != hasActivity else { return nil }
        return hasVideo ? .activityAfterVideo : .videoAfterActivity
    }

    var titleKey: String {
        switch self {
        case .activityAfterVideo: "sourceContinuation.activityTitle"
        case .videoAfterActivity: "sourceContinuation.videoTitle"
        }
    }

    var messageKey: String {
        switch self {
        case .activityAfterVideo: "sourceContinuation.activityMessage"
        case .videoAfterActivity: "sourceContinuation.videoMessage"
        }
    }

    var primaryActionKey: String {
        switch self {
        case .activityAfterVideo: "startupPrompt.chooseActivity"
        case .videoAfterActivity: "startupPrompt.chooseVideo"
        }
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
