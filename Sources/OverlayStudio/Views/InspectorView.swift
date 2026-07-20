import SwiftUI
import OverlayCore

struct InspectorView: View {
    @ObservedObject var model: StudioModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @SceneStorage("inspectorSectionScope") private var selectedScopeRawValue = InspectorSectionScope.content.rawValue
    @SceneStorage("inspectorExpandedSections") private var expandedSectionsRawValue = InspectorSection.defaultExpandedSectionsRawValue
    private static let topAnchorID = "inspector-top"

    var body: some View {
        let selectedClip = model.selectedTimelineClip
        let selectedElement = model.selectedElement
        let selectedMedia = model.selectedMediaAsset

        VStack(spacing: 0) {
            if let selectedMedia {
                HStack(spacing: 9) {
                    Image(systemName: selectedMedia.kind == .video ? "film" : "figure.run")
                        .foregroundStyle(Color.accentColor)
                    Text(selectedMedia.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

                Divider()
                    .overlay(Color.secondary.opacity(0.16))
            } else if let selectedClip {
                TimelineClipInspectorHeader(model: model, clip: selectedClip)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider()
                    .overlay(Color.secondary.opacity(0.16))
            } else if selectedElement != nil {
                InspectorSelectionHeader(model: model)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                InspectorSectionScopeBar(
                    scopes: availableScopes,
                    selectedScopeRawValue: selectedScopeBinding
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

                    Group {
                        if let selectedMedia {
                            MediaAssetInspectorView(model: model, asset: selectedMedia)
                        } else if let selectedClip {
                            TimelineClipInspectorView(model: model, clip: selectedClip)
                        } else {
                            InspectorSettingsPanel(
                                model: model,
                                selectedElement: selectedElement,
                                expandedSections: expandedSectionsBinding,
                                focusedSection: selectedScope.section
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, selectedClip == nil && selectedElement == nil && selectedMedia == nil ? 18 : 14)
                    .padding(.bottom, 14)
                }
                .onChange(of: inspectorScrollIdentity) { _ in
                    withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16)) {
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
        .onChange(of: model.selectedElementPart) { part in
            if part != nil {
                selectedScopeRawValue = InspectorSectionScope.style.rawValue
            }
        }
    }

    private var selectedScope: InspectorSectionScope {
        let scope = InspectorSectionScope(rawValue: selectedScopeRawValue) ?? .content
        guard let element = model.selectedElement else { return .content }
        return scope.isAvailable(for: element) ? scope : .content
    }

    private var selectedElementScopeIdentity: String {
        guard let element = model.selectedElement else { return "none" }
        return "\(element.id):\(element.kind.rawValue)"
    }

    private var selectedElementKindRawValue: String? {
        model.selectedElement?.kind.rawValue
    }

    private var inspectorScrollIdentity: String {
        if let mediaID = model.selectedMediaAssetID {
            return "media:\(mediaID)"
        }
        if let clipID = model.selectedTimelineClipID {
            return "timeline:\(clipID)"
        }
        return "\(selectedElementScopeIdentity):\(selectedScope.rawValue)"
    }

    private func repairSelectedScopeIfNeeded() {
        guard let element = model.selectedElement else {
            selectedScopeRawValue = InspectorSectionScope.content.rawValue
            return
        }

        guard let scope = InspectorSectionScope(rawValue: selectedScopeRawValue) else {
            selectedScopeRawValue = InspectorSectionScope.content.rawValue
            return
        }

        if !scope.isAvailable(for: element) {
            selectedScopeRawValue = InspectorSectionScope.content.rawValue
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
        guard let element = model.selectedElement else { return [] }
        return InspectorSectionScope.allCases.filter { $0.isAvailable(for: element) }
    }
}

private enum InspectorSectionScope: String, CaseIterable, Identifiable {
    case content
    case style
    case data

    var id: String { rawValue }

    var section: InspectorSection {
        switch self {
        case .content:
            return .content
        case .style:
            return .style
        case .data:
            return .data
        }
    }

    var localizationKey: String {
        switch self {
        case .content:
            return "inspector.scope.content"
        case .style:
            return "inspector.scope.style"
        case .data:
            return "inspector.scope.data"
        }
    }

    var systemImage: String {
        switch self {
        case .content:
            return InspectorSection.content.systemImage
        case .style:
            return InspectorSection.style.systemImage
        case .data:
            return InspectorSection.data.systemImage
        }
    }

    func isAvailable(for element: OverlayElement) -> Bool {
        switch self {
        case .content, .style:
            return true
        case .data:
            return element.kind.supportsValuePrecision || element.kind == .speed || element.kind == .weather
        }
    }
}

private struct InspectorSectionScopeBar: View {
    var scopes: [InspectorSectionScope]
    @Binding var selectedScopeRawValue: String
    @EnvironmentObject private var localization: LocalizationStore
    @State private var hoveredScopeRawValue: String?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                scopeStrip(showTitles: true)
                scopeStrip(showTitles: false)
            }
        }
        .accessibilityLabel(localization.string("inspector.sectionScope"))
    }

    private func scopeStrip(showTitles: Bool) -> some View {
        scopeButtons(showTitles: showTitles)
            .padding(3)
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
                    .font(.body.weight(.semibold))

                if showTitle {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: showTitle ? 0 : 30)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
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
