import SwiftUI
import OverlayCore

struct SidebarView: View {
    @ObservedObject var model: StudioModel
    @State private var layoutPresetName = ""

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                SidebarWorkflowSection(
                    step: "1",
                    title: "Source",
                    subtitle: "Video and FIT activity data",
                    systemImage: "film.stack"
                ) {
                    fileSection
                }
                .disabled(model.isExporting)

                SidebarWorkflowSection(
                    step: "2",
                    title: "Sync",
                    subtitle: "Align recording time with activity time",
                    systemImage: "timer"
                ) {
                    syncSection
                }
                .disabled(model.isExporting)

                SidebarWorkflowSection(
                    step: "3",
                    title: "Canvas",
                    subtitle: "Preview grid and reusable gauge layouts",
                    systemImage: "rectangle.dashed"
                ) {
                    canvasSection
                }

                SidebarWorkflowSection(
                    step: "4",
                    title: "Export",
                    subtitle: "Transparent overlay render settings",
                    systemImage: "paperplane"
                ) {
                    exportWorkflowSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .controlSize(.small)
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilePickRow(
                title: "Video",
                subtitle: model.videoURL?.lastPathComponent ?? "Choose source video",
                systemImage: "film",
                isLoaded: model.videoURL != nil,
                action: model.chooseVideo
            )

            FilePickRow(
                title: "FIT",
                subtitle: model.fitURL?.lastPathComponent ?? "Choose activity.fit",
                systemImage: "figure.run",
                isLoaded: model.fitURL != nil,
                action: model.chooseFIT
            )
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarControl(title: "Mode") {
                Picker("Mode", selection: $model.syncMode) {
                    ForEach(SyncMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Button {
                model.markSportStart()
            } label: {
                Label("运动开始", systemImage: "figure.run.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.player == nil || model.isExporting)

            switch model.syncMode {
            case .offset:
                NumberField(title: "Offset", suffix: "s", value: doubleBinding(
                    get: { model.offsetSeconds },
                    set: { model.offsetSeconds = $0 },
                    range: -86_400...86_400
                ))
                Text("Positive means video starts before FIT. Negative means video starts mid-activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .fitStart:
                NumberField(title: "Video 0 = FIT", suffix: "s", value: doubleBinding(
                    get: { model.fitStartSeconds },
                    set: { model.fitStartSeconds = $0 },
                    range: 0...86_400
                ))
            case .syncPoint:
                NumberField(title: "Video point", suffix: "s", value: doubleBinding(
                    get: { model.syncVideoSeconds },
                    set: { model.syncVideoSeconds = $0 },
                    range: 0...86_400
                ))
                NumberField(title: "FIT point", suffix: "s", value: doubleBinding(
                    get: { model.syncFITSeconds },
                    set: { model.syncFITSeconds = $0 },
                    range: 0...86_400
                ))
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarSubsectionHeader(title: "Video", systemImage: "slider.horizontal.3")

            SidebarControl(title: "Resolution") {
                Picker("Resolution", selection: resolutionPresetSelection) {
                    if let sourceTitle = model.sourceResolutionPresetTitle {
                        Text(sourceTitle).tag(OutputResolutionPreset.sourceID)
                    }
                    ForEach(OutputResolutionPreset.fixed) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                    Text("Custom").tag(OutputResolutionPreset.customID)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                CompactNumberIntField(title: "Width", suffix: "px", value: intBinding(
                    get: { model.outputWidth },
                    set: { model.setOutputWidth($0) },
                    range: 2...16_384
                ))
                CompactNumberIntField(title: "Height", suffix: "px", value: intBinding(
                    get: { model.outputHeight },
                    set: { model.setOutputHeight($0) },
                    range: 2...16_384
                ))
            }

            SidebarControl(title: "Frame rate") {
                Picker("Frame rate", selection: frameRatePresetSelection) {
                    if let sourceTitle = model.sourceFrameRatePresetTitle {
                        Text(sourceTitle).tag(OutputFrameRatePreset.sourceID)
                    }
                    ForEach(OutputFrameRatePreset.fixed) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                    Text("Custom").tag(OutputFrameRatePreset.customID)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            NumberField(title: "FPS", suffix: "fps", value: doubleBinding(
                get: { model.outputFPS },
                set: { model.setOutputFPS($0) },
                range: 1...240
            ))
            NumberField(title: "Duration", suffix: "s", value: doubleBinding(
                get: { model.outputDuration },
                set: { model.setOutputDuration($0) },
                range: 0.1...86_400
            ))

            NumberIntField(title: "Bitrate", suffix: "kbps", value: intBinding(
                get: { model.bitRateKbps },
                set: { model.setBitRateKbps($0) },
                range: 1...1_000_000
            ))

            SidebarControl(title: "Distance unit") {
                Picker("Distance unit", selection: $model.distanceUnit) {
                    ForEach(OverlayDistanceUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SidebarControl(title: "Codec") {
                Picker("Codec", selection: $model.codec) {
                    ForEach(OverlayVideoCodec.allCases) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
                .labelsHidden()
            }

            SidebarSubsectionHeader(title: "Destination", systemImage: "folder")

            FilePickRow(
                title: "Save as",
                subtitle: model.outputURL?.lastPathComponent ?? "Ask when exporting",
                systemImage: "square.and.arrow.down",
                isLoaded: model.outputURL != nil,
                action: model.chooseOutput
            )
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarSubsectionHeader(title: "Grid", systemImage: "grid")

            Toggle("Show grid", isOn: $model.showGrid)
            Toggle("Snap while dragging", isOn: $model.snapGaugeToGrid)

            SidebarStepperRow(
                title: "Columns",
                value: Binding(
                    get: { model.gridColumns },
                    set: { model.setGridColumns($0) }
                ),
                range: 2...64
            )
            SidebarStepperRow(
                title: "Rows",
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
            SidebarSubsectionHeader(title: "Presets", systemImage: "rectangle.3.group")

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
            SidebarSubsectionHeader(title: "Render", systemImage: "paperplane")

            if model.isExporting {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: clampedExportProgress)
                    HStack {
                        Text("Exporting overlay")
                        Spacer()
                        Text(clampedExportProgress.percentString)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Export progress")
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
                    .accessibilityLabel("Export disabled")
                    .accessibilityValue(exportReadinessMessage)
            }

            if model.isExporting {
                Button(role: .destructive) {
                    model.cancelExport()
                } label: {
                    Label("Cancel Export", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            } else {
                Button {
                    model.export()
                } label: {
                    Label("Export Overlay", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
                .help(model.exportReadinessMessage ?? "Export transparent overlay video")
            }
        }
    }

    private var clampedExportProgress: Double {
        guard model.exportProgress.isFinite else { return 0 }
        return min(1, max(0, model.exportProgress))
    }
}

struct SidebarWorkflowSection<Content: View>: View {
    var step: String
    var title: String
    var subtitle: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(step)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarSubsectionHeader: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct SidebarDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 2)
    }
}

struct FilePickRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var isLoaded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isLoaded ? Color.accentColor : Color.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: isLoaded ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isLoaded ? Color.accentColor : Color.secondary.opacity(0.65))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SidebarStepperRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .frame(width: SidebarFormMetrics.labelWidth, alignment: .leading)

            Text("\(value)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)

            Spacer(minLength: 8)

            Stepper(title, value: $value, in: range)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarControl<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LayoutPresetRow: View {
    var preset: LayoutPreset
    var isDefault: Bool
    var apply: () -> Void
    var makeDefault: () -> Void
    var delete: () -> Void
    @State private var isConfirmingDelete = false

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

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Delete preset")
        }
        .buttonStyle(.borderless)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            "Delete layout preset?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(preset.name)", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved preset. The current canvas layout is not changed.")
        }
    }
}

struct NumberField: View {
    var title: String
    var suffix: String
    @Binding var value: Double
    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .frame(width: SidebarFormMetrics.labelWidth, alignment: .leading)
            TextField(title, text: $draftText)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 96, maxWidth: .infinity)
                .focused($isFocused)
                .onSubmit(commitDraft)
            Text(suffix)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: SidebarFormMetrics.shortSuffixWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            draftText = NumberTextFormatter.formatDouble(value)
        }
        .onChange(of: value) { _ in
            guard !isFocused else { return }
            draftText = NumberTextFormatter.formatDouble(value)
        }
        .onChange(of: isFocused) { focused in
            if focused {
                draftText = NumberTextFormatter.formatDouble(value)
            } else {
                commitDraft()
            }
        }
    }

    private func commitDraft() {
        guard let parsed = NumberTextFormatter.parseDouble(draftText) else {
            draftText = NumberTextFormatter.formatDouble(value)
            return
        }
        value = parsed
        draftText = NumberTextFormatter.formatDouble(value)
    }
}

struct NumberIntField: View {
    var title: String
    var suffix: String?
    @Binding var value: Int
    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    init(title: String, suffix: String? = nil, value: Binding<Int>) {
        self.title = title
        self.suffix = suffix
        self._value = value
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .frame(width: SidebarFormMetrics.labelWidth, alignment: .leading)
            TextField(title, text: $draftText)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 96, maxWidth: .infinity)
                .focused($isFocused)
                .onSubmit(commitDraft)
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: SidebarFormMetrics.longSuffixWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            draftText = NumberTextFormatter.formatInt(value)
        }
        .onChange(of: value) { _ in
            guard !isFocused else { return }
            draftText = NumberTextFormatter.formatInt(value)
        }
        .onChange(of: isFocused) { focused in
            if focused {
                draftText = NumberTextFormatter.formatInt(value)
            } else {
                commitDraft()
            }
        }
    }

    private func commitDraft() {
        guard let parsed = NumberTextFormatter.parseInt(draftText) else {
            draftText = NumberTextFormatter.formatInt(value)
            return
        }
        value = parsed
        draftText = NumberTextFormatter.formatInt(value)
    }
}

struct CompactNumberIntField: View {
    var title: String
    var suffix: String
    @Binding var value: Int
    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                TextField(title, text: $draftText)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 92)
                    .focused($isFocused)
                    .onSubmit(commitDraft)

                Text(suffix)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: SidebarFormMetrics.shortSuffixWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            draftText = NumberTextFormatter.formatInt(value)
        }
        .onChange(of: value) { _ in
            guard !isFocused else { return }
            draftText = NumberTextFormatter.formatInt(value)
        }
        .onChange(of: isFocused) { focused in
            if focused {
                draftText = NumberTextFormatter.formatInt(value)
            } else {
                commitDraft()
            }
        }
    }

    private func commitDraft() {
        guard let parsed = NumberTextFormatter.parseInt(draftText) else {
            draftText = NumberTextFormatter.formatInt(value)
            return
        }
        value = parsed
        draftText = NumberTextFormatter.formatInt(value)
    }
}

private enum SidebarFormMetrics {
    static let labelWidth: CGFloat = 94
    static let shortSuffixWidth: CGFloat = 34
    static let longSuffixWidth: CGFloat = 54
}
