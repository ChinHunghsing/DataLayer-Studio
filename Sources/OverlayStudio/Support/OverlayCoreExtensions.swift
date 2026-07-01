import AppKit
import SwiftUI
import OverlayCore

extension OverlayComponentID {
    var systemImage: String {
        switch self {
        case .speed:
            return "gauge.with.dots.needle.bottom.50percent"
        case .pace:
            return "timer"
        case .heartRate:
            return "heart.fill"
        case .cadence:
            return "figure.run"
        case .calories:
            return "flame.fill"
        case .strideLength:
            return "figure.run.motion"
        case .power:
            return "bolt.fill"
        case .verticalOscillation:
            return "arrow.up.and.down"
        case .groundContactTime:
            return "timer"
        case .formPower:
            return "bolt.badge.clock"
        case .airPower:
            return "wind"
        case .legSpringStiffness:
            return "figure.run.motion"
        case .weather:
            return "cloud.sun.fill"
        case .distance:
            return "ruler"
        case .route:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .topProgress:
            return "chart.bar.xaxis"
        case .timeDate:
            return "clock"
        }
    }

    var supportsValuePrecision: Bool {
        switch self {
        case .speed, .distance, .strideLength, .topProgress,
             .verticalOscillation, .groundContactTime, .legSpringStiffness:
            return true
        case .pace, .heartRate, .cadence, .calories, .power, .formPower, .airPower,
             .weather, .route, .timeDate:
            return false
        }
    }

    var defaultPrecision: Int {
        switch self {
        case .speed:
            return 1
        case .distance:
            return 2
        case .strideLength:
            return 2
        case .verticalOscillation:
            return 1
        case .groundContactTime:
            return 0
        case .legSpringStiffness:
            return 1
        case .topProgress:
            return 1
        case .pace, .heartRate, .cadence, .calories, .power, .formPower, .airPower,
             .weather, .route, .timeDate:
            return 0
        }
    }

    var supportsLineWidth: Bool {
        switch self {
        case .speed, .route, .topProgress:
            return true
        case .pace, .heartRate, .cadence, .calories, .strideLength, .power,
             .verticalOscillation, .groundContactTime, .formPower, .airPower, .legSpringStiffness,
             .weather, .distance, .timeDate:
            return false
        }
    }

    var supportsLengthScale: Bool {
        switch self {
        case .topProgress:
            return true
        case .speed, .pace, .heartRate, .cadence, .calories, .strideLength, .power,
             .verticalOscillation, .groundContactTime, .formPower, .airPower, .legSpringStiffness,
             .weather, .distance, .route, .timeDate:
            return false
        }
    }
}

extension OverlayAccentColor {
    var swiftUIColor: Color {
        switch self {
        case .telemetryGreen:
            return Color(red: 0.46, green: 0.97, blue: 0.58)
        case .electricBlue:
            return Color(red: 0.45, green: 0.82, blue: 1.00)
        case .amber:
            return Color(red: 1.00, green: 0.76, blue: 0.35)
        case .hotRed:
            return Color(red: 1.00, green: 0.38, blue: 0.42)
        case .cleanWhite:
            return Color(red: 0.96, green: 0.98, blue: 1.0)
        }
    }

    var overlayColor: OverlayColor {
        OverlayColor(swiftUIColor)
    }
}

extension OverlayColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    init(_ color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        self.init(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent)
        )
    }
}

extension Double {
    var percentString: String {
        "\(Int((self * 100).rounded()))%"
    }
}

enum PreviewLayoutLimits {
    static let positionRange: ClosedRange<Double> = -1.0...2.0

    static func clampPosition(_ value: Double) -> Double {
        min(positionRange.upperBound, max(positionRange.lowerBound, value))
    }
}
