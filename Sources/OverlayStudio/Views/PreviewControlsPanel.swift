import SwiftUI

struct PreviewControlsPanel: View {
    @ObservedObject var model: StudioModel
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                transportControls

                Divider()
                    .frame(height: 18)

                zoomControls
            }

            VStack(spacing: 8) {
                transportControls
                zoomControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            Button {
                model.togglePlayback()
            } label: {
                Label(
                    model.isPlaying ? localization.string("preview.pause") : localization.string("preview.play"),
                    systemImage: model.isPlaying ? "pause.fill" : "play.fill"
                )
            }
            .disabled(model.player == nil || model.isExporting)

            PreviewTimelineSlider(
                value: Binding(
                    get: { model.previewTime },
                    set: { model.scrubPreview(to: $0) }
                ),
                range: 0...max(model.outputDuration, 1),
                isEnabled: model.player != nil && !model.isExporting,
                accessibilityLabel: localization.string("preview.time", formatTimecode(model.previewTime)),
                onFrameStep: { model.stepPreviewFrame(by: $0) }
            )
            .frame(minWidth: 140)

            Button {
                model.markSportStart()
            } label: {
                Label(localization.string("toolbar.sportStart"), systemImage: "figure.run.circle")
            }
            .disabled(model.player == nil || model.isExporting)
        }
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
        HStack {
            Text(formatTimecode(model.previewTime))
            Spacer()
            if model.syncMode == .syncPoint, model.syncFITSeconds == 0 {
                Text(localization.string("preview.sportStartAt", formatTimecode(model.syncVideoSeconds)))
                    .foregroundStyle(.tint)
            }
            Spacer()
            Text("\(model.outputWidth)x\(model.outputHeight)")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var warningRow: some View {
        if let previewWarning = model.previewWarning {
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
        let frameRate = max(1, Int(model.previewFrameRate.rounded()))
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
