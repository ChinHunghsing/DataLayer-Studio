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
                .disabled(model.videoURL == nil)
            }

            SyncInfoBox(
                title: localization.string("sidebar.sync.currentFrame"),
                message: currentMappingText,
                systemImage: "arrow.left.arrow.right"
            )

            SidebarDivider()

            Group {
                switch model.syncMode {
                case .syncPoint:
                    matchPointControls
                case .fitStart:
                    videoStartControls
                case .offset:
                    manualOffsetControls
                }
            }
            .disabled(model.videoURL == nil)
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
        let roundedMilliseconds = Int((absoluteSeconds * 1_000).rounded())
        let hours = roundedMilliseconds / 3_600_000
        let minutes = (roundedMilliseconds % 3_600_000) / 60_000
        let seconds = Double(roundedMilliseconds % 60_000) / 1_000

        if hours > 0 {
            return String(format: "%d:%02d:%06.3f", hours, minutes, seconds)
        }
        return String(format: "%02d:%06.3f", minutes, seconds)
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

            ViewThatFits(in: .horizontal) {
                timecodeControls
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        hoursControl
                        timecodeSeparator(":")
                        minutesControl
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        secondsControl
                        timecodeSeparator(".")
                        millisecondsControl
                    }
                }
            }
        }
    }

    private var timecodeControls: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            hoursControl
            timecodeSeparator(":")
            minutesControl
            timecodeSeparator(":")
            secondsControl
            timecodeSeparator(".")
            millisecondsControl
        }
    }

    private var hoursControl: some View {
        TimecodeUnitStepper(
            label: localization.string("sidebar.sync.time.hours"),
            value: componentBinding(.hours),
            range: 0...maxHours
        )
    }

    private var minutesControl: some View {
        TimecodeUnitStepper(
            label: localization.string("sidebar.sync.time.minutes"),
            value: componentBinding(.minutes),
            range: 0...59
        )
    }

    private var secondsControl: some View {
        TimecodeUnitStepper(
            label: localization.string("sidebar.sync.time.seconds"),
            value: componentBinding(.seconds),
            range: 0...59
        )
    }

    private var millisecondsControl: some View {
        TimecodeUnitStepper(
            label: localization.string("sidebar.sync.time.milliseconds"),
            value: componentBinding(.milliseconds),
            range: 0...999
        )
    }

    private func timecodeSeparator(_ text: String) -> some View {
        Text(text)
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
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
                setSeconds(Double(currentSign) * Double(next.totalMilliseconds) / 1_000)
            }
        )
    }

    private var components: TimecodeComponents {
        TimecodeComponents(totalMilliseconds: Int((abs(value.isFinite ? value : 0) * 1_000).rounded()))
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
    case milliseconds

    var keyPath: WritableKeyPath<TimecodeComponents, Int> {
        switch self {
        case .hours:
            return \.hours
        case .minutes:
            return \.minutes
        case .seconds:
            return \.seconds
        case .milliseconds:
            return \.milliseconds
        }
    }
}

private struct TimecodeComponents {
    var hours: Int
    var minutes: Int
    var seconds: Int
    var milliseconds: Int

    init(totalMilliseconds: Int) {
        let clamped = max(0, totalMilliseconds)
        self.hours = clamped / 3_600_000
        self.minutes = (clamped % 3_600_000) / 60_000
        self.seconds = (clamped % 60_000) / 1_000
        self.milliseconds = clamped % 1_000
    }

    var totalMilliseconds: Int {
        hours * 3_600_000 + minutes * 60_000 + seconds * 1_000 + milliseconds
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
