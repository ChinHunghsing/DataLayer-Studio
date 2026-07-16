import Foundation
import OverlayCore

enum DebugLogCategory: String, CaseIterable, Identifiable {
    case input
    case weather
    case preview
    case export
    case status

    var id: String { rawValue }

    var titleKey: String {
        "debug.category.\(rawValue)"
    }
}

struct DebugLogEntry: Identifiable, Equatable {
    let id = UUID()
    var date: Date
    var category: DebugLogCategory
    var message: String
}

struct StudioToast: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case info
        case warning
    }

    let id = UUID()
    var message: String
    var kind: Kind
}

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

    static func isFreeTierResolution(width: Int, height: Int) -> Bool {
        (width == 1920 && height == 1080) || (width == 1080 && height == 1920)
    }
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

enum ExportPresetResolution: Codable, Equatable {
    case source
    case fixed(width: Int, height: Int)
}

enum ExportPresetFrameRate: Codable, Equatable {
    case source
    case fixed(Double)
}

struct ExportPreset: Codable, Equatable, Identifiable {
    static let builtInPrefix = "builtin."

    var id: String
    var name: String
    var resolution: ExportPresetResolution
    var frameRate: ExportPresetFrameRate
    var exportMode: OverlayExportMode
    var codec: OverlayVideoCodec
    var bitRateKbps: Int
    var renderScope: ExportRenderScope

    var isBuiltIn: Bool { id.hasPrefix(Self.builtInPrefix) }

    /// Built-in presets carry no free-form name: their display name always comes from the
    /// `exportPreset.builtin.*` localization table, so the two sources can't drift apart.
    var localizedNameKey: String? { isBuiltIn ? "exportPreset.\(id)" : nil }

    func displayName(localize: (String) -> String) -> String {
        localizedNameKey.map(localize) ?? name
    }

    static let builtIn: [ExportPreset] = [
        ExportPreset(
            id: "\(builtInPrefix)overlay-prores-4444",
            name: "",
            resolution: .source,
            frameRate: .source,
            exportMode: .overlay,
            codec: .proRes4444,
            bitRateKbps: 12_000,
            renderScope: .singleClip
        ),
        ExportPreset(
            id: "\(builtInPrefix)overlay-hevc-alpha",
            name: "",
            resolution: .source,
            frameRate: .source,
            exportMode: .overlay,
            codec: .hevcAlpha,
            bitRateKbps: 12_000,
            renderScope: .singleClip
        ),
        ExportPreset(
            id: "\(builtInPrefix)video-4k-hevc",
            name: "",
            resolution: .fixed(width: 3_840, height: 2_160),
            frameRate: .source,
            exportMode: .video,
            codec: .hevc,
            bitRateKbps: 40_000,
            renderScope: .singleClip
        ),
        ExportPreset(
            id: "\(builtInPrefix)video-1080p-h264",
            name: "",
            resolution: .fixed(width: 1_920, height: 1_080),
            frameRate: .source,
            exportMode: .video,
            codec: .h264,
            bitRateKbps: 12_000,
            renderScope: .singleClip
        ),
        ExportPreset(
            id: "\(builtInPrefix)video-vertical-4k-hevc",
            name: "",
            resolution: .fixed(width: 2_160, height: 3_840),
            frameRate: .source,
            exportMode: .video,
            codec: .hevc,
            bitRateKbps: 35_000,
            renderScope: .singleClip
        )
    ]
}

struct ComponentBaseSize {
    static func size(for id: OverlayComponentID) -> CGSize {
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
