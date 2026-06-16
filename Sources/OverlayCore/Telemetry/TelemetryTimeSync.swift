import Foundation

public struct TelemetryTimeSync: Equatable, CustomStringConvertible {
    public var videoSyncTime: TimeInterval
    public var fitSyncTime: TimeInterval

    public init(videoSyncTime: TimeInterval = 0, fitSyncTime: TimeInterval = 0) {
        self.videoSyncTime = videoSyncTime
        self.fitSyncTime = fitSyncTime
    }

    public static let identity = TelemetryTimeSync()

    public static func legacyOffset(_ seconds: TimeInterval) -> TelemetryTimeSync {
        TelemetryTimeSync(videoSyncTime: seconds, fitSyncTime: 0)
    }

    public var fitOffsetFromVideoStart: TimeInterval {
        fitSyncTime - videoSyncTime
    }

    public func fitElapsed(forVideoTime videoTime: TimeInterval) -> TimeInterval {
        max(0, videoTime + fitOffsetFromVideoStart)
    }

    public var description: String {
        "video \(Self.format(videoSyncTime))s = FIT \(Self.format(fitSyncTime))s"
    }

    public static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }
}

