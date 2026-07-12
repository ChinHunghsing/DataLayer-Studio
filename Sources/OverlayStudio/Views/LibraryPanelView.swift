import OverlayCore
import SwiftUI

private enum LibraryTab: String, CaseIterable, Identifiable, Hashable {
    case media
    case components
    case templates

    var id: String { rawValue }
    var localizationKey: String { "library.tab.\(rawValue)" }
    var systemImage: String {
        switch self {
        case .media: return "film.stack"
        case .components: return "gauge.with.dots.needle.67percent"
        case .templates: return "rectangle.3.group"
        }
    }
}

struct LibraryPanelView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @SceneStorage("library.selectedTab") private var selectedTabRawValue = LibraryTab.media.rawValue
    @State private var componentSearch = ""
    @State private var hoveredComponentID: OverlayComponentID?
    @State private var layoutPresetName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            selectedContent
        }
        .background(.bar)
    }

    private var header: some View {
        Picker(localization.string("library.title"), selection: selectedTabBinding) {
            ForEach(LibraryTab.allCases) { tab in
                Label(localization.string(tab.localizationKey), systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .media:
            mediaContent
        case .components:
            componentsContent
        case .templates:
            templatesContent
        }
    }

    private var mediaContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                librarySectionTitle("sidebar.video.title")
                MediaPoolList(
                    kindTitle: localization.string("sidebar.video.title"),
                    placeholder: localization.string("sidebar.video.placeholder"),
                    systemImage: "film",
                    assets: model.videoAssets,
                    selectedID: model.selectedMediaAssetID,
                    inUseIDs: model.timelineAssetIDsInUse,
                    offlineReasons: model.offlineTimelineAssetReasons,
                    addTitle: localization.string("mediapool.addVideo"),
                    select: model.selectMediaAsset,
                    remove: model.removeVideoAsset,
                    relink: model.chooseReplacementForTimelineAsset,
                    appendToTimeline: model.addVideoAssetToTimeline,
                    timelineDragPayload: { TimelineDragPayload.video(assetID: $0.id) },
                    add: model.chooseVideo
                )

                if let failure = model.videoLoadFailure {
                    LibrarySourceLoadFailureRow(
                        message: localization.string(failure.messageKey, failure.detail),
                        retryTitle: localization.string("sidebar.retryLoad"),
                        retry: model.retryVideoLoad
                    )
                }

                librarySectionTitle("sidebar.fit.title")
                MediaPoolList(
                    kindTitle: localization.string("sidebar.fit.title"),
                    placeholder: localization.string("sidebar.fit.placeholder"),
                    systemImage: "figure.run",
                    assets: model.activityAssets,
                    selectedID: model.selectedMediaAssetID,
                    inUseIDs: model.timelineAssetIDsInUse,
                    offlineReasons: model.offlineTimelineAssetReasons,
                    addTitle: localization.string("mediapool.addActivity"),
                    select: model.selectMediaAsset,
                    remove: model.removeActivityAsset,
                    relink: model.chooseReplacementForTimelineAsset,
                    appendToTimeline: model.addActivityAssetToTimeline,
                    timelineDragPayload: { TimelineDragPayload.activity(assetID: $0.id) },
                    add: model.chooseFIT
                )

                if let failure = model.fitLoadFailure {
                    LibrarySourceLoadFailureRow(
                        message: localization.string(failure.messageKey, failure.detail),
                        retryTitle: localization.string("sidebar.retryLoad"),
                        retry: model.retryFITLoad
                    )
                }

                counterpartPrompt
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var counterpartPrompt: some View {
        if !model.videoAssets.isEmpty, model.activityAssets.isEmpty {
            inlinePrompt(
                "library.media.addActivityPrompt",
                buttonKey: "startupPrompt.chooseActivity",
                systemImage: "figure.run",
                action: model.chooseFIT
            )
        } else if model.videoAssets.isEmpty, !model.activityAssets.isEmpty {
            inlinePrompt(
                "library.media.addVideoPrompt",
                buttonKey: "startupPrompt.chooseVideo",
                systemImage: "film",
                action: model.chooseVideo
            )
        }
    }

    private func inlinePrompt(
        _ messageKey: String,
        buttonKey: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string(messageKey))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: action) {
                Label(localization.string(buttonKey), systemImage: systemImage)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var componentsContent: some View {
        VStack(spacing: 0) {
            TextField(localization.string("library.components.search"), text: $componentSearch)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(ComponentCatalogGroup.allCases) { group in
                        let items = filteredComponents(in: group)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                librarySectionTitle(group.localizationKey)
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
                                    spacing: 8
                                ) {
                                    ForEach(items) { item in
                                        componentCard(item)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func filteredComponents(in group: ComponentCatalogGroup) -> [ComponentCatalogItem] {
        ComponentCatalogItem.all.filter { item in
            guard item.group == group else { return false }
            let query = componentSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty
                || localization.string(item.component.localizationKey).localizedCaseInsensitiveContains(query)
        }
    }

    private func componentCard(_ item: ComponentCatalogItem) -> some View {
        let isAvailable = model.canAddElement(kind: item.component)
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image = ComponentThumbnailLoader.image(named: item.thumbnailResourceName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.black.opacity(0.82)
                        Image(systemName: item.component.systemImage)
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(localization.string(item.component.localizationKey))
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if !isAvailable {
                Text(localization.string("library.components.missingData"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(7)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(Color.secondary.opacity(isAvailable ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isAvailable ? 1 : 0.55)
        .overlay(alignment: .topTrailing) {
            if isAvailable, hoveredComponentID == item.component {
                Button {
                    addComponentCentered(item.component)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .help(localization.string("inspector.add"))
            }
        }
        .onHover { isHovered in
            hoveredComponentID = isHovered ? item.component : nil
        }
        .onTapGesture(count: 2) {
            guard isAvailable else { return }
            addComponentCentered(item.component)
        }
        .modifier(ComponentCatalogDragModifier(
            payload: isAvailable ? ComponentDragPayload.value(for: item.component) : nil
        ))
        .contextMenu {
            Button {
                addComponentCentered(item.component)
            } label: {
                Label(localization.string("inspector.add"), systemImage: "plus")
            }
            .disabled(!isAvailable)
        }
        .help(localization.string(isAvailable ? item.component.localizationKey : "library.components.missingData"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string(item.component.localizationKey))
        .accessibilityHint(localization.string(isAvailable ? "library.components.addHint" : "library.components.missingData"))
        .accessibilityAction(named: Text(localization.string("inspector.add"))) {
            guard isAvailable else { return }
            addComponentCentered(item.component)
        }
    }

    private func addComponentCentered(_ component: OverlayComponentID) {
        model.addElementCentered(kind: component)
    }

    private var templatesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                layoutPresetSyncStatusRow

                HStack(spacing: 8) {
                    TextField(localization.string("sidebar.presetName"), text: $layoutPresetName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if model.saveLayoutPreset(named: layoutPresetName) {
                            layoutPresetName = ""
                        }
                    } label: {
                        Label(localization.string("sidebar.save"), systemImage: "plus")
                    }
                    .disabled(layoutPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack(spacing: 8) {
                    Button {
                        model.importLayoutPresets()
                    } label: {
                        Label(localization.string("sidebar.import"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        model.exportLayoutPresets()
                    } label: {
                        Label(localization.string("sidebar.export"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.layoutPresets.isEmpty)
                }
                .controlSize(.small)

                if model.layoutPresetsForDisplay.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.3.group")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(localization.string("library.templates.empty"))
                            .font(.callout)
                        Text(localization.string("library.templates.emptyHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                        ForEach(model.layoutPresetsForDisplay) { preset in
                            templateCard(preset)
                        }
                    }
                }
            }
            .padding(12)
        }
        .disabled(model.isExporting)
    }

    private func templateCard(_ preset: LayoutPreset) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                model.applyLayoutPreset(id: preset.id)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    LayoutPresetThumbnailView(layout: preset.layout)
                        .frame(height: 76)
                    HStack(spacing: 5) {
                        Text(preset.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if model.defaultLayoutPresetID == preset.id {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            HStack {
                Button(localization.string("library.templates.makeDefault")) {
                    model.setDefaultLayoutPreset(id: preset.id)
                }
                .buttonStyle(.borderless)
                .disabled(model.defaultLayoutPresetID == preset.id)
                Spacer()
                Button(role: .destructive) {
                    model.deleteLayoutPreset(id: preset.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption2)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var layoutPresetSyncStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: layoutPresetSyncStatusIcon)
                .foregroundStyle(model.layoutPresetSyncStatus == .localOnly ? Color.secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(localization.string("sidebar.presetSync.title"))
                    .font(.caption.weight(.semibold))
                Text(layoutPresetSyncStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(9)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var layoutPresetSyncStatusIcon: String {
        switch model.layoutPresetSyncStatus {
        case .localOnly: return "icloud.slash"
        case .ready: return "icloud"
        case .uploadRequested: return "icloud.and.arrow.up"
        case .receivedUpdate: return "icloud.and.arrow.down"
        }
    }

    private var layoutPresetSyncStatusText: String {
        switch model.layoutPresetSyncStatus {
        case .localOnly:
            return localization.string("sidebar.presetSync.localOnly")
        case .ready:
            return localization.string("sidebar.presetSync.ready")
        case let .uploadRequested(date):
            return localization.string("sidebar.presetSync.uploadRequested", date.formatted(.dateTime.hour().minute()))
        case let .receivedUpdate(date):
            return localization.string("sidebar.presetSync.receivedUpdate", date.formatted(.dateTime.hour().minute()))
        }
    }

    private func librarySectionTitle(_ key: String) -> some View {
        Text(localization.string(key))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var selectedTab: LibraryTab {
        LibraryTab(rawValue: selectedTabRawValue) ?? .media
    }

    private var selectedTabBinding: Binding<LibraryTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTabRawValue = $0.rawValue }
        )
    }
}

private struct ComponentCatalogDragModifier: ViewModifier {
    var payload: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let payload {
            content.onDrag { NSItemProvider(object: payload as NSString) }
        } else {
            content
        }
    }
}

private struct LibrarySourceLoadFailureRow: View {
    var message: String
    var retryTitle: String
    var retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(retryTitle, action: retry)
                .controlSize(.small)
        }
        .padding(9)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
