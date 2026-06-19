import SwiftUI
import OverlayCore

struct InspectorSelectionHeader: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        HStack(spacing: 12) {
            titleContent
            Spacer()
            actions
        }
        .buttonStyle(.borderless)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var titleContent: some View {
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
    }

    private var actions: some View {
        HStack(spacing: 8) {
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

    private func elementDisplayTitle(_ element: OverlayElement) -> String {
        element.customization.label(default: localization.string(element.kind.localizationKey))
    }
}
