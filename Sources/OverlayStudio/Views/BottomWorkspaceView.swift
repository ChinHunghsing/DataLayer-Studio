import Foundation
import SwiftUI
import OverlayCore

struct BottomWorkspaceView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @SceneStorage("bottomWorkspaceTab") private var selectedTabRawValue = BottomWorkspaceTab.sync.rawValue
    private static let topAnchorID = "bottom-workspace-top"

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    ShellSegmentedTabs(
                        tabs: BottomWorkspaceTab.allCases.map { tab in
                            ShellSegmentedTabs.Tab(
                                id: tab.rawValue,
                                title: localization.string(tab.localizationKey),
                                systemImage: tab.systemImage
                            )
                        },
                        selection: $selectedTabRawValue,
                        accessibilityLabel: localization.string("workspace.tabs")
                    )
                    .frame(width: 330, alignment: .leading)

                    Spacer(minLength: 0)

                    if selectedTab == .timeline {
                        HStack(spacing: 6) {
                            Button {
                                model.setTimelineZoom(model.timelineZoom / 1.5)
                            } label: {
                                Image(systemName: "minus.magnifyingglass")
                            }
                            .buttonStyle(.plain)
                            .disabled(model.timelineZoom <= StudioModel.timelineZoomRange.lowerBound + 1e-6)

                            Slider(
                                value: Binding(
                                    get: { model.timelineZoom },
                                    set: { model.setTimelineZoom($0) }
                                ),
                                in: StudioModel.timelineZoomRange
                            )
                            .frame(width: 110)

                            Button {
                                model.setTimelineZoom(model.timelineZoom * 1.5)
                            } label: {
                                Image(systemName: "plus.magnifyingglass")
                            }
                            .buttonStyle(.plain)
                            .disabled(model.timelineZoom >= StudioModel.timelineZoomRange.upperBound - 1e-6)
                        }
                        .help(localization.string("timeline.zoom.help"))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(localization.string("timeline.zoom"))

                        Button {
                            model.addVideoTimelineTrack()
                        } label: {
                            Label(
                                localization.string("menu.addVideoTimelineTrack"),
                                systemImage: "plus.rectangle.on.rectangle"
                            )
                        }
                        .disabled(model.isExporting)
                        .help(localization.string("menu.addVideoTimelineTrack"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                WorkspaceTaskHint(message: localization.string(selectedTab.hintLocalizationKey))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            if selectedTab == .timeline {
                ProjectTimelineView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        Color.clear
                            .frame(height: 0)
                            .id(Self.topAnchorID)

                        tabContent
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: selectedTabRawValue) { _ in
                        proxy.scrollTo(Self.topAnchorID, anchor: .top)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.bar)
        .controlSize(.small)
        .onAppear {
            if BottomWorkspaceTab(rawValue: selectedTabRawValue) == nil {
                selectedTabRawValue = BottomWorkspaceTab.sync.rawValue
            }
        }
        .onChange(of: model.videoURL) { url in
            if url != nil {
                selectedTabRawValue = BottomWorkspaceTab.sync.rawValue
            }
        }
        .onChange(of: model.fitURL) { url in
            if url != nil {
                selectedTabRawValue = BottomWorkspaceTab.sync.rawValue
            }
        }
    }

    private var selectedTab: BottomWorkspaceTab {
        BottomWorkspaceTab(rawValue: selectedTabRawValue) ?? .sync
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .sync:
            SidebarSyncSection(model: model)
                .disabled(model.isExporting)
        case .timeline:
            EmptyView() // rendered directly in the body (fills the area)
        }
    }
}

private enum BottomWorkspaceTab: String, CaseIterable, Identifiable {
    case sync
    case timeline

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .sync:
            return "workspace.sync"
        case .timeline:
            return "workspace.timeline"
        }
    }

    var hintLocalizationKey: String {
        switch self {
        case .sync:
            return "workspace.sync.hint"
        case .timeline:
            return "workspace.timeline.hint"
        }
    }

    var systemImage: String {
        switch self {
        case .sync:
            return "arrow.left.arrow.right"
        case .timeline:
            return "timeline.selection"
        }
    }
}

private struct WorkspaceTaskHint: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityElement(children: .combine)
    }
}
