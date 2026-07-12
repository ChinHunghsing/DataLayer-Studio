import SwiftUI
import UniformTypeIdentifiers
import OverlayCore
#if canImport(AppKit)
import AppKit
#endif

enum TimelineSnapSource: Equatable {
    case timelineStart
    case playhead
    case clipEdge
}

struct TimelineSnapResult: Equatable {
    var timelineStart: TimeInterval
    var guideTime: TimeInterval? = nil
    var source: TimelineSnapSource? = nil
}

/// Timeline editor for the current project. Every clip owns its relative timeline position;
/// source match-point controls can align clips, but dragging never rewrites those source times.
/// Dragging the playhead scrubs the same timeline state consumed by preview and export.
struct ProjectTimelineView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    private let headerWidth: CGFloat = 188
    private let rulerHeight: CGFloat = 24
    private let trackHeight: CGFloat = 48
    private let playheadColor = Color(red: 1.0, green: 0.42, blue: 0.34)

    @State private var dragClipID: String?
    @State private var dragStartTrackID: String?
    @State private var dragTargetTrackID: String?
    @State private var dragStartClipTimelineStart: TimeInterval?
    @State private var dragTimelineDuration: TimeInterval?
    @State private var dragVerticalOffset: CGFloat = 0
    @State private var snapGuideTime: TimeInterval?
    @State private var snapGuideSource: TimelineSnapSource?
    @State private var clipTrimID: String?
    @State private var clipTrimIsStart: Bool?
    @State private var clipTrimBaseTime: TimeInterval?
    @State private var magnificationStartZoom: Double?
    @State private var isShowingTrackRename = false
    @State private var renamingTrackID: String?
    @State private var trackNameDraft = ""
    @State private var hoveredTrackID: String?

    private static let playheadMarkerID = "timeline.playhead.marker"

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
                    let baseLaneWidth = max(1, proxy.size.width - headerWidth)
                    let laneWidth = baseLaneWidth * CGFloat(max(1, model.timelineZoom))
                    let timelineContentHeight = max(
                        proxy.size.height,
                        rulerHeight + CGFloat(displayTracks.count) * trackHeight
                    )

                    // Track headers stay pinned on the left; the ruler, lanes, export band and
                    // playhead scroll horizontally together when zoomed in.
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            headerColumn(displayTracks: displayTracks, contentHeight: timelineContentHeight)
                            ScrollViewReader { scrollProxy in
                                ScrollView(.horizontal) {
                                    laneContent(
                                        displayTracks: displayTracks,
                                        project: project,
                                        duration: duration,
                                        laneWidth: laneWidth,
                                        contentHeight: timelineContentHeight
                                    )
                                    .frame(width: laneWidth, height: timelineContentHeight, alignment: .topLeading)
                                }
                                .onChange(of: model.timelineZoom) { _ in
                                    focusPlayhead(using: scrollProxy)
                                }
                                .onChange(of: model.timelinePlayheadFocusGeneration) { _ in
                                    focusPlayhead(using: scrollProxy)
                                }
                            }
                        }
                        .frame(height: timelineContentHeight, alignment: .top)
                    }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                if magnificationStartZoom == nil {
                                    magnificationStartZoom = model.timelineZoom
                                }
                                model.setTimelineZoom((magnificationStartZoom ?? model.timelineZoom) * Double(value))
                            }
                            .onEnded { _ in
                                magnificationStartZoom = nil
                            }
                    )
                }
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                focusTimelineKeyboardCommands()
            }
        )
        .alert(localization.string("timeline.track.rename"), isPresented: $isShowingTrackRename) {
            TextField(localization.string("timeline.track.renamePlaceholder"), text: $trackNameDraft)
            Button(localization.string("common.cancel"), role: .cancel) {
                renamingTrackID = nil
            }
            Button(localization.string("timeline.track.renameConfirm")) {
                if let renamingTrackID {
                    model.renameTimelineTrack(id: renamingTrackID, name: trackNameDraft)
                }
                renamingTrackID = nil
            }
            .disabled(trackNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func headerColumn(displayTracks: [TimelineTrack], contentHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text(localization.string("timeline.tracks"))
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
                .frame(width: headerWidth, height: rulerHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                }
            ForEach(displayTracks) { track in
                trackHeader(track)
            }
            Spacer(minLength: 0)
        }
        .frame(width: headerWidth, height: contentHeight, alignment: .top)
    }

    private func laneContent(
        displayTracks: [TimelineTrack],
        project: TimelineProject,
        duration: TimeInterval,
        laneWidth: CGFloat,
        contentHeight: CGFloat
    ) -> some View {
        let clampedProgress = min(1, max(0, model.previewTime / duration))
        let playheadX = CGFloat(clampedProgress) * laneWidth

        return ZStack(alignment: .topLeading) {
            // Scrub layer (bottom): empty lane areas and video clips pass through to here.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: laneWidth, height: contentHeight)
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
                        .onEnded { value in
                            if abs(value.translation.width) < 2, abs(value.translation.height) < 2 {
                                model.clearTimelineClipSelection()
                            }
                        }
                )

            // Tracks and clips capture their own move/trim gestures.
            VStack(spacing: 0) {
                ruler(duration: duration, laneWidth: laneWidth)
                ForEach(displayTracks) { track in
                    trackLane(track, project: project, duration: duration, laneWidth: laneWidth)
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(true)

            snapGuideLayer(duration: duration, laneWidth: laneWidth, contentHeight: contentHeight)

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

            playheadScrollAnchor(playheadX: playheadX, laneWidth: laneWidth)
        }
    }

    private func playheadScrollAnchor(playheadX: CGFloat, laneWidth: CGFloat) -> some View {
        let markerWidth: CGFloat = 1
        let leadingWidth = min(max(0, playheadX), max(0, laneWidth - markerWidth))

        return HStack(spacing: 0) {
            Color.clear
                .frame(width: leadingWidth, height: markerWidth)
            Color.clear
                .frame(width: markerWidth, height: markerWidth)
                .id(Self.playheadMarkerID)
            Spacer(minLength: 0)
        }
        .frame(width: laneWidth, height: markerWidth, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func focusPlayhead(using scrollProxy: ScrollViewProxy) {
        // Wait for the zoom or seek to lay out the marker at its new timeline position.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.12)) {
                scrollProxy.scrollTo(Self.playheadMarkerID, anchor: .center)
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
        trimSnapResult(
            project: project,
            proposedTime: proposedTime,
            threshold: threshold,
            clipID: clipID,
            playheadTime: playheadTime
        ).timelineStart
    }

    static func trimSnapResult(
        project: TimelineProject,
        proposedTime: TimeInterval,
        threshold: TimeInterval,
        clipID: String,
        playheadTime: TimeInterval
    ) -> TimelineSnapResult {
        snapResult(
            project: project,
            proposedEdges: [(timelineStart: proposedTime, offset: 0)],
            threshold: threshold,
            clipID: clipID,
            playheadTime: playheadTime
        )
    }

    static func moveSnapResult(
        project: TimelineProject,
        proposedStart: TimeInterval,
        clipDuration: TimeInterval,
        threshold: TimeInterval,
        clipID: String,
        playheadTime: TimeInterval
    ) -> TimelineSnapResult {
        snapResult(
            project: project,
            proposedEdges: [
                (timelineStart: proposedStart, offset: 0),
                (timelineStart: proposedStart + clipDuration, offset: clipDuration)
            ],
            threshold: threshold,
            clipID: clipID,
            playheadTime: playheadTime
        )
    }

    private static func snapResult(
        project: TimelineProject,
        proposedEdges: [(timelineStart: TimeInterval, offset: TimeInterval)],
        threshold: TimeInterval,
        clipID: String,
        playheadTime: TimeInterval
    ) -> TimelineSnapResult {
        guard let proposedStart = proposedEdges.first.map({ $0.timelineStart - $0.offset }),
              proposedStart.isFinite,
              threshold.isFinite,
              threshold > 0 else {
            return TimelineSnapResult(timelineStart: max(0, proposedEdges.first?.timelineStart ?? 0))
        }

        var candidates: [(time: TimeInterval, source: TimelineSnapSource)] = [
            (0, .timelineStart)
        ]
        if playheadTime.isFinite, playheadTime >= 0 {
            candidates.append((playheadTime, .playhead))
        }
        candidates.append(contentsOf: project.tracks
            .flatMap(\.clips)
            .filter { $0.id != clipID }
            .flatMap { clip in
                [
                    (time: clip.timelineStart, source: TimelineSnapSource.clipEdge),
                    (time: clip.timelineEnd, source: TimelineSnapSource.clipEdge)
                ]
            })

        var best: (start: TimeInterval, guide: TimeInterval, source: TimelineSnapSource, distance: TimeInterval)?
        for edge in proposedEdges where edge.timelineStart.isFinite {
            for candidate in candidates where candidate.time.isFinite && candidate.time >= 0 {
                let distance = abs(candidate.time - edge.timelineStart)
                let snappedStart = proposedStart + candidate.time - edge.timelineStart
                guard distance <= threshold, snappedStart >= 0 else { continue }
                if best == nil || distance < best!.distance - 1e-9 {
                    best = (snappedStart, candidate.time, candidate.source, distance)
                }
            }
        }

        guard let best else {
            return TimelineSnapResult(timelineStart: max(0, proposedStart))
        }
        return TimelineSnapResult(
            timelineStart: max(0, best.start),
            guideTime: best.guide,
            source: best.source
        )
    }

    static func targetTrackID(
        project: TimelineProject,
        sourceTrackID: String,
        verticalTranslation: CGFloat,
        trackHeight: CGFloat
    ) -> String {
        let displayTracks = Array(project.tracks.reversed())
        guard verticalTranslation.isFinite,
              trackHeight.isFinite,
              trackHeight > 0,
              let sourceIndex = displayTracks.firstIndex(where: { $0.id == sourceTrackID }) else {
            return sourceTrackID
        }

        let proposedIndex = sourceIndex + Int((verticalTranslation / trackHeight).rounded())
        let targetIndex = min(displayTracks.count - 1, max(0, proposedIndex))
        let sourceTrack = displayTracks[sourceIndex]
        let targetTrack = displayTracks[targetIndex]
        guard targetTrack.kind == sourceTrack.kind, !targetTrack.isLocked else {
            return sourceTrackID
        }
        return targetTrack.id
    }

    // MARK: ruler

    private func ruler(duration: TimeInterval, laneWidth: CGFloat) -> some View {
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
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: track row

    private func trackHeader(_ track: TimelineTrack) -> some View {
        HStack(spacing: 8) {
            Image(systemName: track.kind == .video ? "film" : "waveform.path.ecg")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(track.kind == .video ? Color.secondary : Color.accentColor)
                .frame(width: 20, height: 24)

            Button {
                beginRenaming(track)
            } label: {
                HStack(spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if hoveredTrackID == track.id {
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }
                }
                .foregroundStyle(track.isEnabled ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localization.string("timeline.track.rename"))

            Button {
                model.setTimelineTrackEnabled(id: track.id, isEnabled: !track.isEnabled)
            } label: {
                Image(systemName: track.isEnabled ? "eye" : "eye.slash")
                    .frame(width: 24, height: 28)
            }
            .help(localization.string(track.isEnabled ? "timeline.track.disable" : "timeline.track.enable"))
            .accessibilityLabel(localization.string(track.isEnabled ? "timeline.track.disable" : "timeline.track.enable"))

            Button {
                model.setTimelineTrackLocked(id: track.id, isLocked: !track.isLocked)
            } label: {
                Image(systemName: track.isLocked ? "lock.fill" : "lock.open")
                    .frame(width: 24, height: 28)
            }
            .help(localization.string(track.isLocked ? "timeline.track.unlock" : "timeline.track.lock"))
            .accessibilityLabel(localization.string(track.isLocked ? "timeline.track.unlock" : "timeline.track.lock"))

            if track.clips.isEmpty, !track.isLocked {
                Button {
                    model.removeEmptyTimelineTrack(id: track.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 24, height: 28)
                }
                .help(localization.string("menu.deleteEmptyTimelineTrack"))
                .accessibilityLabel(localization.string("menu.deleteEmptyTimelineTrack"))
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(width: headerWidth, height: trackHeight)
        .background(.bar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) { Divider() }
        .onHover { isHovering in
            if isHovering {
                hoveredTrackID = track.id
            } else if hoveredTrackID == track.id {
                hoveredTrackID = nil
            }
        }
    }

    private func trackLane(_ track: TimelineTrack, project: TimelineProject, duration: TimeInterval, laneWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(track.clips) { clip in
                clipView(
                    clip,
                    project: project,
                    kind: track.kind,
                    isLocked: track.isLocked,
                    duration: duration,
                    laneWidth: laneWidth
                )
            }
        }
        .frame(width: laneWidth, height: trackHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .background(
            dragTargetTrackID == track.id
                ? Color.accentColor.opacity(0.10)
                : Color.clear
        )
        .onDrop(of: [.plainText], isTargeted: nil) { providers, location in
            handleMediaDrop(
                providers,
                onTrack: track,
                atX: location.x,
                laneWidth: laneWidth,
                duration: duration
            )
        }
        .opacity(track.isEnabled ? 1 : 0.42)
        .zIndex(track.clips.contains { $0.id == dragClipID } ? 1 : 0)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func handleMediaDrop(
        _ providers: [NSItemProvider],
        onTrack track: TimelineTrack,
        atX locationX: CGFloat,
        laneWidth: CGFloat,
        duration: TimeInterval
    ) -> Bool {
        guard !track.isLocked else { return false }
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        guard laneWidth > 0, duration > 0 else { return false }
        let timelineStart = min(duration, max(0, Double(locationX / laneWidth) * duration))
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? NSString else { return }
            let value = String(payload)
            DispatchQueue.main.async {
                switch track.kind {
                case .video:
                    guard let assetID = TimelineDragPayload.videoAssetID(from: value) else { return }
                    model.addVideoAssetToTimeline(
                        id: assetID,
                        targetTrackID: track.id,
                        timelineStart: timelineStart
                    )
                case .overlay:
                    guard let assetID = TimelineDragPayload.activityAssetID(from: value) else { return }
                    model.addActivityAssetToTimeline(
                        id: assetID,
                        targetTrackID: track.id,
                        timelineStart: timelineStart
                    )
                }
            }
        }
        return true
    }

    @ViewBuilder
    private func clipView(
        _ clip: TimelineClip,
        project: TimelineProject,
        kind: TimelineTrack.Kind,
        isLocked: Bool,
        duration: TimeInterval,
        laneWidth: CGFloat
    ) -> some View {
        let x = CGFloat(clip.timelineStart / duration) * laneWidth
        let width = max(6, CGFloat(clip.duration / duration) * laneWidth)
        let asset = project.asset(id: clip.assetID)
        let name = asset?.displayName ?? clip.assetID
        let isSelected = model.isTimelineClipSelected(id: clip.id)
        let isOffline = model.isTimelineAssetOffline(id: clip.assetID)
        let waveformPeaks = model.videoWaveformPeaksByAssetID[clip.assetID] ?? []
        let pausedRanges = kind == .overlay
            ? (model.activitySeries(forAssetID: clip.assetID)?.pausedRanges ?? [])
            : []
        let activeDragVerticalOffset = dragClipID == clip.id ? dragVerticalOffset : 0

        let clipBody = RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(clipFill(kind))
            .overlay {
                if kind == .video, let asset, !waveformPeaks.isEmpty {
                    TimelineAudioWaveform(
                        peaks: waveformPeaks,
                        sourceIn: clip.sourceIn,
                        clipDuration: clip.duration,
                        assetDuration: asset.duration
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                }
            }
            .overlay {
                if !pausedRanges.isEmpty {
                    // Spans where the activity timer was paused: data holds its last value there.
                    TimelinePausedBands(
                        ranges: pausedRanges,
                        sourceIn: clip.sourceIn,
                        clipDuration: clip.duration
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .overlay(alignment: .leading) {
                HStack(spacing: 4) {
                    if isOffline { Image(systemName: "exclamationmark.triangle.fill") }
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                .padding(.horizontal, 8)
            }
            .overlay {
                // 选中态：更粗的高亮描边 + 内侧白色发丝线，让选中片段和未选片段一眼区分。
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isOffline ? Color.red.opacity(0.9) : (isSelected ? Color.accentColor : Color.white.opacity(0.18)),
                            lineWidth: isSelected ? 3 : 1
                        )
                    if isSelected, !isOffline {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .inset(by: 2.5)
                            .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                    }
                }
            }
            .frame(width: width, height: trackHeight - 12)
            // 选中片段加一圈柔和的强调色辉光，进一步突出焦点。
            .shadow(color: isSelected && !isOffline ? Color.accentColor.opacity(0.65) : .clear, radius: 5)
            .opacity(clip.isEnabled ? 1 : 0.38)

        let block = ZStack {
            clipBody
            if width > 22, !isLocked {
                HStack {
                    clipTrimHandle(clip: clip, project: project, isStart: true, laneWidth: laneWidth, duration: duration)
                    Spacer(minLength: 0)
                    clipTrimHandle(clip: clip, project: project, isStart: false, laneWidth: laneWidth, duration: duration)
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(width: width, height: trackHeight - 12)
        .offset(x: x, y: 6 + activeDragVerticalOffset)
        .zIndex(dragClipID == clip.id ? 1 : 0)
        .onTapGesture {
            focusTimelineKeyboardCommands()
            model.selectTimelineClip(
                id: clip.id,
                extendingSelection: Self.isCommandKeyPressed
            )
        }
        .contextMenu {
            Button(localization.string(clip.isEnabled ? "menu.disableTimelineClip" : "menu.enableTimelineClip")) {
                model.setTimelineClipEnabled(id: clip.id, isEnabled: !clip.isEnabled)
            }
            .disabled(isLocked)

            Divider()

            Button(localization.string("menu.splitTimelineClips")) {
                if !model.isTimelineClipSelected(id: clip.id) {
                    model.selectTimelineClip(id: clip.id)
                }
                model.splitTimelineClipsAtPlayhead()
            }
            .disabled(
                project.splittableClipIDs(atTimelineTime: model.previewTime, clipID: clip.id).isEmpty
            )

            Divider()

            Button(localization.string("menu.deleteTimelineClip")) {
                if !model.isTimelineClipSelected(id: clip.id) {
                    model.selectTimelineClip(id: clip.id)
                }
                model.deleteSelectedTimelineClip(ripple: false)
            }
            .disabled(!model.canDeleteTimelineClip(id: clip.id))

            Button(localization.string("menu.rippleDeleteTimelineClip")) {
                if !model.isTimelineClipSelected(id: clip.id) {
                    model.selectTimelineClip(id: clip.id)
                }
                model.deleteSelectedTimelineClip(ripple: true)
            }
            .disabled(!model.canDeleteTimelineClip(id: clip.id))
        }
        .accessibilityLabel(name)
        .accessibilityValue(
            "\(localization.string(clip.isEnabled ? "timeline.clip.enabled" : "timeline.clip.disabled")), "
                + "\(localization.string("timelineClip.inspector.timelineStart")) \(timecode(clip.timelineStart))"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        block
            .gesture(
                clipMoveGesture(clip: clip, project: project, laneWidth: laneWidth, duration: duration),
                including: isLocked ? .none : .all
            )
            .task(id: kind == .video ? asset?.id : nil) {
                guard kind == .video, let assetID = asset?.id else { return }
                model.loadVideoWaveformIfNeeded(assetID: assetID)
            }
    }

    private func focusTimelineKeyboardCommands() {
        #if canImport(AppKit)
        (NSApp.keyWindow ?? NSApp.mainWindow)?.makeFirstResponder(nil)
        #endif
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
                let snapResult = Self.trimSnapResult(
                    project: project,
                    proposedTime: base + deltaT,
                    threshold: threshold,
                    clipID: clip.id,
                    playheadTime: model.previewTime
                )
                snapGuideTime = snapResult.guideTime
                snapGuideSource = snapResult.source
                if isStart {
                    model.trimTimelineClipStart(id: clip.id, toTimelineTime: snapResult.timelineStart)
                } else {
                    model.trimTimelineClipEnd(id: clip.id, toTimelineTime: snapResult.timelineStart)
                }
            }
            .onEnded { _ in
                clipTrimID = nil
                clipTrimIsStart = nil
                clipTrimBaseTime = nil
                snapGuideTime = nil
                snapGuideSource = nil
            }
    }

    private func clipMoveGesture(clip: TimelineClip, project: TimelineProject, laneWidth: CGFloat, duration: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if dragClipID != clip.id {
                    dragClipID = clip.id
                    dragStartTrackID = project.tracks.first(where: { track in
                        track.clips.contains { $0.id == clip.id }
                    })?.id
                    dragStartClipTimelineStart = clip.timelineStart
                    dragTimelineDuration = duration
                }
                dragVerticalOffset = value.translation.height
                if let dragStartTrackID {
                    dragTargetTrackID = Self.targetTrackID(
                        project: project,
                        sourceTrackID: dragStartTrackID,
                        verticalTranslation: value.translation.height,
                        trackHeight: trackHeight
                    )
                }
                let base = dragStartClipTimelineStart ?? clip.timelineStart
                let gestureDuration = dragTimelineDuration ?? duration
                let deltaT = Double(value.translation.width / laneWidth) * gestureDuration
                let snap = Double(6 / laneWidth) * gestureDuration
                let snapResult = Self.moveSnapResult(
                    project: project,
                    proposedStart: base + deltaT,
                    clipDuration: clip.duration,
                    threshold: snap,
                    clipID: clip.id,
                    playheadTime: model.previewTime
                )
                snapGuideTime = snapResult.guideTime
                snapGuideSource = snapResult.source
                model.moveTimelineClip(id: clip.id, toTimelineStart: snapResult.timelineStart)
            }
            .onEnded { value in
                if let dragStartTrackID {
                    let gestureDuration = dragTimelineDuration ?? duration
                    let deltaT = Double(value.translation.width / laneWidth) * gestureDuration
                    let snap = Double(6 / laneWidth) * gestureDuration
                    let snapResult = Self.moveSnapResult(
                        project: project,
                        proposedStart: (dragStartClipTimelineStart ?? clip.timelineStart) + deltaT,
                        clipDuration: clip.duration,
                        threshold: snap,
                        clipID: clip.id,
                        playheadTime: model.previewTime
                    )
                    let targetTrackID = Self.targetTrackID(
                        project: project,
                        sourceTrackID: dragStartTrackID,
                        verticalTranslation: value.translation.height,
                        trackHeight: trackHeight
                    )
                    model.moveTimelineClip(
                        id: clip.id,
                        toTrackID: targetTrackID,
                        toTimelineStart: snapResult.timelineStart
                    )
                }
                dragClipID = nil
                dragStartTrackID = nil
                dragTargetTrackID = nil
                dragStartClipTimelineStart = nil
                dragTimelineDuration = nil
                dragVerticalOffset = 0
                snapGuideTime = nil
                snapGuideSource = nil
            }
    }

    @ViewBuilder
    private func snapGuideLayer(duration: TimeInterval, laneWidth: CGFloat, contentHeight: CGFloat) -> some View {
        if let snapGuideTime, let snapGuideSource, duration > 0 {
            let x = CGFloat(min(duration, max(0, snapGuideTime)) / duration) * laneWidth
            Rectangle()
                .fill(Color.yellow.opacity(0.9))
                .frame(width: 1, height: max(0, contentHeight - rulerHeight))
                .offset(x: x, y: rulerHeight)
                .shadow(color: Color.yellow.opacity(0.45), radius: 2)
                .allowsHitTesting(false)

            Text(localization.string(snapSourceLocalizationKey(snapGuideSource)))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.76), in: Capsule())
                .offset(x: min(max(2, x + 4), max(2, laneWidth - 88)), y: rulerHeight + 3)
                .allowsHitTesting(false)
        }
    }

    private func snapSourceLocalizationKey(_ source: TimelineSnapSource) -> String {
        switch source {
        case .timelineStart:
            return "timeline.snap.timelineStart"
        case .playhead:
            return "timeline.snap.playhead"
        case .clipEdge:
            return "timeline.snap.clipEdge"
        }
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

    private func beginRenaming(_ track: TimelineTrack) {
        renamingTrackID = track.id
        trackNameDraft = track.name
        isShowingTrackRename = true
    }

    private static var isCommandKeyPressed: Bool {
#if canImport(AppKit)
        NSEvent.modifierFlags.contains(.command)
#else
        false
#endif
    }

    private func tickTimes(duration: TimeInterval) -> [TimeInterval] {
        // Pick the step for the zoomed-in visible span so more ticks appear while zoomed.
        let step = niceStep(duration / max(1, model.timelineZoom))
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

/// Marks the wall-clock spans of an activity clip during which the timer was paused. The data
/// layer holds its last pre-pause values there, so the bands use a distinct muted color.
private struct TimelinePausedBands: View {
    let ranges: [TelemetryPausedRange]
    let sourceIn: TimeInterval
    let clipDuration: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard clipDuration > 0, size.width > 0 else { return }
            for range in ranges {
                let startFraction = (range.start - sourceIn) / clipDuration
                let endFraction = (range.end - sourceIn) / clipDuration
                let x0 = CGFloat(max(0, min(1, startFraction))) * size.width
                let x1 = CGFloat(max(0, min(1, endFraction))) * size.width
                guard x1 - x0 > 0.5 else { continue }
                let rect = CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)
                context.fill(
                    Path(rect),
                    with: .color(Color(red: 0.42, green: 0.44, blue: 0.49).opacity(0.88))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TimelineAudioWaveform: View {
    let peaks: [Float]
    let sourceIn: TimeInterval
    let clipDuration: TimeInterval
    let assetDuration: TimeInterval

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty,
                  size.width > 0,
                  size.height > 0,
                  assetDuration.isFinite,
                  assetDuration > 0 else {
                return
            }

            let barCount = max(1, min(peaks.count, Int(size.width / 2)))
            var path = Path()
            for bar in 0..<barCount {
                let clipFraction = (Double(bar) + 0.5) / Double(barCount)
                let sourceTime = min(
                    assetDuration,
                    max(0, sourceIn + clipDuration * clipFraction)
                )
                let peakIndex = min(
                    peaks.count - 1,
                    max(0, Int(sourceTime / assetDuration * Double(peaks.count)))
                )
                let amplitude = CGFloat(peaks[peakIndex])
                let halfHeight = max(0.6, amplitude * size.height * 0.46)
                let x = (CGFloat(bar) + 0.5) / CGFloat(barCount) * size.width
                path.move(to: CGPoint(x: x, y: size.height / 2 - halfHeight))
                path.addLine(to: CGPoint(x: x, y: size.height / 2 + halfHeight))
            }
            context.stroke(path, with: .color(.white.opacity(0.32)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
