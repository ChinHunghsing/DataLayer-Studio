import SwiftUI
import OverlayCore

struct SidebarView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var layoutPresetName = ""
    @SceneStorage("sidebarWorkflowTab") private var selectedTabRawValue = SidebarWorkflowTab.source.rawValue

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()
            statusFooter
        }
        .controlSize(.small)
    }

    private var statusFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string("sidebar.status"))
        .accessibilityValue(model.status)
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

            if let failure = model.videoLoadFailure {
                SourceLoadFailureRow(
                    message: localization.string(failure.messageKey, failure.detail),
                    retryTitle: localization.string("sidebar.retryLoad"),
                    retry: model.retryVideoLoad
                )
            }

            FilePickRow(
                title: localization.string("sidebar.fit.title"),
                subtitle: model.fitURL?.lastPathComponent ?? localization.string("sidebar.fit.placeholder"),
                systemImage: "figure.run",
                isLoaded: model.fitURL != nil,
                action: model.chooseFIT
            )

            if let failure = model.fitLoadFailure {
                SourceLoadFailureRow(
                    message: localization.string(failure.messageKey, failure.detail),
                    retryTitle: localization.string("sidebar.retryLoad"),
                    retry: model.retryFITLoad
                )
            }
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
                    if let sourceTitle = model.sourceResolutionPresetTitle {
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
                    if let sourceTitle = model.sourceFrameRatePresetTitle {
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
                    ForEach(model.availableCodecs) { codec in
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
            layoutPresetSyncStatusRow

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

    private var layoutPresetSyncStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: layoutPresetSyncStatusIcon)
                .foregroundStyle(layoutPresetSyncStatusTint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(localization.string("sidebar.presetSync.title"))
                    .font(.caption.weight(.semibold))
                Text(layoutPresetSyncStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var layoutPresetSyncStatusIcon: String {
        switch model.layoutPresetSyncStatus {
        case .localOnly:
            return "icloud.slash"
        case .ready:
            return "icloud"
        case .uploadRequested:
            return "icloud.and.arrow.up"
        case .receivedUpdate:
            return "icloud.and.arrow.down"
        }
    }

    private var layoutPresetSyncStatusTint: Color {
        switch model.layoutPresetSyncStatus {
        case .localOnly:
            return .secondary
        default:
            return .accentColor
        }
    }

    private var layoutPresetSyncStatusText: String {
        switch model.layoutPresetSyncStatus {
        case .localOnly:
            return localization.string("sidebar.presetSync.localOnly")
        case .ready:
            return localization.string("sidebar.presetSync.ready")
        case let .uploadRequested(date):
            return localization.string("sidebar.presetSync.uploadRequested", formatPresetSyncTime(date))
        case let .receivedUpdate(date):
            return localization.string("sidebar.presetSync.receivedUpdate", formatPresetSyncTime(date))
        }
    }

    private func formatPresetSyncTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
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
                        Text(localization.string(model.exportMode == .video ? "sidebar.exportingVideo" : "sidebar.exportingOverlay"))
                        Spacer()
                        Text(clampedExportProgress.percentString)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let etaSeconds = model.exportETASeconds {
                        Text(localization.string("sidebar.exportETA", formatETADuration(etaSeconds)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(localization.string("sidebar.exportProgress"))
                .accessibilityValue(clampedExportProgress.percentString)
            }

            if !model.isExporting, let exportedURL = model.lastExportedURL {
                exportSuccessCard(exportedURL)
            }

            if !model.isExporting, let exportReadinessMessage = model.exportReadinessMessage {
                Label(exportReadinessMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localization.string("sidebar.exportDisabled"))
                    .accessibilityValue(exportReadinessMessage)
            }

            exportTrimRangeCard

            exportSummaryCard

            SidebarControl(title: localization.string("sidebar.exportMode")) {
                Picker(localization.string("sidebar.exportMode"), selection: $model.exportMode) {
                    ForEach(OverlayExportMode.allCases) { mode in
                        Text(localization.string(mode.localizationKey)).tag(mode)
                            .disabled(mode == .video && model.videoURL == nil)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .disabled(model.isExporting)

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
                    Label(localization.string(model.exportMode == .video ? "sidebar.exportVideo" : "sidebar.exportOverlay"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
                .help(model.exportReadinessMessage ?? localization.string(model.exportMode == .video ? "help.exportCompositedVideo" : "help.exportTransparentOverlay"))
            }
        }
    }

    private var exportSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localization.string("sidebar.exportSummary"), systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            SidebarSummaryRow(
                title: localization.string("sidebar.exportSummary.type"),
                value: localization.string(model.exportMode.localizationKey)
            )
            SidebarSummaryRow(
                title: localization.string("sidebar.exportSummary.codec"),
                value: localization.string(model.codec.localizationKey)
            )
            SidebarSummaryRow(
                title: localization.string("sidebar.exportSummary.resolution"),
                value: "\(NumberTextFormatter.formatInt(model.outputWidth))×\(NumberTextFormatter.formatInt(model.outputHeight))"
            )
            SidebarSummaryRow(
                title: localization.string("sidebar.exportSummary.frameRate"),
                value: "\(NumberTextFormatter.formatDouble(model.outputFPS)) fps"
            )
            SidebarSummaryRow(
                title: localization.string("sidebar.exportSummary.range"),
                value: "\(formatTrimTime(model.effectiveExportTrimStart)) – \(formatTrimTime(model.effectiveExportTrimEnd))"
            )
            SidebarSummaryRow(
                title: localization.string("sidebar.exportSummary.destination"),
                value: model.outputURL?.lastPathComponent ?? localization.string("sidebar.askWhenExporting")
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string("sidebar.exportSummary"))
    }

    private var exportTrimRangeCard: some View {
        ExportTrimRangeControl(
            start: Binding(
                get: { model.effectiveExportTrimStart },
                set: { model.setExportTrimStart($0) }
            ),
            end: Binding(
                get: { model.effectiveExportTrimEnd },
                set: { model.setExportTrimEnd($0) }
            ),
            sourceDuration: model.exportTrimSourceDuration,
            reset: { model.resetExportTrimRange() },
            formatTime: formatTrimTime
        )
        .disabled(model.isExporting || model.exportTrimSourceDuration <= 0)
    }

    private var clampedExportProgress: Double {
        guard model.exportProgress.isFinite else { return 0 }
        return min(1, max(0, model.exportProgress))
    }

    private func exportSuccessCard(_ exportedURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localization.string("sidebar.exportDone"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)

            Text(exportedURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Button(localization.string("sidebar.revealInFinder")) {
                    model.revealLastExportInFinder()
                }
                Button(localization.string("sidebar.copyPath")) {
                    model.copyLastExportPath()
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func formatETADuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatTrimTime(_ seconds: TimeInterval) -> String {
        let milliseconds = max(0, Int((seconds * 1000).rounded()))
        let ms = milliseconds % 1000
        let totalSeconds = milliseconds / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, ms)
        }
        return String(format: "%02d:%02d.%03d", minutes, secs, ms)
    }
}

private struct ExportTrimRangeControl: View {
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval
    var sourceDuration: TimeInterval
    var reset: () -> Void
    var formatTime: (TimeInterval) -> String
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(localization.string("sidebar.exportRange"), systemImage: "scissors")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(localization.string("sidebar.exportRange.full"), action: reset)
                    .controlSize(.small)
            }

            ExportTrimRangeSlider(
                start: $start,
                end: $end,
                sourceDuration: sourceDuration
            )

            HStack(alignment: .top, spacing: 8) {
                trimValue(label: localization.string("sidebar.exportRange.start"), value: start)
                Spacer(minLength: 8)
                trimValue(label: localization.string("sidebar.exportRange.duration"), value: max(0, end - start))
                Spacer(minLength: 8)
                trimValue(label: localization.string("sidebar.exportRange.end"), value: end, alignment: .trailing)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string("sidebar.exportRange"))
    }

    private func trimValue(
        label: String,
        value: TimeInterval,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatTime(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct ExportTrimRangeSlider: View {
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval
    var sourceDuration: TimeInterval
    @State private var activeHandle: Handle?
    private let minimumRangeDuration: TimeInterval = 0.1

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let startX = xPosition(for: start, width: width)
            let endX = xPosition(for: end, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.25))
                    .frame(height: 4)
                    .position(x: width / 2, y: 16)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, endX - startX), height: 4)
                    .position(x: startX + max(0, endX - startX) / 2, y: 16)

                handle(isActive: activeHandle == .start)
                    .position(x: startX, y: 16)

                handle(isActive: activeHandle == .end)
                    .position(x: endX, y: 16)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard sourceDuration > minimumRangeDuration else { return }
                        let handle = activeHandle ?? nearestHandle(
                            to: value.startLocation.x,
                            startX: startX,
                            endX: endX
                        )
                        activeHandle = handle
                        let time = time(for: value.location.x, width: width)
                        switch handle {
                        case .start:
                            start = min(max(0, time), max(0, end - minimumRangeDuration))
                        case .end:
                            end = max(min(sourceDuration, time), min(sourceDuration, start + minimumRangeDuration))
                        }
                    }
                    .onEnded { _ in activeHandle = nil }
            )
        }
        .frame(height: 32)
    }

    private func handle(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.background)
            .frame(width: 12, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.55), lineWidth: isActive ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    private func xPosition(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard sourceDuration > 0 else { return 0 }
        let progress = min(1, max(0, time / sourceDuration))
        return CGFloat(progress) * width
    }

    private func time(for x: CGFloat, width: CGFloat) -> TimeInterval {
        let progress = min(1, max(0, x / max(1, width)))
        return TimeInterval(progress) * sourceDuration
    }

    private func nearestHandle(to x: CGFloat, startX: CGFloat, endX: CGFloat) -> Handle {
        abs(x - startX) <= abs(x - endX) ? .start : .end
    }

    private enum Handle {
        case start
        case end
    }
}

private struct SourceLoadFailureRow: View {
    var message: String
    var retryTitle: String
    var retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(retryTitle, action: retry)
                .controlSize(.small)
        }
        .padding(8)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct SidebarSummaryRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
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
