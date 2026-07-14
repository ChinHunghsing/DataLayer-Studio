import SwiftUI

struct BottomWorkspaceView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var isTimelineHelpPresented = false
    @AppStorage(TimelineSnappingPreference.defaultsKey) private var isSnappingEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(localization.string("workspace.timeline"), systemImage: "timeline.selection")
                    .font(.subheadline.weight(.semibold))

                Button {
                    isTimelineHelpPresented.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(localization.string("workspace.timeline.hint"))
                .accessibilityLabel(localization.string("workspace.timeline.hint"))
                .popover(isPresented: $isTimelineHelpPresented, arrowEdge: .bottom) {
                    Text(localization.string("workspace.timeline.hint"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(width: 360, alignment: .leading)
                }

                Spacer(minLength: 8)

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
                    .frame(width: 96)

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

                Divider()
                    .frame(height: 18)

                Button {
                    isSnappingEnabled.toggle()
                } label: {
                    Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                        .foregroundStyle(isSnappingEnabled ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(localization.string(isSnappingEnabled ? "timeline.snapping.disable" : "timeline.snapping.enable"))
                .accessibilityLabel(localization.string("timeline.snapping"))
                .accessibilityValue(localization.string(isSnappingEnabled ? "timeline.snapping.on" : "timeline.snapping.off"))

                Divider()
                    .frame(height: 18)

                Menu {
                    Button(localization.string("menu.addVideoTimelineTrack")) {
                        model.addVideoTimelineTrack()
                    }
                    Button(localization.string("menu.addOverlayTimelineTrack")) {
                        model.addOverlayTimelineTrack()
                    }
                } label: {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(model.isExporting)
                .help(localization.string("menu.addTimelineTrack"))
                .accessibilityLabel(localization.string("menu.addTimelineTrack"))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)

            Divider()

            ProjectTimelineView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .background(.bar)
        .controlSize(.small)
    }
}
