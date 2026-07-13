import XCTest
@testable import OverlayStudio

final class CanvasAlignmentSolverTests: XCTestCase {
    private func configuration(
        tolerance: CGFloat = 0.01,
        safeAreaInset: CGFloat = 0
    ) -> CanvasAlignmentSolver.Configuration {
        CanvasAlignmentSolver.Configuration(
            tolerance: CGSize(width: tolerance, height: tolerance),
            safeAreaInset: safeAreaInset
        )
    }

    func testNoSnapOutsideTolerance() {
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 0.21, y: 0.21, width: 0.1, height: 0.1),
            neighborRects: [],
            configuration: configuration(tolerance: 0.005)
        )

        XCTAssertEqual(solution.offset, .zero)
        XCTAssertTrue(solution.guides.isEmpty)
    }

    func testSnapsLeadingEdgeToNeighborLeadingEdge() {
        let neighbor = CGRect(x: 0.4, y: 0.7, width: 0.2, height: 0.1)
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 0.394, y: 0.213, width: 0.12, height: 0.1),
            neighborRects: [neighbor],
            configuration: configuration()
        )

        XCTAssertEqual(solution.offset.dx, 0.006, accuracy: 1e-9)
        XCTAssertEqual(solution.offset.dy, 0)
        XCTAssertEqual(solution.guides, [CanvasAlignmentGuide(axis: .vertical, position: 0.4)])
    }

    func testSnapsCenterToCanvasCenterOnBothAxes() {
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 0.446, y: 0.457, width: 0.1, height: 0.1),
            neighborRects: [],
            configuration: configuration()
        )

        XCTAssertEqual(solution.offset.dx, 0.004, accuracy: 1e-9)
        XCTAssertEqual(solution.offset.dy, -0.007, accuracy: 1e-9)
        XCTAssertTrue(solution.guides.contains(CanvasAlignmentGuide(axis: .vertical, position: 0.5)))
        XCTAssertTrue(solution.guides.contains(CanvasAlignmentGuide(axis: .horizontal, position: 0.5)))
    }

    func testSnapsToCanvasThirds() {
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 1.0 / 3.0 + 0.004, y: 0.2, width: 0.1, height: 0.1),
            neighborRects: [],
            configuration: configuration()
        )

        XCTAssertEqual(solution.offset.dx, -0.004, accuracy: 1e-9)
        XCTAssertEqual(solution.guides, [CanvasAlignmentGuide(axis: .vertical, position: 1.0 / 3.0)])
    }

    func testSnapsToSafeFrameWhenInsetConfigured() {
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 0.047, y: 0.2, width: 0.1, height: 0.1),
            neighborRects: [],
            configuration: configuration(safeAreaInset: 0.05)
        )

        XCTAssertEqual(solution.offset.dx, 0.003, accuracy: 1e-9)
        XCTAssertEqual(solution.guides, [CanvasAlignmentGuide(axis: .vertical, position: 0.05)])
    }

    func testSafeFrameLinesAbsentWhenInsetIsZero() {
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 0.047, y: 0.2, width: 0.1, height: 0.1),
            neighborRects: [],
            configuration: configuration(safeAreaInset: 0)
        )

        XCTAssertEqual(solution.offset, .zero)
        XCTAssertTrue(solution.guides.isEmpty)
    }

    func testPicksNearestCandidateAmongCompetingLines() {
        // Trailing edge is 0.002 from the neighbor's leading edge; the moving rect's
        // own leading edge is 0.006 from the canvas third. Nearest wins.
        let neighbor = CGRect(x: 0.435, y: 0.2, width: 0.2, height: 0.1)
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 1.0 / 3.0 + 0.006, y: 0.52, width: 0.097, height: 0.1),
            neighborRects: [neighbor],
            configuration: configuration()
        )

        XCTAssertEqual(solution.offset.dx, -0.001333333, accuracy: 1e-6)
        XCTAssertEqual(solution.guides, [CanvasAlignmentGuide(axis: .vertical, position: 0.435)])
    }

    func testSnapsCenterToNeighborCenterVertically() {
        let neighbor = CGRect(x: 0.7, y: 0.4, width: 0.1, height: 0.2)
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 0.21, y: 0.457, width: 0.12, height: 0.08),
            neighborRects: [neighbor],
            configuration: configuration()
        )

        // Moving midY 0.497 snaps to neighbor midY 0.5 (canvas center coincides).
        XCTAssertEqual(solution.offset.dy, 0.003, accuracy: 1e-9)
        XCTAssertTrue(solution.guides.contains(CanvasAlignmentGuide(axis: .horizontal, position: 0.5)))
    }

    func testGuidesDeduplicateCoincidentLines() {
        // Neighbor edge sits exactly on the canvas center: only one guide at 0.5.
        let neighbor = CGRect(x: 0.5, y: 0.2, width: 0.2, height: 0.1)
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 0.496, y: 0.7, width: 0.1, height: 0.1),
            neighborRects: [neighbor],
            configuration: configuration()
        )

        XCTAssertEqual(solution.offset.dx, 0.004, accuracy: 1e-9)
        XCTAssertEqual(
            solution.guides.filter { $0 == CanvasAlignmentGuide(axis: .vertical, position: 0.5) }.count,
            1
        )
    }

    func testZeroToleranceNeverSnaps() {
        let solution = CanvasAlignmentSolver.solve(
            movingRect: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1),
            neighborRects: [],
            configuration: configuration(tolerance: 0)
        )

        XCTAssertEqual(solution.offset, .zero)
        XCTAssertTrue(solution.guides.isEmpty)
    }
}
