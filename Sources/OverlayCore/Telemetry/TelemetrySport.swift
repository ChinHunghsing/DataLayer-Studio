import Foundation

/// A parsed activity file's telemetry plus its file-level metadata. `sport` is kept out of
/// `TelemetrySeries` on purpose: the series is a value type copied into every detached preview
/// render, and growing it perturbs a latent render-pipeline data race (see
/// `docs/qa-0.2.3-transparent-and-longform.md`). File metadata rides alongside instead.
public struct ParsedActivity: Equatable {
    public var series: TelemetrySeries
    public var sport: TelemetrySport?

    public init(series: TelemetrySeries, sport: TelemetrySport? = nil) {
        self.series = series
        self.sport = sport
    }
}

/// Activity sport category extracted from FIT session metadata or the GPX track type text.
public enum TelemetrySport: String, Equatable, CaseIterable {
    case running
    case cycling
    case swimming
    case walking
    case hiking
    case rowing
    case skiing
    case snowboarding
    case paddling
    case training
    case generic

    /// FIT profile `sport` enum values (session message field 5).
    public init(fitSportCode: Int) {
        switch fitSportCode {
        case 1:
            self = .running
        case 2:
            self = .cycling
        case 4, 10:
            self = .training
        case 5:
            self = .swimming
        case 11:
            self = .walking
        case 12, 13:
            self = .skiing
        case 14:
            self = .snowboarding
        case 15:
            self = .rowing
        case 16, 17:
            self = .hiking
        case 19:
            self = .paddling
        default:
            self = .generic
        }
    }

    /// Best-effort match for the free-text `<type>` element on a GPX track.
    public init?(gpxTypeText: String) {
        let text = gpxTypeText.lowercased()
        guard !text.isEmpty else { return nil }
        if text.contains("run") || text.contains("jog") {
            self = .running
        } else if text.contains("cycl") || text.contains("bik") || text.contains("ride") {
            self = .cycling
        } else if text.contains("swim") {
            self = .swimming
        } else if text.contains("hik") || text.contains("mountain") {
            self = .hiking
        } else if text.contains("walk") {
            self = .walking
        } else if text.contains("row") {
            self = .rowing
        } else if text.contains("snowboard") {
            self = .snowboarding
        } else if text.contains("ski") {
            self = .skiing
        } else if text.contains("paddle") || text.contains("kayak") || text.contains("canoe") {
            self = .paddling
        } else {
            self = .generic
        }
    }
}
