import Foundation
import SwiftUI
import OverlayCore

struct SidebarView: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var layoutPresetName = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 13) {
                    SidebarWorkflowSection(
                        step: "1",
                        title: localization.string("sidebar.source.title"),
                        subtitle: localization.string("sidebar.source.subtitle"),
                        systemImage: "film.stack"
                    ) {
                        fileSection
                            .disabled(model.isExporting)
                    }

                    SidebarDivider()

                    SidebarWorkflowSection(
                        step: "2",
                        title: localization.string("sidebar.canvas.title"),
                        subtitle: localization.string("sidebar.canvas.subtitle"),
                        systemImage: "rectangle.dashed"
                    ) {
                        canvasSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }

            Divider()
            statusFooter
        }
        .controlSize(.small)
    }

    private var statusFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string("sidebar.status"))
        .accessibilityValue(model.status)
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                MediaPoolList(
                    kindTitle: localization.string("sidebar.video.title"),
                    placeholder: localization.string("sidebar.video.placeholder"),
                    systemImage: "film",
                    assets: model.videoAssets,
                    activeID: model.activeVideoAssetID,
                    inUseIDs: model.timelineAssetIDsInUse,
                    addTitle: localization.string("mediapool.addVideo"),
                    select: model.selectVideoAsset,
                    remove: model.removeVideoAsset,
                    appendToTimeline: model.addVideoAssetToTimeline,
                    timelineDragPayload: { TimelineDragPayload.video(assetID: $0.id) },
                    add: model.chooseVideo
                )

                if let failure = model.videoLoadFailure {
                    SourceLoadFailureRow(
                        message: localization.string(failure.messageKey, failure.detail),
                        retryTitle: localization.string("sidebar.retryLoad"),
                        retry: model.retryVideoLoad
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                MediaPoolList(
                    kindTitle: localization.string("sidebar.fit.title"),
                    placeholder: localization.string("sidebar.fit.placeholder"),
                    systemImage: "figure.run",
                    assets: model.activityAssets,
                    activeID: model.activeActivityAssetID,
                    inUseIDs: model.timelineAssetIDsInUse,
                    addTitle: localization.string("mediapool.addActivity"),
                    select: model.selectActivityAsset,
                    remove: model.removeActivityAsset,
                    appendToTimeline: model.addActivityAssetToTimeline,
                    timelineDragPayload: { TimelineDragPayload.activity(assetID: $0.id) },
                    add: model.chooseFIT
                )

                if let failure = model.fitLoadFailure {
                    SourceLoadFailureRow(
                        message: localization.string(failure.messageKey, failure.detail),
                        retryTitle: localization.string("sidebar.retryLoad"),
                        retry: model.retryFITLoad
                    )
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSubsectionHeader(title: localization.string("sidebar.grid"), systemImage: "grid")

            Toggle(localization.string("sidebar.showGrid"), isOn: $model.showGrid)
            Toggle(localization.string("sidebar.snapWhileDragging"), isOn: $model.snapGaugeToGrid)

            SidebarStepperRow(
                title: localization.string("sidebar.columns"),
                value: Binding(
                    get: { model.gridColumns },
                    set: { model.setGridColumns($0) }
                ),
                range: 2...64
            )
            SidebarStepperRow(
                title: localization.string("sidebar.rows"),
                value: Binding(
                    get: { model.gridRows },
                    set: { model.setGridRows($0) }
                ),
                range: 2...64
            )
        }
    }

    private var layoutPresetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSubsectionHeader(title: localization.string("sidebar.presets"), systemImage: "rectangle.3.group")
            layoutPresetSyncStatusRow

            HStack(spacing: 8) {
                TextField(localization.string("sidebar.presetName"), text: $layoutPresetName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    if model.saveLayoutPreset(named: layoutPresetName) {
                        layoutPresetName = ""
                    }
                } label: {
                    Label(localization.string("sidebar.save"), systemImage: "tray.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .help(localization.string("sidebar.saveCurrentLayout"))
                .disabled(layoutPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 8) {
                Button {
                    model.importLayoutPresets()
                } label: {
                    Label(localization.string("sidebar.import"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.exportLayoutPresets()
                } label: {
                    Label(localization.string("sidebar.export"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.layoutPresets.isEmpty)
            }
            .buttonStyle(.bordered)

            if model.layoutPresets.isEmpty {
                Text(localization.string("sidebar.noSavedPresets"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.layoutPresetsForDisplay) { preset in
                        LayoutPresetRow(
                            preset: preset,
                            isDefault: model.defaultLayoutPresetID == preset.id,
                            apply: { model.applyLayoutPreset(id: preset.id) },
                            makeDefault: { model.setDefaultLayoutPreset(id: preset.id) },
                            delete: { model.deleteLayoutPreset(id: preset.id) }
                        )
                    }
                }
            }
        }
    }

    private var layoutPresetSyncStatusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: layoutPresetSyncStatusIcon)
                .foregroundStyle(layoutPresetSyncStatusTint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(localization.string("sidebar.presetSync.title"))
                    .font(.caption.weight(.semibold))
                Text(layoutPresetSyncStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .shellGroupSurface(cornerRadius: 8)
    }

    private var layoutPresetSyncStatusIcon: String {
        switch model.layoutPresetSyncStatus {
        case .localOnly:
            return "icloud.slash"
        case .ready:
            return "icloud"
        case .uploadRequested:
            return "icloud.and.arrow.up"
        case .receivedUpdate:
            return "icloud.and.arrow.down"
        }
    }

    private var layoutPresetSyncStatusTint: Color {
        switch model.layoutPresetSyncStatus {
        case .localOnly:
            return .secondary
        default:
            return .accentColor
        }
    }

    private var layoutPresetSyncStatusText: String {
        switch model.layoutPresetSyncStatus {
        case .localOnly:
            return localization.string("sidebar.presetSync.localOnly")
        case .ready:
            return localization.string("sidebar.presetSync.ready")
        case let .uploadRequested(date):
            return localization.string("sidebar.presetSync.uploadRequested", formatPresetSyncTime(date))
        case let .receivedUpdate(date):
            return localization.string("sidebar.presetSync.receivedUpdate", formatPresetSyncTime(date))
        }
    }

    private func formatPresetSyncTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewSection
            SidebarDivider()
            layoutPresetSection
                .disabled(model.isExporting)
        }
    }
}

struct ExportTrimRangeControl: View {
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval
    var sourceDuration: TimeInterval
    var currentTime: TimeInterval
    var titleKey = "sidebar.exportRange"
    var fullKey = "sidebar.exportRange.full"
    var setStartKey = "sidebar.exportRange.setStart"
    var setEndKey = "sidebar.exportRange.setEnd"
    var reset: () -> Void
    var formatTime: (TimeInterval) -> String
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(localization.string(titleKey), systemImage: "scissors")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Button {
                    start = currentTime
                } label: {
                    Label(localization.string(setStartKey), systemImage: "arrow.left.to.line")
                }

                Button {
                    end = currentTime
                } label: {
                    Label(localization.string(setEndKey), systemImage: "arrow.right.to.line")
                }

                Spacer(minLength: 6)

                Button(localization.string(fullKey), action: reset)
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)

            ExportTrimRangeSlider(
                start: $start,
                end: $end,
                sourceDuration: sourceDuration
            )

            HStack(alignment: .top, spacing: 8) {
                trimValue(label: localization.string("sidebar.exportRange.start"), value: start)
                Spacer(minLength: 8)
                trimValue(label: localization.string("sidebar.exportRange.duration"), value: max(0, end - start))
                Spacer(minLength: 8)
                trimValue(label: localization.string("sidebar.exportRange.end"), value: end, alignment: .trailing)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shellGroupSurface(cornerRadius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localization.string(titleKey))
    }

    private func trimValue(
        label: String,
        value: TimeInterval,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatTime(value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct ExportTrimRangeSlider: View {
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval
    var sourceDuration: TimeInterval
    @State private var activeHandle: Handle?
    private let minimumRangeDuration: TimeInterval = 0.1

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let startX = xPosition(for: start, width: width)
            let endX = xPosition(for: end, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.25))
                    .frame(height: 4)
                    .position(x: width / 2, y: 12)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, endX - startX), height: 4)
                    .position(x: startX + max(0, endX - startX) / 2, y: 12)

                handle(isActive: activeHandle == .start)
                    .position(x: startX, y: 12)

                handle(isActive: activeHandle == .end)
                    .position(x: endX, y: 12)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard sourceDuration > minimumRangeDuration else { return }
                        let handle = activeHandle ?? nearestHandle(
                            to: value.startLocation.x,
                            startX: startX,
                            endX: endX
                        )
                        activeHandle = handle
                        let time = time(for: value.location.x, width: width)
                        switch handle {
                        case .start:
                            start = min(max(0, time), max(0, end - minimumRangeDuration))
                        case .end:
                            end = max(min(sourceDuration, time), min(sourceDuration, start + minimumRangeDuration))
                        }
                    }
                    .onEnded { _ in activeHandle = nil }
            )
        }
        .frame(height: 24)
    }

    private func handle(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.background)
            .frame(width: 10, height: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.55), lineWidth: isActive ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    private func xPosition(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard sourceDuration > 0 else { return 0 }
        let progress = min(1, max(0, time / sourceDuration))
        return CGFloat(progress) * width
    }

    private func time(for x: CGFloat, width: CGFloat) -> TimeInterval {
        let progress = min(1, max(0, x / max(1, width)))
        return TimeInterval(progress) * sourceDuration
    }

    private func nearestHandle(to x: CGFloat, startX: CGFloat, endX: CGFloat) -> Handle {
        abs(x - startX) <= abs(x - endX) ? .start : .end
    }

    private enum Handle {
        case start
        case end
    }
}

private struct SourceLoadFailureRow: View {
    var message: String
    var retryTitle: String
    var retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(retryTitle, action: retry)
                .controlSize(.small)
        }
        .padding(8)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct SidebarSummaryRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }
}
