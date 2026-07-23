#if os(iOS)
import OverlayCore
import SwiftUI

/// 右栏检查器：选中组件的核心设置子集 + 添加组件。
/// 完整的逐组件深度定制（字体/颜色/刻度等）后续里程碑补齐。
struct TouchInspectorPanel: View {
    @ObservedObject var model: TouchStudioModel
    let localizer: TouchLocalizer

    var body: some View {
        Form {
            addComponentSection
            if let element = selectedElement {
                headerSection(element: element)
                positionSection(element: element)
                appearanceSection(element: element)
                contentSection(element: element)
            } else {
                Section {
                    Text(localizer.string("inspector.noSelection"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var selectedElement: OverlayElement? {
        guard let id = model.selectedElementID else { return nil }
        return model.layout.elements.first { $0.id == id }
    }

    // MARK: - 添加组件

    private var addComponentSection: some View {
        Section {
            Menu {
                ForEach(OverlayComponentID.allCases) { kind in
                    Button {
                        model.addElement(kind: kind)
                    } label: {
                        Label(localizer.string(kind.localizationKey), systemImage: kind.touchSystemImage)
                    }
                    .disabled(!model.canAddElement(kind: kind))
                }
            } label: {
                Label(localizer.string("inspector.addComponent"), systemImage: "plus.circle.fill")
            }
            .disabled(model.isExporting)
        }
    }

    // MARK: - 选中组件

    private func headerSection(element: OverlayElement) -> some View {
        Section {
            Picker(localizer.string("inspector.title"), selection: Binding(
                get: { model.selectedElementID ?? element.id },
                set: { model.selectElement($0) }
            )) {
                ForEach(model.layout.elements) { candidate in
                    Label(localizer.string(candidate.kind.localizationKey), systemImage: candidate.kind.touchSystemImage)
                        .tag(candidate.id)
                }
            }
            .labelsHidden()

            Toggle(localizer.string("inspector.visible"), isOn: elementBinding(element.id, get: {
                $0.frame.isVisible
            }, set: {
                $0.frame.isVisible = $1
            }))

            HStack {
                Button {
                    model.moveSelectedElement(by: 1)
                } label: {
                    Label(localizer.string("inspector.layerForward"), systemImage: "square.2.layers.3d.top.filled")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text(localizer.string("inspector.layerForward")))
                Spacer()
                Button {
                    model.moveSelectedElement(by: -1)
                } label: {
                    Label(localizer.string("inspector.layerBackward"), systemImage: "square.2.layers.3d.bottom.filled")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text(localizer.string("inspector.layerBackward")))
                Spacer()
                Button {
                    model.duplicateSelectedElement()
                } label: {
                    Label(localizer.string("inspector.duplicate"), systemImage: "plus.square.on.square")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text(localizer.string("inspector.duplicate")))
                Spacer()
                Button(role: .destructive) {
                    model.deleteSelectedElement()
                } label: {
                    Label(localizer.string("inspector.delete"), systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text(localizer.string("inspector.delete")))
            }
            .buttonStyle(.borderless)
            .disabled(model.isExporting)
        }
    }

    private func positionSection(element: OverlayElement) -> some View {
        Section(localizer.string("inspector.position")) {
            positionRow(label: "X", elementID: element.id, keyPath: \.frame.x)
            positionRow(label: "Y", elementID: element.id, keyPath: \.frame.y)
        }
    }

    private func positionRow(label: String, elementID: String, keyPath: WritableKeyPath<OverlayElement, Double>) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                TextField(
                    label,
                    value: elementBinding(elementID, get: {
                        ($0[keyPath: keyPath] * 1000).rounded() / 1000
                    }, set: {
                        $0[keyPath: keyPath] = TouchLayoutLimits.clampPosition($1)
                    }),
                    format: .number.precision(.fractionLength(0...3)).grouping(.never)
                )
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 84)

                Stepper(label, value: elementBinding(elementID, get: {
                    $0[keyPath: keyPath]
                }, set: {
                    $0[keyPath: keyPath] = TouchLayoutLimits.clampPosition($1)
                }), step: 0.005)
                .labelsHidden()
            }
        }
    }

    private func appearanceSection(element: OverlayElement) -> some View {
        Section(localizer.string("inspector.appearance")) {
            sliderRow(
                labelKey: "inspector.scale",
                elementID: element.id,
                range: 0.1...4,
                get: { $0.frame.scale },
                set: { $0.frame.scale = $1 }
            )
            sliderRow(
                labelKey: "inspector.textScale",
                elementID: element.id,
                range: 0.1...4,
                get: { $0.frame.style.textScale },
                set: { $0.frame.style.textScale = $1 }
            )
            sliderRow(
                labelKey: "inspector.panelOpacity",
                elementID: element.id,
                range: 0...1,
                get: { $0.frame.style.panelOpacity ?? model.layout.style.panelOpacity },
                set: { $0.frame.style.panelOpacity = $1 }
            )
            if element.kind == .altitudeProfile {
                sliderRow(
                    labelKey: "inspector.width",
                    elementID: element.id,
                    range: 0.25...4,
                    get: { $0.customization.resolvedAltitudeWidthScale },
                    set: { $0.customization.altitudeWidthScale = $1 }
                )
                sliderRow(
                    labelKey: "inspector.height",
                    elementID: element.id,
                    range: 0.25...4,
                    get: { $0.customization.resolvedAltitudeHeightScale },
                    set: { $0.customization.altitudeHeightScale = $1 }
                )
            }

            Picker(localizer.string("inspector.accent"), selection: elementBinding(element.id, get: {
                $0.frame.style.accentColor?.rawValue ?? "global"
            }, set: {
                $0.frame.style.accentColor = OverlayAccentColor(rawValue: $1)
            })) {
                Text(localizer.string("inspector.accent.global")).tag("global")
                ForEach(OverlayAccentColor.allCases) { accent in
                    Text(localizer.string(accent.localizationKey)).tag(accent.rawValue)
                }
            }
        }
    }

    private func contentSection(element: OverlayElement) -> some View {
        Section(localizer.string("inspector.content")) {
            Toggle(localizer.string("inspector.showsPanel"), isOn: elementBinding(element.id, get: {
                $0.customization.showsPanel
            }, set: {
                $0.customization.showsPanel = $1
            }))
            Toggle(localizer.string("inspector.showsLabel"), isOn: elementBinding(element.id, get: {
                $0.customization.showsLabel
            }, set: {
                $0.customization.showsLabel = $1
            }))
            Toggle(localizer.string("inspector.showsUnit"), isOn: elementBinding(element.id, get: {
                $0.customization.showsUnit
            }, set: {
                $0.customization.showsUnit = $1
            }))

            if element.kind == .altitudeProfile {
                Toggle(localizer.string("inspector.showFill"), isOn: elementBinding(element.id, get: {
                    $0.customization.altitudeFillIsVisible
                }, set: {
                    $0.customization.altitudeShowsFill = $1
                }))
                Toggle(localizer.string("inspector.showGrid"), isOn: elementBinding(element.id, get: {
                    $0.customization.altitudeGridIsVisible
                }, set: {
                    $0.customization.altitudeShowsGrid = $1
                }))
                Toggle(localizer.string("inspector.showCursor"), isOn: elementBinding(element.id, get: {
                    $0.customization.altitudeCursorIsVisible
                }, set: {
                    $0.customization.altitudeShowsCursor = $1
                }))
                Toggle(localizer.string("inspector.showMinMax"), isOn: elementBinding(element.id, get: {
                    $0.customization.altitudeMinMaxIsVisible
                }, set: {
                    $0.customization.altitudeShowsMinMax = $1
                }))
                Toggle(localizer.string("inspector.showDistanceLabels"), isOn: elementBinding(element.id, get: {
                    $0.customization.altitudeDistanceLabelsAreVisible
                }, set: {
                    $0.customization.altitudeShowsDistanceLabels = $1
                }))
            }

            if supportsPrecision(element.kind) {
                Stepper(value: elementBinding(element.id, get: {
                    $0.customization.valuePrecision ?? defaultPrecision(element.kind)
                }, set: {
                    $0.customization.valuePrecision = $1
                }), in: 0...3) {
                    LabeledContent(localizer.string("inspector.precision")) {
                        Text("\(element.customization.valuePrecision ?? defaultPrecision(element.kind))")
                    }
                }
            }
        }
    }

    // MARK: - 绑定工具

    private func elementBinding<T>(
        _ elementID: String,
        get: @escaping (OverlayElement) -> T,
        set: @escaping (inout OverlayElement, T) -> Void
    ) -> Binding<T> {
        Binding(
            get: {
                guard let element = model.layout.elements.first(where: { $0.id == elementID }) else {
                    return get(OverlayElement.defaultElement(kind: .speed))
                }
                return get(element)
            },
            set: { newValue in
                model.updateElement(elementID) { element in
                    set(&element, newValue)
                }
            }
        )
    }

    private func sliderRow(
        labelKey: String,
        elementID: String,
        range: ClosedRange<Double>,
        get: @escaping (OverlayElement) -> Double,
        set: @escaping (inout OverlayElement, Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(localizer.string(labelKey))
                Spacer()
                Text(String(format: "%.2f", currentValue(elementID, get: get)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { currentValue(elementID, get: get) },
                    set: { newValue in
                        model.updateElement(elementID, recordUndo: false) { element in
                            set(&element, newValue)
                        }
                    }
                ),
                in: range
            ) { editing in
                if editing {
                    model.beginDragInteraction()
                } else {
                    model.endDragInteraction()
                }
            }
        }
    }

    private func currentValue(_ elementID: String, get: (OverlayElement) -> Double) -> Double {
        guard let element = model.layout.elements.first(where: { $0.id == elementID }) else { return 1 }
        return get(element)
    }

    private func supportsPrecision(_ kind: OverlayComponentID) -> Bool {
        switch kind {
        case .speed, .distance, .ascent, .strideLength, .topProgress,
             .verticalOscillation, .groundContactTime, .groundContactTimePercent,
             .groundContactTimeBalance, .verticalRatio, .respirationRate,
             .stepSpeedLoss, .legSpringStiffness:
            return true
        case .pace, .heartRate, .cadence, .calories, .power, .formPower, .airPower,
             .weather, .route, .altitudeProfile, .timeDate:
            return false
        }
    }

    private func defaultPrecision(_ kind: OverlayComponentID) -> Int {
        switch kind {
        case .speed, .verticalOscillation, .groundContactTimePercent, .groundContactTimeBalance,
             .verticalRatio, .respirationRate, .stepSpeedLoss, .legSpringStiffness, .topProgress:
            return 1
        case .distance, .strideLength:
            return 2
        default:
            return 0
        }
    }
}
#endif
