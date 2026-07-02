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
        element.customization.progressBarColor = OverlayColor(red: 0.9, green: 0.2, blue: 0.2)
        element.customization.progressStartColor = OverlayColor(red: 1, green: 1, blue: 1)
        element.customization.progressCurrentColor = OverlayColor(red: 0.2, green: 0.8, blue: 1)
        element.customization.progressEndColor = OverlayColor(red: 0.8, green: 0.8, blue: 0.8)
        element.customization.progressStartFont = .helveticaNeueBold
        element.customization.progressCurrentFont = .menloBold
        element.customization.progressEndFont = .helveticaNeueBold
        element.customization.progressStartScale = 1.1
        element.customization.progressCurrentScale = 1.35
        element.customization.progressEndScale = 0.9

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

    func testRendererDrawsAdditionalMetricGauges() throws {
        let series = TelemetrySeries(samples: [
            TelemetrySample(
                elapsed: 0,
                powerWatts: 286,
                totalCalories: 42,
                stepLengthMeters: 1.24,
                weatherTemperatureCelsius: 22,
                weatherHumidityPercent: 58,
                weatherSummary: "Clear"
            )
        ])
        let elements = [
            metricElement(id: "calories", kind: .calories, y: 0.06),
            metricElement(id: "stride", kind: .strideLength, y: 0.16),
            metricElement(id: "power", kind: .power, y: 0.26),
            metricElement(id: "weather", kind: .weather, y: 0.36)
        ]
        let renderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(
                size: CGSize(width: 640, height: 360),
                layout: OverlayLayout(elements: elements)
            )
        )
        let pixelBuffer = try makePixelBuffer(width: 640, height: 360)

        try renderer.render(videoTime: 0, into: pixelBuffer)
        XCTAssertGreaterThan(try drawnPixelCount(pixelBuffer: pixelBuffer), 0)
    }

    func testRendererDrawsStrydMetricGauges() throws {
        let series = TelemetrySeries(samples: [
            TelemetrySample(
                elapsed: 0,
                verticalOscillationCentimeters: 5.8,
                groundContactTimeMilliseconds: 251,
                groundContactTimePercent: 31.25,
                groundContactTimeBalancePercent: 50.2,
                verticalRatioPercent: 8.12,
                respirationRateBreathsPerMinute: 18.75,
                stepSpeedLossPercent: 2.64,
                formPowerWatts: 47,
                airPowerWatts: 8,
                legSpringStiffnessKilonewtonsPerMeter: 11.25
            )
        ])
        let elements = [
            metricElement(id: "vertical", kind: .verticalOscillation, y: 0.06),
            metricElement(id: "gct", kind: .groundContactTime, y: 0.16),
            metricElement(id: "gctPercent", kind: .groundContactTimePercent, y: 0.26),
            metricElement(id: "gctBalance", kind: .groundContactTimeBalance, y: 0.36),
            metricElement(id: "verticalRatio", kind: .verticalRatio, y: 0.46),
            metricElement(id: "respiration", kind: .respirationRate, y: 0.56),
            metricElement(id: "stepSpeedLoss", kind: .stepSpeedLoss, y: 0.66),
            metricElement(id: "form", kind: .formPower, y: 0.76),
            metricElement(id: "air", kind: .airPower, y: 0.86),
            metricElement(id: "lss", kind: .legSpringStiffness, y: 0.96)
        ]
        let renderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(
                size: CGSize(width: 640, height: 480),
                layout: OverlayLayout(elements: elements)
            )
        )
        let pixelBuffer = try makePixelBuffer(width: 640, height: 480)

        try renderer.render(videoTime: 0, into: pixelBuffer)
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

    func testRouteDirectionAngleUsesTravelDirection() {
        XCTAssertEqual(
            OverlayRenderer.routeDirectionAngle(before: CGPoint(x: 10, y: 10), after: CGPoint(x: 30, y: 10)) ?? -1,
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            OverlayRenderer.routeDirectionAngle(before: CGPoint(x: 10, y: 10), after: CGPoint(x: 10, y: 30)) ?? -1,
            .pi / 2,
            accuracy: 0.0001
        )
        XCTAssertNil(OverlayRenderer.routeDirectionAngle(before: CGPoint(x: 10, y: 10), after: CGPoint(x: 10.5, y: 10.2)))
    }

    func testRendererDrawsRouteAcrossFrames() throws {
        let series = TelemetrySeries(samples: makeSamples(count: 64))
        let renderer = OverlayRenderer(
            series: series,
            config: OverlayRenderConfig(
                size: CGSize(width: 640, height: 360),
                layout: OverlayLayout(elements: [OverlayElement.defaultElement(kind: .route)])
            )
        )
        let pixelBuffer = try makePixelBuffer(width: 640, height: 360)

        try renderer.render(videoTime: 0, into: pixelBuffer)
        XCTAssertGreaterThan(try drawnPixelCount(pixelBuffer: pixelBuffer), 0)

        try renderer.render(videoTime: 30, into: pixelBuffer)
        XCTAssertGreaterThan(try drawnPixelCount(pixelBuffer: pixelBuffer), 0)
    }

    func testWithLayoutRendersSameAsFreshRendererWhenMetricMoves() throws {
        let series = TelemetrySeries(samples: makeSamples(count: 64))
        let size = CGSize(width: 640, height: 360)
        let layoutA = OverlayLayout(elements: [
            OverlayElement.defaultElement(kind: .route),
            OverlayElement.defaultElement(kind: .pace)
        ])
        var layoutB = layoutA
        layoutB.updateElement(id: "pace") { element in
            element.frame.x = 0.42
            element.frame.y = 0.31
        }

        let base = OverlayRenderer(series: series, config: OverlayRenderConfig(size: size, layout: layoutA))
        let reused = base.withLayout(layoutB)
        let fresh = OverlayRenderer(series: series, config: OverlayRenderConfig(size: size, layout: layoutB))

        try assertRenderersProduceIdenticalPixels(reused, fresh, size: size, videoTime: 30)
    }

    func testWithLayoutComputesRoutePointsWhenRouteBecomesVisible() throws {
        let series = TelemetrySeries(samples: makeSamples(count: 64))
        let size = CGSize(width: 640, height: 360)
        let layoutA = OverlayLayout(elements: [OverlayElement.defaultElement(kind: .pace)])
        let layoutB = OverlayLayout(elements: [
            OverlayElement.defaultElement(kind: .pace),
            OverlayElement.defaultElement(kind: .route)
        ])

        let base = OverlayRenderer(series: series, config: OverlayRenderConfig(size: size, layout: layoutA))
        let reused = base.withLayout(layoutB)
        let fresh = OverlayRenderer(series: series, config: OverlayRenderConfig(size: size, layout: layoutB))

        let pixelBuffer = try makePixelBuffer(width: Int(size.width), height: Int(size.height))
        try reused.render(videoTime: 30, into: pixelBuffer)
        XCTAssertGreaterThan(try drawnPixelCount(pixelBuffer: pixelBuffer), 0)

        try assertRenderersProduceIdenticalPixels(reused, fresh, size: size, videoTime: 30)
    }

    func testWithLayoutRebuildsRoutePathWhenRouteMoves() throws {
        let series = TelemetrySeries(samples: makeSamples(count: 64))
        let size = CGSize(width: 640, height: 360)
        let layoutA = OverlayLayout(elements: [OverlayElement.defaultElement(kind: .route)])
        var layoutB = layoutA
        layoutB.updateElement(id: "route") { element in
            element.frame.x = 0.12
            element.frame.y = 0.08
        }

        let base = OverlayRenderer(series: series, config: OverlayRenderConfig(size: size, layout: layoutA))
        let reused = base.withLayout(layoutB)
        let fresh = OverlayRenderer(series: series, config: OverlayRenderConfig(size: size, layout: layoutB))

        try assertRenderersProduceIdenticalPixels(reused, fresh, size: size, videoTime: 30)
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

    private func assertRenderersProduceIdenticalPixels(
        _ lhs: OverlayRenderer,
        _ rhs: OverlayRenderer,
        size: CGSize,
        videoTime: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let lhsBuffer = try makePixelBuffer(width: Int(size.width), height: Int(size.height))
        let rhsBuffer = try makePixelBuffer(width: Int(size.width), height: Int(size.height))
        try lhs.render(videoTime: videoTime, into: lhsBuffer)
        try rhs.render(videoTime: videoTime, into: rhsBuffer)
        XCTAssertEqual(
            try pixelBytes(pixelBuffer: lhsBuffer),
            try pixelBytes(pixelBuffer: rhsBuffer),
            "Renderers should draw identical pixels",
            file: file,
            line: line
        )
    }

    private func pixelBytes(pixelBuffer: CVPixelBuffer) throws -> [UInt8] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw OverlayVideoError.cannotCreatePixelBuffer
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var result: [UInt8] = []
        result.reserveCapacity(width * height * 4)
        for row in 0..<height {
            let rowStart = row * bytesPerRow
            result.append(contentsOf: UnsafeBufferPointer(start: bytes + rowStart, count: width * 4))
        }
        return result
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
