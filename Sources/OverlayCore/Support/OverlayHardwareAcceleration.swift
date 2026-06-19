import CoreMedia
import CoreImage
import CoreVideo
import Foundation
import Metal
import VideoToolbox

public struct OverlayHardwareEncoder: Equatable, Sendable {
    public let codec: OverlayVideoCodec
    public let encoderID: String?
    public let displayName: String?
    public let gpuRegistryID: UInt64?
    public let performanceRating: Double?
    public let qualityRating: Double?

    public init(
        codec: OverlayVideoCodec,
        encoderID: String?,
        displayName: String?,
        gpuRegistryID: UInt64?,
        performanceRating: Double?,
        qualityRating: Double?
    ) {
        self.codec = codec
        self.encoderID = encoderID
        self.displayName = displayName
        self.gpuRegistryID = gpuRegistryID
        self.performanceRating = performanceRating
        self.qualityRating = qualityRating
    }
}

public struct OverlayHardwareProfile: Equatable, Sendable {
    public let isAppleSiliconProcess: Bool
    public let metalDeviceName: String?
    public let highestSupportedAppleGPUFamily: Int?
    public let hardwareEncoders: [OverlayVideoCodec: OverlayHardwareEncoder]

    public init(
        isAppleSiliconProcess: Bool,
        metalDeviceName: String?,
        highestSupportedAppleGPUFamily: Int?,
        hardwareEncoders: [OverlayVideoCodec: OverlayHardwareEncoder] = [:]
    ) {
        self.isAppleSiliconProcess = isAppleSiliconProcess
        self.metalDeviceName = metalDeviceName
        self.highestSupportedAppleGPUFamily = highestSupportedAppleGPUFamily
        self.hardwareEncoders = hardwareEncoders
    }

    public static var current: OverlayHardwareProfile {
        detect()
    }

    public var canUseMetalRendering: Bool {
        isAppleSiliconProcess && metalDeviceName != nil
    }

    public var canRequestHardwareVideoEncoding: Bool {
        isAppleSiliconProcess && !hardwareEncoders.isEmpty
    }

    public func hardwareEncoder(for codec: OverlayVideoCodec) -> OverlayHardwareEncoder? {
        hardwareEncoders[codec]
    }

    public func canUseHardwareEncoder(for codec: OverlayVideoCodec) -> Bool {
        hardwareEncoder(for: codec) != nil
    }

    public var preferredPreviewBufferCount: Int {
        guard let highestSupportedAppleGPUFamily else { return 2 }
        return highestSupportedAppleGPUFamily >= 8 ? 4 : 3
    }

    public var displaySummary: String {
        var parts = [isAppleSiliconProcess ? "Apple Silicon arm64" : "unsupported CPU"]
        if let metalDeviceName {
            parts.append("Metal: \(metalDeviceName)")
        } else {
            parts.append("Metal unavailable")
        }
        if let highestSupportedAppleGPUFamily {
            parts.append("Apple GPU family \(highestSupportedAppleGPUFamily)")
        }
        if hardwareEncoders.isEmpty {
            parts.append("no matching hardware video encoders")
        } else {
            let codecs = hardwareEncoders.keys
                .sorted { $0.rawValue < $1.rawValue }
                .map(\.displayName)
                .joined(separator: ", ")
            parts.append("hardware encoders: \(codecs)")
        }
        return parts.joined(separator: ", ")
    }

    private static func detect() -> OverlayHardwareProfile {
        #if arch(arm64)
        let isAppleSiliconProcess = true
        #else
        let isAppleSiliconProcess = false
        #endif

        let device = MTLCreateSystemDefaultDevice()
        return OverlayHardwareProfile(
            isAppleSiliconProcess: isAppleSiliconProcess,
            metalDeviceName: device?.name,
            highestSupportedAppleGPUFamily: highestSupportedAppleGPUFamily(device),
            hardwareEncoders: detectHardwareEncoders()
        )
    }

    private static func highestSupportedAppleGPUFamily(_ device: MTLDevice?) -> Int? {
        guard let device else { return nil }
        for family in stride(from: 10, through: 7, by: -1) {
            guard let gpuFamily = MTLGPUFamily(rawValue: 1000 + family) else {
                continue
            }
            if device.supportsFamily(gpuFamily) {
                return family
            }
        }
        return nil
    }

    private static func detectHardwareEncoders() -> [OverlayVideoCodec: OverlayHardwareEncoder] {
        var encoderList: CFArray?
        guard VTCopyVideoEncoderList(nil, &encoderList) == noErr,
              let encoders = encoderList as? [[String: Any]] else {
            return [:]
        }

        var bestEncoders: [OverlayVideoCodec: OverlayHardwareEncoder] = [:]
        for entry in encoders {
            guard let codecNumber = entry[kVTVideoEncoderList_CodecType as String] as? NSNumber,
                  let codec = overlayCodec(for: CMVideoCodecType(codecNumber.uint32Value)),
                  (entry[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) == true else {
                continue
            }

            let encoder = OverlayHardwareEncoder(
                codec: codec,
                encoderID: entry[kVTVideoEncoderList_EncoderID as String] as? String,
                displayName: entry[kVTVideoEncoderList_DisplayName as String] as? String,
                gpuRegistryID: (entry[kVTVideoEncoderList_GPURegistryID as String] as? NSNumber)?.uint64Value,
                performanceRating: (entry[kVTVideoEncoderList_PerformanceRating as String] as? NSNumber)?.doubleValue,
                qualityRating: (entry[kVTVideoEncoderList_QualityRating as String] as? NSNumber)?.doubleValue
            )

            if let existing = bestEncoders[codec] {
                bestEncoders[codec] = bestHardwareEncoder(existing, encoder)
            } else {
                bestEncoders[codec] = encoder
            }
        }

        return bestEncoders
    }

    private static func overlayCodec(for codecType: CMVideoCodecType) -> OverlayVideoCodec? {
        switch codecType {
        case kCMVideoCodecType_HEVCWithAlpha:
            return .hevcAlpha
        case kCMVideoCodecType_AppleProRes4444:
            return .proRes4444
        default:
            return nil
        }
    }

    private static func bestHardwareEncoder(
        _ first: OverlayHardwareEncoder,
        _ second: OverlayHardwareEncoder
    ) -> OverlayHardwareEncoder {
        let firstPerformance = first.performanceRating ?? -.infinity
        let secondPerformance = second.performanceRating ?? -.infinity
        if firstPerformance != secondPerformance {
            return firstPerformance > secondPerformance ? first : second
        }

        let firstQuality = first.qualityRating ?? -.infinity
        let secondQuality = second.qualityRating ?? -.infinity
        if firstQuality != secondQuality {
            return firstQuality > secondQuality ? first : second
        }

        return first
    }
}

enum OverlayCIContextFactory {
    static func makeContext(profile: OverlayHardwareProfile = .current) -> CIContext {
        let options: [CIContextOption: Any] = [
            .cacheIntermediates: true,
            .priorityRequestLow: false
        ]

        if profile.canUseMetalRendering,
           let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }

        return CIContext(options: options)
    }
}

enum OverlayPixelBufferAttributes {
    static func canvas(width: Int, height: Int) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
    }
}
