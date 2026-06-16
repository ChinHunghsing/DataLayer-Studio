import SwiftUI

@main
struct OverlayStudioApp: App {
    @StateObject private var model = StudioModel()

    var body: some Scene {
        WindowGroup("Overlay Studio") {
            ContentView(model: model)
                .frame(minWidth: 1240, minHeight: 760)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Video...") {
                    model.chooseVideo()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open FIT...") {
                    model.chooseFIT()
                }
                .keyboardShortcut("f", modifiers: [.command])

                Divider()

                Button("Export Overlay...") {
                    model.export()
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(!model.canExport || model.isExporting)
            }
        }
    }
}

