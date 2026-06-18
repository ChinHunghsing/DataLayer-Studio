import SwiftUI
import OverlayCore

struct InspectorView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var expandedSections = Set(InspectorSection.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                selectedElementHeader
                Divider()
                selectedElementSettings
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var selectedElementHeader: some View {
        HStack(spacing: 12) {
            if let element = model.selectedElement {
                Image(systemName: element.kind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(elementDisplayTitle(element))
                        .font(.headline)
                        .lineLimit(1)
                    Text(localization.string(element.kind.localizationKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.string("inspector.noSelection.title"))
                        .font(.headline)
                    Text(localization.string("inspector.noSelection.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                ForEach(OverlayComponentID.allCases) { component in
                    Button {
                        model.addElement(kind: component)
                    } label: {
                        Label(localization.string(component.localizationKey), systemImage: component.systemImage)
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .disabled(model.isExporting)
            .help(localization.string("inspector.addElement"))

            Button {
                model.duplicateSelectedElement()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(model.selectedElement == nil || model.isExporting)
            .help(localization.string("inspector.duplicate"))

            Button {
                model.moveSelectedElementBackward()
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(!canMoveSelectedElementBackward || model.isExporting)
            .help(localization.string("inspector.sendBackward"))

            Button {
                model.moveSelectedElementForward()
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!canMoveSelectedElementForward || model.isExporting)
            .help(localization.string("inspector.bringForward"))

            Button(role: .destructive) {
                model.deleteSelectedElement()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(model.selectedElement == nil || model.isExporting)
            .help(localization.string("inspector.delete"))
        }
        .buttonStyle(.borderless)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var selectedElementSettings: some View {
        if let element = model.selectedElement {
            settings(for: element)
                .id(element.id)
                .disabled(model.isExporting)
        } else {
            Text(localization.string("inspector.noSelection.message"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedElementIndex: Int? {
        guard let selectedElementID = model.selectedElementID else { return nil }
        return model.layout.elements.firstIndex { $0.id == selectedElementID }
    }

    private var canMoveSelectedElementBackward: Bool {
        guard let selectedElementIndex else { return false }
        return selectedElementIndex > 0
    }

    private var canMoveSelectedElementForward: Bool {
        guard let selectedElementIndex else { return false }
        return selectedElementIndex < model.layout.elements.count - 1
    }

    @ViewBuilder
    private func settings(for element: OverlayElement) -> some View {
        let id = element.id
        let kind = element.kind

        InspectorGroup(section: .layout, expandedSections: $expandedSections) {
            Toggle(localization.string("inspector.visible"), isOn: boolBinding(
                id: id,
                get: { $0.frame.isVisible },
                set: { $0.frame.isVisible = $1 }
            ))

            LabeledSlider(
                title: "X",
                value: doubleBinding(id: id, get: { $0.frame.x }, set: { $0.frame.x = $1 }),
                range: PreviewLayoutLimits.positionRange,
                label: (currentElement(id)?.frame.x ?? 0).percentString,
                showsTextField: true
            )

            LabeledSlider(
                title: "Y",
                value: doubleBinding(id: id, get: { $0.frame.y }, set: { $0.frame.y = $1 }),
                range: PreviewLayoutLimits.positionRange,
                label: (currentElement(id)?.frame.y ?? 0).percentString,
                showsTextField: true
            )

            LabeledSlider(
                title: localization.string("inspector.size"),
                value: doubleBinding(id: id, get: { $0.frame.scale }, set: { $0.frame.scale = $1 }),
                range: 0.45...1.8,
                label: "\(Int(((currentElement(id)?.frame.scale ?? 1) * 100).rounded()))%"
            )

            if kind.supportsLengthScale {
                LabeledSlider(
                    title: localization.string("inspector.length"),
                    value: doubleBinding(id: id, get: { $0.customization.lengthScale }, set: { $0.customization.lengthScale = $1 }),
                    range: 0.2...2.4,
                    label: "\(Int(((currentElement(id)?.customization.lengthScale ?? 1) * 100).rounded()))%",
                    showsTextField: true
                )
            }
        }

        InspectorGroup(section: .content, expandedSections: $expandedSections) {
            Toggle(localization.string("inspector.label"), isOn: boolBinding(
                id: id,
                get: { $0.customization.showsLabel },
                set: { $0.customization.showsLabel = $1 }
            ))

            if currentElement(id)?.customization.showsLabel == true {
                TextField(localization.string("inspector.labelText"), text: stringBinding(
                    id: id,
                    get: { $0.customization.labelOverride ?? "" },
                    set: { element, value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        element.customization.labelOverride = trimmed.isEmpty ? nil : trimmed
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            let unitToggleTitle = switch kind {
            case .topProgress:
                localization.string("inspector.endLabel")
            case .timeDate:
                localization.string("inspector.clockAndDate")
            default:
                localization.string("inspector.unit")
            }

            Toggle(unitToggleTitle, isOn: boolBinding(
                id: id,
                get: { $0.customization.showsUnit },
                set: { $0.customization.showsUnit = $1 }
            ))

            if currentElement(id)?.customization.showsUnit == true,
               kind != .topProgress,
               kind != .timeDate {
                TextField(localization.string("inspector.unitText"), text: stringBinding(
                    id: id,
                    get: { $0.customization.unitOverride ?? "" },
                    set: { element, value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        element.customization.unitOverride = trimmed.isEmpty ? nil : trimmed
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Toggle(localization.string("inspector.icon"), isOn: boolBinding(
                id: id,
                get: { $0.customization.showsIcon },
                set: { $0.customization.showsIcon = $1 }
            ))

            if currentElement(id)?.customization.showsIcon == true {
                TextField(localization.string("inspector.iconText"), text: stringBinding(
                    id: id,
                    get: { $0.customization.iconOverride ?? "" },
                    set: { element, value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        element.customization.iconOverride = trimmed.isEmpty ? nil : trimmed
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }

        InspectorGroup(section: .appearance, expandedSections: $expandedSections) {
            Toggle(localization.string("inspector.panel"), isOn: boolBinding(
                id: id,
                get: { $0.customization.showsPanel },
                set: { $0.customization.showsPanel = $1 }
            ))

            if currentElement(id)?.customization.showsPanel == true {
                Toggle(localization.string("inspector.panelBorder"), isOn: boolBinding(
                    id: id,
                    get: { $0.customization.panelBorderIsVisible },
                    set: { $0.customization.showsPanelBorder = $1 }
                ))

                LabeledSlider(
                    title: localization.string("inspector.panelOpacity"),
                    value: doubleBinding(
                        id: id,
                        get: { $0.frame.style.panelOpacity ?? model.layout.style.panelOpacity },
                        set: { $0.frame.style.panelOpacity = $1 }
                    ),
                    range: 0.12...0.95,
                    label: (currentElement(id)?.frame.style.panelOpacity ?? model.layout.style.panelOpacity).percentString
                )
            }

            if kind.supportsLineWidth {
                LabeledSlider(
                    title: kind == .speed ? localization.string("inspector.gaugeWidth") : localization.string("inspector.lineWidth"),
                    value: doubleBinding(id: id, get: { $0.customization.lineWidth }, set: { $0.customization.lineWidth = $1 }),
                    range: kind == .topProgress ? 1...36 : 1...24,
                    label: "\(Int((currentElement(id)?.customization.lineWidth ?? 1).rounded())) px",
                    showsTextField: kind == .topProgress,
                    unitLabel: "px"
                )

                ColorPicker(localization.string("inspector.trackColor"), selection: colorBinding(
                    id: id,
                    fallback: .track,
                    get: { $0.customization.trackColor },
                    set: { $0.customization.trackColor = $1 }
                ))
            }

            if kind == .topProgress {
                ColorPicker(localization.string("inspector.progressColor"), selection: colorBinding(
                    id: id,
                    fallback: defaultValueColor(for: element),
                    get: { $0.customization.valueColor },
                    set: { $0.customization.valueColor = $1 }
                ))

                LabeledSlider(
                    title: localization.string("inspector.sidePadding"),
                    value: doubleBinding(
                        id: id,
                        get: { $0.customization.progressInsetScale ?? 1 },
                        set: { $0.customization.progressInsetScale = $1 }
                    ),
                    range: 0...2,
                    label: "\(Int(((currentElement(id)?.customization.progressInsetScale ?? 1) * 100).rounded()))%"
                )

                LabeledSlider(
                    title: localization.string("inspector.knobSize"),
                    value: doubleBinding(
                        id: id,
                        get: { $0.customization.progressKnobScale ?? 1 },
                        set: { $0.customization.progressKnobScale = $1 }
                    ),
                    range: 0.4...2.4,
                    label: "\(Int(((currentElement(id)?.customization.progressKnobScale ?? 1) * 100).rounded()))%"
                )

                LabeledSlider(
                    title: localization.string("inspector.valueMargin"),
                    value: doubleBinding(
                        id: id,
                        get: { $0.customization.progressValueMarginScale ?? 1 },
                        set: { $0.customization.progressValueMarginScale = $1 }
                    ),
                    range: 0...4,
                    label: "\(Int(((currentElement(id)?.customization.progressValueMarginScale ?? 1) * 100).rounded()))%"
                )

                Toggle(localization.string("inspector.tickMarks"), isOn: boolBinding(
                    id: id,
                    get: { $0.customization.showGaugeTicks ?? false },
                    set: { $0.customization.showGaugeTicks = $1 }
                ))

                if currentElement(id)?.customization.showGaugeTicks == true {
                    LabeledSlider(
                        title: localization.string("inspector.tickCount"),
                        value: doubleBinding(
                            id: id,
                            get: { Double($0.customization.progressTickCount ?? 48) },
                            set: { $0.customization.progressTickCount = Int($1.rounded()) }
                        ),
                        range: 0...120,
                        label: "\(currentElement(id)?.customization.progressTickCount ?? 48)"
                    )
                }
            }
        }

        InspectorGroup(section: .typography, expandedSections: $expandedSections) {
            if currentElement(id)?.customization.showsLabel == true {
                TextStyleRow(
                    title: localization.string("inspector.label"),
                    font: fontBinding(id: id, get: { $0.customization.labelFont }, set: { $0.customization.labelFont = $1 }),
                    color: colorBinding(id: id, fallback: .label, get: { $0.customization.labelColor }, set: { $0.customization.labelColor = $1 }),
                    size: fontSizeBinding(id: id, role: .label, kind: kind),
                    sizeLabel: fontSizeLabel(id: id, role: .label, kind: kind)
                )
            }

            TextStyleRow(
                title: localization.string("inspector.value"),
                font: fontBinding(id: id, get: { $0.customization.valueFont }, set: { $0.customization.valueFont = $1 }),
                color: colorBinding(id: id, fallback: defaultValueColor(for: element), get: { $0.customization.valueColor }, set: { $0.customization.valueColor = $1 }),
                size: fontSizeBinding(id: id, role: .value, kind: kind),
                sizeLabel: fontSizeLabel(id: id, role: .value, kind: kind)
            )

            if currentElement(id)?.customization.showsUnit == true {
                TextStyleRow(
                    title: localization.string("inspector.unit"),
                    font: fontBinding(id: id, get: { $0.customization.unitFont }, set: { $0.customization.unitFont = $1 }),
                    color: colorBinding(id: id, fallback: .muted, get: { $0.customization.unitColor }, set: { $0.customization.unitColor = $1 }),
                    size: fontSizeBinding(id: id, role: .unit, kind: kind),
                    sizeLabel: fontSizeLabel(id: id, role: .unit, kind: kind)
                )
            }

            if currentElement(id)?.customization.showsIcon == true {
                TextStyleRow(
                    title: localization.string("inspector.icon"),
                    font: fontBinding(id: id, get: { $0.customization.iconFont }, set: { $0.customization.iconFont = $1 }),
                    color: colorBinding(id: id, fallback: .label, get: { $0.customization.iconColor }, set: { $0.customization.iconColor = $1 }),
                    size: fontSizeBinding(id: id, role: .icon, kind: kind),
                    sizeLabel: fontSizeLabel(id: id, role: .icon, kind: kind)
                )
            }
        }

        if kind.supportsValuePrecision || kind == .speed {
            InspectorGroup(section: .data, expandedSections: $expandedSections) {
                if kind.supportsValuePrecision {
                    Stepper(
                        localization.string("inspector.decimals", currentElement(id)?.customization.valuePrecision ?? kind.defaultPrecision),
                        value: intBinding(
                            id: id,
                            get: { $0.customization.valuePrecision ?? kind.defaultPrecision },
                            set: { $0.customization.valuePrecision = $1 }
                        ),
                        in: 0...3
                    )
                }

                if kind == .speed {
                    Toggle(localization.string("inspector.gaugeTicks"), isOn: boolBinding(
                        id: id,
                        get: { $0.customization.showGaugeTicks ?? model.layout.style.showGaugeTicks },
                        set: { $0.customization.showGaugeTicks = $1 }
                    ))

                    LabeledSlider(
                        title: localization.string("inspector.gaugeMin"),
                        value: doubleBinding(id: id, get: { $0.customization.gaugeMinimum ?? 0 }, set: { $0.customization.gaugeMinimum = $1 }),
                        range: 0...20,
                        label: "\(Int((currentElement(id)?.customization.gaugeMinimum ?? 0).rounded()))"
                    )

                    LabeledSlider(
                        title: localization.string("inspector.gaugeMax"),
                        value: doubleBinding(id: id, get: { $0.customization.gaugeMaximum ?? 24 }, set: { $0.customization.gaugeMaximum = $1 }),
                        range: 6...60,
                        label: "\(Int((currentElement(id)?.customization.gaugeMaximum ?? 24).rounded()))"
                    )
                }
            }
        }
    }

    private func currentElement(_ id: String) -> OverlayElement? {
        model.layout.elements.first { $0.id == id }
    }

    private func fontSizeLabel(id: String, role: TypographyRole, kind: OverlayComponentID) -> String {
        "\(Int(fontSizeValue(id: id, role: role, kind: kind).rounded())) pt"
    }

    private func fontSizeValue(id: String, role: TypographyRole, kind: OverlayComponentID) -> Double {
        guard let element = currentElement(id) else { return typographyBaseSize(for: kind, role: role) }
        return typographyBaseSize(for: kind, role: role) * scaleValue(for: element, role: role)
    }

    private func scaleValue(for element: OverlayElement, role: TypographyRole) -> Double {
        switch role {
        case .label:
            return element.customization.labelScale
        case .value:
            return element.customization.valueScale
        case .unit:
            return element.customization.unitScale
        case .icon:
            return element.customization.iconScale
        }
    }

    private func typographyBaseSize(for kind: OverlayComponentID, role: TypographyRole) -> Double {
        switch (kind, role) {
        case (.speed, .label):
            return 15
        case (.speed, .value):
            return 76
        case (.speed, .unit):
            return 24
        case (.speed, .icon):
            return 13
        case (.pace, .label), (.distance, .label), (.heartRate, .label), (.cadence, .label):
            return 10
        case (.pace, .value), (.distance, .value), (.heartRate, .value), (.cadence, .value):
            return 23
        case (.pace, .unit), (.distance, .unit), (.heartRate, .unit), (.cadence, .unit):
            return 10
        case (.pace, .icon), (.distance, .icon), (.heartRate, .icon), (.cadence, .icon):
            return 10
        case (.route, .label):
            return 13
        case (.route, .value):
            return 18
        case (.route, .unit):
            return 10
        case (.route, .icon):
            return 12
        case (.topProgress, .label):
            return 15
        case (.topProgress, .value):
            return 12
        case (.topProgress, .unit):
            return 15
        case (.topProgress, .icon):
            return 12
        case (.timeDate, .label):
            return 11
        case (.timeDate, .value):
            return 24
        case (.timeDate, .unit):
            return 22
        case (.timeDate, .icon):
            return 12
        }
    }

    private func elementDisplayTitle(_ element: OverlayElement) -> String {
        element.customization.label(default: localization.string(element.kind.localizationKey))
    }

    private func defaultValueColor(for element: OverlayElement) -> OverlayColor {
        if let color = element.frame.style.accentColor?.overlayColor {
            return color
        }
        return model.layout.style.accentColor.overlayColor
    }

    private func boolBinding(
        id: String,
        get: @escaping (OverlayElement) -> Bool,
        set: @escaping (inout OverlayElement, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { currentElement(id).map(get) ?? false },
            set: { newValue in model.updateElement(id) { set(&$0, newValue) } }
        )
    }

    private func doubleBinding(
        id: String,
        get: @escaping (OverlayElement) -> Double,
        set: @escaping (inout OverlayElement, Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { currentElement(id).map(get) ?? 0 },
            set: { newValue in model.updateElement(id) { set(&$0, newValue) } }
        )
    }

    private func fontSizeBinding(id: String, role: TypographyRole, kind: OverlayComponentID) -> Binding<Double> {
        let baseSize = typographyBaseSize(for: kind, role: role)
        return Binding(
            get: { fontSizeValue(id: id, role: role, kind: kind) },
            set: { newValue in
                let clampedSize = min(180, max(6, newValue))
                model.updateElement(id) { element in
                    let scale = clampedSize / baseSize
                    switch role {
                    case .label:
                        element.customization.labelScale = scale
                    case .value:
                        element.customization.valueScale = scale
                    case .unit:
                        element.customization.unitScale = scale
                    case .icon:
                        element.customization.iconScale = scale
                    }
                }
            }
        )
    }

    private func intBinding(
        id: String,
        get: @escaping (OverlayElement) -> Int,
        set: @escaping (inout OverlayElement, Int) -> Void
    ) -> Binding<Int> {
        Binding(
            get: { currentElement(id).map(get) ?? 0 },
            set: { newValue in model.updateElement(id) { set(&$0, newValue) } }
        )
    }

    private func fontBinding(
        id: String,
        get: @escaping (OverlayElement) -> OverlayFontFamily,
        set: @escaping (inout OverlayElement, OverlayFontFamily) -> Void
    ) -> Binding<OverlayFontFamily> {
        Binding(
            get: { currentElement(id).map(get) ?? .helveticaNeueBold },
            set: { newValue in model.updateElement(id) { set(&$0, newValue) } }
        )
    }

    private func colorBinding(
        id: String,
        fallback: OverlayColor,
        get: @escaping (OverlayElement) -> OverlayColor?,
        set: @escaping (inout OverlayElement, OverlayColor) -> Void
    ) -> Binding<Color> {
        Binding(
            get: { (currentElement(id).flatMap(get) ?? fallback).swiftUIColor },
            set: { newValue in model.updateElement(id) { set(&$0, OverlayColor(newValue)) } }
        )
    }

    private func stringBinding(
        id: String,
        get: @escaping (OverlayElement) -> String,
        set: @escaping (inout OverlayElement, String) -> Void
    ) -> Binding<String> {
        Binding(
            get: { currentElement(id).map(get) ?? "" },
            set: { newValue in model.updateElement(id) { set(&$0, newValue) } }
        )
    }
}

private enum TypographyRole {
    case label
    case value
    case unit
    case icon
}

private enum InspectorSection: String, CaseIterable, Identifiable {
    case layout
    case appearance
    case content
    case typography
    case data

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .layout:
            return "inspector.layout"
        case .appearance:
            return "inspector.appearance"
        case .content:
            return "inspector.content"
        case .typography:
            return "inspector.typography"
        case .data:
            return "inspector.data"
        }
    }

    var systemImage: String {
        switch self {
        case .layout:
            return "arrow.up.left.and.arrow.down.right"
        case .appearance:
            return "paintbrush"
        case .content:
            return "textformat"
        case .typography:
            return "character.cursor.ibeam"
        case .data:
            return "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

private struct InspectorGroup<Content: View>: View {
    var section: InspectorSection
    @Binding var expandedSections: Set<InspectorSection>
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedSections.contains(section) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedSections.insert(section)
                        } else {
                            expandedSections.remove(section)
                        }
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(.top, 10)
                .padding(.leading, 1)
            } label: {
                Label(localization.string(section.localizationKey), systemImage: section.systemImage)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 8)

            Divider()
        }
    }
}

private struct TextStyleRow: View {
    var title: String
    @Binding var font: OverlayFontFamily
    @Binding var color: Color
    @Binding var size: Double
    var sizeLabel: String
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(localization.string("inspector.font"), selection: $font) {
                ForEach(OverlayFontFamily.allCases) { font in
                    Text(font.displayName).tag(font)
                }
            }

            ColorPicker(localization.string("inspector.color"), selection: $color)

            LabeledSlider(
                title: localization.string("inspector.fontSize"),
                value: $size,
                range: 6...180,
                label: sizeLabel,
                showsTextField: true,
                unitLabel: "pt"
            )
        }
        .padding(.vertical, 4)
    }
}

struct LabeledSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String
    var showsTextField = false
    var unitLabel: String?
    @State private var draftText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if showsTextField {
                    HStack(spacing: 5) {
                        TextField(title, text: $draftText)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 88)
                            .focused($isTextFieldFocused)
                            .onSubmit(commitDraft)

                        if let unitLabel {
                            Text(unitLabel)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } else {
                    Text(label)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            Slider(value: clampedValue, in: range)
        }
        .onAppear {
            draftText = NumberTextFormatter.formatDouble(clamp(value))
        }
        .onChange(of: value) { _ in
            guard !isTextFieldFocused else { return }
            draftText = NumberTextFormatter.formatDouble(clamp(value))
        }
        .onChange(of: isTextFieldFocused) { focused in
            if focused {
                draftText = NumberTextFormatter.formatDouble(clamp(value))
            } else {
                commitDraft()
            }
        }
    }

    private var clampedValue: Binding<Double> {
        Binding(
            get: { clamp(value) },
            set: { value = clamp($0) }
        )
    }

    private func clamp(_ rawValue: Double) -> Double {
        let finiteValue = rawValue.isFinite ? rawValue : range.lowerBound
        return min(range.upperBound, max(range.lowerBound, finiteValue))
    }

    private func commitDraft() {
        guard let parsed = NumberTextFormatter.parseDouble(draftText) else {
            draftText = NumberTextFormatter.formatDouble(clamp(value))
            return
        }
        value = clamp(parsed)
        draftText = NumberTextFormatter.formatDouble(clamp(value))
    }
}
