import AppKit
import SwiftUI
import OverlayCore

struct InspectorSettingsPanel: View {
    @ObservedObject var model: StudioModel
    @Binding var expandedSections: Set<InspectorSection>
    var focusedSection: InspectorSection?
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        selectedElementSettings
    }

    @ViewBuilder
    private var selectedElementSettings: some View {
        if let element = model.selectedElement {
            VStack(alignment: .leading, spacing: 12) {
                if !element.frame.isVisible {
                    InspectorInlineStatusBar(
                        systemImage: "eye.slash",
                        title: localization.string("inspector.hiddenElement.title"),
                        message: localization.string("inspector.hiddenElement.message"),
                        actionTitle: localization.string("inspector.hiddenElement.action")
                    ) {
                        model.updateElement(element.id) { element in
                            element.frame.isVisible = true
                        }
                    }
                }
                settings(for: element)
            }
            .id(element.id)
            .disabled(model.isExporting)
        } else {
            InspectorEmptyState(model: model)
        }
    }

    @ViewBuilder
    private func settings(for element: OverlayElement) -> some View {
        ForEach(InspectorSection.displayOrder) { section in
            if shouldShow(section) {
                sectionView(section, for: element)
            }
        }
    }

    private func shouldShow(_ section: InspectorSection) -> Bool {
        focusedSection == nil || focusedSection == section
    }

    @ViewBuilder
    private func sectionView(_ section: InspectorSection, for element: OverlayElement) -> some View {
        switch section {
        case .layout:
            layoutSection(for: element)
        case .content:
            contentSection(for: element)
        case .appearance:
            appearanceSection(for: element)
        case .typography:
            typographySection(for: element)
        case .data:
            dataSection(for: element)
        }
    }

    private func layoutSection(for element: OverlayElement) -> some View {
        let id = element.id
        let kind = element.kind

        return sectionContainer(
            section: .layout,
            summary: layoutSummary(for: element),
            expandedSections: $expandedSections
        ) {
            LabeledSlider(
                title: "X",
                value: doubleBinding(id: id, get: { $0.frame.x }, set: { $0.frame.x = $1 }),
                range: PreviewLayoutLimits.positionRange,
                label: layoutCoordinateLabel(currentElement(id)?.frame.x ?? 0),
                showsTextField: true,
                displayScale: 1_000,
                keyboardStep: 1
            )

            LabeledSlider(
                title: "Y",
                value: doubleBinding(id: id, get: { $0.frame.y }, set: { $0.frame.y = $1 }),
                range: PreviewLayoutLimits.positionRange,
                label: layoutCoordinateLabel(currentElement(id)?.frame.y ?? 0),
                showsTextField: true,
                displayScale: 1_000,
                keyboardStep: 1
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
    }

    private func contentSection(for element: OverlayElement) -> some View {
        let id = element.id
        let kind = element.kind

        return sectionContainer(
            section: .content,
            summary: contentSummary(for: element),
            expandedSections: $expandedSections
        ) {
            InspectorToggleRow(title: localization.string("inspector.label"), isOn: boolBinding(
                id: id,
                get: { $0.customization.showsLabel },
                set: { $0.customization.showsLabel = $1 }
            ))

            if currentElement(id)?.customization.showsLabel == true {
                InspectorTextRow(
                    title: localization.string("inspector.labelText"),
                    text: stringBinding(
                        id: id,
                        get: { $0.customization.labelOverride ?? "" },
                        set: { element, value in
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            element.customization.labelOverride = trimmed.isEmpty ? nil : trimmed
                        }
                    )
                )
            }

            let unitToggleTitle = switch kind {
            case .topProgress:
                localization.string("inspector.endLabel")
            case .timeDate:
                localization.string("inspector.clockAndDate")
            default:
                localization.string("inspector.unit")
            }

            InspectorToggleRow(title: unitToggleTitle, isOn: boolBinding(
                id: id,
                get: { $0.customization.showsUnit },
                set: { $0.customization.showsUnit = $1 }
            ))

            if currentElement(id)?.customization.showsUnit == true,
               kind != .topProgress,
               kind != .timeDate {
                InspectorTextRow(
                    title: localization.string("inspector.unitText"),
                    text: stringBinding(
                        id: id,
                        get: { $0.customization.unitOverride ?? "" },
                        set: { element, value in
                            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            element.customization.unitOverride = trimmed.isEmpty ? nil : trimmed
                        }
                    )
                )
            }

            InspectorToggleRow(title: localization.string("inspector.icon"), isOn: boolBinding(
                id: id,
                get: { $0.customization.showsIcon },
                set: { $0.customization.showsIcon = $1 }
            ))

            if currentElement(id)?.customization.showsIcon == true {
                if kind == .weather {
                    InspectorWeatherIconRow(
                        title: localization.string("inspector.weatherIcon"),
                        selection: weatherIconBinding(id: id)
                    )
                } else {
                    InspectorTextRow(
                        title: localization.string("inspector.iconText"),
                        text: stringBinding(
                            id: id,
                            get: { $0.customization.iconOverride ?? "" },
                            set: { element, value in
                                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                element.customization.iconOverride = trimmed.isEmpty ? nil : trimmed
                            }
                        )
                    )
                }
            }
        }
    }

    private func appearanceSection(for element: OverlayElement) -> some View {
        let id = element.id
        let kind = element.kind

        return sectionContainer(
            section: .appearance,
            summary: appearanceSummary(for: element),
            expandedSections: $expandedSections
        ) {
            InspectorSubheading(localization.string("inspector.panelSection"))

            InspectorToggleRow(title: localization.string("inspector.panel"), isOn: boolBinding(
                id: id,
                get: { $0.customization.showsPanel },
                set: { $0.customization.showsPanel = $1 }
            ))

            if currentElement(id)?.customization.showsPanel == true {
                InspectorToggleRow(title: localization.string("inspector.panelBorder"), isOn: boolBinding(
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
                InspectorRule()
                InspectorSubheading(localization.string("inspector.lineSection"))

                LabeledSlider(
                    title: kind == .speed ? localization.string("inspector.gaugeWidth") : localization.string("inspector.lineWidth"),
                    value: doubleBinding(id: id, get: { $0.customization.lineWidth }, set: { $0.customization.lineWidth = $1 }),
                    range: kind == .topProgress ? 1...36 : 1...24,
                    label: "\(Int((currentElement(id)?.customization.lineWidth ?? 1).rounded())) px",
                    showsTextField: kind == .topProgress,
                    unitLabel: "px"
                )

                InspectorColorRow(
                    title: localization.string("inspector.trackColor"),
                    selection: colorBinding(
                        id: id,
                        fallback: .track,
                        get: { $0.customization.trackColor },
                        set: { $0.customization.trackColor = $1 }
                    )
                )
            }

            if kind == .topProgress {
                InspectorRule()
                InspectorSubheading(localization.string("inspector.progressSection"))

                InspectorColorRow(
                    title: localization.string("inspector.progressColor"),
                    selection: colorBinding(
                        id: id,
                        fallback: defaultValueColor(for: element),
                        get: { $0.customization.progressBarColor },
                        set: { $0.customization.progressBarColor = $1 }
                    )
                )

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

                InspectorRule()
                InspectorSubheading(localization.string("inspector.tickSection"))

                InspectorToggleRow(title: localization.string("inspector.tickMarks"), isOn: boolBinding(
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

            if kind == .weather,
               currentElement(id)?.customization.showsIcon == true,
               currentElement(id)?.customization.showsUnit == true {
                InspectorRule()
                InspectorSubheading(localization.string("inspector.weatherIcon"))

                LabeledSlider(
                    title: localization.string("inspector.weatherIconSpacing"),
                    value: doubleBinding(
                        id: id,
                        get: { $0.customization.weatherIconSpacingScale ?? 1 },
                        set: { $0.customization.weatherIconSpacingScale = $1 }
                    ),
                    range: 0...3,
                    label: "\(Int(((currentElement(id)?.customization.weatherIconSpacingScale ?? 1) * 100).rounded()))%"
                )
            }
        }
    }

    private func typographySection(for element: OverlayElement) -> some View {
        let id = element.id
        let kind = element.kind

        return sectionContainer(
            section: .typography,
            summary: typographySummary(for: element),
            expandedSections: $expandedSections
        ) {
            if kind == .topProgress {
                topProgressTypographyRows(id: id, element: element)
            } else {
                if currentElement(id)?.customization.showsLabel == true {
                    TextStyleRow(
                        title: localization.string("inspector.label"),
                        font: fontBinding(id: id, get: { $0.customization.labelFont }, set: { $0.customization.labelFont = $1 }),
                        color: colorBinding(id: id, fallback: .label, get: { $0.customization.labelColor }, set: { $0.customization.labelColor = $1 }),
                        size: fontSizeBinding(id: id, role: .label, kind: kind),
                        sizeLabel: fontSizeLabel(id: id, role: .label, kind: kind)
                    )
                    InspectorRule()
                }

                TextStyleRow(
                    title: localization.string("inspector.value"),
                    font: fontBinding(id: id, get: { $0.customization.valueFont }, set: { $0.customization.valueFont = $1 }),
                    color: colorBinding(id: id, fallback: defaultValueColor(for: element), get: { $0.customization.valueColor }, set: { $0.customization.valueColor = $1 }),
                    size: fontSizeBinding(id: id, role: .value, kind: kind),
                    sizeLabel: fontSizeLabel(id: id, role: .value, kind: kind)
                )

                if currentElement(id)?.customization.showsUnit == true {
                    InspectorRule()
                    TextStyleRow(
                        title: localization.string("inspector.unit"),
                        font: fontBinding(id: id, get: { $0.customization.unitFont }, set: { $0.customization.unitFont = $1 }),
                        color: colorBinding(id: id, fallback: .muted, get: { $0.customization.unitColor }, set: { $0.customization.unitColor = $1 }),
                        size: fontSizeBinding(id: id, role: .unit, kind: kind),
                        sizeLabel: fontSizeLabel(id: id, role: .unit, kind: kind)
                    )
                }

                if currentElement(id)?.customization.showsIcon == true {
                    InspectorRule()
                    TextStyleRow(
                        title: localization.string("inspector.icon"),
                        font: fontBinding(id: id, get: { $0.customization.iconFont }, set: { $0.customization.iconFont = $1 }),
                        color: colorBinding(id: id, fallback: .label, get: { $0.customization.iconColor }, set: { $0.customization.iconColor = $1 }),
                        size: fontSizeBinding(id: id, role: .icon, kind: kind),
                        sizeLabel: fontSizeLabel(id: id, role: .icon, kind: kind)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func topProgressTypographyRows(id: String, element: OverlayElement) -> some View {
        if currentElement(id)?.customization.showsLabel == true {
            TextStyleRow(
                title: localization.string("inspector.startDistance"),
                font: optionalFontBinding(
                    id: id,
                    fallback: { $0.customization.labelFont },
                    get: { $0.customization.progressStartFont },
                    set: { $0.customization.progressStartFont = $1 }
                ),
                color: colorBinding(id: id, fallback: .label, get: { $0.customization.progressStartColor }, set: { $0.customization.progressStartColor = $1 }),
                size: progressFontSizeBinding(id: id, role: .start),
                sizeLabel: progressFontSizeLabel(id: id, role: .start)
            )
            InspectorRule()
            TextStyleRow(
                title: localization.string("inspector.currentDistance"),
                font: optionalFontBinding(
                    id: id,
                    fallback: { $0.customization.valueFont },
                    get: { $0.customization.progressCurrentFont },
                    set: { $0.customization.progressCurrentFont = $1 }
                ),
                color: colorBinding(id: id, fallback: defaultValueColor(for: element), get: { $0.customization.progressCurrentColor }, set: { $0.customization.progressCurrentColor = $1 }),
                size: progressFontSizeBinding(id: id, role: .current),
                sizeLabel: progressFontSizeLabel(id: id, role: .current)
            )
        }

        if currentElement(id)?.customization.showsUnit == true {
            if currentElement(id)?.customization.showsLabel == true {
                InspectorRule()
            }
            TextStyleRow(
                title: localization.string("inspector.endDistance"),
                font: optionalFontBinding(
                    id: id,
                    fallback: { $0.customization.unitFont },
                    get: { $0.customization.progressEndFont },
                    set: { $0.customization.progressEndFont = $1 }
                ),
                color: colorBinding(id: id, fallback: .muted, get: { $0.customization.progressEndColor }, set: { $0.customization.progressEndColor = $1 }),
                size: progressFontSizeBinding(id: id, role: .end),
                sizeLabel: progressFontSizeLabel(id: id, role: .end)
            )
        }

        if currentElement(id)?.customization.showsIcon == true {
            if currentElement(id)?.customization.showsLabel == true ||
                currentElement(id)?.customization.showsUnit == true {
                InspectorRule()
            }
            TextStyleRow(
                title: localization.string("inspector.icon"),
                font: fontBinding(id: id, get: { $0.customization.iconFont }, set: { $0.customization.iconFont = $1 }),
                color: colorBinding(id: id, fallback: .label, get: { $0.customization.iconColor }, set: { $0.customization.iconColor = $1 }),
                size: fontSizeBinding(id: id, role: .icon, kind: .topProgress),
                sizeLabel: fontSizeLabel(id: id, role: .icon, kind: .topProgress)
            )
        }
    }

    @ViewBuilder
    private func dataSection(for element: OverlayElement) -> some View {
        let id = element.id
        let kind = element.kind

        if kind.supportsValuePrecision || kind == .speed || kind == .weather {
            sectionContainer(
                section: .data,
                summary: dataSummary(for: element),
                expandedSections: $expandedSections
            ) {
                if kind == .weather {
                    InspectorMessageBlock(
                        systemImage: "cloud.sun",
                        title: localization.string("inspector.weatherRefresh.title"),
                        message: localization.string("inspector.weatherRefresh.message")
                    ) {
                        SecureField(localization.string("sidebar.weather.openWeatherKey"), text: Binding(
                            get: { model.openWeatherAPIKey },
                            set: { model.setOpenWeatherAPIKey($0) }
                        ))
                        .onSubmit {
                            model.refreshOpenWeatherForCurrentFIT()
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                        Text(localization.string("sidebar.weather.openWeatherHint"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            model.refreshOpenWeatherForCurrentFIT()
                        } label: {
                            Label(localization.string("inspector.weatherRefresh.action"), systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .padding(.top, 2)

                        if let message = model.weatherRefreshMessage {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                }

                if kind.supportsValuePrecision {
                    InspectorStepperRow(
                        title: localization.string("inspector.decimalsTitle"),
                        value: intBinding(
                            id: id,
                            get: { $0.customization.valuePrecision ?? kind.defaultPrecision },
                            set: { $0.customization.valuePrecision = $1 }
                        ),
                        in: 0...3
                    )
                }

                if kind == .speed {
                    InspectorToggleRow(title: localization.string("inspector.gaugeTicks"), isOn: boolBinding(
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
        } else if focusedSection == .data {
            InspectorUnavailableSection(
                title: localization.string("inspector.noDataSettings.title"),
                message: localization.string("inspector.noDataSettings.message")
            )
        }
    }

    private func currentElement(_ id: String) -> OverlayElement? {
        model.layout.elements.first { $0.id == id }
    }

    @ViewBuilder
    private func sectionContainer<Content: View>(
        section: InspectorSection,
        summary: [String],
        expandedSections: Binding<Set<InspectorSection>>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if focusedSection == section {
            InspectorFocusedSection(section: section, summary: summary) {
                content()
            }
        } else {
            InspectorGroup(section: section, summary: summary, expandedSections: expandedSections) {
                content()
            }
        }
    }

    private func layoutSummary(for element: OverlayElement) -> [String] {
        let frame = currentElement(element.id)?.frame ?? element.frame
        var parts = [
            "X \(layoutCoordinateLabel(frame.x))",
            "Y \(layoutCoordinateLabel(frame.y))",
            "\(Int((frame.scale * 100).rounded()))%"
        ]
        let current = currentElement(element.id) ?? element
        if current.kind.supportsLengthScale {
            parts.append("\(localization.string("inspector.length")) \(Int((current.customization.lengthScale * 100).rounded()))%")
        }
        return parts
    }

    private func contentSummary(for element: OverlayElement) -> [String] {
        let current = currentElement(element.id) ?? element
        var parts = [String]()

        if current.customization.showsLabel {
            parts.append(localization.string("inspector.label"))
        }
        if current.customization.showsUnit {
            switch current.kind {
            case .topProgress:
                parts.append(localization.string("inspector.endLabel"))
            case .timeDate:
                parts.append(localization.string("inspector.clockAndDate"))
            default:
                parts.append(localization.string("inspector.unit"))
            }
        }
        if current.customization.showsIcon {
            parts.append(localization.string("inspector.icon"))
        }

        if parts.isEmpty {
            parts.append(localization.string("inspector.contentHidden"))
        }

        return parts
    }

    private func appearanceSummary(for element: OverlayElement) -> [String] {
        let current = currentElement(element.id) ?? element
        var parts = [String]()

        if current.customization.showsPanel {
            parts.append(localization.string("inspector.panel"))
            if current.customization.panelBorderIsVisible {
                parts.append(localization.string("inspector.panelBorder"))
            }
            parts.append((current.frame.style.panelOpacity ?? model.layout.style.panelOpacity).percentString)
        } else {
            parts.append(localization.string("inspector.panelHidden"))
        }
        if current.kind.supportsLineWidth {
            parts.append("\(Int(current.customization.lineWidth.rounded())) px")
        }
        if current.kind == .topProgress,
           current.customization.showGaugeTicks == true {
            parts.append(localization.string("inspector.tickMarks"))
        }

        return parts
    }

    private func typographySummary(for element: OverlayElement) -> [String] {
        let current = currentElement(element.id) ?? element
        var parts = [String]()
        if current.kind == .topProgress {
            if current.customization.showsLabel {
                parts.append("\(localization.string("inspector.startDistance")) \(progressFontSizeLabel(id: element.id, role: .start))")
                parts.append("\(localization.string("inspector.currentDistance")) \(progressFontSizeLabel(id: element.id, role: .current))")
            }
            if current.customization.showsUnit {
                parts.append("\(localization.string("inspector.endDistance")) \(progressFontSizeLabel(id: element.id, role: .end))")
            }
            if current.customization.showsIcon {
                parts.append("\(localization.string("inspector.icon")) \(fontSizeLabel(id: element.id, role: .icon, kind: element.kind))")
            }
            return parts
        }
        if current.customization.showsLabel {
            parts.append("\(localization.string("inspector.label")) \(fontSizeLabel(id: element.id, role: .label, kind: element.kind))")
        }
        parts.append("\(localization.string("inspector.value")) \(fontSizeLabel(id: element.id, role: .value, kind: element.kind))")
        if current.customization.showsUnit {
            parts.append("\(localization.string("inspector.unit")) \(fontSizeLabel(id: element.id, role: .unit, kind: element.kind))")
        }
        if current.customization.showsIcon {
            parts.append("\(localization.string("inspector.icon")) \(fontSizeLabel(id: element.id, role: .icon, kind: element.kind))")
        }
        return parts
    }

    private func dataSummary(for element: OverlayElement) -> [String] {
        let current = currentElement(element.id) ?? element
        var parts = [String]()

        if current.kind.supportsValuePrecision {
            let precision = current.customization.valuePrecision ?? current.kind.defaultPrecision
            parts.append(localization.string("inspector.decimals", precision))
        }
        if current.kind == .speed {
            let minimum = Int((current.customization.gaugeMinimum ?? 0).rounded())
            let maximum = Int((current.customization.gaugeMaximum ?? 24).rounded())
            parts.append("\(minimum)-\(maximum)")
        }
        if current.kind == .weather {
            parts.append("OpenWeather")
        }

        return parts
    }

    private func fontSizeLabel(id: String, role: TypographyRole, kind: OverlayComponentID) -> String {
        "\(Int(fontSizeValue(id: id, role: role, kind: kind).rounded())) pt"
    }

    private func progressFontSizeLabel(id: String, role: ProgressTypographyRole) -> String {
        "\(Int(progressFontSizeValue(id: id, role: role).rounded())) pt"
    }

    private func layoutCoordinateLabel(_ value: Double) -> String {
        NumberTextFormatter.formatDouble(value * 1_000)
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
        case (.pace, .label), (.distance, .label), (.heartRate, .label), (.cadence, .label), (.calories, .label), (.strideLength, .label), (.power, .label), (.weather, .label):
            return 10
        case (.pace, .value), (.distance, .value), (.heartRate, .value), (.cadence, .value), (.calories, .value), (.strideLength, .value), (.power, .value), (.weather, .value):
            return 23
        case (.pace, .unit), (.distance, .unit), (.heartRate, .unit), (.cadence, .unit), (.calories, .unit), (.strideLength, .unit), (.power, .unit), (.weather, .unit):
            return 10
        case (.pace, .icon), (.distance, .icon), (.heartRate, .icon), (.cadence, .icon), (.calories, .icon), (.strideLength, .icon), (.power, .icon), (.weather, .icon):
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

    private func progressFontSizeValue(id: String, role: ProgressTypographyRole) -> Double {
        guard let element = currentElement(id) else { return progressBaseSize(for: role) }
        return progressBaseSize(for: role) * progressScaleValue(for: element, role: role)
    }

    private func progressScaleValue(for element: OverlayElement, role: ProgressTypographyRole) -> Double {
        switch role {
        case .start:
            return element.customization.progressStartScale ?? element.customization.labelScale
        case .current:
            return element.customization.progressCurrentScale ?? element.customization.valueScale
        case .end:
            return element.customization.progressEndScale ?? element.customization.unitScale
        }
    }

    private func progressBaseSize(for role: ProgressTypographyRole) -> Double {
        switch role {
        case .start:
            return 15
        case .current:
            return 12
        case .end:
            return 15
        }
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

    private func progressFontSizeBinding(id: String, role: ProgressTypographyRole) -> Binding<Double> {
        let baseSize = progressBaseSize(for: role)
        return Binding(
            get: { progressFontSizeValue(id: id, role: role) },
            set: { newValue in
                let clampedSize = min(180, max(6, newValue))
                model.updateElement(id) { element in
                    let scale = clampedSize / baseSize
                    switch role {
                    case .start:
                        element.customization.progressStartScale = scale
                    case .current:
                        element.customization.progressCurrentScale = scale
                    case .end:
                        element.customization.progressEndScale = scale
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

    private func weatherIconBinding(id: String) -> Binding<OverlayWeatherIcon> {
        Binding(
            get: {
                guard let rawValue = currentElement(id)?.customization.iconOverride else { return .auto }
                return OverlayWeatherIcon(rawValue: rawValue) ?? .auto
            },
            set: { newValue in
                model.updateElement(id) { element in
                    element.customization.iconOverride = newValue == .auto ? nil : newValue.rawValue
                }
            }
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

    private func optionalFontBinding(
        id: String,
        fallback: @escaping (OverlayElement) -> OverlayFontFamily,
        get: @escaping (OverlayElement) -> OverlayFontFamily?,
        set: @escaping (inout OverlayElement, OverlayFontFamily) -> Void
    ) -> Binding<OverlayFontFamily> {
        Binding(
            get: {
                guard let element = currentElement(id) else { return .helveticaNeueBold }
                return get(element) ?? fallback(element)
            },
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

private enum ProgressTypographyRole {
    case start
    case current
    case end
}

private struct InspectorFocusedSection<Content: View>: View {
    var section: InspectorSection
    var summary: [String]
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionTitle(section: section, summary: summary, isFocused: true, showsSummary: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()
                .overlay(Color.secondary.opacity(0.16))

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InspectorStyle.sectionFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(InspectorStyle.sectionStroke)
        }
    }
}

enum InspectorSection: String, CaseIterable, Identifiable {
    case layout
    case content
    case appearance
    case typography
    case data

    var id: String { rawValue }

    static let displayOrder: [InspectorSection] = [.layout, .content, .appearance, .typography, .data]
    static let defaultExpandedSections = Set(displayOrder)
    static let defaultExpandedSectionsRawValue = displayOrder.map(\.rawValue).joined(separator: ",")

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
    var summary: [String]
    @Binding var expandedSections: Set<InspectorSection>
    @ViewBuilder var content: () -> Content
    @EnvironmentObject private var localization: LocalizationStore
    @State private var isHoveringHeader = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle()
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    InspectorSectionTitle(section: section, summary: summary, isFocused: false, showsSummary: true)

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .background(headerFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .onHover { hovering in
                isHoveringHeader = hovering
            }

            if isExpanded {
                Divider()
                    .overlay(Color.secondary.opacity(0.16))

                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InspectorStyle.sectionFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(InspectorStyle.sectionStroke)
        }
    }

    private var isExpanded: Bool {
        expandedSections.contains(section)
    }

    private var headerFill: Color {
        if isExpanded {
            return Color.secondary.opacity(0.035)
        }
        return isHoveringHeader ? Color.secondary.opacity(0.045) : Color.clear
    }

    private func toggle() {
        if isExpanded {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
}

private struct InspectorSectionTitle: View {
    var section: InspectorSection
    var summary: [String]
    var isFocused: Bool
    var showsSummary: Bool
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionIdentity

            if showsSummary && !summary.isEmpty {
                InspectorSummaryPills(parts: summary)
                    .padding(.leading, 27)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionIdentity: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: section.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFocused ? Color.accentColor : Color.secondary)
                .frame(width: 18, height: 18)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(localization.string(section.localizationKey))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var iconBackground: Color {
        isFocused ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.065)
    }
}

private struct InspectorSummaryPills: View {
    var parts: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                ForEach(Array(visibleParts.enumerated()), id: \.offset) { _, part in
                    InspectorSummaryPill(part)
                }

                if hiddenCount > 0 {
                    InspectorSummaryPill("+\(hiddenCount)", style: .count)
                }
            }

            Text(fallbackText)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var visibleParts: [String] {
        Array(parts.prefix(2))
    }

    private var hiddenCount: Int {
        max(0, parts.count - visibleParts.count)
    }

    private var fallbackText: String {
        if hiddenCount > 0 {
            return (visibleParts + ["+\(hiddenCount)"]).joined(separator: " · ")
        }
        return parts.joined(separator: " · ")
    }
}

private struct InspectorSummaryPill: View {
    enum Style {
        case value
        case count
    }

    var value: String
    var style: Style

    init(_ value: String, style: Style = .value) {
        self.value = value
        self.style = style
    }

    var body: some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var foregroundStyle: Color {
        switch style {
        case .value:
            return .secondary
        case .count:
            return .accentColor
        }
    }

    private var backgroundFill: Color {
        switch style {
        case .value:
            return Color.secondary.opacity(0.07)
        case .count:
            return Color.accentColor.opacity(0.10)
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
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: InspectorFormMetrics.rowGap) {
                    Text(title)
                        .inspectorControlLabel()

                    fontAndColorControls
                }

                VStack(alignment: .leading, spacing: InspectorFormMetrics.stackedRowGap) {
                    Text(title)
                        .inspectorControlLabel(width: nil)

                    fontAndColorControls
                }
            }

            LabeledSlider(
                title: localization.string("inspector.fontSize"),
                value: $size,
                range: 6...180,
                label: sizeLabel,
                showsTextField: true,
                unitLabel: "pt",
                usesRowSurface: false
            )
        }
        .padding(.vertical, 2)
        .inspectorControlRowSurface()
    }

    private var fontAndColorControls: some View {
        HStack(alignment: .center, spacing: InspectorFormMetrics.accessoryGap) {
            Picker(localization.string("inspector.font"), selection: $font) {
                ForEach(OverlayFontFamily.allCases) { font in
                    Text(font.displayName).tag(font)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)

            ColorPicker(localization.string("inspector.color"), selection: $color)
                .labelsHidden()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct InspectorSubheading: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorRule: View {
    var body: some View {
        Divider()
            .overlay(Color.secondary.opacity(0.18))
            .padding(.vertical, 2)
    }
}

private struct InspectorColorRow: View {
    var title: String
    @Binding var selection: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: InspectorFormMetrics.rowGap) {
                Text(title)
                    .inspectorControlLabel()

                Spacer(minLength: 8)

                colorPicker
            }

            VStack(alignment: .leading, spacing: InspectorFormMetrics.stackedRowGap) {
                Text(title)
                    .inspectorControlLabel(width: nil)

                colorPicker
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .inspectorControlRowSurface()
    }

    private var colorPicker: some View {
        ColorPicker(title, selection: $selection)
            .labelsHidden()
            .controlSize(.small)
    }
}

private struct InspectorToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: InspectorFormMetrics.rowGap) {
                Text(title)
                    .inspectorControlLabel()

                Spacer(minLength: 8)

                toggle
            }

            HStack(spacing: InspectorFormMetrics.rowGap) {
                Text(title)
                    .inspectorControlLabel(width: nil)

                Spacer(minLength: 8)

                toggle
            }
        }
        .inspectorControlRowSurface()
    }

    private var toggle: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel(title)
    }
}

private struct InspectorTextRow: View {
    var title: String
    @Binding var text: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: InspectorFormMetrics.rowGap) {
                Text(title)
                    .inspectorControlLabel()

                Spacer(minLength: 8)

                textField
                    .frame(width: InspectorFormMetrics.textFieldWidth)
            }

            VStack(alignment: .leading, spacing: InspectorFormMetrics.stackedRowGap) {
                Text(title)
                    .inspectorControlLabel(width: nil)

                textField
                    .frame(maxWidth: .infinity)
            }
        }
        .inspectorControlRowSurface()
    }

    private var textField: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
    }
}

private struct InspectorWeatherIconRow: View {
    var title: String
    @Binding var selection: OverlayWeatherIcon
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: InspectorFormMetrics.rowGap) {
                Text(title)
                    .inspectorControlLabel()

                Spacer(minLength: 8)

                picker
                    .frame(width: InspectorFormMetrics.textFieldWidth)
            }

            VStack(alignment: .leading, spacing: InspectorFormMetrics.stackedRowGap) {
                Text(title)
                    .inspectorControlLabel(width: nil)

                picker
                    .frame(maxWidth: .infinity)
            }
        }
        .inspectorControlRowSurface()
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(OverlayWeatherIcon.allCases) { icon in
                Text(label(for: icon)).tag(icon)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .pickerStyle(.menu)
    }

    private func label(for icon: OverlayWeatherIcon) -> String {
        let title = localization.string("inspector.weatherIcon.\(icon.rawValue)")
        return icon == .auto ? title : "\(icon.symbol)  \(title)"
    }
}

private struct InspectorStepperRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    init(title: String, value: Binding<Int>, in range: ClosedRange<Int>) {
        self.title = title
        self._value = value
        self.range = range
    }

    var body: some View {
        Stepper(value: $value, in: range) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: InspectorFormMetrics.rowGap) {
                    Text(title)
                        .inspectorControlLabel()

                    Spacer(minLength: 8)

                    InspectorValuePill("\(value)")
                }

                VStack(alignment: .leading, spacing: InspectorFormMetrics.stackedRowGap) {
                    Text(title)
                        .inspectorControlLabel(width: nil)

                    InspectorValuePill("\(value)")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .inspectorControlRowSurface()
    }
}

private struct InspectorUnavailableSection: View {
    var title: String
    var message: String

    var body: some View {
        InspectorMessageBlock(
            systemImage: "slider.horizontal.below.rectangle",
            title: title,
            message: message
        )
    }
}

private struct InspectorInlineStatusBar: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .font(.caption.weight(.semibold))
                .controlSize(.small)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(InspectorStyle.sectionFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(InspectorStyle.sectionStroke)
        }
    }
}

private struct LabeledSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String
    var showsTextField = false
    var unitLabel: String?
    var usesRowSurface = true
    var displayScale = 1.0
    var displayFractionDigits = 3
    var keyboardStep: Double?
    @State private var draftText = ""
    @State private var isTextFieldFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .inspectorControlLabel()

                    Spacer(minLength: 8)

                    valueAccessory
                }

                VStack(alignment: .leading, spacing: InspectorFormMetrics.stackedRowGap) {
                    Text(title)
                        .inspectorControlLabel(width: nil)

                    valueAccessory
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Slider(value: clampedValue, in: range)
                .controlSize(.small)
        }
        .onAppear {
            draftText = formatDisplayValue(clamp(value))
        }
        .onChange(of: value) { _ in
            guard !isTextFieldFocused else { return }
            draftText = formatDisplayValue(clamp(value))
        }
        .onChange(of: isTextFieldFocused) { focused in
            if focused {
                draftText = formatDisplayValue(clamp(value))
            }
        }
        .inspectorControlRowSurface(enabled: usesRowSurface)
    }

    @ViewBuilder
    private var valueAccessory: some View {
        if showsTextField {
            HStack(spacing: InspectorFormMetrics.accessoryGap) {
                SteppableNumericTextField(
                    title: title,
                    text: $draftText,
                    onCommit: commitDraft,
                    onStep: stepDraft,
                    onFocusChange: { isTextFieldFocused = $0 }
                )
                .frame(width: InspectorFormMetrics.numericFieldWidth)

                if let unitLabel {
                    Text(unitLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 18, alignment: .leading)
                }
            }
        } else {
            InspectorValuePill(label)
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
            draftText = formatDisplayValue(clamp(value))
            return
        }
        value = clamp(parsed / displayScale)
        draftText = formatDisplayValue(clamp(value))
    }

    private func stepDraft(by direction: Int) {
        let baseDisplayValue = NumberTextFormatter.parseDouble(draftText) ?? displayValue(for: value)
        let step = keyboardStep ?? defaultKeyboardStep
        value = clamp((baseDisplayValue + (Double(direction) * step)) / displayScale)
        draftText = formatDisplayValue(clamp(value))
    }

    private var defaultKeyboardStep: Double {
        if displayScale == 1 {
            return max(0.1, (range.upperBound - range.lowerBound) / 100)
        }
        return 1
    }

    private func displayValue(for rawValue: Double) -> Double {
        clamp(rawValue) * displayScale
    }

    private func formatDisplayValue(_ rawValue: Double) -> String {
        NumberTextFormatter.formatDouble(displayValue(for: rawValue), maximumFractionDigits: displayFractionDigits)
    }
}

private struct SteppableNumericTextField: NSViewRepresentable {
    var title: String
    @Binding var text: String
    var onCommit: () -> Void
    var onStep: (Int) -> Void
    var onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onStep: onStep, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.delegate = context.coordinator
        textField.placeholderString = title
        textField.alignment = .right
        textField.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.controlSize = .small
        textField.lineBreakMode = .byClipping
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        context.coordinator.onStep = onStep
        context.coordinator.onFocusChange = onFocusChange
        nsView.placeholderString = title

        if nsView.stringValue != text,
           nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onCommit: () -> Void
        var onStep: (Int) -> Void
        var onFocusChange: (Bool) -> Void

        init(
            text: Binding<String>,
            onCommit: @escaping () -> Void,
            onStep: @escaping (Int) -> Void,
            onFocusChange: @escaping (Bool) -> Void
        ) {
            self.text = text
            self.onCommit = onCommit
            self.onStep = onStep
            self.onFocusChange = onFocusChange
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            onFocusChange(true)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
            onFocusChange(false)
            onCommit()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                text.wrappedValue = textView.string
                onStep(1)
                textView.string = text.wrappedValue
                return true
            case #selector(NSResponder.moveDown(_:)):
                text.wrappedValue = textView.string
                onStep(-1)
                textView.string = text.wrappedValue
                return true
            default:
                return false
            }
        }
    }
}

private struct InspectorValuePill: View {
    var value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: InspectorFormMetrics.valuePillWidth, idealWidth: 68, maxWidth: 96, alignment: .trailing)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.095), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private enum InspectorFormMetrics {
    static let labelWidth: CGFloat = 112
    static let rowGap: CGFloat = 10
    static let stackedRowGap: CGFloat = 6
    static let accessoryGap: CGFloat = 6
    static let textFieldWidth: CGFloat = 178
    static let numericFieldWidth: CGFloat = 84
    static let valuePillWidth: CGFloat = 58
}

private extension View {
    @ViewBuilder
    func inspectorControlLabel(width: CGFloat? = InspectorFormMetrics.labelWidth) -> some View {
        let label = font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

        if let width {
            label.frame(width: width, alignment: .leading)
        } else {
            label.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InspectorEmptyState: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorMessageBlock(
                systemImage: "cursorarrow.click.2",
                title: localization.string("inspector.noSelection.emptyTitle"),
                message: localization.string("inspector.noSelection.message")
            ) {
                addElementMenu
                    .padding(.top, 4)
            }
        }
    }

    private var addElementMenu: some View {
        Menu {
            ForEach(OverlayComponentID.allCases) { component in
                Button {
                    model.addElement(kind: component)
                } label: {
                    Label(localization.string(component.localizationKey), systemImage: component.systemImage)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))

                Text(localization.string("inspector.addElement"))
                    .font(.caption.weight(.semibold))

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.24))
            }
        }
        .menuStyle(.borderlessButton)
        .disabled(model.isExporting)
        .help(localization.string("inspector.addElement"))
        .accessibilityLabel(localization.string("inspector.addElement"))
    }
}

private struct InspectorMessageBlock<Actions: View>: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @ViewBuilder var actions: () -> Actions

    init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) where Actions == EmptyView {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.actions = { EmptyView() }
    }

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = nil
        self.action = nil
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .padding(.top, 2)
                }

                actions()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(InspectorStyle.messageFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(InspectorStyle.messageStroke)
        }
    }
}

enum InspectorStyle {
    static let headerFill = Color.secondary.opacity(0.036)
    static let headerStroke = Color.secondary.opacity(0.085)
    static let sectionFill = Color.secondary.opacity(0.026)
    static let sectionStroke = Color.secondary.opacity(0.072)
    static let messageFill = Color.secondary.opacity(0.045)
    static let messageStroke = Color.secondary.opacity(0.09)
    static let actionGroupFill = Color.secondary.opacity(0.04)
    static let actionGroupStroke = Color.secondary.opacity(0.085)
    static let controlRowHoverFill = Color.secondary.opacity(0.045)
}

private struct InspectorControlRowSurface: ViewModifier {
    var enabled: Bool
    @State private var isHovering = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(rowFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onHover { hovering in
                    isHovering = hovering
                }
        } else {
            content
        }
    }

    private var rowFill: Color {
        isHovering ? InspectorStyle.controlRowHoverFill : Color.clear
    }
}

private extension View {
    func inspectorControlRowSurface(enabled: Bool = true) -> some View {
        modifier(InspectorControlRowSurface(enabled: enabled))
    }
}
