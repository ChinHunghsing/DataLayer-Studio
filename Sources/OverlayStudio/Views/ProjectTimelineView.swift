import SwiftUI
import OverlayCore

/// Read-only timeline of the currently active source(s): a video track and an overlay track with
/// the FIT clip positioned to reflect the current sync. Dragging the playhead scrubs the preview.
/// Editing (drag/trim/multi-clip) arrives in later phases; sync and trim still live in their tabs.
struct ProjectTimelineView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    private let headerWidth: CGFloat = 116
    private let rulerHeight: CGFloat = 24
    private let trackHeight: CGFloat = 48
    private let playheadColor = Color(red: 1.0, green: 0.42, blue: 0.34)

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
                        VStack(spacing: 0) {
                            ruler(duration: duration, laneWidth: laneWidth)
                            ForEach(displayTracks) { track in
                                trackRow(track, duration: duration, laneWidth: laneWidth)
                            }
                            Spacer(minLength: 0)
                        }

                        // Scrub anywhere over the lane column.
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: laneWidth)
                            .offset(x: headerWidth)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let t = Double(value.location.x / laneWidth) * duration
                                        model.scrubPreview(to: min(duration, max(0, t)))
                                    }
                            )

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

    private func trackRow(_ track: TimelineTrack, duration: TimeInterval, laneWidth: CGFloat) -> some View {
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
                    clipView(clip, kind: track.kind, duration: duration, laneWidth: laneWidth)
                }
            }
            .frame(width: laneWidth, height: trackHeight, alignment: .topLeading)
        }
        .frame(height: trackHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func clipView(_ clip: TimelineClip, kind: TimelineTrack.Kind, duration: TimeInterval, laneWidth: CGFloat) -> some View {
        let x = CGFloat(clip.timelineStart / duration) * laneWidth
        let width = max(6, CGFloat(clip.duration / duration) * laneWidth)
        let name = model.currentTimelineProject.asset(id: clip.assetID)?.displayName ?? clip.assetID

        return RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .frame(width: width, height: trackHeight - 12)
            .offset(x: x, y: 6)
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
