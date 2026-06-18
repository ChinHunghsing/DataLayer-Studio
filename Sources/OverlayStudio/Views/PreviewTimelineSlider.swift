import AppKit
import SwiftUI

struct PreviewTimelineSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var isEnabled: Bool
    var accessibilityLabel: String
    var onFrameStep: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onFrameStep: onFrameStep)
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
        nsView.minValue = range.lowerBound
        nsView.maxValue = range.upperBound
        nsView.isEnabled = isEnabled
        nsView.onFrameStep = { context.coordinator.stepFrame(by: $0) }
        nsView.setAccessibilityLabel(accessibilityLabel)

        if abs(nsView.doubleValue - value) > 0.000_001 {
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
            value.wrappedValue = sender.doubleValue
        }

        func stepFrame(by offset: Int) {
            onFrameStep(offset)
        }
    }
}

final class FocusableTimelineSlider: NSSlider {
    var onFrameStep: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
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
