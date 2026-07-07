import OverlayTouch
import SwiftUI

@main
struct DataLayerStudioMobileApp: App {
    var body: some Scene {
        WindowGroup {
            TouchEditorRootView(enforcesSubscription: true)
        }
    }
}
