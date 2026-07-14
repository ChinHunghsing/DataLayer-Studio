import XCTest
@testable import OverlayCore

final class VideoMetadataTests: XCTestCase {
    private let containerDate = Date(timeIntervalSince1970: 1_752_000_000)
    private let recordingDate = Date(timeIntervalSince1970: 1_751_000_000)

    func testExplicitRecordingMetadataWinsOverEditorSignature() {
        let resolved = VideoMetadata.resolveCreationDate(
            containerCreationDate: containerDate,
            explicitRecordingDate: recordingDate,
            writingApplication: "Blackmagic Design DaVinci Resolve Studio"
        )

        XCTAssertEqual(resolved.date, recordingDate)
        XCTAssertEqual(resolved.source, .recordingMetadata)
    }

    func testDaVinciContainerDateIsRejectedWithoutRecordingMetadata() {
        let resolved = VideoMetadata.resolveCreationDate(
            containerCreationDate: containerDate,
            explicitRecordingDate: nil,
            writingApplication: "Blackmagic Design DaVinci Resolve Studio"
        )

        XCTAssertNil(resolved.date)
        XCTAssertEqual(resolved.source, .untrustedExport)
    }

    func testOrdinaryContainerDateRemainsAvailableAsFallback() {
        let resolved = VideoMetadata.resolveCreationDate(
            containerCreationDate: containerDate,
            explicitRecordingDate: nil,
            writingApplication: nil
        )

        XCTAssertEqual(resolved.date, containerDate)
        XCTAssertEqual(resolved.source, .containerMetadata)
    }
}
