import Foundation
import SwiftUI
import OverlayCore

/// 顶部“输出”按钮弹出的输出面板：集中所有输出设置、导出摘要与导出动作。
struct OutputPanelView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    private let columns = [
        GridItem(.flexible(minimum: 200), spacing: 14, alignment: .top),
        GridItem(.flexible(minimum: 200), spacing: 14, alignment: .top)
    ]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                outputSettingsSection
                    .disabled(model.isExporting)

                SidebarDivider()

                ExportSummaryCard(model: model)

                SidebarDivider()

                exportActionFooter
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .frame(minHeight: 360, idealHeight: 520, maxHeight: 620)
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
                    accessory: .disclosure,
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

    private var exportActionFooter: some View {
        let hasVideo = model.videoURL != nil

        return HStack(alignment: .top, spacing: 10) {
            exportActionSlot(
                mode: .overlay,
                titleKey: "sidebar.exportOverlay",
                helpKey: "help.exportTransparentOverlay",
                systemImage: "square.on.square",
                isPrimary: !hasVideo
            )
            if hasVideo {
                exportActionSlot(
                    mode: .video,
                    titleKey: "sidebar.exportVideo",
                    helpKey: "help.exportCompositedVideo",
                    systemImage: "play.fill",
                    isPrimary: true
                )
            }
        }
        .frame(maxWidth: .infinity)
        .controlSize(.large)
    }

    private func exportActionSlot(
        mode: OverlayExportMode,
        titleKey: String,
        helpKey: String,
        systemImage: String,
        isPrimary: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            exportButton(
                mode: mode,
                titleKey: titleKey,
                helpKey: helpKey,
                systemImage: systemImage,
                isPrimary: isPrimary
            )

            if !model.isExporting, let message = model.exportReadinessMessage(for: mode) {
                Label(message, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(localization.string("sidebar.exportDisabled"))
                    .accessibilityValue(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func exportButton(
        mode: OverlayExportMode,
        titleKey: String,
        helpKey: String,
        systemImage: String,
        isPrimary: Bool
    ) -> some View {
        let label = Label(localization.string(titleKey), systemImage: systemImage)
            .frame(maxWidth: .infinity)
        let button = Button { model.export(as: mode) } label: { label }
            .disabled(model.isExporting || !model.canExport(as: mode))
            .help(model.exportReadinessMessage(for: mode) ?? localization.string(helpKey))

        if isPrimary {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
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
}

/// 导出摘要卡片：输出栏与裁剪栏共用。
struct ExportSummaryCard: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    private let columns = [
        GridItem(.flexible(minimum: 200), spacing: 14, alignment: .top),
        GridItem(.flexible(minimum: 200), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localization.string("sidebar.exportSummary"), systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
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
        .shellGroupSurface(cornerRadius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string("sidebar.exportSummary"))
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

    private func formatEstimatedFileSize(duration: TimeInterval, bitRateKbps: Int) -> String {
        let bytes = max(0, duration) * Double(max(0, bitRateKbps)) * 125
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes.rounded()))
    }
}
