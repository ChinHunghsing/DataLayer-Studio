import AppKit
import SwiftUI

struct StudioWorkspacePaneWidths: Equatable {
    var library: CGFloat
    var inspector: CGFloat

    static func resolve(
        totalWidth: CGFloat,
        requestedLibrary: CGFloat,
        requestedInspector: CGFloat,
        showsLibrary: Bool,
        showsInspector: Bool
    ) -> StudioWorkspacePaneWidths {
        let library = min(420, max(260, requestedLibrary))
        let inspector = min(480, max(320, requestedInspector))
        let dividerAllowance: CGFloat = (showsLibrary ? 7 : 0) + (showsInspector ? 7 : 0)
        let maximumSideWidth = max(0, totalWidth - 420 - dividerAllowance)
        var resolvedLibrary = showsLibrary ? library : 0
        var resolvedInspector = showsInspector ? inspector : 0
        var excess = max(0, resolvedLibrary + resolvedInspector - maximumSideWidth)

        if showsLibrary, excess > 0 {
            let reduction = min(excess / (showsInspector ? 2 : 1), resolvedLibrary - 260)
            resolvedLibrary -= reduction
            excess -= reduction
        }
        if showsInspector, excess > 0 {
            let reduction = min(excess, resolvedInspector - 320)
            resolvedInspector -= reduction
            excess -= reduction
        }
        if showsLibrary, excess > 0 {
            resolvedLibrary = max(260, resolvedLibrary - excess)
        }

        return StudioWorkspacePaneWidths(
            library: resolvedLibrary,
            inspector: resolvedInspector
        )
    }
}

struct HorizontalPaneResizeHandle: View {
    enum Edge {
        case trailing
        case leading
    }

    var edge: Edge
    @Binding var width: Double
    var range: ClosedRange<Double>
    @State private var dragStartWidth: Double?

    var body: some View {
        ZStack {
            Divider()
            Color.clear
                .frame(width: 7)
                .contentShape(Rectangle())
        }
        .frame(width: 7)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil { dragStartWidth = width }
                    let direction = edge == .trailing ? 1.0 : -1.0
                    width = min(
                        range.upperBound,
                        max(range.lowerBound, (dragStartWidth ?? width) + Double(value.translation.width) * direction)
                    )
                }
                .onEnded { _ in dragStartWidth = nil }
        )
        .accessibilityHidden(true)
    }
}
