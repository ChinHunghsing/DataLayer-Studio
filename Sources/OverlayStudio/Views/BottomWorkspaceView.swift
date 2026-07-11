import SwiftUI

struct BottomWorkspaceView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    Label(localization.string("workspace.timeline"), systemImage: "timeline.selection")
                        .font(.headline.weight(.semibold))

                    Spacer(minLength: 0)

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

                    Menu {
                        Button(localization.string("menu.addVideoTimelineTrack")) {
                            model.addVideoTimelineTrack()
                        }
                        Button(localization.string("menu.addOverlayTimelineTrack")) {
                            model.addOverlayTimelineTrack()
                        }
                    } label: {
                        Label(
                            localization.string("menu.addTimelineTrack"),
                            systemImage: "plus.rectangle.on.rectangle"
                        )
                    }
                    .disabled(model.isExporting)
                    .help(localization.string("menu.addTimelineTrack"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                WorkspaceTaskHint(message: localization.string("workspace.timeline.hint"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            ProjectTimelineView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .background(.bar)
        .controlSize(.small)
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
