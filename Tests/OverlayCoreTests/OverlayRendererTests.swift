@testable import OverlayCore
import CoreVideo
import XCTest

final class OverlayRendererTests: XCTestCase {
    override func tearDown() {
        OverlayRenderer.clearTextWidthCacheForTesting()
        super.tearDown()
    }

    func testRendererCanReuseTextWidthCacheAcrossRendererInstances() throws {
        OverlayRenderer.clearTextWidthCacheForTesting()
        let series = TelemetrySeries(samples: [
            TelemetrySample(
                elapsed: 0,
                date: Date(timeIntervalSince1970: 1_787_000_000),
                latitude: 35,
                longitude: 139,
                heartRate: 150,
                cadence: 180,
                distanceMeters: 0,
                speedMetersPerSecond: 3.4
            ),
            TelemetrySample(
                elapsed: 1,
                date: Date(timeIntervalSince1970: 1_787_000_001),
                latitude: 35.0001,
                longitude: 139.0001,
                heartRate: 151,
                cadence: 182,
                distanceMeters: 3.4,
                speedMetersPerSecond: 3.4
            )
        ])
        let firstRenderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(size: CGSize(width: 640, height: 360))
        )
        let secondRenderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(size: CGSize(width: 640, height: 360))
        )
        let pixelBuffer = try makePixelBuffer(width: 640, height: 360)

        try firstRenderer.render(videoTime: 0, into: pixelBuffer)
        let countAfterFirstRender = OverlayRenderer.textWidthCacheCountForTesting
        try secondRenderer.render(videoTime: 0, into: pixelBuffer)

        XCTAssertGreaterThan(countAfterFirstRender, 0)
        XCTAssertEqual(OverlayRenderer.textWidthCacheCountForTesting, countAfterFirstRender)
    }

    func testMetricTilesShareAlignedWidthWhenOneValueNeedsMoreSpace() throws {
        let series = TelemetrySeries(samples: [
            TelemetrySample(
                elapsed: 0,
                heartRate: 179,
                cadence: 204,
                distanceMeters: 1_230,
                speedMetersPerSecond: 4.82
            )
        ])
        let elements = [
            metricElement(id: "pace", kind: .pace, y: 0.06, valueScale: 1.8),
            metricElement(id: "distance", kind: .distance, y: 0.16),
            metricElement(id: "heart", kind: .heartRate, y: 0.26),
            metricElement(id: "cadence", kind: .cadence, y: 0.36)
        ]
        let renderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(
                size: CGSize(width: 1920, height: 1080),
                layout: OverlayLayout(elements: elements)
            )
        )
        let pixelBuffer = try makePixelBuffer(width: 1920, height: 1080)

        try renderer.render(videoTime: 0, into: pixelBuffer)
        let bounds = try wideDrawnRowBounds(pixelBuffer: pixelBuffer)

        XCTAssertEqual(bounds.count, 4)
        let minX = bounds[0].minX
        let maxX = bounds[0].maxX
        for bound in bounds.dropFirst() {
            XCTAssertEqual(bound.minX, minX, accuracy: 2)
            XCTAssertEqual(bound.maxX, maxX, accuracy: 2)
        }
    }

    func testTopProgressRendererAcceptsCustomBarStyle() throws {
        let series = TelemetrySeries(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: 0),
            TelemetrySample(elapsed: 10, distanceMeters: 5_000)
        ])
        var element = OverlayElement.defaultElement(kind: .topProgress)
        element.customization.showGaugeTicks = true
        element.customization.progressInsetScale = 0.35
        element.customization.progressKnobScale = 1.8
        element.customization.progressValueMarginScale = 2.2
        element.customization.progressTickCount = 64
        element.customization.lineWidth = 24
        element.customization.lengthScale = 0.8

        let renderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(
                size: CGSize(width: 1280, height: 720),
                layout: OverlayLayout(elements: [element])
            )
        )
        let pixelBuffer = try makePixelBuffer(width: 1280, height: 720)

        try renderer.render(videoTime: 4, into: pixelBuffer)
        XCTAssertGreaterThan(try drawnPixelCount(pixelBuffer: pixelBuffer), 0)
    }

    func testRouteDownsampleHonorsLimitAndKeepsEndpoints() {
        let samples = makeSamples(count: 1_799)

        let downsampled = OverlayRenderer.downsample(samples: samples, limit: 900)

        XCTAssertLessThanOrEqual(downsampled.count, 900)
        XCTAssertEqual(downsampled.first?.elapsed, samples.first?.elapsed)
        XCTAssertEqual(downsampled.last?.elapsed, samples.last?.elapsed)
        XCTAssertEqual(downsampled.map(\.elapsed), downsampled.map(\.elapsed).sorted())
    }

    func testRouteDownsampleHandlesSmallLimits() {
        let samples = makeSamples(count: 12)

        XCTAssertEqual(OverlayRenderer.downsample(samples: samples, limit: 0), [])
        XCTAssertEqual(OverlayRenderer.downsample(samples: samples, limit: 1), [samples[0]])
        XCTAssertEqual(OverlayRenderer.downsample(samples: samples, limit: 20), samples)
    }

    func testLastFiniteDistanceSkipsMissingAndInvalidDistances() {
        let samples = [
            TelemetrySample(elapsed: 0, distanceMeters: 1_000),
            TelemetrySample(elapsed: 1, distanceMeters: .nan),
            TelemetrySample(elapsed: 2, distanceMeters: nil)
        ]

        XCTAssertEqual(OverlayRenderer.lastFiniteDistance(samples: samples), 1_000)
        XCTAssertNil(OverlayRenderer.lastFiniteDistance(samples: [
            TelemetrySample(elapsed: 0, distanceMeters: .infinity),
            TelemetrySample(elapsed: 1, distanceMeters: nil)
        ]))
    }

    private func makeSamples(count: Int) -> [TelemetrySample] {
        (0..<count).map { index in
            TelemetrySample(
                elapsed: TimeInterval(index),
                latitude: 35 + Double(index) * 0.00001,
                longitude: 139 + Double(index) * 0.00001
            )
        }
    }

    private func metricElement(
        id: String,
        kind: OverlayComponentID,
        y: Double,
        valueScale: Double = 1
    ) -> OverlayElement {
        OverlayElement(
            id: id,
            kind: kind,
            frame: OverlayComponentFrame(x: 0.05, y: y),
            customization: OverlayElementCustomization(valueScale: valueScale)
        )
    }

    private struct RowBounds {
        var minX: Int
        var maxX: Int
    }

    private func wideDrawnRowBounds(pixelBuffer: CVPixelBuffer) throws -> [RowBounds] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var rowBounds: [(row: Int, bounds: RowBounds)] = []

        for row in 0..<height {
            var minX: Int?
            var maxX: Int?
            let rowStart = row * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * 4
                let isDrawn = bytes[offset] > 2 || bytes[offset + 1] > 2 || bytes[offset + 2] > 2 || bytes[offset + 3] > 2
                guard isDrawn else { continue }
                minX = min(minX ?? x, x)
                maxX = max(maxX ?? x, x)
            }

            if let minX, let maxX, maxX - minX > 80 {
                rowBounds.append((row, RowBounds(minX: minX, maxX: maxX)))
            }
        }

        var groups: [[RowBounds]] = []
        var previousRow: Int?
        for item in rowBounds {
            if let previousRow, item.row > previousRow + 1 {
                groups.append([])
            } else if groups.isEmpty {
                groups.append([])
            }
            groups[groups.count - 1].append(item.bounds)
            previousRow = item.row
        }

        return groups.map { group in
            group.max { lhs, rhs in
                (lhs.maxX - lhs.minX) < (rhs.maxX - rhs.minX)
            }!
        }.sorted { $0.minX < $1.minX }
    }

    private func drawnPixelCount(pixelBuffer: CVPixelBuffer) throws -> Int {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var count = 0
        for row in 0..<height {
            let rowStart = row * bytesPerRow
            for x in 0..<width {
                let offset = rowStart + x * 4
                if bytes[offset] > 2 || bytes[offset + 1] > 2 || bytes[offset + 2] > 2 || bytes[offset + 3] > 2 {
                    count += 1
                }
            }
        }
        return count
    }

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }
        return pixelBuffer
    }
}
