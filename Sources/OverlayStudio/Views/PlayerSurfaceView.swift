import AppKit
import AVFoundation
import QuartzCore
import SwiftUI

struct PlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        nsView.player = player
    }

    static func dismantleNSView(_ nsView: PlayerLayerHostView, coordinator: ()) {
        nsView.player = nil
    }
}

final class PlayerLayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    private func setupLayer() {
        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.black.cgColor
        layer = rootLayer
        wantsLayer = true

        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        rootLayer.addSublayer(playerLayer)
    }
}
