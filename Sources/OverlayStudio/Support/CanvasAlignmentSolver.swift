import CoreGraphics

/// A single smart-guide line surfaced while dragging, in normalized canvas coordinates (0...1).
struct CanvasAlignmentGuide: Equatable, Hashable {
    enum Axis: Hashable {
        case vertical
        case horizontal
    }

    var axis: Axis
    var position: CGFloat
}

/// Result of one snap pass: the offset to add to the proposed drag position plus the
/// guide lines that justify it. A zero offset with empty guides means "no snap".
struct CanvasAlignmentSolution: Equatable {
    var offset: CGVector = .zero
    var guides: [CanvasAlignmentGuide] = []
}

/// Pure snap computation for canvas drags. Aligns the moving element's edges and centers
/// against sibling element edges/centers, the canvas center and thirds, the canvas edges,
/// and an inset safe frame. All coordinates are normalized to the canvas (0...1 per axis),
/// so callers convert their pixel snap radius into per-axis normalized tolerances.
enum CanvasAlignmentSolver {
    struct Configuration: Equatable {
        /// Maximum normalized distance per axis at which an anchor snaps to a line.
        var tolerance: CGSize
        /// Normalized safe-frame inset (0 disables the safe-frame lines).
        var safeAreaInset: CGFloat

        init(tolerance: CGSize, safeAreaInset: CGFloat = 0) {
            self.tolerance = tolerance
            self.safeAreaInset = max(0, min(0.45, safeAreaInset))
        }
    }

    /// Matching slop used when collecting the guide lines that coincide with the snapped
    /// position. Distinct from the snap tolerance: once snapped, only lines the element
    /// actually lies on should light up.
    private static let guideEpsilon: CGFloat = 0.0005

    static func solve(
        movingRect: CGRect,
        neighborRects: [CGRect],
        configuration: Configuration
    ) -> CanvasAlignmentSolution {
        let verticalLines = candidateLines(
            safeAreaInset: configuration.safeAreaInset,
            neighborSpans: neighborRects.map { ($0.minX, $0.midX, $0.maxX) }
        )
        let horizontalLines = candidateLines(
            safeAreaInset: configuration.safeAreaInset,
            neighborSpans: neighborRects.map { ($0.minY, $0.midY, $0.maxY) }
        )
        let verticalAnchors = [movingRect.minX, movingRect.midX, movingRect.maxX]
        let horizontalAnchors = [movingRect.minY, movingRect.midY, movingRect.maxY]

        let dx = bestSnapDelta(anchors: verticalAnchors, lines: verticalLines, tolerance: configuration.tolerance.width)
        let dy = bestSnapDelta(anchors: horizontalAnchors, lines: horizontalLines, tolerance: configuration.tolerance.height)

        var guides: [CanvasAlignmentGuide] = []
        if let dx {
            guides += matchedGuides(
                axis: .vertical,
                anchors: verticalAnchors.map { $0 + dx },
                lines: verticalLines
            )
        }
        if let dy {
            guides += matchedGuides(
                axis: .horizontal,
                anchors: horizontalAnchors.map { $0 + dy },
                lines: horizontalLines
            )
        }
        return CanvasAlignmentSolution(
            offset: CGVector(dx: dx ?? 0, dy: dy ?? 0),
            guides: guides
        )
    }

    private static func candidateLines(
        safeAreaInset: CGFloat,
        neighborSpans: [(CGFloat, CGFloat, CGFloat)]
    ) -> [CGFloat] {
        var lines: [CGFloat] = [0, 1.0 / 3.0, 0.5, 2.0 / 3.0, 1]
        if safeAreaInset > 0 {
            lines.append(safeAreaInset)
            lines.append(1 - safeAreaInset)
        }
        for span in neighborSpans {
            lines.append(span.0)
            lines.append(span.1)
            lines.append(span.2)
        }
        return lines
    }

    private static func bestSnapDelta(
        anchors: [CGFloat],
        lines: [CGFloat],
        tolerance: CGFloat
    ) -> CGFloat? {
        guard tolerance > 0 else { return nil }
        var best: CGFloat?
        for anchor in anchors {
            for line in lines {
                let delta = line - anchor
                guard abs(delta) <= tolerance else { continue }
                if let current = best, abs(delta) >= abs(current) { continue }
                best = delta
            }
        }
        return best
    }

    private static func matchedGuides(
        axis: CanvasAlignmentGuide.Axis,
        anchors: [CGFloat],
        lines: [CGFloat]
    ) -> [CanvasAlignmentGuide] {
        var positions: [CGFloat] = []
        for line in lines {
            guard anchors.contains(where: { abs($0 - line) <= guideEpsilon }) else { continue }
            guard !positions.contains(where: { abs($0 - line) <= guideEpsilon }) else { continue }
            positions.append(line)
        }
        return positions.map { CanvasAlignmentGuide(axis: axis, position: $0) }
    }
}
