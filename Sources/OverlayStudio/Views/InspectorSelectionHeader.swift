import SwiftUI
import OverlayCore

struct InspectorSelectionHeader: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            titleContent
                .layoutPriority(1)
            Spacer(minLength: 8)
            headerActions
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(InspectorStyle.panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(InspectorStyle.panelStroke)
        }
    }

    @ViewBuilder
    private var titleContent: some View {
        if let element = model.selectedElement {
            HStack(alignment: .center, spacing: 10) {
                symbolBadge(systemName: element.kind.systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(elementDisplayTitle(element))
                        .font(.headline)
                        .lineLimit(1)

                    elementMetadata(element)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                symbolBadge(systemName: "slider.horizontal.3")

                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.string("inspector.noSelection.title"))
                        .font(.headline)
                    Text(localization.string("inspector.noSelection.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func elementMetadata(_ element: OverlayElement) -> some View {
        HStack(spacing: 6) {
            Text(localization.string(element.kind.localizationKey))
                .lineLimit(1)

            if let selectedElementIndex {
                Text("/")
                    .foregroundStyle(.tertiary)

                Text(localization.string("inspector.layerPosition", selectedElementIndex + 1, model.layout.elements.count))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var headerActions: some View {
        if model.selectedElement != nil {
            InspectorHeaderActionGroup {
                addElementMenu(compact: true)
                selectedElementActions
            }
        } else {
            addElementMenu(compact: false)
        }
    }

    private func addElementMenu(compact: Bool) -> some View {
        Menu {
            ForEach(OverlayComponentID.allCases) { component in
                Button {
                    model.addElement(kind: component)
                } label: {
                    Label(localization.string(component.localizationKey), systemImage: component.systemImage)
                }
            }
        } label: {
            if compact {
                actionIcon("plus")
            } else {
                Label(localization.string("inspector.add"), systemImage: "plus")
                    .frame(minWidth: 86)
            }
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .disabled(model.isExporting)
        .help(localization.string("inspector.addElement"))
    }

    @ViewBuilder
    private var selectedElementActions: some View {
        Button {
            model.duplicateSelectedElement()
        } label: {
            actionIcon("doc.on.doc")
        }
        .disabled(model.isExporting)
        .help(localization.string("inspector.duplicate"))

        Menu {
            Button {
                model.moveSelectedElementForward()
            } label: {
                Label(localization.string("inspector.bringForward"), systemImage: "arrow.up")
            }
            .disabled(!canMoveSelectedElementForward || model.isExporting)

            Button {
                model.moveSelectedElementBackward()
            } label: {
                Label(localization.string("inspector.sendBackward"), systemImage: "arrow.down")
            }
            .disabled(!canMoveSelectedElementBackward || model.isExporting)
        } label: {
            actionIcon("square.stack.3d.up")
        }
        .menuStyle(.borderlessButton)
        .disabled(model.isExporting)
        .help(localization.string("inspector.arrange"))

        Button(role: .destructive) {
            model.deleteSelectedElement()
        } label: {
            actionIcon("trash")
        }
        .disabled(model.isExporting)
        .help(localization.string("inspector.delete"))
    }

    private func symbolBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 32, height: 32)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func actionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 24, height: 24)
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

private struct InspectorHeaderActionGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) {
            content()
        }
        .controlSize(.small)
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(InspectorStyle.actionGroupFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(InspectorStyle.actionGroupStroke)
        }
    }
}
