import AudioToolbox
import AVFoundation
import CoreMedia
import CoreVideo
@testable import OverlayCore
import XCTest

final class TimelineVideoWriterTests: XCTestCase {
    func testSingleSourceTimelineOutputMatchesCompositedWriter() async throws {
        let sourceURL = temporaryMovieURL("timeline-source")
        let compositedURL = temporaryMovieURL("timeline-composited-output")
        let timelineURL = temporaryMovieURL("timeline-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(compositedURL)
            Self.removeTemporaryFile(timelineURL)
        }

        try makeTinySourceVideo(at: sourceURL) { _ in (0, 0, 0) }

        var element = OverlayElement.defaultElement(kind: .pace)
        element.frame = OverlayComponentFrame(x: 0.25, y: 0.4, scale: 1.6)
        element.customization.showsPanel = false
        element.customization.valueColor = OverlayColor(red: 1, green: 1, blue: 1)
        element.customization.labelColor = OverlayColor(red: 1, green: 1, blue: 1)
        let layout = OverlayLayout(elements: [element])
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3)
        ])

        let compositedWriter = CompositedVideoWriter(
            outputURL: compositedURL,
            sourceVideoURL: sourceURL,
            series: series,
            config: CompositedVideoWriterConfig(
                width: 128,
                height: 128,
                framesPerSecond: 2,
                duration: 0.5,
                averageBitRate: 400_000,
                codec: .h264,
                overlayLayout: layout
            )
        )
        let project = TimelineProject.migratingSingleSource(
            outputWidth: 128,
            outputHeight: 128,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            videoAsset: MediaAsset(
                id: "video",
                kind: .video,
                url: sourceURL,
                displayName: sourceURL.lastPathComponent,
                duration: 1,
                width: 64,
                height: 64,
                framesPerSecond: 2
            ),
            activityAsset: MediaAsset(
                id: "activity",
                kind: .activity,
                url: URL(fileURLWithPath: "/tmp/activity.fit"),
                displayName: "activity.fit",
                duration: 1
            ),
            sync: .identity,
            layout: layout
        )
        let timelineWriter = TimelineVideoWriter(
            outputURL: timelineURL,
            project: project,
            telemetrySeriesByAssetID: ["activity": series],
            config: TimelineVideoWriterConfig(
                width: 128,
                height: 128,
                framesPerSecond: 2,
                duration: 0.5,
                averageBitRate: 400_000,
                codec: .h264
            )
        )

        do {
            try compositedWriter.write()
            try timelineWriter.write()
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Timeline video test encoder is unavailable on this Mac: \(error.description)")
        }

        let compositedLuma = try await firstFrameLuma(from: compositedURL)
        let timelineLuma = try await firstFrameLuma(from: timelineURL)
        XCTAssertEqual(timelineLuma.max, compositedLuma.max, accuracy: 4)
        XCTAssertEqual(timelineLuma.mean, compositedLuma.mean, accuracy: 2)
    }

    func testTimelineWriterRejectsMissingTelemetrySeries() {
        let project = TimelineProject.migratingSingleSource(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            videoAsset: MediaAsset(
                id: "video",
                kind: .video,
                url: temporaryMovieURL("missing-series-video"),
                displayName: "video.mov",
                duration: 1
            ),
            activityAsset: MediaAsset(
                id: "activity",
                kind: .activity,
                url: URL(fileURLWithPath: "/tmp/activity.fit"),
                displayName: "activity.fit",
                duration: 1
            ),
            sync: .identity,
            layout: .default
        )
        let writer = TimelineVideoWriter(
            outputURL: temporaryMovieURL("missing-series-output"),
            project: project,
            telemetrySeriesByAssetID: [:],
            config: TimelineVideoWriterConfig(width: 64, height: 64, framesPerSecond: 2, duration: 1, codec: .h264)
        )

        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
        }
    }

    func testTimelineWriterRejectsProjectsWithoutVideoClip() {
        let project = TimelineProject.migratingSingleSource(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            videoAsset: nil,
            activityAsset: MediaAsset(
                id: "activity",
                kind: .activity,
                url: URL(fileURLWithPath: "/tmp/activity.fit"),
                displayName: "activity.fit",
                duration: 1
            ),
            sync: .identity,
            layout: .default
        )
        let writer = TimelineVideoWriter(
            outputURL: temporaryMovieURL("missing-video-output"),
            project: project,
            telemetrySeriesByAssetID: ["activity": TelemetrySeries(samples: [])],
            config: TimelineVideoWriterConfig(width: 64, height: 64, framesPerSecond: 2, duration: 1, codec: .h264)
        )

        XCTAssertThrowsError(try writer.write()) { error in
            guard case OverlayVideoError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
        }
    }

    func testTimelineWriterRendersTransparentOverlayMode() throws {
        guard OverlayHardwareProfile.current.canUseHardwareEncoder(for: .hevcAlpha) else {
            throw XCTSkip("HEVC alpha hardware encoder is unavailable on this Mac.")
        }

        let outputURL = temporaryMovieURL("timeline-transparent-output")
        defer { Self.removeTemporaryFile(outputURL) }

        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 3)
        ])
        let project = TimelineProject.migratingSingleSource(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            videoAsset: nil,
            activityAsset: MediaAsset(
                id: "activity",
                kind: .activity,
                url: URL(fileURLWithPath: "/tmp/activity.fit"),
                displayName: "activity.fit",
                duration: 1
            ),
            sync: .identity,
            layout: OverlayLayout(elements: [])
        )
        let writer = TimelineVideoWriter(
            outputURL: outputURL,
            project: project,
            telemetrySeriesByAssetID: ["activity": series],
            config: TimelineVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 0.5,
                averageBitRate: 200_000,
                codec: .hevcAlpha
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Timeline transparent test encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testTimelineWriterRendersMultipleTransparentOverlayClips() throws {
        let outputURL = temporaryMovieURL("timeline-multi-transparent-output")
        defer { Self.removeTemporaryFile(outputURL) }

        let firstSeries = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 1, distanceMeters: 3)
        ])
        let secondSeries = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 10),
            TelemetrySample(elapsed: 1, distanceMeters: 13)
        ])
        let project = TimelineProject(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            assets: [
                MediaAsset(
                    id: "activity-a",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity-a.fit"),
                    displayName: "activity-a.fit",
                    duration: 1
                ),
                MediaAsset(
                    id: "activity-b",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity-b.fit"),
                    displayName: "activity-b.fit",
                    duration: 1
                )
            ],
            tracks: [
                TimelineTrack(
                    id: "overlay-a",
                    kind: .overlay,
                    name: "O1",
                    clips: [
                        TimelineClip(
                            id: "clip-a",
                            assetID: "activity-a",
                            timelineStart: 0,
                            duration: 1,
                            layout: OverlayLayout(elements: [])
                        )
                    ]
                ),
                TimelineTrack(
                    id: "overlay-b",
                    kind: .overlay,
                    name: "O2",
                    clips: [
                        TimelineClip(
                            id: "clip-b",
                            assetID: "activity-b",
                            timelineStart: 0,
                            duration: 1,
                            layout: OverlayLayout(elements: [])
                        )
                    ]
                )
            ]
        )
        let writer = TimelineVideoWriter(
            outputURL: outputURL,
            project: project,
            telemetrySeriesByAssetID: [
                "activity-a": firstSeries,
                "activity-b": secondSeries
            ],
            config: TimelineVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 0.5,
                averageBitRate: 200_000,
                codec: .proRes4444
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Timeline multi-overlay test encoder is unavailable on this Mac: \(error.description)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testTimelineWriterRendersMultipleOverlayClipsOntoCompositedVideo() async throws {
        let sourceURL = temporaryMovieURL("timeline-multi-composited-source")
        let outputURL = temporaryMovieURL("timeline-multi-composited-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL) { _ in (0, 0, 0) }

        var element = OverlayElement.defaultElement(kind: .pace)
        element.frame = OverlayComponentFrame(x: 0.25, y: 0.4, scale: 1.6)
        element.customization.showsPanel = false
        element.customization.valueColor = OverlayColor(red: 1, green: 1, blue: 1)
        element.customization.labelColor = OverlayColor(red: 1, green: 1, blue: 1)
        let visibleLayout = OverlayLayout(elements: [element])

        let firstSeries = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3)
        ])
        let secondSeries = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 10, speedMetersPerSecond: 4),
            TelemetrySample(elapsed: 1, distanceMeters: 14, speedMetersPerSecond: 4)
        ])
        let project = TimelineProject(
            outputWidth: 128,
            outputHeight: 128,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            assets: [
                MediaAsset(
                    id: "video",
                    kind: .video,
                    url: sourceURL,
                    displayName: sourceURL.lastPathComponent,
                    duration: 1,
                    width: 64,
                    height: 64,
                    framesPerSecond: 2
                ),
                MediaAsset(
                    id: "activity-a",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity-a.fit"),
                    displayName: "activity-a.fit",
                    duration: 1
                ),
                MediaAsset(
                    id: "activity-b",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity-b.fit"),
                    displayName: "activity-b.fit",
                    duration: 1
                )
            ],
            tracks: [
                TimelineTrack(
                    id: "video-track",
                    kind: .video,
                    name: "V1",
                    clips: [TimelineClip(id: "video-clip", assetID: "video", timelineStart: 0, duration: 1)]
                ),
                TimelineTrack(
                    id: "overlay-a",
                    kind: .overlay,
                    name: "O1",
                    clips: [
                        TimelineClip(
                            id: "clip-a",
                            assetID: "activity-a",
                            timelineStart: 0,
                            duration: 1,
                            layout: OverlayLayout(elements: [])
                        )
                    ]
                ),
                TimelineTrack(
                    id: "overlay-b",
                    kind: .overlay,
                    name: "O2",
                    clips: [
                        TimelineClip(
                            id: "clip-b",
                            assetID: "activity-b",
                            timelineStart: 0,
                            duration: 1,
                            layout: visibleLayout
                        )
                    ]
                )
            ]
        )
        let writer = TimelineVideoWriter(
            outputURL: outputURL,
            project: project,
            telemetrySeriesByAssetID: [
                "activity-a": firstSeries,
                "activity-b": secondSeries
            ],
            config: TimelineVideoWriterConfig(
                width: 128,
                height: 128,
                framesPerSecond: 2,
                duration: 0.5,
                averageBitRate: 400_000,
                codec: .h264
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Timeline multi-composited test encoder is unavailable on this Mac: \(error.description)")
        }

        let luma = try await firstFrameLuma(from: outputURL)
        XCTAssertGreaterThan(luma.max, 120)
    }

    func testTimelineWriterUsesLastOverlappingClipWithinOneOverlayTrack() async throws {
        let sourceURL = temporaryMovieURL("timeline-overlap-source")
        let outputURL = temporaryMovieURL("timeline-overlap-output")
        defer {
            Self.removeTemporaryFile(sourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: sourceURL) { _ in (0, 0, 0) }

        var element = OverlayElement.defaultElement(kind: .pace)
        element.frame = OverlayComponentFrame(x: 0.25, y: 0.4, scale: 1.6)
        element.customization.showsPanel = false
        element.customization.valueColor = OverlayColor(red: 1, green: 1, blue: 1)
        element.customization.labelColor = OverlayColor(red: 1, green: 1, blue: 1)
        let visibleLayout = OverlayLayout(elements: [element])

        let firstSeries = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0, speedMetersPerSecond: 3),
            TelemetrySample(elapsed: 1, distanceMeters: 3, speedMetersPerSecond: 3)
        ])
        let secondSeries = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 10, speedMetersPerSecond: 4),
            TelemetrySample(elapsed: 1, distanceMeters: 14, speedMetersPerSecond: 4)
        ])
        let project = TimelineProject(
            outputWidth: 128,
            outputHeight: 128,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            assets: [
                MediaAsset(
                    id: "video",
                    kind: .video,
                    url: sourceURL,
                    displayName: sourceURL.lastPathComponent,
                    duration: 1,
                    width: 64,
                    height: 64,
                    framesPerSecond: 2
                ),
                MediaAsset(
                    id: "activity-visible",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity-visible.fit"),
                    displayName: "activity-visible.fit",
                    duration: 1
                ),
                MediaAsset(
                    id: "activity-empty",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity-empty.fit"),
                    displayName: "activity-empty.fit",
                    duration: 1
                )
            ],
            tracks: [
                TimelineTrack(
                    id: "video-track",
                    kind: .video,
                    name: "V1",
                    clips: [TimelineClip(id: "video-clip", assetID: "video", timelineStart: 0, duration: 1)]
                ),
                TimelineTrack(
                    id: "overlay-track",
                    kind: .overlay,
                    name: "O1",
                    clips: [
                        TimelineClip(
                            id: "visible-first",
                            assetID: "activity-visible",
                            timelineStart: 0,
                            duration: 1,
                            layout: visibleLayout
                        ),
                        TimelineClip(
                            id: "empty-last",
                            assetID: "activity-empty",
                            timelineStart: 0,
                            duration: 1,
                            layout: OverlayLayout(elements: [])
                        )
                    ]
                )
            ]
        )
        let writer = TimelineVideoWriter(
            outputURL: outputURL,
            project: project,
            telemetrySeriesByAssetID: [
                "activity-visible": firstSeries,
                "activity-empty": secondSeries
            ],
            config: TimelineVideoWriterConfig(
                width: 128,
                height: 128,
                framesPerSecond: 2,
                duration: 0.5,
                averageBitRate: 400_000,
                codec: .h264
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Timeline overlapping-overlay test encoder is unavailable on this Mac: \(error.description)")
        }

        let luma = try await firstFrameLuma(from: outputURL)
        XCTAssertLessThan(luma.max, 20)
    }

    func testTimelineWriterRendersSequentialVideoClipsIntoCompositedOutput() async throws {
        let firstSourceURL = temporaryMovieURL("timeline-first-video-source")
        let secondSourceURL = temporaryMovieURL("timeline-second-video-source")
        let outputURL = temporaryMovieURL("timeline-sequential-video-output")
        defer {
            Self.removeTemporaryFile(firstSourceURL)
            Self.removeTemporaryFile(secondSourceURL)
            Self.removeTemporaryFile(outputURL)
        }

        try makeTinySourceVideo(at: firstSourceURL, frameCount: 2, includeAudio: true) { _ in (220, 20, 20) }
        try makeTinySourceVideo(at: secondSourceURL, frameCount: 2, includeAudio: true) { _ in (20, 40, 220) }

        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 2, distanceMeters: 6)
        ])
        let project = TimelineProject(
            outputWidth: 64,
            outputHeight: 64,
            framesPerSecond: 2,
            distanceUnit: .kilometers,
            assets: [
                MediaAsset(
                    id: "video-a",
                    kind: .video,
                    url: firstSourceURL,
                    displayName: firstSourceURL.lastPathComponent,
                    duration: 1,
                    width: 64,
                    height: 64,
                    framesPerSecond: 2
                ),
                MediaAsset(
                    id: "video-b",
                    kind: .video,
                    url: secondSourceURL,
                    displayName: secondSourceURL.lastPathComponent,
                    duration: 1,
                    width: 64,
                    height: 64,
                    framesPerSecond: 2
                ),
                MediaAsset(
                    id: "activity",
                    kind: .activity,
                    url: URL(fileURLWithPath: "/tmp/activity.fit"),
                    displayName: "activity.fit",
                    duration: 2
                )
            ],
            tracks: [
                TimelineTrack(
                    id: "video-track",
                    kind: .video,
                    name: "V1",
                    clips: [
                        TimelineClip(id: "video-a-clip", assetID: "video-a", timelineStart: 0, duration: 1),
                        TimelineClip(id: "video-b-clip", assetID: "video-b", timelineStart: 1, duration: 1)
                    ]
                ),
                TimelineTrack(
                    id: "overlay-track",
                    kind: .overlay,
                    name: "O1",
                    clips: [
                        TimelineClip(
                            id: "overlay-clip",
                            assetID: "activity",
                            timelineStart: 0,
                            duration: 2,
                            layout: OverlayLayout(elements: [])
                        )
                    ]
                )
            ]
        )
        let writer = TimelineVideoWriter(
            outputURL: outputURL,
            project: project,
            telemetrySeriesByAssetID: ["activity": series],
            config: TimelineVideoWriterConfig(
                width: 64,
                height: 64,
                framesPerSecond: 2,
                duration: 2,
                averageBitRate: 400_000,
                codec: .h264
            )
        )

        do {
            try writer.write()
        } catch let error as OverlayVideoError where error.isUnavailableTimelineTestEncoder {
            throw XCTSkip("Timeline sequential-video test encoder is unavailable on this Mac: \(error.description)")
        }

        let firstFrame = try await frameMeanRGB(from: outputURL, at: 0.25)
        let secondFrame = try await frameMeanRGB(from: outputURL, at: 1.25)
        XCTAssertGreaterThan(firstFrame.red, firstFrame.blue + 80)
        XCTAssertGreaterThan(secondFrame.blue, secondFrame.red + 80)
        let audioTracks = try await AVURLAsset(url: outputURL).loadTracks(withMediaType: .audio)
        XCTAssertFalse(audioTracks.isEmpty)
    }

    private func temporaryMovieURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }

    private static func removeTemporaryFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func makeTinySourceVideo(
        at url: URL,
        frameCount: Int = 2,
        framesPerSecond: Int32 = 2,
        includeAudio: Bool = false,
        frameColor: (Int) -> (red: UInt8, green: UInt8, blue: UInt8) = { index in
            (UInt8(80 + index * 40), 120, 160)
        }
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 64
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(input) else {
            throw OverlayVideoError.unsupportedEncoder("Could not create tiny source video input.")
        }
        writer.add(input)

        let sampleRate = 44_100.0
        let totalDuration = Double(frameCount) / Double(framesPerSecond)
        var audioInput: AVAssetWriterInput?
        if includeAudio {
            let newInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            newInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(newInput) else {
                throw OverlayVideoError.unsupportedEncoder("Could not create tiny source audio input.")
            }
            writer.add(newInput)
            audioInput = newInput
        }

        guard writer.startWriting() else {
            throw OverlayVideoError.cannotStartWriter(writer.error?.localizedDescription ?? "Could not start tiny source writer.")
        }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            let color = frameColor(frameIndex)
            let buffer = try makePixelBuffer(red: color.red, green: color.green, blue: color.blue)
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append tiny source frame.")
            }
        }
        input.markAsFinished()

        if let audioInput {
            let sampleBuffer = try makeSilentAudioSampleBuffer(durationSeconds: totalDuration, sampleRate: sampleRate)
            while !audioInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard audioInput.append(sampleBuffer) else {
                throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Could not append tiny source audio.")
            }
            audioInput.markAsFinished()
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        guard writer.status == .completed else {
            throw OverlayVideoError.writerFailed(writer.error?.localizedDescription ?? "Tiny source writer failed.")
        }
    }

    private func makeSilentAudioSampleBuffer(durationSeconds: Double, sampleRate: Double) throws -> CMSampleBuffer {
        let sampleCount = Int(sampleRate * durationSeconds)
        let bytesPerSample = 2
        let dataSize = sampleCount * bytesPerSample

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerSample),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerSample),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            throw OverlayVideoError.writerFailed("Could not create tiny source audio format description.")
        }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else {
            throw OverlayVideoError.writerFailed("Could not allocate tiny source audio block buffer.")
        }
        guard CMBlockBufferFillDataBytes(
            with: 0,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: dataSize
        ) == noErr else {
            throw OverlayVideoError.writerFailed("Could not zero-fill tiny source audio block buffer.")
        }

        var sampleBuffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: sampleCount,
            presentationTimeStamp: .zero,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else {
            throw OverlayVideoError.writerFailed("Could not create tiny source audio sample buffer.")
        }
        return sampleBuffer
    }

    private func makePixelBuffer(red: UInt8, green: UInt8, blue: UInt8) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            64,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<64 {
            for x in 0..<64 {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = blue
                bytes[offset + 1] = green
                bytes[offset + 2] = red
                bytes[offset + 3] = 255
            }
        }
        return pixelBuffer
    }

    private func firstFrameLuma(from url: URL) async throws -> (max: Double, mean: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: try XCTUnwrap(tracks.first),
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let sampleBuffer = try XCTUnwrap(output.copyNextSampleBuffer())
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)

        var maxLuma = 0.0
        var sumLuma = 0.0
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * 4
                let blue = Double(bytes[offset])
                let green = Double(bytes[offset + 1])
                let red = Double(bytes[offset + 2])
                let luma = 0.299 * red + 0.587 * green + 0.114 * blue
                maxLuma = max(maxLuma, luma)
                sumLuma += luma
            }
        }
        return (maxLuma, sumLuma / Double(width * height))
    }

    private func frameMeanRGB(from url: URL, at seconds: TimeInterval) async throws -> (red: Double, green: Double, blue: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: seconds, preferredTimescale: 600),
            duration: CMTime(seconds: 0.25, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(
            track: try XCTUnwrap(tracks.first),
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let sampleBuffer = try XCTUnwrap(output.copyNextSampleBuffer())
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * 4
                blue += Double(bytes[offset])
                green += Double(bytes[offset + 1])
                red += Double(bytes[offset + 2])
            }
        }
        let pixelCount = Double(width * height)
        return (red / pixelCount, green / pixelCount, blue / pixelCount)
    }
}

private extension OverlayVideoError {
    var isUnavailableTimelineTestEncoder: Bool {
        switch self {
        case .unsupportedEncoder, .cannotStartWriter:
            return true
        case let .writerFailed(message):
            return message.localizedCaseInsensitiveContains("encoder") || message.contains("-12903")
        case .unreadableVideo,
             .cannotCreatePixelBuffer,
             .cannotCreateBitmapContext,
             .invalidConfiguration,
             .cancelled:
            return false
        }
    }
}
