import SwiftUI

struct PreviewTimelineSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var isEnabled: Bool
    var accessibilityLabel: String
    var onFrameStep: (Int) -> Void
    var onLiveChange: (Double) -> Void = { _ in }

    @FocusState private var hasFocus: Bool
    @State private var dragValue: Double?

    static let valueChangeEpsilon = 0.000_5

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let displayedValue = dragValue ?? value
            let fraction = fraction(for: displayedValue)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.26))
                    .frame(height: 6)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: width * fraction, height: 6)
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(Circle().stroke(Color.accentColor.opacity(hasFocus ? 0.95 : 0.35), lineWidth: 2))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .frame(width: 18, height: 18)
                    .offset(x: max(0, min(width - 18, width * fraction - 9)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { update(locationX: $0.location.x, width: width) }
                    .onEnded { _ in
                        if let dragValue {
                            value = dragValue
                        }
                        dragValue = nil
                    }
            )
        }
        .frame(height: 22)
        .opacity(isEnabled ? 1 : 0.45)
        .focusable(isEnabled)
        .focused($hasFocus)
        .onMoveCommand { direction in
            guard isEnabled else { return }
            switch direction {
            case .left:
                onFrameStep(-1)
            case .right:
                onFrameStep(1)
            default:
                break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(String(format: "%.3f", value)))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func update(locationX: CGFloat, width: CGFloat) {
        guard isEnabled else { return }
        hasFocus = true
        let nextValue = Self.value(forX: locationX, width: width, minValue: range.lowerBound, maxValue: range.upperBound)
        guard abs((dragValue ?? value) - nextValue) > Self.valueChangeEpsilon else { return }
        dragValue = nextValue
        onLiveChange(nextValue)
    }

    private func fraction(for value: Double) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        return CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    static func value(forX x: CGFloat, width: CGFloat, minValue: Double, maxValue: Double) -> Double {
        guard width > 0, maxValue > minValue else { return minValue }
        let fraction = min(1, max(0, Double(x / width)))
        return minValue + (maxValue - minValue) * fraction
    }
}
