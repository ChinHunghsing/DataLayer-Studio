#if os(iOS)
import OverlayCore
import SwiftUI

/// iPad 编辑器根视图：regular 宽度三栏常驻，compact 宽度画布优先 + sheet。
public struct TouchEditorRootView: View {
    @StateObject private var model: TouchStudioModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale

    @State private var showsSourcesColumn = true
    @State private var showsInspectorColumn = true
    @State private var activeCompactSheet: CompactSheet?
    @State private var showsSettings = false

    private enum CompactSheet: Int, Identifiable {
        case sources
        case inspector

        var id: Int { rawValue }
    }

    public init() {
        _model = StateObject(wrappedValue: TouchStudioModel(runtimeGuard: TouchExportRuntimeGuard()))
    }

    public var body: some View {
        let localizer = TouchLocalizer(locale: locale)

        NavigationStack {
            content(localizer: localizer)
                .navigationTitle(sourceTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    toolbarContent(localizer: localizer)
                }
        }
        .sheet(item: $activeCompactSheet) { sheet in
            switch sheet {
            case .sources:
                NavigationStack {
                    TouchSourcesPanel(model: model, localizer: localizer)
                        .navigationTitle(localizer.string("sources.title"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            case .inspector:
                NavigationStack {
                    TouchInspectorPanel(model: model, localizer: localizer)
                        .navigationTitle(localizer.string("inspector.title"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                settingsView(localizer: localizer)
                    .navigationTitle(localizer.string("settings.title"))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .onOpenURL { url in
            model.openIncomingFile(url)
        }
        .task {
            autoloadSimulatorSamplesIfRequested()
        }
    }

    @ViewBuilder
    private func content(localizer: TouchLocalizer) -> some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                if showsSourcesColumn {
                    TouchSourcesPanel(model: model, localizer: localizer)
                        .frame(width: 340)
                    Divider()
                }

                canvasColumn(localizer: localizer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsInspectorColumn {
                    Divider()
                    TouchInspectorPanel(model: model, localizer: localizer)
                        .frame(width: 340)
                }
            }
        } else {
            canvasColumn(localizer: localizer)
        }
    }

    private func canvasColumn(localizer: TouchLocalizer) -> some View {
        VStack(spacing: 0) {
            TouchCanvasView(model: model, localizer: localizer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            TouchTimelineBar(model: model, localizer: localizer)
            statusBar(localizer: localizer)
        }
    }

    private func statusBar(localizer: TouchLocalizer) -> some View {
        HStack(spacing: 12) {
            Text(localizer.format(model.statusMessage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let warning = model.previewWarning {
                Label(localizer.format(warning), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private func toolbarContent(localizer: TouchLocalizer) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if horizontalSizeClass == .regular {
                Button {
                    withAnimation {
                        showsSourcesColumn.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .accessibilityLabel(Text(localizer.string("toolbar.sources")))
            } else {
                Button {
                    activeCompactSheet = .sources
                } label: {
                    Image(systemName: "film.stack")
                }
                .accessibilityLabel(Text(localizer.string("toolbar.sources")))
            }

            Button {
                model.undoLayoutChange()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel(Text(localizer.string("common.undo")))
            .disabled(!model.canUndoLayout || model.isExporting)

            Button {
                model.redoLayoutChange()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .accessibilityLabel(Text(localizer.string("common.redo")))
            .disabled(!model.canRedoLayout || model.isExporting)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(Text(localizer.string("toolbar.settings")))

            if horizontalSizeClass == .regular {
                Button {
                    withAnimation {
                        showsInspectorColumn.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .accessibilityLabel(Text(localizer.string("toolbar.inspector")))
            } else {
                Button {
                    activeCompactSheet = .inspector
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(Text(localizer.string("toolbar.inspector")))
            }
        }
    }

    private func settingsView(localizer: TouchLocalizer) -> some View {
        Form {
            Picker(localizer.string("settings.unit"), selection: $model.distanceUnit) {
                Text(localizer.string("unit.kilometers")).tag(OverlayDistanceUnit.kilometers)
                Text(localizer.string("unit.meters")).tag(OverlayDistanceUnit.meters)
            }
            .onChange(of: model.distanceUnit) { _, _ in
                model.refreshOverlayOnly(coalesceIfBusy: true)
            }
        }
    }

    private var sourceTitle: String {
        if let videoURL = model.videoURL {
            return videoURL.lastPathComponent
        }
        if let activityURL = model.activityURL {
            return activityURL.lastPathComponent
        }
        return "DataLayer Studio"
    }

    /// 模拟器调试用：SIMCTL_CHILD_ 环境变量注入本地样本路径与自动导出，跳过手工文件挑选。
    private func autoloadSimulatorSamplesIfRequested() {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        if let videoPath = environment["TOUCH_AUTOLOAD_VIDEO"], FileManager.default.fileExists(atPath: videoPath) {
            model.setVideo(URL(fileURLWithPath: videoPath), isSecurityScoped: false)
        }
        if let fitPath = environment["TOUCH_AUTOLOAD_FIT"], FileManager.default.fileExists(atPath: fitPath) {
            model.setActivityFile(URL(fileURLWithPath: fitPath), isSecurityScoped: false)
        }
        guard let autoExport = environment["TOUCH_AUTOEXPORT"], !autoExport.isEmpty else {
            return
        }
        Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard model.series != nil, model.metadata != nil else { continue }
                if let maxSeconds = environment["TOUCH_AUTOEXPORT_MAX_SECONDS"].flatMap(Double.init) {
                    model.setExportTrimEnd(min(model.effectiveExportTrimEnd, maxSeconds))
                }
                guard model.canExport else { continue }
                model.export()
                return
            }
        }
        #endif
    }
}
#endif
