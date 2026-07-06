import AppKit
import SwiftUI

struct PreviewTimelineSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var isEnabled: Bool
    var accessibilityLabel: String
    var onFrameStep: (Int) -> Void
    static let valueChangeEpsilon = 0.000_5

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onFrameStep: onFrameStep)
    }

    func makeNSView(context: Context) -> FocusableTimelineSlider {
        let slider = FocusableTimelineSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.valueChanged(_:)))
        slider.isContinuous = true
        slider.focusRingType = .none
        slider.onFrameStep = { context.coordinator.stepFrame(by: $0) }
        slider.setAccessibilityLabel(accessibilityLabel)
        return slider
    }

    func updateNSView(_ nsView: FocusableTimelineSlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onFrameStep = onFrameStep
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

        init(value: Binding<Double>, onFrameStep: @escaping (Int) -> Void) {
            self.value = value
            self.onFrameStep = onFrameStep
        }

        @objc func valueChanged(_ sender: NSSlider) {
            guard abs(value.wrappedValue - sender.doubleValue) > PreviewTimelineSlider.valueChangeEpsilon else { return }
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
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isTrackingMouse = true
        defer {
            isTrackingMouse = false
            needsDisplay = true
        }
        super.mouseDown(with: event)
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
}
