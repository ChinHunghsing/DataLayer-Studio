#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

struct TouchPlayerSurface: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> TouchPlayerLayerView {
        let view = TouchPlayerLayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: TouchPlayerLayerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
    }
}

final class TouchPlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }
}
#endif
