import SwiftUI

struct SidebarSyncSection: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    private let syncModeDisplayOrder: [SyncMode] = [.syncPoint, .fitStart, .offset]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SidebarControl(title: localization.string("sidebar.sync.mode")) {
                Picker(localization.string("sidebar.sync.mode"), selection: $model.syncMode) {
                    ForEach(syncModeDisplayOrder) { mode in
                        Text(localization.string(mode.localizationKey)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SyncInfoBox(
                title: localization.string("sidebar.sync.currentFrame"),
                message: currentMappingText,
                systemImage: "arrow.left.arrow.right"
            )

            SidebarDivider()

            switch model.syncMode {
            case .syncPoint:
                matchPointControls
            case .fitStart:
                videoStartControls
            case .offset:
                manualOffsetControls
            }
        }
    }

    private var matchPointControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.markSportStart()
            } label: {
                Label(localization.string("sidebar.sync.setCurrentAsStart"), systemImage: "figure.run.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.player == nil || model.isExporting)

            Text(localization.string("sidebar.sync.setCurrentAsStartHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            NumberField(title: localization.string("sidebar.sync.videoTime"), suffix: "s", value: boundedDoubleBinding(
                get: { model.syncVideoSeconds },
                set: { model.syncVideoSeconds = $0 },
                range: 0...86_400
            ))

            NumberField(title: localization.string("sidebar.sync.activityTime"), suffix: "s", value: boundedDoubleBinding(
                get: { model.syncFITSeconds },
                set: { model.syncFITSeconds = $0 },
                range: 0...86_400
            ))

            Text(localization.string("sidebar.sync.matchHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var videoStartControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            NumberField(title: localization.string("sidebar.sync.activityAtVideoStart"), suffix: "s", value: boundedDoubleBinding(
                get: { model.fitStartSeconds },
                set: { model.fitStartSeconds = $0 },
                range: 0...86_400
            ))

            SyncInfoBox(
                title: localization.string("sidebar.sync.whenToUse"),
                message: localization.string("sidebar.sync.videoStartHelp"),
                systemImage: "video"
            )
        }
    }

    private var manualOffsetControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            NumberField(title: localization.string("sidebar.sync.manualOffset"), suffix: "s", value: boundedDoubleBinding(
                get: { model.offsetSeconds },
                set: { model.offsetSeconds = $0 },
                range: -86_400...86_400
            ))

            SyncInfoBox(
                title: localization.string("sidebar.sync.offsetResult"),
                message: manualOffsetText,
                systemImage: "plus.forwardslash.minus"
            )

            Text(localization.string("sidebar.sync.manualOffsetHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentMappingText: String {
        localization.string(
            "sidebar.sync.currentMapping",
            formatDuration(model.previewTime),
            formatActivityTime(model.timeSync.rawFitElapsed(forVideoTime: model.previewTime))
        )
    }

    private var manualOffsetText: String {
        let offset = model.offsetSeconds
        if abs(offset) < 0.0005 {
            return localization.string("sidebar.sync.offsetAligned")
        }
        if offset > 0 {
            return localization.string("sidebar.sync.offsetVideoBeforeFit", formatDuration(offset))
        }
        return localization.string("sidebar.sync.offsetVideoAfterFit", formatDuration(abs(offset)))
    }

    private func boundedDoubleBinding(
        get: @escaping () -> Double,
        set: @escaping (Double) -> Void,
        range: ClosedRange<Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                let value = get()
                return min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
            },
            set: {
                set(min(range.upperBound, max(range.lowerBound, $0.isFinite ? $0 : range.lowerBound)))
            }
        )
    }

    private func formatActivityTime(_ seconds: TimeInterval) -> String {
        if seconds < 0 {
            return localization.string("sidebar.sync.beforeActivity", formatDuration(abs(seconds)))
        }
        return formatDuration(seconds)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let absoluteSeconds = max(0, abs(seconds))
        let roundedTenths = Int((absoluteSeconds * 10).rounded())
        let hours = roundedTenths / 36_000
        let minutes = (roundedTenths % 36_000) / 600
        let seconds = Double(roundedTenths % 600) / 10

        if hours > 0 {
            return String(format: "%d:%02d:%04.1f", hours, minutes, seconds)
        }
        return String(format: "%02d:%04.1f", minutes, seconds)
    }
}

private struct SyncInfoBox: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
