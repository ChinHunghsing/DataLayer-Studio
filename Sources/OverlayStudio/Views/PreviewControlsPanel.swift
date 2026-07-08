import SwiftUI

struct PreviewControlsPanel: View {
    let model: StudioModel
    let state: PreviewControlsState
    @Binding var zoom: Double
    let isFullscreen: Bool
    let onToggleFullscreen: () -> Void
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                controlRow
                statusRow
                warningRow
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private var controlRow: some View {
        VStack(spacing: 8) {
            timelineSlider

            HStack(spacing: 10) {
                transportControls
                Spacer(minLength: 12)
                zoomControls
                    .layoutPriority(1)
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 2) {
            transportButton(
                systemImage: "backward.frame.fill",
                help: localization.string("preview.previousFrame")
            ) {
                model.stepPreviewFrame(by: -1)
            }
            .disabled(!state.hasSeries || state.isExporting)

            transportButton(
                systemImage: state.isPlaying ? "pause.fill" : "play.fill",
                help: state.isPlaying ? localization.string("preview.pause") : localization.string("preview.play"),
                isPrimary: true
            ) {
                model.togglePlayback()
            }
            .disabled(!state.hasPlayer || state.isExporting)

            transportButton(
                systemImage: "forward.frame.fill",
                help: localization.string("preview.nextFrame")
            ) {
                model.stepPreviewFrame(by: 1)
            }
            .disabled(!state.hasSeries || state.isExporting)
        }
        .padding(2)
        .background(ShellStyle.tileFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func transportButton(
        systemImage: String,
        help: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isPrimary ? 13 : 11, weight: .semibold))
                .frame(width: isPrimary ? 30 : 24, height: 24)
                .foregroundStyle(isPrimary ? Color.accentColor : Color.secondary)
                .background(
                    isPrimary ? AnyShapeStyle(.background) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var timelineSlider: some View {
        PreviewTimelineSlider(
            value: Binding(
                get: { state.previewTime },
                set: { model.scrubPreview(to: $0) }
            ),
            range: state.previewTimeRange,
            isEnabled: state.hasSeries && !state.isExporting,
            accessibilityLabel: localization.string("preview.time", formatTimecode(state.previewTime)),
            onFrameStep: { model.stepPreviewFrame(by: $0) }
        )
        .frame(maxWidth: .infinity)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button {
                setZoom(zoom / 1.2)
            } label: {
                Label(localization.string("preview.zoomOut"), systemImage: "minus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help(localization.string("preview.zoomOutHelp"))

            Slider(
                value: Binding(
                    get: { clampedZoom(zoom) },
                    set: { setZoom($0) }
                ),
                in: PreviewZoomLimits.range
            )
            .frame(minWidth: 92, idealWidth: 118, maxWidth: 160)

            Text("\(Int((clampedZoom(zoom) * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

            Button {
                setZoom(zoom * 1.2)
            } label: {
                Label(localization.string("preview.zoomIn"), systemImage: "plus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help(localization.string("preview.zoomInHelp"))

            Button {
                setZoom(1)
            } label: {
                Label(localization.string("preview.fit"), systemImage: "arrow.counterclockwise")
            }
            .labelStyle(.iconOnly)
            .help(localization.string("preview.fitHelp"))

            Button {
                onToggleFullscreen()
            } label: {
                Label(
                    isFullscreen ? localization.string("preview.exitFullscreen") : localization.string("preview.fullscreen"),
                    systemImage: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                )
            }
            .labelStyle(.iconOnly)
            .help(isFullscreen ? localization.string("preview.exitFullscreenHelp") : localization.string("preview.fullscreenHelp"))
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Text(formatTimecode(state.previewTime))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)

            if state.syncMode == .syncPoint, state.syncFITSeconds == 0 {
                ShellStatusChip(
                    localization.string("preview.sportStartAt", formatTimecode(state.syncVideoSeconds)),
                    systemImage: "flag.checkered",
                    kind: .active
                )
            }

            Spacer(minLength: 8)

            Text(verbatim: "\(state.outputWidth)×\(state.outputHeight)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ShellStyle.tileFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private var warningRow: some View {
        if let previewWarning = state.previewWarning {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text(previewWarning)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(localization.string("preview.warning"))
            .accessibilityValue(previewWarning)
        }
    }

    private func clampedZoom(_ value: Double) -> Double {
        PreviewZoomLimits.clamp(value)
    }

    private func setZoom(_ value: Double) {
        zoom = clampedZoom(value)
    }

    private func formatTimecode(_ time: TimeInterval) -> String {
        let frameRate = max(1, Int(state.previewFrameRate.rounded()))
        let safeTime = max(0, time.isFinite ? time : 0)
        let wholeSeconds = Int(safeTime.rounded(.down))
        let fractionalSecond = safeTime - Double(wholeSeconds)
        let frame = min(frameRate - 1, max(0, Int((fractionalSecond * Double(frameRate)).rounded(.down))))
        return String(
            format: "%02d:%02d:%02d:%02d",
            wholeSeconds / 3600,
            (wholeSeconds / 60) % 60,
            wholeSeconds % 60,
            frame
        )
    }
}

struct PreviewControlsState: Equatable {
    var previewTime: TimeInterval
    var previewDuration: TimeInterval
    var previewTimeRange: ClosedRange<TimeInterval>
    var previewFrameRate: Double
    var isPlaying: Bool
    var hasPlayer: Bool
    var isExporting: Bool
    var hasSeries: Bool
    var syncMode: SyncMode
    var syncFITSeconds: Double
    var syncVideoSeconds: Double
    var outputWidth: Int
    var outputHeight: Int
    var previewWarning: String?

    @MainActor
    init(model: StudioModel) {
        previewTime = model.previewTime
        previewDuration = model.previewDuration
        let modelRange = model.previewTimeRange
        previewTimeRange = modelRange.lowerBound...max(modelRange.lowerBound + 0.001, modelRange.upperBound)
        previewFrameRate = model.previewFrameRate
        isPlaying = model.isPlaying
        hasPlayer = model.player != nil
        isExporting = model.isExporting
        hasSeries = model.series != nil
        syncMode = model.syncMode
        syncFITSeconds = model.syncFITSeconds
        syncVideoSeconds = model.syncVideoSeconds
        outputWidth = model.outputWidth
        outputHeight = model.outputHeight
        previewWarning = model.previewWarning
    }
}
