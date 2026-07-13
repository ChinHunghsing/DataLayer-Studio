import CoreGraphics

enum CanvasElementAlignment: CaseIterable {
    case left
    case horizontalCenter
    case right
    case top
    case verticalCenter
    case bottom
}

enum CanvasElementDistribution: CaseIterable {
    case horizontal
    case vertical
}

/// Pure align/distribute math over normalized element rects. Returns one offset per input
/// rect (matching input order) so the caller can apply them to element frames in one
/// undoable layout change.
enum CanvasArrangement {
    static func alignmentOffsets(rects: [CGRect], alignment: CanvasElementAlignment) -> [CGVector] {
        guard rects.count >= 2 else { return rects.map { _ in .zero } }
        switch alignment {
        case .left:
            let target = rects.map(\.minX).min() ?? 0
            return rects.map { CGVector(dx: target - $0.minX, dy: 0) }
        case .right:
            let target = rects.map(\.maxX).max() ?? 0
            return rects.map { CGVector(dx: target - $0.maxX, dy: 0) }
        case .horizontalCenter:
            let bounds = boundingRect(of: rects)
            return rects.map { CGVector(dx: bounds.midX - $0.midX, dy: 0) }
        case .top:
            let target = rects.map(\.minY).min() ?? 0
            return rects.map { CGVector(dx: 0, dy: target - $0.minY) }
        case .bottom:
            let target = rects.map(\.maxY).max() ?? 0
            return rects.map { CGVector(dx: 0, dy: target - $0.maxY) }
        case .verticalCenter:
            let bounds = boundingRect(of: rects)
            return rects.map { CGVector(dx: 0, dy: bounds.midY - $0.midY) }
        }
    }

    /// Distributes the rects between the outermost pair with equal gaps, preserving order
    /// along the chosen axis. The first and last rects stay put.
    static func distributionOffsets(rects: [CGRect], distribution: CanvasElementDistribution) -> [CGVector] {
        guard rects.count >= 3 else { return rects.map { _ in .zero } }
        switch distribution {
        case .horizontal:
            let order = rects.indices.sorted { rects[$0].midX < rects[$1].midX }
            let sorted = order.map { rects[$0] }
            let span = sorted.last!.maxX - sorted.first!.minX
            let totalWidth = sorted.reduce(0) { $0 + $1.width }
            let gap = (span - totalWidth) / CGFloat(sorted.count - 1)
            var offsets = [CGVector](repeating: .zero, count: rects.count)
            var cursor = sorted.first!.minX
            for (position, index) in order.enumerated() {
                if position > 0, position < order.count - 1 {
                    offsets[index] = CGVector(dx: cursor - rects[index].minX, dy: 0)
                }
                cursor += rects[index].width + gap
            }
            return offsets
        case .vertical:
            let order = rects.indices.sorted { rects[$0].midY < rects[$1].midY }
            let sorted = order.map { rects[$0] }
            let span = sorted.last!.maxY - sorted.first!.minY
            let totalHeight = sorted.reduce(0) { $0 + $1.height }
            let gap = (span - totalHeight) / CGFloat(sorted.count - 1)
            var offsets = [CGVector](repeating: .zero, count: rects.count)
            var cursor = sorted.first!.minY
            for (position, index) in order.enumerated() {
                if position > 0, position < order.count - 1 {
                    offsets[index] = CGVector(dx: 0, dy: cursor - rects[index].minY)
                }
                cursor += rects[index].height + gap
            }
            return offsets
        }
    }

    private static func boundingRect(of rects: [CGRect]) -> CGRect {
        rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    }
}
