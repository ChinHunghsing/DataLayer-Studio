import SwiftUI
import OverlayCore

struct SidebarView: View {
    @ObservedObject var model: StudioModel
    @State private var layoutPresetName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                fileSection
                syncSection
                previewSection
                layoutPresetSection
                outputSection
                exportSection
            }
            .padding(18)
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Inputs", systemImage: "folder")

            FilePickRow(
                title: "Video",
                subtitle: model.videoURL?.lastPathComponent ?? "Choose source video",
                action: model.chooseVideo
            )

            FilePickRow(
                title: "FIT",
                subtitle: model.fitURL?.lastPathComponent ?? "Choose activity.fit",
                action: model.chooseFIT
            )
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Time Sync", systemImage: "timer")

            Picker("Mode", selection: $model.syncMode) {
                ForEach(SyncMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Button {
                model.markSportStart()
            } label: {
                Label("运动开始", systemImage: "figure.run.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.player == nil)

            switch model.syncMode {
            case .offset:
                NumberField(title: "Offset", suffix: "s", value: $model.offsetSeconds)
                Text("Positive means video starts before FIT. Negative means video starts mid-activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .fitStart:
                NumberField(title: "Video 0 = FIT", suffix: "s", value: $model.fitStartSeconds)
            case .syncPoint:
                NumberField(title: "Video point", suffix: "s", value: $model.syncVideoSeconds)
                NumberField(title: "FIT point", suffix: "s", value: $model.syncFITSeconds)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Output", systemImage: "slider.horizontal.3")

            Picker("Resolution", selection: resolutionPresetSelection) {
                if let sourceTitle = model.sourceResolutionPresetTitle {
                    Text(sourceTitle).tag(OutputResolutionPreset.sourceID)
                }
                ForEach(OutputResolutionPreset.fixed) { preset in
                    Text(preset.title).tag(preset.id)
                }
                Text("Custom").tag(OutputResolutionPreset.customID)
            }
            .pickerStyle(.menu)

            HStack {
                NumberIntField(title: "W", value: $model.outputWidth)
                NumberIntField(title: "H", value: $model.outputHeight)
            }

            Picker("Frame rate", selection: frameRatePresetSelection) {
                if let sourceTitle = model.sourceFrameRatePresetTitle {
                    Text(sourceTitle).tag(OutputFrameRatePreset.sourceID)
                }
                ForEach(OutputFrameRatePreset.fixed) { preset in
                    Text(preset.title).tag(preset.id)
                }
                Text("Custom").tag(OutputFrameRatePreset.customID)
            }
            .pickerStyle(.menu)

            NumberField(title: "FPS", suffix: "fps", value: $model.outputFPS)
            NumberField(title: "Duration", suffix: "s", value: $model.outputDuration)

            NumberIntField(title: "Bitrate", suffix: "kbps", value: $model.bitRateKbps)

            Picker("Distance unit", selection: $model.distanceUnit) {
                ForEach(OverlayDistanceUnit.allCases) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            Picker("Codec", selection: $model.codec) {
                ForEach(OverlayVideoCodec.allCases) { codec in
                    Text(codec.displayName).tag(codec)
                }
            }

            FilePickRow(
                title: "Save as",
                subtitle: model.outputURL?.lastPathComponent ?? "Choose overlay.mov",
                action: model.chooseOutput
            )
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Preview Grid", systemImage: "grid")

            Toggle("Show grid", isOn: $model.showGrid)
            Toggle("Snap while dragging", isOn: $model.snapGaugeToGrid)

            Stepper("Columns: \(model.gridColumns)", value: $model.gridColumns, in: 2...64)
            Stepper("Rows: \(model.gridRows)", value: $model.gridRows, in: 2...64)
        }
    }

    private var layoutPresetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Layout Presets", systemImage: "rectangle.3.group")

            HStack(spacing: 8) {
                TextField("Preset name", text: $layoutPresetName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    if model.saveLayoutPreset(named: layoutPresetName) {
                        layoutPresetName = ""
                    }
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .help("Save current layout")
                .disabled(layoutPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                Button {
                    model.importLayoutPresets()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.exportLayoutPresets()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.layoutPresets.isEmpty)
            }
            .buttonStyle(.bordered)

            if model.layoutPresets.isEmpty {
                Text("No saved presets.")
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

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Render", systemImage: "paperplane")
            if model.isExporting {
                ProgressView(value: model.exportProgress)
            }
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Button {
                model.export()
            } label: {
                Label(model.isExporting ? "Exporting..." : "Export Overlay", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canExport || model.isExporting)
        }
    }
}

struct SectionHeader: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }
}

struct FilePickRow: View {
    var title: String
    var subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LayoutPresetRow: View {
    var preset: LayoutPreset
    var isDefault: Bool
    var apply: () -> Void
    var makeDefault: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                Text("\(preset.layout.elements.count) gauges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: apply) {
                Label("Apply", systemImage: "arrow.down.left.and.arrow.up.right")
                    .labelStyle(.iconOnly)
            }
            .help("Apply preset")

            Button(action: makeDefault) {
                Label("Set default", systemImage: isDefault ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
            }
            .help("Set as default")
            .disabled(isDefault)

            Button(role: .destructive, action: delete) {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Delete preset")
        }
        .buttonStyle(.borderless)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct NumberField: View {
    var title: String
    var suffix: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...3)))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 92)
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
        }
    }
}

struct NumberIntField: View {
    var title: String
    var suffix: String?
    @Binding var value: Int

    init(title: String, suffix: String? = nil, value: Binding<Int>) {
        self.title = title
        self.suffix = suffix
        self._value = value
    }

    var body: some View {
        HStack {
            Text(title)
            TextField(title, value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)
            }
        }
    }
}
