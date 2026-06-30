import AppKit
import QuartzCore
import SwiftUI

final class PreviewLiveScrubController {
    private weak var overlayView: PreviewLiveOverlayView?
    private(set) var currentTime: TimeInterval?

    func attach(_ view: PreviewLiveOverlayView) {
        overlayView = view
        view.setLiveTime(currentTime)
    }

    func setTime(_ time: TimeInterval?) {
        currentTime = time
        overlayView?.setLiveTime(time)
    }
}

struct PreviewLiveOverlayHost: NSViewRepresentable {
    let controller: PreviewLiveScrubController
    let cachedOverlay: NSImage?
    let contentSize: CGSize
    let displayRect: CGRect
    let liveOverlayImage: (TimeInterval) -> NSImage?

    func makeNSView(context: Context) -> PreviewLiveOverlayView {
        let view = PreviewLiveOverlayView()
        view.configure(
            cachedOverlay: cachedOverlay,
            contentSize: contentSize,
            displayRect: displayRect,
            liveOverlayImage: liveOverlayImage
        )
        controller.attach(view)
        return view
    }

    func updateNSView(_ view: PreviewLiveOverlayView, context: Context) {
        view.configure(
            cachedOverlay: cachedOverlay,
            contentSize: contentSize,
            displayRect: displayRect,
            liveOverlayImage: liveOverlayImage
        )
        controller.attach(view)
    }
}

final class PreviewLiveOverlayView: NSView {
    private var cachedOverlay: NSImage?
    private var liveOverlay: NSImage?
    private var displayRect: CGRect = .zero
    private var contentSize: CGSize = .zero
    private var liveOverlayImage: ((TimeInterval) -> NSImage?)?
    private var liveTime: TimeInterval?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        cachedOverlay: NSImage?,
        contentSize: CGSize,
        displayRect: CGRect,
        liveOverlayImage: @escaping (TimeInterval) -> NSImage?
    ) {
        self.cachedOverlay = cachedOverlay
        self.contentSize = contentSize
        self.displayRect = displayRect
        self.liveOverlayImage = liveOverlayImage
        frame.size = contentSize
        if let liveTime {
            liveOverlay = liveOverlayImage(liveTime)
        }
        needsDisplay = true
    }

    func setLiveTime(_ time: TimeInterval?) {
        liveTime = time
        if let time {
            liveOverlay = liveOverlayImage?(time)
        } else {
            liveOverlay = nil
        }
        display()
        CATransaction.flush()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let overlay = liveOverlay ?? cachedOverlay,
              !displayRect.isEmpty else { return }
        overlay.draw(in: displayRect)
    }
}
