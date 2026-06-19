import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: StudioModel
    @State private var expandedSections = Set(InspectorSection.allCases)
    @SceneStorage("inspectorSectionScope") private var selectedScopeRawValue = InspectorSectionScope.all.rawValue

    var body: some View {
        VStack(spacing: 0) {
            InspectorSelectionHeader(model: model)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, model.selectedElement == nil ? 12 : 10)

            if model.selectedElement != nil {
                InspectorSectionScopeBar(
                    selectedScopeRawValue: $selectedScopeRawValue,
                    expandedSections: $expandedSections
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }

            Divider()
                .overlay(Color.secondary.opacity(0.16))

            ScrollView {
                InspectorSettingsPanel(
                    model: model,
                    expandedSections: $expandedSections,
                    focusedSection: selectedScope.section
                )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
        }
    }

    private var selectedScope: InspectorSectionScope {
        InspectorSectionScope(rawValue: selectedScopeRawValue) ?? .all
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
}

private struct InspectorSectionScopeBar: View {
    @Binding var selectedScopeRawValue: String
    @Binding var expandedSections: Set<InspectorSection>
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(InspectorSectionScope.allCases) { scope in
                Button {
                    select(scope)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: scope.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 13)

                        Text(localization.string(scope.localizationKey))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(isSelected(scope) ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .padding(.horizontal, 4)
                    .background(scopeBackground(for: scope), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(scopeStroke(for: scope))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(localization.string(scope.localizationKey))
            }
        }
        .padding(3)
        .background(InspectorStyle.scopeBarFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(InspectorStyle.scopeBarStroke)
        }
        .accessibilityLabel(localization.string("inspector.sectionScope"))
    }

    private func isSelected(_ scope: InspectorSectionScope) -> Bool {
        selectedScopeRawValue == scope.rawValue
    }

    private func select(_ scope: InspectorSectionScope) {
        selectedScopeRawValue = scope.rawValue
        if let section = scope.section {
            expandedSections.insert(section)
        }
    }

    private func scopeBackground(for scope: InspectorSectionScope) -> Color {
        isSelected(scope) ? InspectorStyle.scopeSelectedFill : Color.clear
    }

    private func scopeStroke(for scope: InspectorSectionScope) -> Color {
        isSelected(scope) ? InspectorStyle.scopeSelectedStroke : Color.clear
    }
}
