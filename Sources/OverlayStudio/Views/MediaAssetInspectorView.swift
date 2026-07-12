import AppKit
import OverlayCore
import SwiftUI

struct MediaAssetInspectorView: View {
    @ObservedObject var model: StudioModel
    var asset: MediaAsset
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            infoRow("library.mediaInspector.kind", value: localization.string(
                asset.kind == .video ? "library.mediaInspector.video" : "library.mediaInspector.activity"
            ))
            infoRow("library.mediaInspector.duration", value: formatDuration(asset.duration))

            if let width = asset.width, let height = asset.height {
                infoRow("library.mediaInspector.resolution", value: "\(width)×\(height)")
            }
            if let framesPerSecond = asset.framesPerSecond {
                infoRow("library.mediaInspector.frameRate", value: String(format: "%.3g fps", framesPerSecond))
            }
            if let wallClockStart = asset.wallClockStart {
                infoRow(
                    "library.mediaInspector.recordedAt",
                    value: wallClockStart.formatted(date: .abbreviated, time: .standard)
                )
            }
            if let reason = model.offlineTimelineAssetReasons[asset.id] {
                infoRow("library.mediaInspector.status", value: localization.string(reason.localizationKey), tint: .orange)
            } else {
                infoRow("library.mediaInspector.status", value: localization.string("library.mediaInspector.available"))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(localization.string("library.mediaInspector.path"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(asset.url.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    if asset.kind == .video {
                        model.addVideoAssetToTimeline(id: asset.id)
                    } else {
                        model.addActivityAssetToTimeline(id: asset.id)
                    }
                } label: {
                    Label(localization.string("mediapool.addToTimeline"), systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(model.offlineTimelineAssetIDs.contains(asset.id))

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([asset.url])
                } label: {
                    Label(localization.string("library.mediaInspector.reveal"), systemImage: "folder")
                }
                .disabled(!FileManager.default.fileExists(atPath: asset.url.path))
            }
            .controlSize(.small)

            if model.offlineTimelineAssetIDs.contains(asset.id) {
                Button {
                    model.chooseReplacementForTimelineAsset(id: asset.id)
                } label: {
                    Label(localization.string("mediapool.relink"), systemImage: "link.badge.plus")
                }
                .controlSize(.small)
            }
        }
    }

    private func infoRow(_ key: String, value: String, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(localization.string(key))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

