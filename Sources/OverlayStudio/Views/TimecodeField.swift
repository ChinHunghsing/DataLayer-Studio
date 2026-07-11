import SwiftUI

struct TimecodeField: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>

    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

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
            label: localization.string("timecode.hours"),
            accessibilityLabel: "\(title) — \(localization.string("timecode.hours"))",
            value: componentBinding(.hours)
        )
    }

    private var minutesControl: some View {
        TimecodeUnitStepper(
            label: localization.string("timecode.minutes"),
            accessibilityLabel: "\(title) — \(localization.string("timecode.minutes"))",
            value: componentBinding(.minutes)
        )
    }

    private var secondsControl: some View {
        TimecodeUnitStepper(
            label: localization.string("timecode.seconds"),
            accessibilityLabel: "\(title) — \(localization.string("timecode.seconds"))",
            value: componentBinding(.seconds)
        )
    }

    private var millisecondsControl: some View {
        TimecodeUnitStepper(
            label: localization.string("timecode.milliseconds"),
            accessibilityLabel: "\(title) — \(localization.string("timecode.milliseconds"))",
            value: componentBinding(.milliseconds)
        )
    }

    private func timecodeSeparator(_ text: String) -> some View {
        Text(verbatim: text)
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
    var accessibilityLabel: String
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
                    .accessibilityLabel(accessibilityLabel)
                Stepper(label, value: $value)
                    .labelsHidden()
                    .accessibilityLabel(accessibilityLabel)
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
