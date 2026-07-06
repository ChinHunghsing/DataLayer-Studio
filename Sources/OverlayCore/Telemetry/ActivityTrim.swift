import Foundation

public struct ActivityTrim: Codable, Equatable {
    public var startSeconds: TimeInterval
    public var endSeconds: TimeInterval?

    public static let none = ActivityTrim()

    public init(startSeconds: TimeInterval = 0, endSeconds: TimeInterval? = nil) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public func start(in sourceDuration: TimeInterval) -> TimeInterval {
        let duration = sanitizedDuration(sourceDuration)
        let start = startSeconds.isFinite ? startSeconds : 0
        return min(duration, max(0, start))
    }

    public func end(in sourceDuration: TimeInterval) -> TimeInterval {
        let duration = sanitizedDuration(sourceDuration)
        let start = start(in: duration)
        let end = endSeconds.flatMap { $0.isFinite ? $0 : nil } ?? duration
        return min(duration, max(start, end))
    }

    public func duration(in sourceDuration: TimeInterval) -> TimeInterval {
        max(0, end(in: sourceDuration) - start(in: sourceDuration))
    }

    public func displayElapsed(forRawElapsed rawElapsed: TimeInterval, sourceDuration: TimeInterval) -> TimeInterval {
        let duration = sanitizedDuration(sourceDuration)
        let start = start(in: duration)
        let end = end(in: duration)
        let raw = rawElapsed.isFinite ? rawElapsed : 0
        let clampedRaw = min(end, max(start, raw))
        return max(0, clampedRaw - start)
    }

    public func isActive(for sourceDuration: TimeInterval) -> Bool {
        let duration = sanitizedDuration(sourceDuration)
        guard duration > 0 else { return false }
        return start(in: duration) > 0.000_5 || end(in: duration) < duration - 0.000_5
    }

    private func sanitizedDuration(_ sourceDuration: TimeInterval) -> TimeInterval {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return 0 }
        return sourceDuration
    }
}
