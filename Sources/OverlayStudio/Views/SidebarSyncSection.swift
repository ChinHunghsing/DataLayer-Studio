import SwiftUI

struct SidebarSyncSection: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.videoURL == nil {
                SyncInfoBox(
                    title: localization.string("sidebar.sync.noVideo.title"),
                    message: localization.string("sidebar.sync.noVideo.message"),
                    systemImage: "info.circle"
                )
            } else {
                matchPointControls
            }
        }
        .onAppear {
            model.useMatchPointSyncMode()
        }
    }

    private var matchPointControls: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            SyncInfoBox(
                title: localization.string("sidebar.sync.currentFrame"),
                message: currentMappingText,
                systemImage: "arrow.left.arrow.right"
            )

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

    private var currentMappingText: String {
        localization.string(
            "sidebar.sync.currentMapping",
            formatDuration(model.previewTime),
            formatActivityTime(model.timeSync.rawFitElapsed(forVideoTime: model.previewTime))
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

    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
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
            accessibilityLabel: "\(title) — \(localization.string("sidebar.sync.time.hours"))",
            value: componentBinding(.hours)
        )
    }

    private var minutesControl: some View {
        TimecodeUnitStepper(
            label: localization.string("sidebar.sync.time.minutes"),
            accessibilityLabel: "\(title) — \(localization.string("sidebar.sync.time.minutes"))",
            value: componentBinding(.minutes)
        )
    }

    private var secondsControl: some View {
        TimecodeUnitStepper(
            label: localization.string("sidebar.sync.time.seconds"),
            accessibilityLabel: "\(title) — \(localization.string("sidebar.sync.time.seconds"))",
            value: componentBinding(.seconds)
        )
    }

    private var millisecondsControl: some View {
        TimecodeUnitStepper(
            label: localization.string("sidebar.sync.time.milliseconds"),
            accessibilityLabel: "\(title) — \(localization.string("sidebar.sync.time.milliseconds"))",
            value: componentBinding(.milliseconds)
        )
    }

    private func timecodeSeparator(_ text: String) -> some View {
        Text(text)
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func componentBinding(_ component: TimecodeComponent) -> Binding<Int> {
        Binding(
            get: { components[keyPath: component.keyPath] },
            set: { newValue in
                let milliseconds = components.totalMilliseconds(replacing: component, with: newValue)
                setSeconds(Double(milliseconds) / 1_000)
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
    var accessibilityLabel: String?
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 2) {
                TextField(label, value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(minWidth: 34)
                    .accessibilityLabel(accessibilityLabel ?? label)
                Stepper(label, value: $value)
                    .labelsHidden()
                    .accessibilityLabel(accessibilityLabel ?? label)
                    .accessibilityValue("\(value)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum TimecodeComponent {
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

struct TimecodeComponents {
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

    func totalMilliseconds(replacing component: TimecodeComponent, with value: Int) -> Int {
        var next = self
        next[keyPath: component.keyPath] = value
        return next.totalMilliseconds
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
