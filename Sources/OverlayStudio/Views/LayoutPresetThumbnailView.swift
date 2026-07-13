import OverlayCore
import SwiftUI

struct LayoutPresetThumbnailView: View {
    var layout: OverlayLayout

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.82))

                ForEach(layout.visibleElements) { element in
                    let baseSize = tileSize(for: element.kind)
                    let width = baseSize.width * CGFloat(element.frame.scale)
                    let height = baseSize.height * CGFloat(element.frame.scale)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: element.kind).opacity(0.9))
                        .frame(width: width, height: height)
                        .offset(
                            x: min(
                                max(0, proxy.size.width - width),
                                max(0, CGFloat(element.frame.x) * proxy.size.width)
                            ),
                            y: min(
                                max(0, proxy.size.height - height),
                                max(0, CGFloat(element.frame.y) * proxy.size.height)
                            )
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
