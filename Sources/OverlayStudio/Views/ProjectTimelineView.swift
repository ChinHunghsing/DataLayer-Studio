import SwiftUI
import UniformTypeIdentifiers
import OverlayCore

/// Timeline editor for the current project. Every clip owns its relative timeline position;
/// source match-point controls can align clips, but dragging never rewrites those source times.
/// Dragging the playhead scrubs the same timeline state consumed by preview and export.
struct ProjectTimelineView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    private let headerWidth: CGFloat = 116
    private let rulerHeight: CGFloat = 24
    private let trackHeight: CGFloat = 48
    private let playheadColor = Color(red: 1.0, green: 0.42, blue: 0.34)

    @State private var dragClipID: String?
    @State private var dragStartClipTimelineStart: TimeInterval?
    @State private var dragTimelineDuration: TimeInterval?
    @State private var clipTrimID: String?
    @State private var clipTrimIsStart: Bool?
    @State private var clipTrimBaseTime: TimeInterval?
    @State private var trimDragStart: TimeInterval?
    @State private var trimDragEnd: TimeInterval?

    var body: some View {
        let project = model.currentTimelineProject
        let duration = max(0.001, max(project.duration, model.previewDuration))
        // Display overlays on top, video at the bottom (project.tracks is bottom-to-top).
        let displayTracks = Array(project.tracks.reversed())

        Group {
            if project.tracks.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    let laneWidth = max(1, proxy.size.width - headerWidth)
                    let clampedProgress = min(1, max(0, model.previewTime / duration))
                    let playheadX = headerWidth + CGFloat(clampedProgress) * laneWidth

                    ZStack(alignment: .topLeading) {
                        // Scrub layer (bottom): empty lane areas and video clips pass through to here.
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: headerWidth)
                                .allowsHitTesting(false)
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: laneWidth)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            model.scrubPreview(
                                                to: Self.scrubTime(
                                                    laneLocationX: value.location.x,
                                                    laneWidth: laneWidth,
                                                    duration: duration
                                                )
                                            )
                                        }
                                )
                        }

                        // Tracks and clips capture their own move/trim gestures.
                        VStack(spacing: 0) {
                            ruler(duration: duration, laneWidth: laneWidth)
                            ForEach(displayTracks) { track in
                                trackRow(track, project: project, duration: duration, laneWidth: laneWidth)
                            }
                            Spacer(minLength: 0)
                        }
                        .allowsHitTesting(true)

                        // Export range (in/out band): dims excluded regions, drag edges to trim.
                        exportRangeLayer(duration: duration, laneWidth: laneWidth)

                        // Playhead
                        Rectangle()
                            .fill(playheadColor)
                            .frame(width: 2)
                            .offset(x: playheadX - 1)
                            .shadow(color: playheadColor.opacity(0.6), radius: 3)
                            .allowsHitTesting(false)
                        Path { p in
                            p.move(to: CGPoint(x: playheadX - 6, y: 0))
                            p.addLine(to: CGPoint(x: playheadX + 6, y: 0))
                            p.addLine(to: CGPoint(x: playheadX, y: 8))
                            p.closeSubpath()
                        }
                        .fill(playheadColor)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    static func scrubTime(
        laneLocationX: CGFloat,
        laneWidth: CGFloat,
        duration: TimeInterval
    ) -> TimeInterval {
        guard laneLocationX.isFinite,
              laneWidth.isFinite,
              laneWidth > 0,
              duration.isFinite,
              duration > 0 else { return 0 }
        let progress = min(1, max(0, laneLocationX / laneWidth))
        return Double(progress) * duration
    }

    static func trimSnapTime(
        project: TimelineProject,
        proposedTime: TimeInterval,
        threshold: TimeInterval,
        clipID: String,
        playheadTime: TimeInterval
    ) -> TimeInterval {
        project.snappedTimelineTime(
            proposedTime,
            threshold: threshold,
            excludingClipID: clipID,
            additionalCandidates: [playheadTime]
        )
    }

    // MARK: ruler

    private func ruler(duration: TimeInterval, laneWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: headerWidth)
            ZStack(alignment: .topLeading) {
                ForEach(tickTimes(duration: duration), id: \.self) { t in
                    let x = CGFloat(t / duration) * laneWidth
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1, height: rulerHeight)
                        Text(timecode(t))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                            .padding(.top, 4)
                    }
                    .offset(x: x)
                }
            }
            .frame(width: laneWidth, height: rulerHeight, alignment: .topLeading)
        }
        .frame(height: rulerHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: track row

    private func trackRow(_ track: TimelineTrack, project: TimelineProject, duration: TimeInterval, laneWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // header
            HStack(spacing: 8) {
                Text(trackBadge(track))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(track.kind == .video ? Color.secondary : Color.accentColor)
                    .frame(width: 22, height: 18)
                    .background(
                        (track.kind == .video ? Color.secondary.opacity(0.16) : ShellStyle.accentSoft),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                Text(track.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(width: headerWidth, height: trackHeight)
            .background(.bar)
            .overlay(alignment: .trailing) { Divider() }

            // lane
            ZStack(alignment: .topLeading) {
                ForEach(track.clips) { clip in
                    clipView(clip, project: project, kind: track.kind, duration: duration, laneWidth: laneWidth)
                }
            }
            .frame(width: laneWidth, height: trackHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .onDrop(of: [.plainText], isTargeted: nil) { providers, location in
                handleActivityDrop(
                    providers,
                    onTrack: track,
                    atX: location.x,
                    laneWidth: laneWidth,
                    duration: duration
                )
            }
        }
        .frame(height: trackHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func handleActivityDrop(
        _ providers: [NSItemProvider],
        onTrack track: TimelineTrack,
        atX locationX: CGFloat,
        laneWidth: CGFloat,
        duration: TimeInterval
    ) -> Bool {
        guard track.kind == .overlay else { return false }
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        guard laneWidth > 0, duration > 0 else { return false }
        let timelineStart = min(duration, max(0, Double(locationX / laneWidth) * duration))
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString,
                  let assetID = TimelineDragPayload.activityAssetID(from: String(payload)) else { return }
            DispatchQueue.main.async {
                model.addActivityAssetToTimeline(
                    id: assetID,
                    targetTrackID: track.id,
                    timelineStart: timelineStart
                )
            }
        }
        return true
    }

    @ViewBuilder
    private func clipView(_ clip: TimelineClip, project: TimelineProject, kind: TimelineTrack.Kind, duration: TimeInterval, laneWidth: CGFloat) -> some View {
        let x = CGFloat(clip.timelineStart / duration) * laneWidth
        let width = max(6, CGFloat(clip.duration / duration) * laneWidth)
        let name = project.asset(id: clip.assetID)?.displayName ?? clip.assetID
        let isSelected = model.selectedTimelineClipID == clip.id

        let clipBody = RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(clipFill(kind))
            .overlay(alignment: .leading) {
                Text(name)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.18),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .frame(width: width, height: trackHeight - 12)

        let block = ZStack {
            clipBody
            if width > 22 {
                HStack {
                    clipTrimHandle(clip: clip, project: project, isStart: true, laneWidth: laneWidth, duration: duration)
                    Spacer(minLength: 0)
                    clipTrimHandle(clip: clip, project: project, isStart: false, laneWidth: laneWidth, duration: duration)
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(width: width, height: trackHeight - 12)
        .offset(x: x, y: 6)
        .onTapGesture {
            model.selectTimelineClip(id: clip.id)
        }
        .contextMenu {
            Button(localization.string("menu.splitTimelineClips")) {
                model.splitTimelineClipsAtPlayhead()
            }
            .disabled(!model.canSplitTimelineClipsAtPlayhead)

            Divider()

            Button(localization.string("menu.deleteTimelineClip")) {
                model.deleteTimelineClip(id: clip.id, ripple: false)
            }
            .disabled(!model.canDeleteTimelineClip(id: clip.id))

            Button(localization.string("menu.rippleDeleteTimelineClip")) {
                model.deleteTimelineClip(id: clip.id, ripple: true)
            }
            .disabled(!model.canDeleteTimelineClip(id: clip.id))
        }
        .accessibilityLabel(name)
        .accessibilityValue("\(localization.string("timelineClip.inspector.timelineStart")) \(timecode(clip.timelineStart))")

        block.gesture(clipMoveGesture(clip: clip, project: project, laneWidth: laneWidth, duration: duration))
    }

    private func clipTrimHandle(clip: TimelineClip, project: TimelineProject, isStart: Bool, laneWidth: CGFloat, duration: TimeInterval) -> some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.32))
            .frame(width: 5, height: trackHeight - 22)
            .frame(width: 14, height: trackHeight - 12)
            .contentShape(Rectangle())
            .highPriorityGesture(clipTrimGesture(clip: clip, project: project, isStart: isStart, laneWidth: laneWidth, duration: duration))
    }

    private func clipTrimGesture(clip: TimelineClip, project: TimelineProject, isStart: Bool, laneWidth: CGFloat, duration: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if clipTrimID != clip.id || clipTrimIsStart != isStart {
                    clipTrimID = clip.id
                    clipTrimIsStart = isStart
                    clipTrimBaseTime = isStart ? clip.timelineStart : clip.timelineEnd
                }
                let base = clipTrimBaseTime ?? (isStart ? clip.timelineStart : clip.timelineEnd)
                let deltaT = Double(value.translation.width / laneWidth) * duration
                let threshold = Double(6 / laneWidth) * duration
                let target = Self.trimSnapTime(
                    project: project,
                    proposedTime: base + deltaT,
                    threshold: threshold,
                    clipID: clip.id,
                    playheadTime: model.previewTime
                )
                if isStart {
                    model.trimTimelineClipStart(id: clip.id, toTimelineTime: target)
                } else {
                    model.trimTimelineClipEnd(id: clip.id, toTimelineTime: target)
                }
            }
            .onEnded { _ in
                clipTrimID = nil
                clipTrimIsStart = nil
                clipTrimBaseTime = nil
            }
    }

    private func clipMoveGesture(clip: TimelineClip, project: TimelineProject, laneWidth: CGFloat, duration: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if dragClipID != clip.id {
                    dragClipID = clip.id
                    dragStartClipTimelineStart = clip.timelineStart
                    dragTimelineDuration = duration
                }
                let base = dragStartClipTimelineStart ?? clip.timelineStart
                let gestureDuration = dragTimelineDuration ?? duration
                let deltaT = Double(value.translation.width / laneWidth) * gestureDuration
                let snap = Double(6 / laneWidth) * gestureDuration
                let newStart = project.snappedTimelineTime(base + deltaT, threshold: snap, excludingClipID: clip.id)
                model.moveTimelineClip(id: clip.id, toTimelineStart: newStart)
            }
            .onEnded { _ in
                dragClipID = nil
                dragStartClipTimelineStart = nil
                dragTimelineDuration = nil
            }
    }

    // MARK: export range (in/out)

    /// Dims the excluded regions and provides draggable in/out handles that write back to the
    /// existing export-trim range. Maps 1:1 onto the timeline time base (same source duration).
    @ViewBuilder
    private func exportRangeLayer(duration: TimeInterval, laneWidth: CGFloat) -> some View {
        if model.exportTrimSourceDuration > 0 {
            let start = min(duration, max(0, model.effectiveExportTrimStart))
            let end = min(duration, max(start, model.effectiveExportTrimEnd))
            let startX = headerWidth + CGFloat(start / duration) * laneWidth
            let endX = headerWidth + CGFloat(end / duration) * laneWidth

            ZStack(alignment: .topLeading) {
                // Dim the region before the in-point.
                Rectangle()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: max(0, startX - headerWidth))
                    .offset(x: headerWidth)
                    .allowsHitTesting(false)
                // Dim the region after the out-point.
                Rectangle()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: max(0, headerWidth + laneWidth - endX))
                    .offset(x: endX)
                    .allowsHitTesting(false)

                trimHandle(atX: startX, isStart: true, laneWidth: laneWidth, duration: duration)
                trimHandle(atX: endX, isStart: false, laneWidth: laneWidth, duration: duration)
            }
        }
    }

    private func trimHandle(atX x: CGFloat, isStart: Bool, laneWidth: CGFloat, duration: TimeInterval) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 9, height: 16)
                .overlay(
                    Image(systemName: isStart ? "chevron.compact.right" : "chevron.compact.left")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        }
        .frame(width: 18)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .offset(x: x - 9)
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    let base: TimeInterval
                    if isStart {
                        if trimDragStart == nil { trimDragStart = model.effectiveExportTrimStart }
                        base = trimDragStart ?? model.effectiveExportTrimStart
                    } else {
                        if trimDragEnd == nil { trimDragEnd = model.effectiveExportTrimEnd }
                        base = trimDragEnd ?? model.effectiveExportTrimEnd
                    }
                    let deltaT = Double(value.translation.width / laneWidth) * duration
                    if isStart {
                        model.setExportTrimStart(base + deltaT)
                    } else {
                        model.setExportTrimEnd(base + deltaT)
                    }
                }
                .onEnded { _ in
                    trimDragStart = nil
                    trimDragEnd = nil
                }
        )
    }

    private func clipFill(_ kind: TimelineTrack.Kind) -> LinearGradient {
        switch kind {
        case .video:
            return LinearGradient(
                colors: [Color(red: 0.24, green: 0.34, blue: 0.44), Color(red: 0.18, green: 0.28, blue: 0.38)],
                startPoint: .top, endPoint: .bottom
            )
        case .overlay:
            return LinearGradient(
                colors: [Color.accentColor.opacity(0.9), Color.accentColor.opacity(0.62)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "timeline.selection")
                .foregroundStyle(.secondary)
            Text(localization.string("workspace.timeline.empty"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: helpers

    private func trackBadge(_ track: TimelineTrack) -> String {
        track.kind == .video ? "V" : "O"
    }

    private func tickTimes(duration: TimeInterval) -> [TimeInterval] {
        let step = niceStep(duration)
        var times: [TimeInterval] = []
        var t = 0.0
        while t < duration - step * 0.25 {
            times.append(t)
            t += step
        }
        return times
    }

    private func niceStep(_ duration: TimeInterval) -> TimeInterval {
        let target = duration / 6
        let candidates: [TimeInterval] = [1, 2, 5, 10, 15, 20, 30, 60, 120, 300, 600, 900, 1800, 3600]
        return candidates.first { $0 >= target } ?? 3600
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
