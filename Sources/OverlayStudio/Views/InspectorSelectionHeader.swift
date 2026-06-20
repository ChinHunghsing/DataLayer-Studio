import SwiftUI
import OverlayCore

struct InspectorSelectionHeader: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalHeader
            stackedHeader
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(InspectorStyle.headerFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(InspectorStyle.headerStroke)
        }
    }

    private var horizontalHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            titleContent
                .layoutPriority(1)
            Spacer(minLength: 8)
            headerActions
        }
    }

    private var stackedHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleContent
                .frame(maxWidth: .infinity, alignment: .leading)

            headerActions
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var titleContent: some View {
        if let element = model.selectedElement {
            HStack(alignment: .center, spacing: 8) {
                symbolBadge(systemName: element.kind.systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    Text(elementDisplayTitle(element))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    elementMetadata(element)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                symbolBadge(systemName: "slider.horizontal.3")

                VStack(alignment: .leading, spacing: 2) {
                    Text(localization.string("inspector.noSelection.title"))
                        .font(.subheadline.weight(.semibold))
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
                metadataSeparator

                Text(localization.string("inspector.layerPosition", selectedElementIndex + 1, model.layout.elements.count))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            if !element.frame.isVisible {
                metadataSeparator

                Text(localization.string("inspector.hiddenElement.badge"))
                    .lineLimit(1)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var metadataSeparator: some View {
        Circle()
            .fill(Color.secondary.opacity(0.42))
            .frame(width: 3, height: 3)
    }

    @ViewBuilder
    private var headerActions: some View {
        if let element = model.selectedElement {
            InspectorHeaderActionGroup {
                addElementMenu(compact: true)
                InspectorHeaderActionDivider()
                selectedElementActions(for: element)
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
    private func selectedElementActions(for element: OverlayElement) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                visibilityButton(for: element)
                InspectorHeaderActionDivider()
                duplicateButton
                sendBackwardButton
                bringForwardButton
                InspectorHeaderActionDivider()
                deleteButton
            }

            HStack(spacing: 2) {
                visibilityButton(for: element)
                compactActionsMenu
            }
        }
    }

    private func visibilityButton(for element: OverlayElement) -> some View {
        Button {
            toggleVisibility(of: element)
        } label: {
            actionIcon(element.frame.isVisible ? "eye" : "eye.slash")
        }
        .disabled(model.isExporting)
        .help(localization.string(element.frame.isVisible ? "inspector.hideElement.action" : "inspector.hiddenElement.action"))
        .accessibilityLabel(localization.string(element.frame.isVisible ? "inspector.hideElement.action" : "inspector.hiddenElement.action"))
    }

    private var duplicateButton: some View {
        Button {
            model.duplicateSelectedElement()
        } label: {
            actionIcon("doc.on.doc")
        }
        .disabled(model.isExporting)
        .help(localization.string("inspector.duplicate"))
        .accessibilityLabel(localization.string("inspector.duplicate"))
    }

    private var bringForwardButton: some View {
        Button {
            model.moveSelectedElementForward()
        } label: {
            actionIcon("arrow.up")
        }
        .disabled(model.isExporting || !canMoveSelectedElementForward)
        .help(localization.string("inspector.bringForward"))
        .accessibilityLabel(localization.string("inspector.bringForward"))
    }

    private var sendBackwardButton: some View {
        Button {
            model.moveSelectedElementBackward()
        } label: {
            actionIcon("arrow.down")
        }
        .disabled(model.isExporting || !canMoveSelectedElementBackward)
        .help(localization.string("inspector.sendBackward"))
        .accessibilityLabel(localization.string("inspector.sendBackward"))
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.deleteSelectedElement()
        } label: {
            actionIcon("trash", foregroundStyle: .red, isDestructive: true)
        }
        .disabled(model.isExporting)
        .help(localization.string("inspector.delete"))
        .accessibilityLabel(localization.string("inspector.delete"))
    }

    private var compactActionsMenu: some View {
        Menu {
            Button {
                model.duplicateSelectedElement()
            } label: {
                Label(localization.string("inspector.duplicate"), systemImage: "doc.on.doc")
            }
            .disabled(model.isExporting)

            Divider()

            Button {
                model.moveSelectedElementForward()
            } label: {
                Label(localization.string("inspector.bringForward"), systemImage: "arrow.up")
            }
            .disabled(model.isExporting || !canMoveSelectedElementForward)

            Button {
                model.moveSelectedElementBackward()
            } label: {
                Label(localization.string("inspector.sendBackward"), systemImage: "arrow.down")
            }
            .disabled(model.isExporting || !canMoveSelectedElementBackward)

            Divider()

            Button(role: .destructive) {
                model.deleteSelectedElement()
            } label: {
                Label(localization.string("inspector.delete"), systemImage: "trash")
            }
            .disabled(model.isExporting)
        } label: {
            actionIcon("ellipsis")
        }
        .menuStyle(.borderlessButton)
        .disabled(model.isExporting)
        .help(localization.string("inspector.moreActions"))
        .accessibilityLabel(localization.string("inspector.moreActions"))
    }

    private func symbolBadge(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(Color.secondary.opacity(0.075), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.06))
            }
    }

    private func actionIcon(_ systemName: String, foregroundStyle: Color? = nil, isDestructive: Bool = false) -> some View {
        InspectorHeaderActionIcon(systemName: systemName, foregroundStyle: foregroundStyle, isDestructive: isDestructive)
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

    private func toggleVisibility(of element: OverlayElement) {
        model.updateElement(element.id) { element in
            element.frame.isVisible.toggle()
        }
    }

    private func elementDisplayTitle(_ element: OverlayElement) -> String {
        element.customization.label(default: localization.string(element.kind.localizationKey))
    }
}

private struct InspectorHeaderActionIcon: View {
    var systemName: String
    var foregroundStyle: Color?
    var isDestructive: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(currentForegroundStyle)
            .frame(width: 22, height: 22)
            .background(backgroundFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var currentForegroundStyle: Color {
        guard isEnabled else { return Color.secondary.opacity(0.46) }
        return foregroundStyle ?? Color.primary
    }

    private var backgroundFill: Color {
        guard isEnabled, isHovering else { return Color.clear }
        if isDestructive {
            return Color.red.opacity(0.12)
        }
        return Color.secondary.opacity(0.09)
    }
}

private struct InspectorHeaderActionGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) {
            content()
        }
        .controlSize(.small)
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(InspectorStyle.actionGroupFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(InspectorStyle.actionGroupStroke)
        }
    }
}

private struct InspectorHeaderActionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.16))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
    }
}
