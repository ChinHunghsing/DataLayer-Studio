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
        case .trim:
            trimContent
        case .timeline:
            EmptyView() // rendered directly in the body (fills the area)
        }
    }

    private var trimContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                activityTrimRangeCard
                exportTrimRangeCard
            }
            VStack(alignment: .leading, spacing: 12) {
                activityTrimRangeCard
                exportTrimRangeCard
            }
        }
    }

    private var exportTrimRangeCard: some View {
        ExportTrimRangeControl(
            start: Binding(
                get: { model.effectiveExportTrimStart },
                set: { model.setExportTrimStart($0) }
            ),
            end: Binding(
                get: { model.effectiveExportTrimEnd },
                set: { model.setExportTrimEnd($0) }
            ),
            sourceDuration: model.exportTrimSourceDuration,
            currentTime: model.previewTime,
            reset: { model.resetExportTrimRange() },
            formatTime: formatTrimTime
        )
        .disabled(model.isExporting || model.exportTrimSourceDuration <= 0)
    }

    private var activityTrimRangeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExportTrimRangeControl(
                start: Binding(
                    get: { model.effectiveActivityTrimStart },
                    set: { model.setActivityTrimStart($0) }
                ),
                end: Binding(
                    get: { model.effectiveActivityTrimEnd },
                    set: { model.setActivityTrimEnd($0) }
                ),
                sourceDuration: model.activityTrimSourceDuration,
                currentTime: model.currentActivityElapsedForTrim,
                titleKey: "sidebar.activityRange",
                fullKey: "sidebar.activityRange.full",
                setStartKey: "sidebar.activityRange.setStart",
                setEndKey: "sidebar.activityRange.setEnd",
                reset: { model.resetActivityTrimRange() },
                formatTime: formatTrimTime
            )
            Text(localization.string("sidebar.activityRange.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(model.isExporting || model.activityTrimSourceDuration <= 0)
    }

    private func formatTrimTime(_ seconds: TimeInterval) -> String {
        let milliseconds = max(0, Int((seconds * 1000).rounded()))
        let ms = milliseconds % 1000
        let totalSeconds = milliseconds / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, secs, ms)
        }
        return String(format: "%02d:%02d.%03d", minutes, secs, ms)
    }
}

private enum BottomWorkspaceTab: String, CaseIterable, Identifiable {
    case sync
    case trim
    case timeline

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .sync:
            return "workspace.sync"
        case .trim:
            return "workspace.trim"
        case .timeline:
            return "workspace.timeline"
        }
    }

    var hintLocalizationKey: String {
        switch self {
        case .sync:
            return "workspace.sync.hint"
        case .trim:
            return "workspace.trim.hint"
        case .timeline:
            return "workspace.timeline.hint"
        }
    }

    var systemImage: String {
        switch self {
        case .sync:
            return "arrow.left.arrow.right"
        case .trim:
            return "scissors"
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
