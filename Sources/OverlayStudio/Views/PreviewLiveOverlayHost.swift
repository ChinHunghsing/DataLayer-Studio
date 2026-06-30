import AppKit
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
    let liveContent: (TimeInterval) -> AnyView

    func makeNSView(context: Context) -> PreviewLiveOverlayView {
        let view = PreviewLiveOverlayView()
        view.configure(
            cachedOverlay: cachedOverlay,
            contentSize: contentSize,
            displayRect: displayRect,
            liveContent: liveContent
        )
        controller.attach(view)
        return view
    }

    func updateNSView(_ view: PreviewLiveOverlayView, context: Context) {
        view.configure(
            cachedOverlay: cachedOverlay,
            contentSize: contentSize,
            displayRect: displayRect,
            liveContent: liveContent
        )
        controller.attach(view)
    }
}

final class PreviewLiveOverlayView: NSView {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var cachedOverlay: NSImage?
    private var displayRect: CGRect = .zero
    private var contentSize: CGSize = .zero
    private var liveContent: ((TimeInterval) -> AnyView)?
    private var liveTime: TimeInterval?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.isHidden = true
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        cachedOverlay: NSImage?,
        contentSize: CGSize,
        displayRect: CGRect,
        liveContent: @escaping (TimeInterval) -> AnyView
    ) {
        self.cachedOverlay = cachedOverlay
        self.contentSize = contentSize
        self.displayRect = displayRect
        self.liveContent = liveContent
        frame.size = contentSize
        if let liveTime {
            renderLive(time: liveTime)
        }
        needsDisplay = true
    }

    func setLiveTime(_ time: TimeInterval?) {
        liveTime = time
        if let time {
            renderLive(time: time)
        } else {
            hostingView.rootView = AnyView(EmptyView())
            hostingView.isHidden = true
        }
        needsDisplay = true
        displayIfNeeded()
        hostingView.displayIfNeeded()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard liveTime == nil,
              let cachedOverlay,
              !displayRect.isEmpty else { return }
        cachedOverlay.draw(in: displayRect)
    }

    private func renderLive(time: TimeInterval) {
        guard let liveContent else { return }
        hostingView.rootView = liveContent(time)
        hostingView.isHidden = false
    }
}
