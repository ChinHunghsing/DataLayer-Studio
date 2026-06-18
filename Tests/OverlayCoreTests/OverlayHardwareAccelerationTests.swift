import AVFoundation
import CoreMedia
import CoreVideo
@testable import OverlayCore
import VideoToolbox
import XCTest

final class OverlayHardwareAccelerationTests: XCTestCase {
    func testCurrentHardwareProfileRequiresAppleSiliconProcess() {
        #if arch(arm64)
        XCTAssertTrue(OverlayHardwareProfile.current.isAppleSiliconProcess)
        #else
        XCTAssertFalse(OverlayHardwareProfile.current.isAppleSiliconProcess)
        #endif
    }

    func testPixelBufferAttributesAreMetalShareable() {
        let attributes = OverlayPixelBufferAttributes.canvas(width: 1920, height: 1080)

        XCTAssertEqual(attributes[kCVPixelBufferPixelFormatTypeKey as String] as? OSType, kCVPixelFormatType_32BGRA)
        XCTAssertEqual(attributes[kCVPixelBufferMetalCompatibilityKey as String] as? Bool, true)
        XCTAssertNotNil(attributes[kCVPixelBufferIOSurfacePropertiesKey as String])
    }

    func testVideoOutputSettingsPreferHardwareEncoderOnAppleSilicon() {
        let profile = OverlayHardwareProfile(
            isAppleSiliconProcess: true,
            metalDeviceName: "Apple M-Series",
            highestSupportedAppleGPUFamily: 8,
            hardwareEncoders: [
                .hevcAlpha: OverlayHardwareEncoder(
                    codec: .hevcAlpha,
                    encoderID: "test.hevc.alpha",
                    displayName: "Test HEVC Alpha",
                    gpuRegistryID: 123,
                    performanceRating: 100,
                    qualityRating: 90
                )
            ]
        )

        let settings = TransparentVideoWriter.videoOutputSettings(
            width: 1920,
            height: 1080,
            codec: .hevcAlpha,
            averageBitRate: 12_000_000,
            encoderFrameRate: 30,
            hardwareProfile: profile
        )

        let encoderSpecification = settings[AVVideoEncoderSpecificationKey] as? [String: Any]
        XCTAssertEqual(
            encoderSpecification?[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String] as? Bool,
            true
        )
        XCTAssertEqual(
            (encoderSpecification?[kVTVideoEncoderSpecification_PreferredEncoderGPURegistryID as String] as? NSNumber)?.uint64Value,
            123
        )
        XCTAssertEqual(encoderSpecification?[kVTVideoEncoderSpecification_EncoderID as String] as? String, "test.hevc.alpha")
    }

    func testVideoOutputSettingsAllowsHardwareFallbackWhenSpecificEncoderIsUnknown() {
        let profile = OverlayHardwareProfile(
            isAppleSiliconProcess: true,
            metalDeviceName: "Apple M-Series",
            highestSupportedAppleGPUFamily: 8
        )

        let settings = TransparentVideoWriter.videoOutputSettings(
            width: 1920,
            height: 1080,
            codec: .hevcAlpha,
            averageBitRate: 12_000_000,
            encoderFrameRate: 30,
            hardwareProfile: profile
        )

        let encoderSpecification = settings[AVVideoEncoderSpecificationKey] as? [String: Any]
        XCTAssertEqual(
            encoderSpecification?[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String] as? Bool,
            true
        )
        XCTAssertNil(encoderSpecification?[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String])
    }

    func testCurrentProfileDetectsHardwareHEVCAlphaWhenVideoToolboxListsIt() throws {
        guard videoToolboxListsHardwareEncoder(for: kCMVideoCodecType_HEVCWithAlpha) else {
            throw XCTSkip("This Mac does not list a hardware HEVC-with-alpha encoder.")
        }

        XCTAssertTrue(OverlayHardwareProfile.current.canUseHardwareEncoder(for: .hevcAlpha))
    }

    private func videoToolboxListsHardwareEncoder(for codecType: CMVideoCodecType) -> Bool {
        var encoderList: CFArray?
        guard VTCopyVideoEncoderList(nil, &encoderList) == noErr,
              let encoders = encoderList as? [[String: Any]] else {
            return false
        }

        return encoders.contains { entry in
            guard let codecNumber = entry[kVTVideoEncoderList_CodecType as String] as? NSNumber else {
                return false
            }
            return CMVideoCodecType(codecNumber.uint32Value) == codecType
                && (entry[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) == true
        }
    }
}
