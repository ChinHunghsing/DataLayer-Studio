import CoreGraphics
import Foundation
import OverlayCore

public enum TouchSyncMode: String, CaseIterable, Identifiable {
    case offset
    case fitStart
    case syncPoint

    public var id: String { rawValue }
}

public struct TouchMessage: Equatable {
    public var key: String
    public var arguments: [String]

    public init(_ key: String, _ arguments: [String] = []) {
        self.key = key
        self.arguments = arguments
    }
}

@MainActor
public protocol SubscriptionEntitlementProviding: AnyObject {
    var hasActiveExportEntitlement: Bool { get }
}

@MainActor
public final class TouchSubscriptionBypass: SubscriptionEntitlementProviding {
    public static let shared = TouchSubscriptionBypass()
    public var hasActiveExportEntitlement: Bool { true }

    private init() {}
}

public enum TouchPresetSyncStatus: Equatable {
    case localOnly
    case ready
    case uploadRequested(Date)
    case receivedUpdate(Date)
}

public struct TouchSourceLoadFailure: Equatable {
    public var url: URL
    public var isSecurityScoped: Bool
    public var messageKey: String
    public var detail: String
}

public struct TouchResolutionPreset: Identifiable, Hashable {
    public static let sourceID = "source"
    public static let customID = "custom"

    public let id: String
    public let title: String
    public let width: Int
    public let height: Int

    public static let fixed: [TouchResolutionPreset] = [
        TouchResolutionPreset(id: "uhd-4k", title: "4K UHD 3840x2160", width: 3840, height: 2160),
        TouchResolutionPreset(id: "qhd-1440", title: "QHD 2560x1440", width: 2560, height: 1440),
        TouchResolutionPreset(id: "fhd-1080", title: "FHD 1920x1080", width: 1920, height: 1080),
        TouchResolutionPreset(id: "hd-720", title: "HD 1280x720", width: 1280, height: 720),
        TouchResolutionPreset(id: "vertical-4k", title: "Vertical 2160x3840", width: 2160, height: 3840),
        TouchResolutionPreset(id: "vertical-1080", title: "Vertical 1080x1920", width: 1080, height: 1920),
        TouchResolutionPreset(id: "vertical-720", title: "Vertical 720x1280", width: 720, height: 1280)
    ]
}

public struct TouchFrameRatePreset: Identifiable, Hashable {
    public static let sourceID = "source"
    public static let customID = "custom"

    public let id: String
    public let title: String
    public let framesPerSecond: Double

    public static let fixed: [TouchFrameRatePreset] = [
        TouchFrameRatePreset(id: "fps-23976", title: "23.976 fps", framesPerSecond: 23.976),
        TouchFrameRatePreset(id: "fps-24", title: "24 fps", framesPerSecond: 24),
        TouchFrameRatePreset(id: "fps-25", title: "25 fps", framesPerSecond: 25),
        TouchFrameRatePreset(id: "fps-2997", title: "29.97 fps", framesPerSecond: 29.97),
        TouchFrameRatePreset(id: "fps-30", title: "30 fps", framesPerSecond: 30),
        TouchFrameRatePreset(id: "fps-50", title: "50 fps", framesPerSecond: 50),
        TouchFrameRatePreset(id: "fps-5994", title: "59.94 fps", framesPerSecond: 59.94),
        TouchFrameRatePreset(id: "fps-60", title: "60 fps", framesPerSecond: 60)
    ]
}

public enum TouchComponentBaseSize {
    public static func size(for id: OverlayComponentID) -> CGSize {
        switch id {
        case .speed:
            return CGSize(width: 420, height: 238)
        case .weather:
            return CGSize(width: 136, height: 76)
        case .pace, .heartRate, .cadence, .calories, .ascent, .strideLength, .power, .distance,
             .verticalOscillation, .groundContactTime, .groundContactTimePercent,
             .groundContactTimeBalance, .verticalRatio, .respirationRate,
             .stepSpeedLoss, .formPower, .airPower, .legSpringStiffness:
            return CGSize(width: 160, height: 74)
        case .route:
            return CGSize(width: 382, height: 238)
        case .topProgress:
            return CGSize(width: 1650, height: 58)
        case .timeDate:
            return CGSize(width: 300, height: 118)
        }
    }
}

public enum TouchLayoutLimits {
    public static let positionRange: ClosedRange<Double> = -1.0...2.0

    public static func clampPosition(_ value: Double) -> Double {
        min(positionRange.upperBound, max(positionRange.lowerBound, value))
    }
}

/// 导出期间的运行时保护（iOS：常亮屏幕 + 后台收尾窗口；macOS 测试环境：空实现）。
public protocol TouchExportRuntimeGuarding {
    func exportDidStart()
    func exportDidEnd()
}

public struct TouchExportRuntimeNoopGuard: TouchExportRuntimeGuarding {
    public init() {}
    public func exportDidStart() {}
    public func exportDidEnd() {}
}
