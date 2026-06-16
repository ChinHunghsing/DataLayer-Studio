import CoreGraphics
import Foundation

public enum OverlayDistanceUnit: String, CaseIterable, Identifiable {
    case meters = "m"
    case kilometers = "km"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .meters:
            return "Meters (m)"
        case .kilometers:
            return "Kilometers (km)"
        }
    }

    public var symbol: String { rawValue }

    public func format(meters: Double?) -> String {
        guard let meters, meters.isFinite else { return "--" }
        switch self {
        case .meters:
            return String(format: "%.0f", meters)
        case .kilometers:
            return String(format: "%.2f", meters / 1000)
        }
    }
}

public struct OverlayRenderConfig {
    public var size: CGSize
    public var timeSync: TelemetryTimeSync
    public var routePointLimit: Int
    public var layout: OverlayLayout
    public var distanceUnit: OverlayDistanceUnit

    public init(
        size: CGSize,
        timeSync: TelemetryTimeSync = .identity,
        routePointLimit: Int = 900,
        layout: OverlayLayout = .default,
        distanceUnit: OverlayDistanceUnit = .kilometers
    ) {
        self.size = size
        self.timeSync = timeSync
        self.routePointLimit = routePointLimit
        self.layout = layout
        self.distanceUnit = distanceUnit
    }

    public init(
        size: CGSize,
        telemetryOffset: TimeInterval,
        routePointLimit: Int = 900,
        distanceUnit: OverlayDistanceUnit = .kilometers
    ) {
        self.init(
            size: size,
            timeSync: .legacyOffset(telemetryOffset),
            routePointLimit: routePointLimit,
            distanceUnit: distanceUnit
        )
    }
}
