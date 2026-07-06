#if os(iOS)
import OverlayTouch
import SwiftUI

@main
struct OverlayTouchHostApp: App {
    var body: some Scene {
        WindowGroup {
            OverlayTouchRootView()
        }
    }
}
#else
/// 该 target 只用于 iOS/iPadOS App 壳；macOS 全量构建时给出提示即可。
@main
struct OverlayTouchHostCLI {
    static func main() {
        print("overlay-touch-host is an iOS app shell. Build it with scripts/build_touch_sim_app.sh.")
    }
}
#endif
