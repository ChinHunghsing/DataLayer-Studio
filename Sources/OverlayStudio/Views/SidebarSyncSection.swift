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

            TimecodeField(
                title: localization.string("sidebar.sync.videoTime"),
                value: $model.syncVideoSeconds,
                range: 0...86_400
            )

            TimecodeField(
                title: localization.string("sidebar.sync.activityTime"),
                value: $model.syncFITSeconds,
                range: 0...86_400
            )

            Text(localization.string("sidebar.sync.matchHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var videoStartControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimecodeField(
                title: localization.string("sidebar.sync.activityAtVideoStart"),
                value: $model.fitStartSeconds,
                range: 0...86_400
            )

            SyncInfoBox(
                title: localization.string("sidebar.sync.whenToUse"),
                message: localization.string("sidebar.sync.videoStartHelp"),
                systemImage: "video"
            )
        }
    }

    private var manualOffsetControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimecodeField(
                title: localization.string("sidebar.sync.manualOffset"),
                value: $model.offsetSeconds,
                range: -86_400...86_400,
                allowsNegative: true
            )

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

private struct TimecodeField: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var allowsNegative = false

    @EnvironmentObject private var localization: LocalizationStore
    @State private var zeroSign = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if allowsNegative {
                    Picker(localization.string("sidebar.sync.time.sign"), selection: signBinding) {
                        Text("+").tag(1)
                        Text("-").tag(-1)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 64)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TimecodeUnitStepper(
                    label: localization.string("sidebar.sync.time.hours"),
                    value: componentBinding(.hours),
                    range: 0...maxHours
                )
                Text(":")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                TimecodeUnitStepper(
                    label: localization.string("sidebar.sync.time.minutes"),
                    value: componentBinding(.minutes),
                    range: 0...59
                )
                Text(":")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                TimecodeUnitStepper(
                    label: localization.string("sidebar.sync.time.seconds"),
                    value: componentBinding(.seconds),
                    range: 0...59
                )
            }
        }
    }

    private var signBinding: Binding<Int> {
        Binding(
            get: { currentSign },
            set: { newSign in
                zeroSign = newSign
                let absolute = abs(value.isFinite ? value : 0)
                setSeconds(Double(newSign) * absolute)
            }
        )
    }

    private var currentSign: Int {
        if value < 0 { return -1 }
        if value > 0 { return 1 }
        return zeroSign
    }

    private var maxHours: Int {
        max(0, Int(abs(range.upperBound).rounded(.down)) / 3_600)
    }

    private func componentBinding(_ component: TimecodeComponent) -> Binding<Int> {
        Binding(
            get: { components[keyPath: component.keyPath] },
            set: { newValue in
                var next = components
                next[keyPath: component.keyPath] = newValue
                setSeconds(Double(currentSign) * Double(next.totalSeconds))
            }
        )
    }

    private var components: TimecodeComponents {
        TimecodeComponents(totalSeconds: Int(abs(value.isFinite ? value : 0).rounded()))
    }

    private func setSeconds(_ seconds: Double) {
        guard seconds.isFinite else {
            value = range.lowerBound
            return
        }
        value = min(range.upperBound, max(range.lowerBound, seconds))
    }
}

private struct TimecodeUnitStepper: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 2) {
                TextField(label, value: clampedValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(minWidth: 34)
                Stepper(label, value: clampedValue, in: range)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { min(range.upperBound, max(range.lowerBound, value)) },
            set: { value = min(range.upperBound, max(range.lowerBound, $0)) }
        )
    }
}

private enum TimecodeComponent {
    case hours
    case minutes
    case seconds

    var keyPath: WritableKeyPath<TimecodeComponents, Int> {
        switch self {
        case .hours:
            return \.hours
        case .minutes:
            return \.minutes
        case .seconds:
            return \.seconds
        }
    }
}

private struct TimecodeComponents {
    var hours: Int
    var minutes: Int
    var seconds: Int

    init(totalSeconds: Int) {
        let clamped = max(0, totalSeconds)
        self.hours = clamped / 3_600
        self.minutes = (clamped % 3_600) / 60
        self.seconds = clamped % 60
    }

    var totalSeconds: Int {
        hours * 3_600 + minutes * 60 + seconds
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
