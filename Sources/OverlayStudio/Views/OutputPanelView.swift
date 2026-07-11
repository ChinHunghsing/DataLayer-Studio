import Foundation
import SwiftUI
import OverlayCore

/// 居中弹出的输出 sheet：集中所有输出设置、导出摘要与导出动作。
struct OutputPanelView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss
    @State private var forceCustomResolution = false

    private var isCustomResolution: Bool {
        forceCustomResolution || model.selectedResolutionPresetID == OutputResolutionPreset.customID
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(localization.string("toolbar.output"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                Spacer(minLength: 8)
                Button(localization.string("common.done")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                pictureCard
                    .disabled(model.isExporting)
                encodingCard
                    .disabled(model.isExporting)
                destinationRow
                    .disabled(model.isExporting)

                ExportSummaryCard(model: model)

                exportActionFooter
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: 画面

    private var pictureCard: some View {
        settingsCard(title: localization.string("output.section.picture"), systemImage: "aspectratio") {
            settingRow(localization.string("sidebar.resolution")) {
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
                .fixedSize()
            }

            if isCustomResolution {
                rowDivider
                settingRow(localization.string("output.dimensions")) {
                    HStack(spacing: 6) {
                        InlineIntField(value: model.outputWidth, range: 2...16_384) { model.setOutputWidth($0) }
                        Text(verbatim: "×").foregroundStyle(.secondary)
                        InlineIntField(value: model.outputHeight, range: 2...16_384) { model.setOutputHeight($0) }
                        Text(verbatim: "px").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            rowDivider
            settingRow(localization.string("sidebar.frameRate")) {
                Picker(localization.string("sidebar.frameRate"), selection: frameRatePresetSelection) {
                    if let sourceTitle = model.sourceFrameRatePresetTitle {
                        Text(sourceTitle).tag(OutputFrameRatePreset.sourceID)
                    }
                    ForEach(OutputFrameRatePreset.fixed) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    // MARK: 编码与单位

    private var encodingCard: some View {
        settingsCard(title: localization.string("output.section.encoding"), systemImage: "slider.horizontal.3") {
            settingRow(localization.string("output.renderScope")) {
                Picker(localization.string("output.renderScope"), selection: $model.exportRenderScope) {
                    ForEach(ExportRenderScope.allCases) { scope in
                        Text(localization.string(scope.localizationKey)).tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .help(localization.string("help.renderScope"))
            }
            rowDivider
            settingRow(localization.string("sidebar.codec")) {
                Picker(localization.string("sidebar.codec"), selection: $model.codec) {
                    ForEach(model.availableCodecs) { codec in
                        Text(localization.string(codec.localizationKey)).tag(codec)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            rowDivider
            settingRow(localization.string("sidebar.bitrate")) {
                HStack(spacing: 6) {
                    InlineIntField(value: model.bitRateKbps, range: 1...1_000_000) { model.setBitRateKbps($0) }
                    Text(verbatim: "kbps").font(.caption).foregroundStyle(.secondary)
                }
            }
            rowDivider
            settingRow(localization.string("sidebar.distanceUnit")) {
                Picker(localization.string("sidebar.distanceUnit"), selection: distanceUnitSelection) {
                    ForEach(OverlayDistanceUnit.allCases) { unit in
                        Text(localization.string(unit.localizationKey)).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private var distanceUnitSelection: Binding<OverlayDistanceUnit> {
        Binding(
            get: { model.distanceUnitForCurrentSelection },
            set: { model.setDistanceUnitForCurrentSelection($0) }
        )
    }

    private var destinationRow: some View {
        FilePickRow(
            title: localization.string("sidebar.saveAs"),
            subtitle: model.outputURL?.lastPathComponent ?? localization.string("sidebar.askWhenExporting"),
            systemImage: "square.and.arrow.down",
            isLoaded: model.outputURL != nil,
            accessory: .disclosure,
            action: model.chooseOutput
        )
    }

    // MARK: 组件

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            content()
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shellGroupSurface()
    }

    private func settingRow<Control: View>(
        _ label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var rowDivider: some View {
        Divider().padding(.horizontal, 12)
    }

    private var exportActionFooter: some View {
        let hasVideo = model.currentTimelineProject.tracks.contains {
            $0.kind == .video && !$0.clips.isEmpty
        }

        return HStack(alignment: .top, spacing: 10) {
            exportActionSlot(
                mode: .overlay,
                titleKey: "sidebar.exportOverlay",
                helpKey: "help.exportTransparentOverlay",
                systemImage: "square.on.square"
            )
            if hasVideo {
                exportActionSlot(
                    mode: .video,
                    titleKey: "sidebar.exportVideo",
                    helpKey: "help.exportCompositedVideo",
                    systemImage: "play.fill"
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
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            exportButton(
                mode: mode,
                titleKey: titleKey,
                helpKey: helpKey,
                systemImage: systemImage
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

    private func exportButton(
        mode: OverlayExportMode,
        titleKey: String,
        helpKey: String,
        systemImage: String
    ) -> some View {
        let label = Label(localization.string(titleKey), systemImage: systemImage)
            .frame(maxWidth: .infinity)
        // 导出视频与导出浮层使用同一种蓝色主按钮样式，避免两个动作视觉权重不一致。
        return Button { model.export(as: mode) } label: { label }
            .disabled(model.isExporting || !model.canExport(as: mode))
            .help(model.exportReadinessMessage(for: mode) ?? localization.string(helpKey))
            .buttonStyle(.borderedProminent)
    }

    private var resolutionPresetSelection: Binding<String> {
        Binding(
            get: { isCustomResolution ? OutputResolutionPreset.customID : model.selectedResolutionPresetID },
            set: { newID in
                if newID == OutputResolutionPreset.customID {
                    forceCustomResolution = true
                } else {
                    forceCustomResolution = false
                    model.applyResolutionPreset(id: newID)
                }
            }
        )
    }

    private var frameRatePresetSelection: Binding<String> {
        Binding(
            get: { model.selectedFrameRatePresetID },
            set: { model.applyFrameRatePreset(id: $0) }
        )
    }
}

/// 面板内联整数输入：只用纯数字文本，避免千分位逗号；失焦或回车时提交并夹取。
private struct InlineIntField: View {
    var value: Int
    var range: ClosedRange<Int>
    var set: (Int) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 74)
            .focused($focused)
            .onSubmit(commit)
            .onAppear { draft = String(value) }
            .onChange(of: draft) { _ in publishValidDraft() }
            .onChange(of: value) { newValue in
                if !focused { draft = String(newValue) }
            }
            .onChange(of: focused) { isFocused in
                if isFocused {
                    draft = String(value)
                } else {
                    commit()
                }
            }
    }

    private func publishValidDraft() {
        guard focused,
              let parsed = Int(draft),
              range.contains(parsed) else { return }
        set(parsed)
    }

    private func commit() {
        guard let parsed = Int(draft.filter(\.isNumber)), draft.contains(where: \.isNumber) else {
            draft = String(value)
            return
        }
        let clamped = min(range.upperBound, max(range.lowerBound, parsed))
        set(clamped)
        draft = String(clamped)
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
                    title: localization.string("sidebar.exportSummary.codec"),
                    value: localization.string(model.codec.localizationKey)
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
                    title: localization.string("output.renderScope"),
                    value: localization.string(model.exportRenderScope.localizationKey)
                )
                SidebarSummaryRow(
                    title: localization.string("sidebar.exportSummary.estimatedSize"),
                    value: formatEstimatedFileSize(bytes: model.estimatedExportFileSizeBytes)
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

    private func formatEstimatedFileSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
