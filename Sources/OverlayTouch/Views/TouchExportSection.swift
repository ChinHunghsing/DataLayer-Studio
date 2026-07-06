#if os(iOS)
import OverlayCore
import SwiftUI

/// 导出设置、进度与结果卡片（左栏底部分区）。
struct TouchExportSection: View {
    @ObservedObject var model: TouchStudioModel
    let localizer: TouchLocalizer

    @State private var isSavingToPhotos = false
    @State private var photosSaveMessage: String?

    var body: some View {
        Section {
            if model.isExporting {
                exportingContent
            } else {
                settingsContent
            }
            if model.hasExportResult, !model.isExporting {
                resultContent
            }
        } header: {
            Text(localizer.string("export.title"))
        } footer: {
            Text(localizer.string("export.inFiles"))
                .font(.caption)
        }
    }

    // MARK: - 设置

    @ViewBuilder
    private var settingsContent: some View {
        Picker(localizer.string("export.codec"), selection: $model.codec) {
            ForEach(model.availableCodecs) { codec in
                Text(codec.displayName).tag(codec)
            }
        }

        Picker(localizer.string("export.resolution"), selection: Binding(
            get: { model.selectedResolutionPresetID },
            set: { model.applyResolutionPreset(id: $0) }
        )) {
            if model.sourceDimensions != nil {
                Text(localizer.string("export.source")).tag(TouchResolutionPreset.sourceID)
            }
            ForEach(TouchResolutionPreset.fixed) { preset in
                Text(preset.title).tag(preset.id)
            }
            if model.selectedResolutionPresetID == TouchResolutionPreset.customID {
                Text(localizer.string("export.custom")).tag(TouchResolutionPreset.customID)
            }
        }

        LabeledContent(localizer.string("export.resolution")) {
            HStack(spacing: 6) {
                TextField(
                    localizer.string("export.width"),
                    value: Binding(get: { model.outputWidth }, set: { model.setOutputWidth($0) }),
                    format: .number.grouping(.never)
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 76)
                Text("×")
                    .foregroundStyle(.secondary)
                TextField(
                    localizer.string("export.height"),
                    value: Binding(get: { model.outputHeight }, set: { model.setOutputHeight($0) }),
                    format: .number.grouping(.never)
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 76)
            }
        }

        Picker(localizer.string("export.frameRate"), selection: Binding(
            get: { model.selectedFrameRatePresetID },
            set: { model.applyFrameRatePreset(id: $0) }
        )) {
            if model.metadata != nil {
                Text(localizer.string("export.source")).tag(TouchFrameRatePreset.sourceID)
            }
            ForEach(TouchFrameRatePreset.fixed) { preset in
                Text(preset.title).tag(preset.id)
            }
            if model.selectedFrameRatePresetID == TouchFrameRatePreset.customID {
                Text(localizer.string("export.custom")).tag(TouchFrameRatePreset.customID)
            }
        }

        LabeledContent(localizer.string("export.bitrate")) {
            TextField(
                localizer.string("export.bitrate"),
                value: Binding(get: { model.bitRateKbps }, set: { model.setBitRateKbps($0) }),
                format: .number.grouping(.never)
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110)
        }

        trimRow(
            labelKey: "export.rangeStart",
            value: model.effectiveExportTrimStart,
            setValue: { model.setExportTrimStart($0) }
        )
        trimRow(
            labelKey: "export.rangeEnd",
            value: model.effectiveExportTrimEnd,
            setValue: { model.setExportTrimEnd($0) }
        )

        if let readiness = model.exportReadinessMessage {
            Label(localizer.format(readiness), systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Button {
            model.export()
        } label: {
            Label(localizer.string("export.start"), systemImage: "square.and.arrow.up.on.square")
                .frame(maxWidth: .infinity)
        }
        .keyboardShortcut("e", modifiers: .command)
        .buttonStyle(.borderedProminent)
        .disabled(!model.canExport)
    }

    private func trimRow(
        labelKey: String,
        value: TimeInterval,
        setValue: @escaping (TimeInterval) -> Void
    ) -> some View {
        LabeledContent(localizer.string(labelKey)) {
            HStack(spacing: 8) {
                Button(localizer.string("export.useCurrentFrame")) {
                    setValue(model.previewTime)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                TextField(
                    localizer.string(labelKey),
                    value: Binding(get: { value }, set: { setValue($0) }),
                    format: .number.precision(.fractionLength(0...3)).grouping(.never)
                )
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            }
        }
    }

    // MARK: - 导出中

    @ViewBuilder
    private var exportingContent: some View {
        ProgressView(value: model.exportProgress) {
            Text(localizer.format(model.statusMessage))
                .font(.callout)
        } currentValueLabel: {
            HStack {
                Text("\(Int((model.exportProgress * 100).rounded()))%")
                if let eta = model.exportETASeconds {
                    Text(localizer.format(TouchMessage("export.eta", [TouchStudioModel.formatSeconds(eta)])))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text(localizer.string("export.keepForeground"))
            .font(.caption)
            .foregroundStyle(.secondary)

        if model.thermalStateIsSerious {
            Label(localizer.string("export.thermalWarning"), systemImage: "thermometer.high")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        Button(localizer.string("export.cancel"), role: .destructive) {
            model.cancelExport()
        }
        .keyboardShortcut(".", modifiers: .command)
    }

    // MARK: - 结果

    @ViewBuilder
    private var resultContent: some View {
        if let exportedURL = model.lastExportedURL {
            VStack(alignment: .leading, spacing: 6) {
                Label(exportedURL.lastPathComponent, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let elapsed = model.lastExportElapsedSeconds {
                    Text(localizer.format(TouchMessage("export.elapsed", [TouchStudioModel.formatSeconds(elapsed)])))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ShareLink(item: exportedURL) {
                Label(localizer.string("export.share"), systemImage: "square.and.arrow.up")
            }

            Button {
                saveToPhotos(exportedURL)
            } label: {
                if isSavingToPhotos {
                    ProgressView()
                } else {
                    Label(localizer.string("export.saveToPhotos"), systemImage: "photo.badge.plus")
                }
            }
            .disabled(isSavingToPhotos)

            if let photosSaveMessage {
                Text(photosSaveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let errorMessage = model.lastExportErrorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        } else if model.lastExportWasCancelled {
            Label(localizer.string("status.exportCancelled"), systemImage: "xmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func saveToPhotos(_ url: URL) {
        isSavingToPhotos = true
        photosSaveMessage = nil
        Task { @MainActor in
            defer { isSavingToPhotos = false }
            do {
                try await TouchPhotoLibrarySaver.saveVideo(at: url)
                photosSaveMessage = localizer.string("export.savedToPhotos")
            } catch {
                photosSaveMessage = localizer.format(
                    TouchMessage("export.saveToPhotosFailed", [error.localizedDescription])
                )
            }
        }
    }
}
#endif
