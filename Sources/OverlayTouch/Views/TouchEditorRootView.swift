#if os(iOS)
import OverlayCore
import SwiftUI

/// iPad 编辑器根视图：regular 宽度三栏常驻，compact 宽度画布优先 + sheet。
public struct TouchEditorRootView: View {
    @StateObject private var model: TouchStudioModel
    @StateObject private var subscriptionStore: MobileSubscriptionStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var showsSourcesColumn = true
    @State private var showsInspectorColumn = true
    @State private var activeCompactSheet: CompactSheet?
    @State private var showsSettings = false
    @State private var showsPaywall = false
    @State private var presentsPaywallAfterSheetDismiss = false
    @State private var regularContentWidth = CGFloat.greatestFiniteMagnitude

    private let enforcesSubscription: Bool
    private static let minimumTwoSidebarWidth: CGFloat = 1_040

    private enum CompactSheet: Int, Identifiable {
        case sources
        case inspector

        var id: Int { rawValue }
    }

    public init(enforcesSubscription: Bool = false) {
        let subscriptionStore = MobileSubscriptionStore()
        let entitlement: any SubscriptionEntitlementProviding = enforcesSubscription
            ? subscriptionStore
            : TouchSubscriptionBypass.shared
        _subscriptionStore = StateObject(wrappedValue: subscriptionStore)
        _model = StateObject(wrappedValue: TouchStudioModel(
            runtimeGuard: TouchExportRuntimeGuard(),
            subscriptionEntitlement: entitlement
        ))
        self.enforcesSubscription = enforcesSubscription
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
        .sheet(item: $activeCompactSheet, onDismiss: presentQueuedPaywall) { sheet in
            switch sheet {
            case .sources:
                NavigationStack {
                    TouchSourcesPanel(
                        model: model,
                        subscriptionStore: activeSubscriptionStore,
                        localizer: localizer,
                        showPaywall: requestPaywall
                    )
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
        .sheet(isPresented: $showsSettings, onDismiss: presentQueuedPaywall) {
            NavigationStack {
                settingsView(localizer: localizer)
                    .navigationTitle(localizer.string("settings.title"))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsPaywall) {
            NavigationStack {
                TouchSubscriptionPaywallView(
                    subscriptionStore: subscriptionStore,
                    localizer: localizer
                )
            }
        }
        .onOpenURL { url in
            model.openIncomingFile(url)
        }
        .onChange(of: model.subscriptionPaywallRequestID) { _, _ in
            guard enforcesSubscription else { return }
            requestPaywall()
        }
        .task {
            if enforcesSubscription {
                subscriptionStore.start()
            }
            TouchImportedMovie.removeStaleImportedFiles()
            autoloadSimulatorSamplesIfRequested()
        }
    }

    @ViewBuilder
    private func content(localizer: TouchLocalizer) -> some View {
        if horizontalSizeClass == .regular {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    if showsSourcesColumn {
                        TouchSourcesPanel(
                            model: model,
                            subscriptionStore: activeSubscriptionStore,
                            localizer: localizer,
                            showPaywall: requestPaywall
                        )
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
                .onAppear { updateRegularContentWidth(proxy.size.width) }
                .onChange(of: proxy.size.width) { _, width in
                    updateRegularContentWidth(width)
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
                    toggleSourcesSidebar()
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
                    toggleInspectorSidebar()
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

            if let activeSubscriptionStore {
                Section(localizer.string("settings.subscription")) {
                    TouchSubscriptionStatusBlock(
                        subscriptionStore: activeSubscriptionStore,
                        localizer: localizer,
                        showPaywall: requestPaywall
                    )

                    Button(localizer.string("paywall.restore")) {
                        Task { await activeSubscriptionStore.restore() }
                    }

                    Button(localizer.string("paywall.manage")) {
                        Task { await activeSubscriptionStore.showManageSubscriptions() }
                    }

                    Button(localizer.string("paywall.redeem")) {
                        Task { await activeSubscriptionStore.redeemOfferCode() }
                    }

                    Link(localizer.string("paywall.eula"), destination: MobileSubscriptionStore.standardEULAURL)
                    Link(localizer.string("paywall.privacy"), destination: MobileSubscriptionStore.privacyURL)
                }
            }
        }
    }

    private var activeSubscriptionStore: MobileSubscriptionStore? {
        enforcesSubscription ? subscriptionStore : nil
    }

    private var usesSingleSidebarLayout: Bool {
        horizontalSizeClass == .regular && regularContentWidth < Self.minimumTwoSidebarWidth
    }

    private func updateRegularContentWidth(_ width: CGFloat) {
        regularContentWidth = width
        if usesSingleSidebarLayout, showsSourcesColumn, showsInspectorColumn {
            showsInspectorColumn = false
        }
    }

    private func toggleSourcesSidebar() {
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            if usesSingleSidebarLayout, !showsSourcesColumn {
                showsInspectorColumn = false
            }
            showsSourcesColumn.toggle()
        }
    }

    private func toggleInspectorSidebar() {
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            if usesSingleSidebarLayout, !showsInspectorColumn {
                showsSourcesColumn = false
            }
            showsInspectorColumn.toggle()
        }
    }

    private func requestPaywall() {
        if activeCompactSheet != nil {
            presentsPaywallAfterSheetDismiss = true
            activeCompactSheet = nil
        } else if showsSettings {
            presentsPaywallAfterSheetDismiss = true
            showsSettings = false
        } else {
            showsPaywall = true
        }
    }

    private func presentQueuedPaywall() {
        guard presentsPaywallAfterSheetDismiss,
              activeCompactSheet == nil,
              !showsSettings else { return }
        presentsPaywallAfterSheetDismiss = false
        showsPaywall = true
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
