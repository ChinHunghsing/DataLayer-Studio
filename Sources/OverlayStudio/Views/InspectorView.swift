import SwiftUI
import OverlayCore

struct InspectorView: View {
    @ObservedObject var model: StudioModel
    @SceneStorage("inspectorSectionScope") private var selectedScopeRawValue = InspectorSectionScope.all.rawValue
    @SceneStorage("inspectorExpandedSections") private var expandedSectionsRawValue = InspectorSection.defaultExpandedSectionsRawValue
    private static let topAnchorID = "inspector-top"

    var body: some View {
        let selectedElement = model.selectedElement

        VStack(spacing: 0) {
            if selectedElement != nil {
                InspectorSelectionHeader(model: model)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                InspectorSectionScopeBar(
                    scopes: availableScopes,
                    selectedScopeRawValue: selectedScopeBinding,
                    expandedSections: expandedSectionsBinding
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

                Divider()
                    .overlay(Color.secondary.opacity(0.16))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchorID)

                    InspectorSettingsPanel(
                        model: model,
                        selectedElement: selectedElement,
                        expandedSections: expandedSectionsBinding,
                        focusedSection: selectedScope.section
                    )
                        .padding(.horizontal, 18)
                        .padding(.top, selectedElement == nil ? 18 : 14)
                        .padding(.bottom, 14)
                }
                .onChange(of: inspectorScrollIdentity) { _ in
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(Self.topAnchorID, anchor: .top)
                    }
                }
            }
        }
        .onAppear(perform: repairSelectedScopeIfNeeded)
        .onChange(of: selectedElementScopeIdentity) { _ in
            repairSelectedScopeIfNeeded()
        }
        .onChange(of: selectedElementKindRawValue) { _ in
            expandedSectionsRawValue = InspectorSection.defaultExpandedSectionsRawValue
        }
    }

    private var selectedScope: InspectorSectionScope {
        let scope = InspectorSectionScope(rawValue: selectedScopeRawValue) ?? .all
        guard let element = model.selectedElement else { return .all }
        return scope.isAvailable(for: element) ? scope : .all
    }

    private var selectedElementScopeIdentity: String {
        guard let element = model.selectedElement else { return "none" }
        return "\(element.id):\(element.kind.rawValue)"
    }

    private var selectedElementKindRawValue: String? {
        model.selectedElement?.kind.rawValue
    }

    private var inspectorScrollIdentity: String {
        "\(selectedElementScopeIdentity):\(selectedScope.rawValue)"
    }

    private func repairSelectedScopeIfNeeded() {
        guard let element = model.selectedElement else {
            selectedScopeRawValue = InspectorSectionScope.all.rawValue
            return
        }

        let scope = InspectorSectionScope(rawValue: selectedScopeRawValue) ?? .all
        if !scope.isAvailable(for: element) {
            selectedScopeRawValue = InspectorSectionScope.all.rawValue
        }
    }

    private var selectedScopeBinding: Binding<String> {
        Binding(
            get: { selectedScope.rawValue },
            set: { rawValue in
                selectedScopeRawValue = rawValue
                if let section = InspectorSectionScope(rawValue: rawValue)?.section {
                    var expandedSections = decodedExpandedSections
                    expandedSections.insert(section)
                    expandedSectionsRawValue = Self.encode(expandedSections)
                }
            }
        )
    }

    private var expandedSectionsBinding: Binding<Set<InspectorSection>> {
        Binding(
            get: { decodedExpandedSections },
            set: { expandedSectionsRawValue = Self.encode($0) }
        )
    }

    private var decodedExpandedSections: Set<InspectorSection> {
        let sections = expandedSectionsRawValue
            .split(separator: ",")
            .compactMap { InspectorSection(rawValue: String($0)) }
        return Set(sections)
    }

    private static func encode(_ sections: Set<InspectorSection>) -> String {
        InspectorSection.displayOrder
            .filter { sections.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    private var availableScopes: [InspectorSectionScope] {
        guard let element = model.selectedElement else { return [.all] }
        return InspectorSectionScope.allCases.filter { $0.isAvailable(for: element) }
    }
}

private enum InspectorSectionScope: String, CaseIterable, Identifiable {
    case all
    case layout
    case content
    case appearance
    case typography
    case data

    var id: String { rawValue }

    var section: InspectorSection? {
        switch self {
        case .all:
            return nil
        case .layout:
            return .layout
        case .content:
            return .content
        case .appearance:
            return .appearance
        case .typography:
            return .typography
        case .data:
            return .data
        }
    }

    var localizationKey: String {
        switch self {
        case .all:
            return "inspector.scope.all"
        case .layout:
            return "inspector.scope.layout"
        case .content:
            return "inspector.scope.content"
        case .appearance:
            return "inspector.scope.appearance"
        case .typography:
            return "inspector.scope.typography"
        case .data:
            return "inspector.scope.data"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .layout:
            return InspectorSection.layout.systemImage
        case .content:
            return InspectorSection.content.systemImage
        case .appearance:
            return InspectorSection.appearance.systemImage
        case .typography:
            return InspectorSection.typography.systemImage
        case .data:
            return InspectorSection.data.systemImage
        }
    }

    func isAvailable(for element: OverlayElement) -> Bool {
        switch self {
        case .all, .layout, .content, .appearance, .typography:
            return true
        case .data:
            return element.kind.supportsValuePrecision || element.kind == .speed
        }
    }
}

private struct InspectorSectionScopeBar: View {
    var scopes: [InspectorSectionScope]
    @Binding var selectedScopeRawValue: String
    @Binding var expandedSections: Set<InspectorSection>
    @EnvironmentObject private var localization: LocalizationStore
    @State private var hoveredScopeRawValue: String?
    @State private var isHoveringSectionActions = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                scopeStrip(showTitles: true)
                scopeStrip(showTitles: false)
            }

            if showsSectionActions {
                Spacer(minLength: 4)

                sectionActions
            }
        }
        .accessibilityLabel(localization.string("inspector.sectionScope"))
    }

    private var showsSectionActions: Bool {
        selectedScopeRawValue == InspectorSectionScope.all.rawValue
    }

    private var sectionActions: some View {
        ViewThatFits(in: .horizontal) {
            directSectionActions
            sectionActionsMenu
        }
    }

    private var directSectionActions: some View {
        HStack(spacing: 2) {
            InspectorSectionActionButton(
                systemName: "rectangle.expand.vertical",
                title: localization.string("inspector.expandAllSections"),
                isDisabled: expandedSections == InspectorSection.defaultExpandedSections
            ) {
                expandedSections = InspectorSection.defaultExpandedSections
            }

            InspectorSectionActionButton(
                systemName: "rectangle.compress.vertical",
                title: localization.string("inspector.collapseAllSections"),
                isDisabled: expandedSections.isEmpty
            ) {
                expandedSections.removeAll()
            }
        }
        .padding(2)
        .background(InspectorStyle.actionGroupFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(InspectorStyle.actionGroupStroke)
        }
        .fixedSize()
    }

    private func scopeStrip(showTitles: Bool) -> some View {
        scopeButtons(showTitles: showTitles)
            .padding(2)
            .background(InspectorStyle.actionGroupFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(InspectorStyle.actionGroupStroke)
            }
    }

    private func scopeButtons(showTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(scopes) { scope in
                scopeButton(scope, showTitle: showTitles)
            }
        }
    }

    private func scopeButton(_ scope: InspectorSectionScope, showTitle: Bool) -> some View {
        let title = localization.string(scope.localizationKey)

        return Button {
            selectedScopeRawValue = scope.rawValue
        } label: {
            HStack(spacing: showTitle ? 5 : 0) {
                Image(systemName: scope.systemImage)
                    .font(.caption.weight(.semibold))

                if showTitle {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: showTitle ? 0 : 30)
            .padding(.horizontal, showTitle ? 8 : 6)
            .padding(.vertical, 5)
            .foregroundStyle(selectedScopeRawValue == scope.rawValue ? Color.accentColor : Color.secondary)
            .background(scopeFill(scope), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(scopeStroke(scope))
            }
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { hovering in
            hoveredScopeRawValue = hovering ? scope.rawValue : nil
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedScopeRawValue == scope.rawValue ? .isSelected : [])
    }

    private var sectionActionsMenu: some View {
        Menu {
            Button {
                expandedSections = InspectorSection.defaultExpandedSections
            } label: {
                Label(localization.string("inspector.expandAllSections"), systemImage: "rectangle.expand.vertical")
            }

            Button {
                expandedSections.removeAll()
            } label: {
                Label(localization.string("inspector.collapseAllSections"), systemImage: "rectangle.compress.vertical")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .background(sectionActionsFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(sectionActionsStroke)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onHover { hovering in
            isHoveringSectionActions = hovering
        }
        .help(localization.string("inspector.sectionActions"))
        .accessibilityLabel(localization.string("inspector.sectionActions"))
    }

    private var sectionActionsFill: Color {
        isHoveringSectionActions ? Color.secondary.opacity(0.08) : InspectorStyle.actionGroupFill
    }

    private var sectionActionsStroke: Color {
        isHoveringSectionActions ? Color.secondary.opacity(0.16) : InspectorStyle.actionGroupStroke
    }

    private func scopeFill(_ scope: InspectorSectionScope) -> Color {
        if selectedScopeRawValue == scope.rawValue {
            return Color.accentColor.opacity(0.12)
        }
        if hoveredScopeRawValue == scope.rawValue {
            return Color.secondary.opacity(0.08)
        }
        return Color.clear
    }

    private func scopeStroke(_ scope: InspectorSectionScope) -> Color {
        if selectedScopeRawValue == scope.rawValue {
            return Color.accentColor.opacity(0.34)
        }
        if hoveredScopeRawValue == scope.rawValue {
            return Color.secondary.opacity(0.16)
        }
        return Color.clear
    }
}

private struct InspectorSectionActionButton: View {
    var systemName: String
    var title: String
    var isDisabled: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(backgroundFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundStyle)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private var foregroundStyle: Color {
        isDisabled ? Color.secondary.opacity(0.42) : Color.secondary
    }

    private var backgroundFill: Color {
        guard !isDisabled, isHovering else { return .clear }
        return Color.secondary.opacity(0.09)
    }
}
