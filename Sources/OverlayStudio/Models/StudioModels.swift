import Foundation
import OverlayCore

enum SyncMode: String, CaseIterable, Identifiable {
    case offset
    case fitStart
    case syncPoint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .offset:
            return "Offset"
        case .fitStart:
            return "FIT start"
        case .syncPoint:
            return "Sync point"
        }
    }
}

struct OutputResolutionPreset: Identifiable, Hashable {
    static let sourceID = "source"
    static let customID = "custom"

    let id: String
    let title: String
    let width: Int
    let height: Int

    static let fixed: [OutputResolutionPreset] = [
        OutputResolutionPreset(id: "uhd-4k", title: "4K UHD 3840x2160", width: 3840, height: 2160),
        OutputResolutionPreset(id: "qhd-1440", title: "QHD 2560x1440", width: 2560, height: 1440),
        OutputResolutionPreset(id: "fhd-1080", title: "FHD 1920x1080", width: 1920, height: 1080),
        OutputResolutionPreset(id: "hd-720", title: "HD 1280x720", width: 1280, height: 720),
        OutputResolutionPreset(id: "vertical-4k", title: "Vertical 2160x3840", width: 2160, height: 3840),
        OutputResolutionPreset(id: "vertical-1080", title: "Vertical 1080x1920", width: 1080, height: 1920),
        OutputResolutionPreset(id: "vertical-720", title: "Vertical 720x1280", width: 720, height: 1280)
    ]
}

struct OutputFrameRatePreset: Identifiable, Hashable {
    static let sourceID = "source"
    static let customID = "custom"

    let id: String
    let title: String
    let framesPerSecond: Double

    static let fixed: [OutputFrameRatePreset] = [
        OutputFrameRatePreset(id: "fps-23976", title: "23.976 fps", framesPerSecond: 23.976),
        OutputFrameRatePreset(id: "fps-24", title: "24 fps", framesPerSecond: 24),
        OutputFrameRatePreset(id: "fps-25", title: "25 fps", framesPerSecond: 25),
        OutputFrameRatePreset(id: "fps-2997", title: "29.97 fps", framesPerSecond: 29.97),
        OutputFrameRatePreset(id: "fps-30", title: "30 fps", framesPerSecond: 30),
        OutputFrameRatePreset(id: "fps-50", title: "50 fps", framesPerSecond: 50),
        OutputFrameRatePreset(id: "fps-5994", title: "59.94 fps", framesPerSecond: 59.94),
        OutputFrameRatePreset(id: "fps-60", title: "60 fps", framesPerSecond: 60)
    ]
}

struct ComponentBaseSize {
    static func size(for id: OverlayComponentID) -> CGSize {
        switch id {
        case .speed:
            return CGSize(width: 420, height: 238)
        case .pace, .heartRate, .cadence, .distance:
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
