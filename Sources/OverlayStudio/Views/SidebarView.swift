import SwiftUI
import OverlayCore

struct SidebarView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var layoutPresetName = ""
    @SceneStorage("sidebarWorkflowTab") private var selectedTabRawValue = SidebarWorkflowTab.source.rawValue

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                workflowTabs

                SidebarWorkflowSection(
                    step: selectedTab.step,
                    title: localization.string(selectedTab.titleKey),
                    subtitle: localization.string(selectedTab.subtitleKey),
                    systemImage: selectedTab.systemImage
                ) {
                    selectedTabContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .controlSize(.small)
    }

    private var selectedTab: SidebarWorkflowTab {
        SidebarWorkflowTab(rawValue: selectedTabRawValue) ?? .source
    }

    private var workflowTabs: some View {
        Picker(localization.string("sidebar.workflowTabs"), selection: $selectedTabRawValue) {
            ForEach(SidebarWorkflowTab.allCases) { tab in
                Text(localization.string(tab.titleKey)).tag(tab.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel(localization.string("sidebar.workflowTabs"))
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .source:
            fileSection
                .disabled(model.isExporting)
        case .sync:
            syncSection
                .disabled(model.isExporting)
        case .canvas:
            canvasSection
        case .export:
            exportWorkflowSection
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilePickRow(
                title: localization.string("sidebar.video.title"),
                subtitle: model.videoURL?.lastPathComponent ?? localization.string("sidebar.video.placeholder"),
                systemImage: "film",
                isLoaded: model.videoURL != nil,
                action: model.chooseVideo
            )

            FilePickRow(
                title: localization.string("sidebar.fit.title"),
                subtitle: model.fitURL?.lastPathComponent ?? localization.string("sidebar.fit.placeholder"),
                systemImage: "figure.run",
                isLoaded: model.fitURL != nil,
                action: model.chooseFIT
            )
        }
    }

    private var syncSection: some View {
        SidebarSyncSection(model: model)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarSubsectionHeader(title: localization.string("sidebar.videoSettings"), systemImage: "slider.horizontal.3")

            SidebarControl(title: localization.string("sidebar.resolution")) {
                Picker(localization.string("sidebar.resolution"), selection: resolutionPresetSelection) {
                    if let sourceTitle = sourceResolutionPresetTitle {
                        Text(sourceTitle).tag(OutputResolutionPreset.sourceID)
                    }
                    ForEach(OutputResolutionPreset.fixed) { preset in
                        Text(localization.string(preset.localizationKey)).tag(preset.id)
                    }
                    Text(localization.string("sidebar.custom")).tag(OutputResolutionPreset.customID)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                CompactNumberIntField(title: localization.string("sidebar.width"), suffix: "px", value: intBinding(
                    get: { model.outputWidth },
                    set: { model.setOutputWidth($0) },
                    range: 2...16_384
                ))
                CompactNumberIntField(title: localization.string("sidebar.height"), suffix: "px", value: intBinding(
                    get: { model.outputHeight },
                    set: { model.setOutputHeight($0) },
                    range: 2...16_384
                ))
            }

            SidebarControl(title: localization.string("sidebar.frameRate")) {
                Picker(localization.string("sidebar.frameRate"), selection: frameRatePresetSelection) {
                    if let sourceTitle = sourceFrameRatePresetTitle {
                        Text(sourceTitle).tag(OutputFrameRatePreset.sourceID)
                    }
                    ForEach(OutputFrameRatePreset.fixed) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                    Text(localization.string("sidebar.custom")).tag(OutputFrameRatePreset.customID)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            NumberField(title: localization.string("sidebar.fps"), suffix: "fps", value: doubleBinding(
                get: { model.outputFPS },
                set: { model.setOutputFPS($0) },
                range: 1...240
            ))

            NumberIntField(title: localization.string("sidebar.bitrate"), suffix: "kbps", value: intBinding(
                get: { model.bitRateKbps },
                set: { model.setBitRateKbps($0) },
                range: 1...1_000_000
            ))

            SidebarControl(title: localization.string("sidebar.distanceUnit")) {
                Picker(localization.string("sidebar.distanceUnit"), selection: $model.distanceUnit) {
                    ForEach(OverlayDistanceUnit.allCases) { unit in
                        Text(localization.string(unit.localizationKey)).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SidebarControl(title: localization.string("sidebar.codec")) {
                Picker(localization.string("sidebar.codec"), selection: $model.codec) {
                    ForEach(OverlayVideoCodec.allCases) { codec in
                        Text(localization.string(codec.localizationKey)).tag(codec)
                    }
                }
                .labelsHidden()
            }

            SidebarSubsectionHeader(title: localization.string("sidebar.destination"), systemImage: "folder")

            FilePickRow(
                title: localization.string("sidebar.saveAs"),
                subtitle: model.outputURL?.lastPathComponent ?? localization.string("sidebar.askWhenExporting"),
                systemImage: "square.and.arrow.down",
                isLoaded: model.outputURL != nil,
                action: model.chooseOutput
            )
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarSubsectionHeader(title: localization.string("sidebar.grid"), systemImage: "grid")

            Toggle(localization.string("sidebar.showGrid"), isOn: $model.showGrid)
            Toggle(localization.string("sidebar.snapWhileDragging"), isOn: $model.snapGaugeToGrid)

            SidebarStepperRow(
                title: localization.string("sidebar.columns"),
                value: Binding(
                    get: { model.gridColumns },
                    set: { model.setGridColumns($0) }
                ),
                range: 2...64
            )
            SidebarStepperRow(
                title: localization.string("sidebar.rows"),
                value: Binding(
                    get: { model.gridRows },
                    set: { model.setGridRows($0) }
                ),
                range: 2...64
            )
        }
    }

    private var layoutPresetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarSubsectionHeader(title: localization.string("sidebar.presets"), systemImage: "rectangle.3.group")

            HStack(spacing: 8) {
                TextField(localization.string("sidebar.presetName"), text: $layoutPresetName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    if model.saveLayoutPreset(named: layoutPresetName) {
                        layoutPresetName = ""
                    }
                } label: {
                    Label(localization.string("sidebar.save"), systemImage: "tray.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .help(localization.string("sidebar.saveCurrentLayout"))
                .disabled(layoutPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                Button {
                    model.importLayoutPresets()
                } label: {
                    Label(localization.string("sidebar.import"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.exportLayoutPresets()
                } label: {
                    Label(localization.string("sidebar.export"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.layoutPresets.isEmpty)
            }
            .buttonStyle(.bordered)

            if model.layoutPresets.isEmpty {
                Text(localization.string("sidebar.noSavedPresets"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.layoutPresets) { preset in
                        LayoutPresetRow(
                            preset: preset,
                            isDefault: model.defaultLayoutPresetID == preset.id,
                            apply: { model.applyLayoutPreset(id: preset.id) },
                            makeDefault: { model.setDefaultLayoutPreset(id: preset.id) },
                            delete: { model.deleteLayoutPreset(id: preset.id) }
                        )
                    }
                }
            }
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            previewSection
            SidebarDivider()
            layoutPresetSection
                .disabled(model.isExporting)
        }
    }

    private var exportWorkflowSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            outputSection
                .disabled(model.isExporting)
            SidebarDivider()
            exportSection
        }
    }

    private var resolutionPresetSelection: Binding<String> {
        Binding(
            get: { model.selectedResolutionPresetID },
            set: { model.applyResolutionPreset(id: $0) }
        )
    }

    private var frameRatePresetSelection: Binding<String> {
        Binding(
            get: { model.selectedFrameRatePresetID },
            set: { model.applyFrameRatePreset(id: $0) }
        )
    }

    private var sourceResolutionPresetTitle: String? {
        guard let metadata = model.metadata else { return nil }
        let width = StudioModel.sanitizedOutputDimension(Int(metadata.size.width.rounded()))
        let height = StudioModel.sanitizedOutputDimension(Int(metadata.size.height.rounded()))
        return localization.string("sidebar.sourceResolutionPreset", String(width), String(height))
    }

    private var sourceFrameRatePresetTitle: String? {
        guard let metadata = model.metadata else { return nil }
        let fps = metadata.framesPerSecond
        guard fps.isFinite, fps >= 1, fps <= 240 else { return nil }
        return localization.string("sidebar.sourceFrameRatePreset", formatFrameRate(fps))
    }

    private func formatFrameRate(_ fps: Double) -> String {
        if abs(fps - fps.rounded()) < 0.01 {
            return String(format: "%.0f", fps)
        }
        return String(format: "%.3f", fps)
    }

    private func intBinding(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { min(range.upperBound, max(range.lowerBound, get())) },
            set: { set(min(range.upperBound, max(range.lowerBound, $0))) }
        )
    }

    private func doubleBinding(
        get: @escaping () -> Double,
        set: @escaping (Double) -> Void,
        range: ClosedRange<Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                let value = get()
                return min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
            },
            set: {
                set(min(range.upperBound, max(range.lowerBound, $0.isFinite ? $0 : range.lowerBound)))
            }
        )
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarSubsectionHeader(title: localization.string("sidebar.render"), systemImage: "paperplane")

            if model.isExporting {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: clampedExportProgress)
                    HStack {
                        Text(localization.string("sidebar.exportingOverlay"))
                        Spacer()
                        Text(clampedExportProgress.percentString)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(localization.string("sidebar.exportProgress"))
                .accessibilityValue(clampedExportProgress.percentString)
            }
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            if !model.isExporting, let exportReadinessMessage = model.exportReadinessMessage {
                Label(exportReadinessMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localization.string("sidebar.exportDisabled"))
                    .accessibilityValue(exportReadinessMessage)
            }

            if model.isExporting {
                Button(role: .destructive) {
                    model.cancelExport()
                } label: {
                    Label(localization.string("toolbar.cancelExport"), systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            } else {
                Button {
                    model.export()
                } label: {
                    Label(localization.string("sidebar.exportOverlay"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
                .help(model.exportReadinessMessage ?? localization.string("help.exportTransparentOverlay"))
            }
        }
    }

    private var clampedExportProgress: Double {
        guard model.exportProgress.isFinite else { return 0 }
        return min(1, max(0, model.exportProgress))
    }
}

private enum SidebarWorkflowTab: String, CaseIterable, Identifiable {
    case source
    case sync
    case canvas
    case export

    var id: String { rawValue }

    var step: String {
        switch self {
        case .source:
            return "1"
        case .sync:
            return "2"
        case .canvas:
            return "3"
        case .export:
            return "4"
        }
    }

    var titleKey: String {
        switch self {
        case .source:
            return "sidebar.source.title"
        case .sync:
            return "sidebar.sync.title"
        case .canvas:
            return "sidebar.canvas.title"
        case .export:
            return "sidebar.export.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .source:
            return "sidebar.source.subtitle"
        case .sync:
            return "sidebar.sync.subtitle"
        case .canvas:
            return "sidebar.canvas.subtitle"
        case .export:
            return "sidebar.export.subtitle"
        }
    }

    var systemImage: String {
        switch self {
        case .source:
            return "film.stack"
        case .sync:
            return "timer"
        case .canvas:
            return "rectangle.dashed"
        case .export:
            return "paperplane"
        }
    }
}
