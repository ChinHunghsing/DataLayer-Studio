import Foundation
import SwiftUI
import OverlayCore

struct BottomWorkspaceView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @SceneStorage("bottomWorkspaceTab") private var selectedTabRawValue = BottomWorkspaceTab.output.rawValue

    private let columns = [
        GridItem(.flexible(minimum: 220), spacing: 14, alignment: .top),
        GridItem(.flexible(minimum: 220), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker(localization.string("workspace.tabs"), selection: $selectedTabRawValue) {
                    ForEach(BottomWorkspaceTab.allCases) { tab in
                        Text(localization.string(tab.localizationKey)).tag(tab.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                .accessibilityLabel(localization.string("workspace.tabs"))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            ScrollView(.vertical) {
                tabContent
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 148, idealHeight: 220, maxHeight: 280)

            if selectedTab == .output {
                Divider()
                exportActionFooter
            }
        }
        .background(.bar)
        .controlSize(.small)
    }

    private var selectedTab: BottomWorkspaceTab {
        BottomWorkspaceTab(rawValue: selectedTabRawValue) ?? .sync
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .sync:
            SidebarSyncSection(model: model)
                .disabled(model.isExporting)
        case .trim:
            trimContent
        case .output:
            outputContent
        }
    }

    private var trimContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            exportTrimRangeCard
            exportSummaryCard
        }
    }

    private var outputContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            outputSettingsSection
                .disabled(model.isExporting)

            SidebarDivider()

            renderSection
        }
    }

    private var outputSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarSubsectionHeader(title: localization.string("workspace.outputSettings"), systemImage: "slider.horizontal.3")

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                resolutionControl

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

                frameRateControl

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

                distanceUnitControl

                codecControl

                FilePickRow(
                    title: localization.string("sidebar.saveAs"),
                    subtitle: model.outputURL?.lastPathComponent ?? localization.string("sidebar.askWhenExporting"),
                    systemImage: "square.and.arrow.down",
                    isLoaded: model.outputURL != nil,
                    action: model.chooseOutput
                )
            }
        }
    }

    private var resolutionControl: some View {
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
    }

    private var frameRateControl: some View {
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
    }

    private var distanceUnitControl: some View {
        SidebarControl(title: localization.string("sidebar.distanceUnit")) {
            Picker(localization.string("sidebar.distanceUnit"), selection: $model.distanceUnit) {
                ForEach(OverlayDistanceUnit.allCases) { unit in
                    Text(localization.string(unit.localizationKey)).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var codecControl: some View {
        SidebarControl(title: localization.string("sidebar.codec")) {
            Picker(localization.string("sidebar.codec"), selection: $model.codec) {
                ForEach(model.availableCodecs) { codec in
                    Text(localization.string(codec.localizationKey)).tag(codec)
                }
            }
            .labelsHidden()
        }
    }

    private var renderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarSubsectionHeader(title: localization.string("sidebar.render"), systemImage: "paperplane")

            if model.isExporting {
                exportProgressCard
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

            exportSummaryCard
            exportModeControl
        }
    }

    private var exportProgressCard: some View {
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

    private var exportModeControl: some View {
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
    }

    private var exportActionFooter: some View {
        Group {
            if model.isExporting {
                Button(role: .destructive) {
                    model.cancelExport()
                } label: {
                    Label(localization.string("toolbar.cancelExport"), systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    model.export()
                } label: {
                    Label(localization.string(model.exportMode == .video ? "sidebar.exportVideo" : "sidebar.exportOverlay"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
                .help(model.exportReadinessMessage ?? localization.string(model.exportMode == .video ? "help.exportCompositedVideo" : "help.exportTransparentOverlay"))
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var exportSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localization.string("sidebar.exportSummary"), systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                SidebarSummaryRow(
                    title: localization.string("sidebar.exportSummary.type"),
                    value: localization.string(model.exportMode.localizationKey)
                )
                SidebarSummaryRow(
                    title: localization.string("sidebar.exportSummary.resolution"),
                    value: "\(model.outputWidth)×\(model.outputHeight)"
                )
                SidebarSummaryRow(
                    title: localization.string("sidebar.exportSummary.frameRate"),
                    value: "\(formatFrameRate(model.outputFPS)) fps"
                )
                SidebarSummaryRow(
                    title: localization.string("sidebar.exportSummary.bitrate"),
                    value: "\(model.bitRateKbps) kbps"
                )
                SidebarSummaryRow(
                    title: localization.string("sidebar.exportSummary.duration"),
                    value: formatTrimTime(model.effectiveExportTrimDuration)
                )
                SidebarSummaryRow(
                    title: localization.string("sidebar.exportSummary.estimatedSize"),
                    value: formatEstimatedFileSize(duration: model.effectiveExportTrimDuration, bitRateKbps: model.bitRateKbps)
                )
                SidebarSummaryRow(
                    title: localization.string("sidebar.exportSummary.destination"),
                    value: model.outputURL?.lastPathComponent ?? localization.string("sidebar.askWhenExporting")
                )
            }
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
            currentTime: model.previewTime,
            reset: { model.resetExportTrimRange() },
            formatTime: formatTrimTime
        )
        .disabled(model.isExporting || model.exportTrimSourceDuration <= 0)
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

    private func formatFrameRate(_ fps: Double) -> String {
        guard fps.isFinite else { return "0" }
        var text = String(format: "%.3f", fps)
        while text.contains(".") && text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private func formatEstimatedFileSize(duration: TimeInterval, bitRateKbps: Int) -> String {
        let bytes = max(0, duration) * Double(max(0, bitRateKbps)) * 125
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes.rounded()))
    }
}

private enum BottomWorkspaceTab: String, CaseIterable, Identifiable {
    case sync
    case trim
    case output

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .sync:
            return "workspace.sync"
        case .trim:
            return "workspace.trim"
        case .output:
            return "workspace.output"
        }
    }
}
