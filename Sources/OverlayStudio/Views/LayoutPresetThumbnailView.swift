import OverlayCore
import SwiftUI

struct LayoutPresetThumbnailView: View {
    var layout: OverlayLayout

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black)

                ForEach(layout.visibleElements) { element in
                    let size = tileSize(for: element, in: proxy.size)
                    componentGlyph(for: element)
                        .frame(width: size.width, height: size.height)
                        .offset(
                            x: CGFloat(element.frame.x) * proxy.size.width,
                            y: CGFloat(element.frame.y) * proxy.size.height
                        )
                }
            }
            .clipped()
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func tileSize(for element: OverlayElement, in canvas: CGSize) -> CGSize {
        let base = ComponentBaseSize.size(for: element.kind)
        let scale = CGFloat(element.frame.scale)
        let lengthScale = CGFloat(max(0.1, element.customization.lengthScale))
        return CGSize(
            width: min(canvas.width, max(2, base.width / 1920 * canvas.width * scale * lengthScale)),
            height: min(canvas.height, max(2, base.height / 1080 * canvas.height * scale))
        )
    }

    private func componentGlyph(for element: OverlayElement) -> some View {
        Canvas { context, size in
            switch element.kind {
            case .route:
                var route = Path()
                route.move(to: CGPoint(x: size.width * 0.04, y: size.height * 0.84))
                route.addLine(to: CGPoint(x: size.width * 0.22, y: size.height * 0.72))
                route.addLine(to: CGPoint(x: size.width * 0.18, y: size.height * 0.52))
                route.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.46))
                route.addLine(to: CGPoint(x: size.width * 0.36, y: size.height * 0.28))
                route.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.12))
                route.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.34))
                route.addLine(to: CGPoint(x: size.width * 0.94, y: size.height * 0.62))
                route.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.86))
                context.stroke(
                    route,
                    with: .color(Color(red: 0.72, green: 1, blue: 0.84)),
                    style: StrokeStyle(lineWidth: max(0.8, size.height * 0.08), lineCap: .round, lineJoin: .round)
                )

            case .topProgress:
                let track = CGRect(x: 0, y: size.height * 0.38, width: size.width, height: max(1, size.height * 0.24))
                context.fill(Path(roundedRect: track, cornerRadius: track.height / 2), with: .color(.gray))
                let knob = CGRect(
                    x: 0,
                    y: size.height * 0.22,
                    width: max(2, size.height * 0.56),
                    height: max(2, size.height * 0.56)
                )
                context.fill(Path(ellipseIn: knob), with: .color(.red))

            case .timeDate:
                for row in 0..<3 {
                    let width = size.width * (row == 0 ? 0.72 : 0.92)
                    let rect = CGRect(
                        x: size.width - width,
                        y: CGFloat(row) * size.height * 0.34,
                        width: width,
                        height: max(1, size.height * 0.15)
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(.white.opacity(0.88)))
                }

            default:
                let bounds = CGRect(origin: .zero, size: size)
                let panel = Path(roundedRect: bounds, cornerRadius: min(2, size.height * 0.16))
                context.fill(panel, with: .color(.black))
                context.stroke(panel, with: .color(.gray.opacity(0.65)), lineWidth: max(0.5, size.height * 0.04))
                let accent = color(for: element.kind)
                context.fill(
                    Path(roundedRect: CGRect(x: size.width * 0.10, y: size.height * 0.50, width: size.width * 0.48, height: max(1, size.height * 0.18)), cornerRadius: 1),
                    with: .color(accent)
                )
                if element.kind == .weather {
                    context.fill(
                        Path(ellipseIn: CGRect(x: size.width * 0.72, y: size.height * 0.42, width: size.width * 0.16, height: size.height * 0.22)),
                        with: .color(.white.opacity(0.9))
                    )
                }
            }
        }
    }

    private func color(for kind: OverlayComponentID) -> Color {
        switch kind {
        case .heartRate:
            return .red
        case .cadence, .distance:
            return .green
        case .pace, .weather:
            return .cyan
        default:
            return .orange
        }
    }
}
