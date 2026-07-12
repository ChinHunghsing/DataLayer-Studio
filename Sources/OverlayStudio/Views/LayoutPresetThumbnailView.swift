import OverlayCore
import SwiftUI

struct LayoutPresetThumbnailView: View {
    var layout: OverlayLayout

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.82))

                ForEach(layout.visibleElements) { element in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: element.kind).opacity(0.9))
                        .frame(
                            width: tileSize(for: element.kind).width,
                            height: tileSize(for: element.kind).height
                        )
                        .position(
                            x: min(proxy.size.width - 5, max(5, CGFloat(element.frame.x) * proxy.size.width)),
                            y: min(proxy.size.height - 4, max(4, CGFloat(element.frame.y) * proxy.size.height))
                        )
                }
            }
            .clipped()
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func tileSize(for kind: OverlayComponentID) -> CGSize {
        switch kind {
        case .route:
            return CGSize(width: 23, height: 18)
        case .topProgress:
            return CGSize(width: 42, height: 5)
        case .timeDate, .weather:
            return CGSize(width: 22, height: 10)
        default:
            return CGSize(width: 16, height: 9)
        }
    }

    private func color(for kind: OverlayComponentID) -> Color {
        switch kind {
        case .heartRate:
            return .red
        case .cadence, .distance, .topProgress:
            return .green
        case .pace, .route:
            return .blue
        case .weather, .timeDate:
            return .white
        default:
            return .orange
        }
    }
}

