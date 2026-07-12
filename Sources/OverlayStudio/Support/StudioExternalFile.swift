import Foundation

enum StudioEntryRequestResult: Equatable {
    case accepted
    case cancelled
    case failed(String)
}

enum StudioExternalFileKind: Equatable {
    case timelineProject
    case layoutPreset
    case legacyJSON
    case video
    case activity
    case unsupported

    static func classify(_ url: URL) -> StudioExternalFileKind {
        if TimelineProjectFileType.matches(url) {
            return .timelineProject
        }
        if LayoutPresetFileType.matches(url) {
            return .layoutPreset
        }

        switch url.pathExtension.lowercased() {
        case "json":
            return .legacyJSON
        case "fit", "gpx":
            return .activity
        case "mov", "mp4", "m4v", "mpeg", "mpg", "avi":
            return .video
        default:
            return .unsupported
        }
    }
}
