import SwiftUI

@main
struct OverlayStudioApp: App {
    @StateObject private var localization = LocalizationStore()

    var body: some Scene {
        WindowGroup(localization.string("app.name"), id: "studio") {
            StudioWindowView()
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
        }

        Settings {
            SettingsView()
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
        }
        .commands {
            StudioFileCommands(localization: localization)
            PreviewCommands(localization: localization)
            ArrangeCommands(localization: localization)
        }
    }
}

private struct StudioFileCommands: Commands {
    @ObservedObject var localization: LocalizationStore
    @FocusedValue(\.studioCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(localization.string("menu.openVideo")) {
                actions?.chooseVideo()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(actions == nil || actions?.isExporting == true)

            Button(localization.string("menu.openFit")) {
                actions?.chooseFIT()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(actions == nil || actions?.isExporting == true)

            Divider()

            Button(localization.string("menu.exportOverlay")) {
                actions?.export()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(actions == nil || actions?.canExport != true || actions?.isExporting == true)

            Button(localization.string("menu.cancelExport")) {
                actions?.cancelExport()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(actions?.isExporting != true)
        }
    }
}

private struct ArrangeCommands: Commands {
    @ObservedObject var localization: LocalizationStore
    @FocusedValue(\.studioCommandActions) private var actions

    var body: some Commands {
        CommandMenu(localization.string("menu.arrange")) {
            Button(localization.string("menu.bringForward")) {
                actions?.moveSelectionForward()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(actions?.canMoveSelectionForward != true)

            Button(localization.string("menu.sendBackward")) {
                actions?.moveSelectionBackward()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(actions?.canMoveSelectionBackward != true)
        }
    }
}

private struct PreviewCommands: Commands {
    @ObservedObject var localization: LocalizationStore
    @FocusedValue(\.studioCommandActions) private var studioActions
    @FocusedValue(\.previewCommandActions) private var previewActions

    var body: some Commands {
        CommandMenu(localization.string("menu.preview")) {
            Button(localization.string("menu.refreshPreview")) {
                studioActions?.refreshPreview()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(studioActions == nil || studioActions?.isExporting == true)

            Button(studioActions?.isPlayingPreview == true ? localization.string("menu.pausePreview") : localization.string("menu.playPreview")) {
                studioActions?.togglePlayback()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(studioActions?.canPlayPreview != true)

            Button(localization.string("menu.setSportStart")) {
                studioActions?.markSportStart()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(studioActions?.canMarkSportStart != true)

            Divider()

            Button(localization.string("menu.zoomIn")) {
                previewActions?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(previewActions == nil)

            Button(localization.string("menu.zoomOut")) {
                previewActions?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(previewActions == nil)

            Button(localization.string("menu.resetZoom")) {
                previewActions?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(previewActions == nil)

            Divider()

            Button(previewActions?.isFullscreen == true ? localization.string("menu.exitPreviewFullscreen") : localization.string("menu.enterPreviewFullscreen")) {
                previewActions?.toggleFullscreen()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(previewActions == nil)
        }
    }
}
