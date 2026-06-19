import SwiftUI

struct InspectorView: View {
    @ObservedObject var model: StudioModel
    @State private var expandedSections = Set(InspectorSection.allCases)
    @SceneStorage("inspectorSectionScope") private var selectedScopeRawValue = InspectorSectionScope.all.rawValue

    var body: some View {
        VStack(spacing: 0) {
            InspectorSelectionHeader(model: model)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

            InspectorSectionScopePicker(
                selectedScopeRawValue: $selectedScopeRawValue,
                expandedSections: $expandedSections
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()
                .overlay(Color.secondary.opacity(0.16))

            ScrollView {
                InspectorSettingsPanel(
                    model: model,
                    expandedSections: $expandedSections,
                    focusedSection: selectedScope.section
                )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
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
}

private struct InspectorSectionScopePicker: View {
    @Binding var selectedScopeRawValue: String
    @Binding var expandedSections: Set<InspectorSection>
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        Picker(localization.string("inspector.sectionScope"), selection: selection) {
            ForEach(InspectorSectionScope.allCases) { scope in
                Text(localization.string(scope.localizationKey))
                    .tag(scope.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .accessibilityLabel(localization.string("inspector.sectionScope"))
    }

    private var selection: Binding<String> {
        Binding(
            get: { selectedScopeRawValue },
            set: { newValue in
                selectedScopeRawValue = newValue
                if let section = InspectorSectionScope(rawValue: newValue)?.section {
                    expandedSections.insert(section)
                }
            }
        )
    }
}
