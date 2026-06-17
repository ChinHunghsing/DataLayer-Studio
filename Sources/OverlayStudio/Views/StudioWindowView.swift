import SwiftUI

struct StudioWindowView: View {
    @StateObject private var model = StudioModel()

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 1240, minHeight: 760)
    }
}
