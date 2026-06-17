import SwiftUI

@main
struct OverlayStudioApp: App {
    var body: some Scene {
        WindowGroup("Overlay Studio", id: "studio") {
            StudioWindowView()
        }
        .commands {
            StudioFileCommands()
            PreviewCommands()
            ArrangeCommands()
        }
    }
}

private struct StudioFileCommands: Commands {
    @FocusedValue(\.studioCommandActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Video...") {
                actions?.chooseVideo()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(actions == nil || actions?.isExporting == true)

            Button("Open FIT...") {
                actions?.chooseFIT()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(actions == nil || actions?.isExporting == true)

            Divider()

            Button("Export Overlay...") {
                actions?.export()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(actions == nil || actions?.canExport != true || actions?.isExporting == true)

            Button("Cancel Export") {
                actions?.cancelExport()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(actions?.isExporting != true)
        }
    }
}

private struct ArrangeCommands: Commands {
    @FocusedValue(\.studioCommandActions) private var actions

    var body: some Commands {
        CommandMenu("Arrange") {
            Button("Bring Forward") {
                actions?.moveSelectionForward()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(actions?.canMoveSelectionForward != true)

            Button("Send Backward") {
                actions?.moveSelectionBackward()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(actions?.canMoveSelectionBackward != true)
        }
    }
}

private struct PreviewCommands: Commands {
    @FocusedValue(\.studioCommandActions) private var studioActions
    @FocusedValue(\.previewCommandActions) private var previewActions

    var body: some Commands {
        CommandMenu("Preview") {
            Button("Refresh Preview") {
                studioActions?.refreshPreview()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(studioActions == nil || studioActions?.isExporting == true)

            Button(studioActions?.isPlayingPreview == true ? "Pause Preview" : "Play Preview") {
                studioActions?.togglePlayback()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(studioActions?.canPlayPreview != true)

            Button("Set Sport Start") {
                studioActions?.markSportStart()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(studioActions?.canMarkSportStart != true)

            Divider()

            Button("Zoom In") {
                previewActions?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(previewActions == nil)

            Button("Zoom Out") {
                previewActions?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(previewActions == nil)

            Button("Reset Zoom") {
                previewActions?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(previewActions == nil)

            Divider()

            Button(previewActions?.isFullscreen == true ? "Exit Preview Full Screen" : "Enter Preview Full Screen") {
                previewActions?.toggleFullscreen()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(previewActions == nil)
        }
    }
}
