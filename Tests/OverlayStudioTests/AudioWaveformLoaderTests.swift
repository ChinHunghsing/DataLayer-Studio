import XCTest
@testable import OverlayStudio

final class AudioWaveformLoaderTests: XCTestCase {
    func testNormalizedPeaksScaleQuietAudioWithoutChangingShape() {
        let normalized = AudioWaveformLoader.normalizedPeaks([0, 0.25, 1])

        XCTAssertEqual(normalized.count, 3)
        XCTAssertEqual(normalized[0], 0, accuracy: 0.0001)
        XCTAssertEqual(normalized[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(normalized[2], 1, accuracy: 0.0001)
    }

    func testNormalizedPeaksKeepsSilenceEmpty() {
        XCTAssertEqual(AudioWaveformLoader.normalizedPeaks([0, 0, 0]), [])
    }
}
