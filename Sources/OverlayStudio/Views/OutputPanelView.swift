import Foundation
import SwiftUI

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
import OverlayCore

/// 居中弹出的输出 sheet：集中所有输出设置、导出摘要与导出动作。
struct OutputPanelView: View {
    @ObservedObject var model: StudioModel
    @Binding var isCancelExportConfirmationPresented: Bool
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.dismiss) private var dismiss
    @State private var forceCustomResolution = false
    @State private var isAspectRatioLocked = true
    @State private var lockedAspectRatio: Double?
    @State private var widthRefreshGeneration = 0
    @State private var heightRefreshGeneration = 0
    @State private var selectedPresetID: String?
    @State private var presetName = ""

    private var isCustomResolution: Bool {
        forceCustomResolution || model.selectedResolutionPresetID == OutputResolutionPreset.customID
    }

    var body: some View {
        Group {
            if model.isExporting {
                exportingContent
            } else if model.hasExportResult {
                resultContent
            } else {
                configurationContent
            }
        }
        .overlay(alignment: .bottomTrailing) {
            StudioToastOverlay(toasts: model.toasts, dismiss: model.dismissToast)
                .padding(ShellStyle.spacing4)
        }
        .frame(width: 860, height: 620)
        .interactiveDismissDisabled(model.isExporting)
        .alert(localization.string("exportDialog.cancelTitle"), isPresented: $isCancelExportConfirmationPresented) {
            Button(localization.string("exportDialog.confirmCancel"), role: .destructive) {
                model.cancelExport()
            }
            Button(localization.string("common.cancel"), role: .cancel) { }
        } message: {
            Text(localization.string("exportDialog.cancelMessage"))
        }
        .onDisappear {
            if !model.isExporting {
                model.clearExportResult()
            }
        }
    }

    private var configurationContent: some View {
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

            HStack(spacing: 0) {
                presetSidebar
                    .frame(width: 230)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: ShellStyle.spacing3) {
                        pictureCard
                        encodingCard
                        destinationRow
                        ExportSummaryCard(model: model)
                        exportActionFooter
                    }
                    .padding(ShellStyle.spacing6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .controlSize(.small)
    }

    private var presetSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedPresetID) {
                Section(localization.string("output.presets.builtIn")) {
                    ForEach(ExportPreset.builtIn) { preset in
                        presetRow(preset).tag(Optional(preset.id))
                    }
                }

                Section(localization.string("output.presets.user")) {
                    if model.userExportPresets.isEmpty {
                        Text(localization.string("output.presets.userEmpty"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.userExportPresets) { preset in
                            presetRow(preset).tag(Optional(preset.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedPresetID) { id in
                guard let id,
                      let preset = model.exportPresetsForDisplay.first(where: { $0.id == id }) else { return }
                forceCustomResolution = false
                model.applyExportPreset(id: id)
                lockCurrentAspectRatio()
                let name = preset.isBuiltIn
                    ? localization.string("exportPreset.\(preset.id)")
                    : preset.name
                model.showToast(
                    localization.string("status.appliedExportPreset", name),
                    kind: .success
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                TextField(localization.string("output.presets.namePlaceholder"), text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveCurrentPreset)

                HStack(spacing: 8) {
                    Button(action: saveCurrentPreset) {
                        Label(localization.string("output.presets.save"), systemImage: "plus")
                    }
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer(minLength: 0)

                    if let selectedPresetID,
                       model.userExportPresets.contains(where: { $0.id == selectedPresetID }) {
                        Button(role: .destructive) {
                            model.deleteUserExportPreset(id: selectedPresetID)
                            self.selectedPresetID = nil
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help(localization.string("output.presets.delete"))
                        .accessibilityLabel(localization.string("output.presets.delete"))
                    }
                }
            }
            .padding(12)
        }
        .background(.bar)
    }

    private func presetRow(_ preset: ExportPreset) -> some View {
        Label(
            preset.isBuiltIn ? localization.string("exportPreset.\(preset.id)") : preset.name,
            systemImage: preset.exportMode == .overlay ? "square.on.square" : "film"
        )
        .lineLimit(1)
    }

    private func saveCurrentPreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.saveCurrentExportPreset(named: name) else { return }
        selectedPresetID = model.userExportPresets.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }?.id
        presetName = ""
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
        .padding(28)
        .frame(width: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 20) {
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

            resultDetail
            Divider()

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
                    model.clearExportResult()
                    dismiss()
                } label: {
                    Label(localization.string("common.done"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func statusGlyph(systemImage: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.14))
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 48, height: 48)
    }

    private var resultTitle: String {
        if model.lastExportedURL != nil { return localization.string("sidebar.exportDone") }
        if model.lastExportWasCancelled { return localization.string("exportDialog.cancelled") }
        return localization.string("exportDialog.failed")
    }

    private var resultSystemImage: String {
        if model.lastExportedURL != nil { return "checkmark" }
        if model.lastExportWasCancelled { return "xmark" }
        return "exclamationmark"
    }

    private var resultColor: Color {
        if model.lastExportedURL != nil { return .green }
        if model.lastExportWasCancelled { return .secondary }
        return .red
    }

    private var clampedExportProgress: Double {
        guard model.exportProgress.isFinite else { return 0 }
        return min(1, max(0, model.exportProgress))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3_600 {
            return String(format: "%d:%02d:%02d", total / 3_600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
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
                        InlineIntField(
                            value: model.outputWidth,
                            range: 2...16_384,
                            refreshToken: widthRefreshGeneration
                        ) {
                            setOutputWidth($0)
                        }
                        Text(verbatim: "×").foregroundStyle(.secondary)
                        InlineIntField(
                            value: model.outputHeight,
                            range: 2...16_384,
                            refreshToken: heightRefreshGeneration
                        ) {
                            setOutputHeight($0)
                        }
                        Text(verbatim: "px").font(.caption).foregroundStyle(.secondary)
                        Toggle(localization.string("output.lockAspectRatio"), isOn: aspectRatioLockBinding)
                            .toggleStyle(.switch)
                            .fixedSize()
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
        }
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
                    lockCurrentAspectRatio()
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

    private var aspectRatioLockBinding: Binding<Bool> {
        Binding(
            get: { isAspectRatioLocked },
            set: { locked in
                isAspectRatioLocked = locked
                lockedAspectRatio = locked ? currentAspectRatio : nil
            }
        )
    }

    private var currentAspectRatio: Double {
        Double(model.outputWidth) / Double(model.outputHeight)
    }

    private func lockCurrentAspectRatio() {
        isAspectRatioLocked = true
        lockedAspectRatio = currentAspectRatio
    }

    private func setOutputWidth(_ width: Int) {
        let aspectRatio = isAspectRatioLocked ? lockedAspectRatio ?? currentAspectRatio : nil
        lockedAspectRatio = aspectRatio
        model.setOutputWidth(width, lockedAspectRatio: aspectRatio)
        heightRefreshGeneration &+= 1
    }

    private func setOutputHeight(_ height: Int) {
        let aspectRatio = isAspectRatioLocked ? lockedAspectRatio ?? currentAspectRatio : nil
        lockedAspectRatio = aspectRatio
        model.setOutputHeight(height, lockedAspectRatio: aspectRatio)
        widthRefreshGeneration &+= 1
    }
}

/// 面板内联整数输入：只用纯数字文本，避免千分位逗号；失焦或回车时提交并夹取。
private struct InlineIntField: View {
    var value: Int
    var range: ClosedRange<Int>
    var refreshToken = 0
    var set: (Int) -> Void

    var body: some View {
        IntegerTextField(
            value: value,
            range: range,
            width: 74,
            publishesValidDraft: true,
            refreshToken: refreshToken,
            set: set
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
