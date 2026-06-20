import Foundation
import OverlayCore

struct CommandLineOptions {
    var videoURL: URL
    var fitURL: URL
    var outputURL: URL
    var width: Int?
    var height: Int?
    var framesPerSecond: Double?
    var timeSync: TelemetryTimeSync
    var averageBitRate: Int
    var codec: OverlayVideoCodec
    var distanceUnit: OverlayDistanceUnit
    var layoutPresetReference: String?
    var validateFITCRC: Bool
    var inspectOnly: Bool

    static func parse(arguments: [String]) throws -> CommandLineOptions {
        var values: [String: String] = [:]
        var flags = Set<String>()
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "-h", "--help":
                throw CLIError.helpRequested
            case "--skip-fit-crc", "--inspect":
                flags.insert(argument)
                index += 1
            case "--video", "--fit", "--output", "--width", "--height", "--fps", "--offset", "--fit-start", "--sync-video", "--sync-fit", "--bitrate", "--bitrate-bps", "--codec", "--distance-unit", "--layout-preset":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                values[argument] = arguments[index + 1]
                index += 2
            default:
                throw CLIError.unknownArgument(argument)
            }
        }

        guard let video = values["--video"] else { throw CLIError.missingRequired("--video") }
        guard let fit = values["--fit"] else { throw CLIError.missingRequired("--fit") }
        guard let output = values["--output"] else { throw CLIError.missingRequired("--output") }

        return CommandLineOptions(
            videoURL: URL(fileURLWithPath: video),
            fitURL: URL(fileURLWithPath: fit),
            outputURL: URL(fileURLWithPath: output),
            width: try optionalInt(values["--width"], name: "--width", minimum: 2, maximum: 16_384, requireEven: true),
            height: try optionalInt(values["--height"], name: "--height", minimum: 2, maximum: 16_384, requireEven: true),
            framesPerSecond: try optionalDouble(values["--fps"], name: "--fps", minimum: 1),
            timeSync: try parseTimeSync(values: values),
            averageBitRate: try parseAverageBitRate(values: values),
            codec: try parseCodec(values["--codec"]),
            distanceUnit: try parseDistanceUnit(values["--distance-unit"]),
            layoutPresetReference: values["--layout-preset"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            validateFITCRC: !flags.contains("--skip-fit-crc"),
            inspectOnly: flags.contains("--inspect")
        )
    }

    private static func optionalInt(
        _ raw: String?,
        name: String,
        minimum: Int,
        maximum: Int? = nil,
        requireEven: Bool = false
    ) throws -> Int? {
        guard let raw else { return nil }
        guard let value = Int(raw),
              value >= minimum,
              maximum.map({ value <= $0 }) ?? true,
              !requireEven || value % 2 == 0 else {
            throw CLIError.invalidValue(name, raw)
        }
        return value
    }

    private static func parseAverageBitRate(values: [String: String]) throws -> Int {
        if values["--bitrate"] != nil, values["--bitrate-bps"] != nil {
            throw CLIError.conflictingArguments("--bitrate cannot be combined with --bitrate-bps")
        }

        if let rawBPS = values["--bitrate-bps"] {
            return try parsePositiveInt(rawBPS, name: "--bitrate-bps")
        }

        guard let rawKBPS = values["--bitrate"] else {
            return 12_000_000
        }

        let value = try parsePositiveInt(rawKBPS, name: "--bitrate")
        if value > 1_000_000 {
            return value
        }
        return value * 1000
    }

    private static func parsePositiveInt(_ raw: String, name: String) throws -> Int {
        guard let value = Int(raw), value > 0 else { throw CLIError.invalidValue(name, raw) }
        return value
    }

    private static func parseTimeSync(values: [String: String]) throws -> TelemetryTimeSync {
        let hasOffset = values["--offset"] != nil
        let hasFitStart = values["--fit-start"] != nil
        let hasSyncVideo = values["--sync-video"] != nil
        let hasSyncFit = values["--sync-fit"] != nil

        if hasOffset, hasFitStart || hasSyncVideo || hasSyncFit {
            throw CLIError.conflictingArguments("--offset cannot be combined with --fit-start, --sync-video, or --sync-fit")
        }
        if hasFitStart, hasSyncVideo || hasSyncFit {
            throw CLIError.conflictingArguments("--fit-start cannot be combined with --sync-video or --sync-fit")
        }

        if hasSyncVideo || hasSyncFit {
            guard let video = values["--sync-video"] else { throw CLIError.missingRequired("--sync-video") }
            guard let fit = values["--sync-fit"] else { throw CLIError.missingRequired("--sync-fit") }
            return TelemetryTimeSync(
                videoSyncTime: try parseDouble(video, name: "--sync-video", allowNegative: false),
                fitSyncTime: try parseDouble(fit, name: "--sync-fit", allowNegative: false)
            )
        }

        if let fitStart = values["--fit-start"] {
            return TelemetryTimeSync(
                videoSyncTime: 0,
                fitSyncTime: try parseDouble(fitStart, name: "--fit-start", allowNegative: false)
            )
        }

        if let offset = values["--offset"] {
            return .legacyOffset(try parseDouble(offset, name: "--offset", allowNegative: true))
        }

        return .identity
    }

    private static func optionalDouble(_ raw: String?, name: String, minimum: Double) throws -> Double? {
        guard let raw else { return nil }
        let value = try parseDouble(raw, name: name, allowNegative: false)
        guard value >= minimum else { throw CLIError.invalidValue(name, raw) }
        return value
    }

    private static func parseDouble(_ raw: String, name: String, allowNegative: Bool) throws -> Double {
        guard let value = Double(raw), value.isFinite, allowNegative || value >= 0 else {
            throw CLIError.invalidValue(name, raw)
        }
        return value
    }

    private static func parseCodec(_ raw: String?) throws -> OverlayVideoCodec {
        guard let raw else { return .hevcAlpha }
        guard let codec = OverlayVideoCodec(rawValue: raw) else {
            throw CLIError.invalidValue("--codec", raw)
        }
        return codec
    }

    private static func parseDistanceUnit(_ raw: String?) throws -> OverlayDistanceUnit {
        guard let raw else { return .kilometers }
        guard let unit = OverlayDistanceUnit(rawValue: raw) else {
            throw CLIError.invalidValue("--distance-unit", raw)
        }
        return unit
    }
}

enum CLIError: Error, CustomStringConvertible {
    case helpRequested
    case missingValue(String)
    case missingRequired(String)
    case invalidValue(String, String)
    case invalidOutputDimensions(Int, Int)
    case layoutPresetNotFound(String)
    case layoutPresetFileUnreadable(String, String)
    case layoutPresetFileInvalid(String)
    case conflictingArguments(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .helpRequested:
            return Self.help
        case let .missingValue(name):
            return "Missing value for \(name).\n\n\(Self.help)"
        case let .missingRequired(name):
            return "Missing required argument \(name).\n\n\(Self.help)"
        case let .invalidValue(name, value):
            return "Invalid value for \(name): \(value).\n\n\(Self.help)"
        case let .invalidOutputDimensions(width, height):
            return "Invalid output dimensions: \(width)x\(height). Width and height must be 2...16384 and even pixel values."
        case let .layoutPresetNotFound(reference):
            return "Layout preset not found: \(reference).\n\n\(Self.help)"
        case let .layoutPresetFileUnreadable(path, reason):
            return "Could not read layout preset file \(path): \(reason).\n\n\(Self.help)"
        case let .layoutPresetFileInvalid(path):
            return "Layout preset file does not contain any usable preset: \(path).\n\n\(Self.help)"
        case let .conflictingArguments(message):
            return "\(message).\n\n\(Self.help)"
        case let .unknownArgument(argument):
            return "Unknown argument \(argument).\n\n\(Self.help)"
        }
    }

    static let help = """
    Usage:
      overlay --video run.mov --fit activity.fit --output overlay.mov [options]

    Required:
      --video PATH       Source video. Used for duration, resolution, and frame rate.
      --fit PATH         Standard .FIT activity file.
      --output PATH      Output .mov file encoded as HEVC/H.265 with alpha.

    Options:
      --width PX         Override output width, 2...16384 and even. Defaults to source video width.
      --height PX        Override output height, 2...16384 and even. Defaults to source video height.
      --fps N            Override output frame rate, minimum 1. Defaults to source video frame rate.
      --fit-start SEC    FIT elapsed time at video 0. Use when recording starts mid-activity.
      --sync-video SEC   Video timestamp for a sync point. Requires --sync-fit.
      --sync-fit SEC     FIT elapsed timestamp for the same sync point. Requires --sync-video.
      --offset SEC       Legacy shorthand: video starts SEC seconds before FIT. Negative starts mid-FIT.
      --bitrate KBPS     Average HEVC bitrate in kbps. Default: 12000.
                         Existing values above 1000000 are accepted as legacy bps.
      --bitrate-bps BPS  Legacy explicit bps bitrate.
      --codec NAME       hevc-alpha (default) or prores-4444.
      --distance-unit U  Distance unit for overlay labels: km (default) or m.
      --layout-preset P  Use a saved GUI layout preset by name/ID, or a GUI-exported JSON file.
      --skip-fit-crc     Parse FIT even if CRC validation fails.
      --inspect          Parse video and FIT, print metadata, do not render.
      -h, --help         Show this help.
    """
}

struct ResolvedOverlayLayout {
    var layout: OverlayLayout
    var presetName: String?
}

func resolveOverlayLayout(
    presetReference: String?,
    loadPresetState: () -> LayoutPresetState = { LayoutPresetStore.loadSharedAppState() }
) throws -> ResolvedOverlayLayout {
    guard let presetReference else {
        return ResolvedOverlayLayout(layout: .default, presetName: nil)
    }
    let trimmedReference = presetReference.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedReference.isEmpty else {
        throw CLIError.invalidValue("--layout-preset", presetReference)
    }

    let fileURL = URL(fileURLWithPath: trimmedReference)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
        return try resolveOverlayLayout(fromPresetFile: fileURL)
    }

    let state = loadPresetState()
    guard let preset = state.preset(matching: trimmedReference) else {
        throw CLIError.layoutPresetNotFound(trimmedReference)
    }

    return ResolvedOverlayLayout(layout: preset.layout.sanitized, presetName: preset.name)
}

private func resolveOverlayLayout(fromPresetFile fileURL: URL) throws -> ResolvedOverlayLayout {
    let data: Data
    do {
        data = try Data(contentsOf: fileURL)
    } catch {
        throw CLIError.layoutPresetFileUnreadable(fileURL.path, error.localizedDescription)
    }

    let decoder = JSONDecoder()
    if let state = try? decoder.decode(LayoutPresetState.self, from: data) {
        let sanitizedState = state.sanitized
        if let defaultPresetID = sanitizedState.defaultPresetID,
           let defaultPreset = sanitizedState.presets.first(where: { $0.id == defaultPresetID }) {
            return ResolvedOverlayLayout(layout: defaultPreset.layout.sanitized, presetName: defaultPreset.name)
        }
        if let preset = sanitizedState.presets.first {
            return ResolvedOverlayLayout(layout: preset.layout.sanitized, presetName: preset.name)
        }
        throw CLIError.layoutPresetFileInvalid(fileURL.path)
    }

    if let preset = try? decoder.decode(LayoutPreset.self, from: data) {
        let sanitizedState = LayoutPresetState(presets: [preset], defaultPresetID: preset.id).sanitized
        guard let sanitizedPreset = sanitizedState.presets.first else {
            throw CLIError.layoutPresetFileInvalid(fileURL.path)
        }
        return ResolvedOverlayLayout(layout: sanitizedPreset.layout.sanitized, presetName: sanitizedPreset.name)
    }

    throw CLIError.layoutPresetFileInvalid(fileURL.path)
}

func run() async throws {
    let options = try CommandLineOptions.parse(arguments: CommandLine.arguments)
    let parser = FITParser(validateCRC: options.validateFITCRC)
    let series = try parser.parse(url: options.fitURL)
    let metadata = try await VideoMetadata.loadAsync(from: options.videoURL)
    let resolvedLayout = try resolveOverlayLayout(presetReference: options.layoutPresetReference)

    let width = options.width ?? Int(metadata.size.width.rounded())
    let height = options.height ?? Int(metadata.size.height.rounded())
    let fps = options.framesPerSecond ?? metadata.framesPerSecond
    let duration = metadata.duration

    print("Video: \(width)x\(height), \(String(format: "%.3f", fps)) fps, \(String(format: "%.2f", duration)) s")
    print("FIT: \(series.samples.count) samples, \(String(format: "%.2f", series.duration)) s telemetry")
    print("Codec: \(options.codec.rawValue)")
    print("Bitrate: \(options.averageBitRate / 1000) kbps")
    print("Distance unit: \(options.distanceUnit.rawValue)")
    if let presetName = resolvedLayout.presetName {
        print("Layout preset: \(presetName)")
    } else {
        print("Layout: built-in default")
    }
    print("Hardware: \(OverlayHardwareProfile.current.displaySummary)")
    printSyncSummary(timeSync: options.timeSync, videoDuration: duration, fitDuration: series.duration)

    if options.inspectOnly {
        return
    }
    try validateOutputDimensions(width: width, height: height)

    let writer = TransparentVideoWriter(
        outputURL: options.outputURL,
        series: series,
        config: TransparentVideoWriterConfig(
            width: width,
            height: height,
            framesPerSecond: fps,
            duration: duration,
            averageBitRate: options.averageBitRate,
            timeSync: options.timeSync,
            codec: options.codec,
            overlayLayout: resolvedLayout.layout,
            distanceUnit: options.distanceUnit,
            progressHandler: { completed, total in
                let percent = Double(completed) / Double(total) * 100
                print(String(format: "Rendered %d/%d frames (%.0f%%)", completed, total, percent))
            }
        )
    )
    try writer.write()
    print("Wrote \(options.outputURL.path)")
}

func validateOutputDimensions(width: Int, height: Int) throws {
    guard width >= 2, width <= 16_384,
          height >= 2, height <= 16_384,
          width % 2 == 0, height % 2 == 0 else {
        throw CLIError.invalidOutputDimensions(width, height)
    }
}

func printSyncSummary(timeSync: TelemetryTimeSync, videoDuration: TimeInterval, fitDuration: TimeInterval) {
    let fitAtVideoStart = timeSync.fitElapsed(forVideoTime: 0)
    let fitAtVideoEnd = timeSync.fitElapsed(forVideoTime: videoDuration)
    print(
        "Sync: \(timeSync.description); video 0.000s -> FIT \(TelemetryTimeSync.format(fitAtVideoStart))s, video end -> FIT \(TelemetryTimeSync.format(fitAtVideoEnd))s"
    )

    if timeSync.fitOffsetFromVideoStart < 0 {
        print("Sync note: video begins before FIT telemetry; first sample is held until FIT time reaches 0.")
    }
    if fitAtVideoEnd > fitDuration {
        print("Sync note: video extends beyond FIT telemetry; last sample is held after FIT \(TelemetryTimeSync.format(fitDuration))s.")
    }
}

@main
struct OverlayCLI {
    static func main() async {
        do {
            try await run()
        } catch let error as CLIError {
            print(error.description)
            if case .helpRequested = error {
                exit(0)
            }
            exit(2)
        } catch let error as FITError {
            fputs("FIT error: \(error.description)\n", stderr)
            exit(1)
        } catch let error as OverlayVideoError {
            fputs("Video error: \(error.description)\n", stderr)
            exit(1)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
