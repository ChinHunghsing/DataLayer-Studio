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
    static let liveChangeInterval: TimeInterval = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> TimelineScrubberView {
        let view = TimelineScrubberView()
        view.onCommit = { context.coordinator.value.wrappedValue = $0 }
        view.onLiveChange = { context.coordinator.onLiveChange($0) }
        view.onFrameStep = { context.coordinator.onFrameStep($0) }
        return view
    }

    func updateNSView(_ view: TimelineScrubberView, context: Context) {
        context.coordinator.value = $value
        context.coordinator.onLiveChange = onLiveChange
        context.coordinator.onFrameStep = onFrameStep
        view.configure(
            value: value,
            range: range,
            isEnabled: isEnabled,
            accessibilityLabel: accessibilityLabel
        )
    }

    static func value(forX x: CGFloat, width: CGFloat, minValue: Double, maxValue: Double) -> Double {
        TimelineScrubberView.value(forX: x, width: width, minValue: minValue, maxValue: maxValue)
    }

    final class Coordinator {
        var value: Binding<Double>
        var onLiveChange: (Double) -> Void = { _ in }
        var onFrameStep: (Int) -> Void = { _ in }

        init(value: Binding<Double>) {
            self.value = value
        }
    }
}

final class TimelineScrubberView: NSView {
    var onCommit: (Double) -> Void = { _ in }
    var onLiveChange: (Double) -> Void = { _ in }
    var onFrameStep: (Int) -> Void = { _ in }

    private var currentValue: Double = 0
    private var range: ClosedRange<Double> = 0...1
    private var isScrubberEnabled = true
    private var isTrackingPointer = false

    override var acceptsFirstResponder: Bool { isScrubberEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        value: Double,
        range: ClosedRange<Double>,
        isEnabled: Bool,
        accessibilityLabel: String
    ) {
        self.range = range
        isScrubberEnabled = isEnabled
        alphaValue = isEnabled ? 1 : 0.45
        if !isTrackingPointer {
            currentValue = clamped(value)
        }
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(String(format: "%.3f", currentValue))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isScrubberEnabled else { return }
        window?.makeFirstResponder(self)
        isTrackingPointer = true
        update(with: event, commit: false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isScrubberEnabled else { return }
        update(with: event, commit: false)
    }

    override func mouseUp(with event: NSEvent) {
        guard isScrubberEnabled else { return }
        update(with: event, commit: true)
        isTrackingPointer = false
    }

    override func keyDown(with event: NSEvent) {
        guard isScrubberEnabled else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 123:
            onFrameStep(-1)
        case 124:
            onFrameStep(1)
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackHeight: CGFloat = 6
        let knobDiameter: CGFloat = 18
        let trackRect = NSRect(
            x: 0,
            y: bounds.midY - trackHeight / 2,
            width: bounds.width,
            height: trackHeight
        )
        let fraction = self.fraction(for: currentValue)
        let progressRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: trackRect.width * fraction,
            height: trackRect.height
        )
        let knobX = max(0, min(bounds.width - knobDiameter, bounds.width * fraction - knobDiameter / 2))
        let knobRect = NSRect(
            x: knobX,
            y: bounds.midY - knobDiameter / 2,
            width: knobDiameter,
            height: knobDiameter
        )

        NSColor.secondaryLabelColor.withAlphaComponent(0.26).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()

        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: progressRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()

        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: knobRect).fill()

        let stroke = window?.firstResponder === self ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.35)
        stroke.setStroke()
        let knobPath = NSBezierPath(ovalIn: knobRect.insetBy(dx: 1, dy: 1))
        knobPath.lineWidth = 2
        knobPath.stroke()
    }

    private func update(with event: NSEvent, commit: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let nextValue = Self.value(
            forX: point.x,
            width: bounds.width,
            minValue: range.lowerBound,
            maxValue: range.upperBound
        )
        guard abs(currentValue - nextValue) > PreviewTimelineSlider.valueChangeEpsilon || commit else { return }
        currentValue = nextValue
        setAccessibilityValue(String(format: "%.3f", currentValue))
        needsDisplay = true
        onLiveChange(nextValue)
        if commit {
            onCommit(nextValue)
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, value.isFinite ? value : range.lowerBound))
    }

    private func fraction(for value: Double) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        return CGFloat((clamped(value) - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    static func value(forX x: CGFloat, width: CGFloat, minValue: Double, maxValue: Double) -> Double {
        guard width > 0, maxValue > minValue else { return minValue }
        let fraction = min(1, max(0, Double(x / width)))
        return minValue + (maxValue - minValue) * fraction
    }
}
