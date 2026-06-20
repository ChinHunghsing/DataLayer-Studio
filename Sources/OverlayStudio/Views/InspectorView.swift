import SwiftUI
import OverlayCore

struct InspectorView: View {
    @ObservedObject var model: StudioModel
    @State private var expandedSections = InspectorSection.defaultExpandedSections
    @SceneStorage("inspectorSectionScope") private var selectedScopeRawValue = InspectorSectionScope.all.rawValue

    var body: some View {
        VStack(spacing: 0) {
            InspectorSelectionHeader(model: model)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, model.selectedElement == nil ? 12 : 10)

            if model.selectedElement != nil {
                InspectorSectionScopeBar(
                    scopes: availableScopes,
                    selectedScopeRawValue: selectedScopeBinding
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
        let scope = InspectorSectionScope(rawValue: selectedScopeRawValue) ?? .all
        guard let element = model.selectedElement else { return .all }
        return scope.isAvailable(for: element) ? scope : .all
    }

    private var selectedScopeBinding: Binding<String> {
        Binding(
            get: { selectedScope.rawValue },
            set: { rawValue in
                selectedScopeRawValue = rawValue
                if let section = InspectorSectionScope(rawValue: rawValue)?.section {
                    expandedSections.insert(section)
                }
            }
        )
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
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(scopes) { scope in
                    Button {
                        selectedScopeRawValue = scope.rawValue
                    } label: {
                        Label(localization.string(scope.localizationKey), systemImage: scope.systemImage)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .foregroundStyle(selectedScopeRawValue == scope.rawValue ? Color.accentColor : Color.secondary)
                            .background(scopeFill(scope), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(scopeStroke(scope))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localization.string(scope.localizationKey))
                    .accessibilityAddTraits(selectedScopeRawValue == scope.rawValue ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
        .accessibilityLabel(localization.string("inspector.sectionScope"))
    }

    private func scopeFill(_ scope: InspectorSectionScope) -> Color {
        selectedScopeRawValue == scope.rawValue
            ? Color.accentColor.opacity(0.12)
            : Color.secondary.opacity(0.045)
    }

    private func scopeStroke(_ scope: InspectorSectionScope) -> Color {
        selectedScopeRawValue == scope.rawValue
            ? Color.accentColor.opacity(0.34)
            : Color.secondary.opacity(0.07)
    }
}
