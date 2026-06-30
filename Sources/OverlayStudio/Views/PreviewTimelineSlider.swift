import AppKit
import SwiftUI

struct PreviewTimelineSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var isEnabled: Bool
    var accessibilityLabel: String
    var onFrameStep: (Int) -> Void
    var onLiveChange: (Double) -> Void = { _ in }
    static let valueChangeEpsilon = 0.000_5

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onFrameStep: onFrameStep, onLiveChange: onLiveChange)
    }

    func makeNSView(context: Context) -> FocusableTimelineSlider {
        let slider = FocusableTimelineSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.isContinuous = true
        slider.onFrameStep = { context.coordinator.stepFrame(by: $0) }
        slider.setAccessibilityLabel(accessibilityLabel)
        return slider
    }

    func updateNSView(_ nsView: FocusableTimelineSlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onFrameStep = onFrameStep
        context.coordinator.onLiveChange = onLiveChange
        if nsView.minValue != range.lowerBound {
            nsView.minValue = range.lowerBound
        }
        if nsView.maxValue != range.upperBound {
            nsView.maxValue = range.upperBound
        }
        if nsView.isEnabled != isEnabled {
            nsView.isEnabled = isEnabled
        }
        if nsView.accessibilityLabel() != accessibilityLabel {
            nsView.setAccessibilityLabel(accessibilityLabel)
        }

        if !nsView.isTrackingMouse, abs(nsView.doubleValue - value) > 0.000_001 {
            nsView.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var onFrameStep: (Int) -> Void
        var onLiveChange: (Double) -> Void

        init(value: Binding<Double>, onFrameStep: @escaping (Int) -> Void, onLiveChange: @escaping (Double) -> Void) {
            self.value = value
            self.onFrameStep = onFrameStep
            self.onLiveChange = onLiveChange
        }

        @objc func valueChanged(_ sender: NSSlider) {
            guard abs(value.wrappedValue - sender.doubleValue) > PreviewTimelineSlider.valueChangeEpsilon else { return }
            onLiveChange(sender.doubleValue)
            value.wrappedValue = sender.doubleValue
        }

        func stepFrame(by offset: Int) {
            onFrameStep(offset)
        }
    }
}

final class FocusableTimelineSlider: NSSlider {
    var onFrameStep: ((Int) -> Void)?
    private(set) var isTrackingMouse = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        isTrackingMouse = true
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingMouse else { return }
        updateValue(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingMouse else { return }
        updateValue(with: event)
        isTrackingMouse = false
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onFrameStep?(-1)
        case 124:
            onFrameStep?(1)
        default:
            super.keyDown(with: event)
        }
    }

    private func updateValue(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let nextValue = Self.value(
            forX: location.x,
            width: bounds.width,
            minValue: minValue,
            maxValue: maxValue
        )
        guard abs(doubleValue - nextValue) > PreviewTimelineSlider.valueChangeEpsilon else { return }
        doubleValue = nextValue
        _ = sendAction(action, to: target)
        window?.displayIfNeeded()
    }

    static func value(forX x: CGFloat, width: CGFloat, minValue: Double, maxValue: Double) -> Double {
        guard width > 0, maxValue > minValue else { return minValue }
        let fraction = min(1, max(0, Double(x / width)))
        return minValue + (maxValue - minValue) * fraction
    }
}
