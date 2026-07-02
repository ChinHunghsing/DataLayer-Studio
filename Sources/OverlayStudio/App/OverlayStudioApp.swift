import AppKit
import OverlayCore
import SwiftUI
@preconcurrency import UserNotifications

@main
struct OverlayStudioApp: App {
    @StateObject private var localization: LocalizationStore
    @AppStorage(AppAppearanceSelection.defaultsKey) private var appearanceRawValue = AppAppearanceSelection.system.rawValue

    init() {
        TransparentVideoWriter.removeStaleTemporaryOutputs()
        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared
        AppLocalizer.applyStoredProcessLanguagePreference()
        _localization = StateObject(wrappedValue: LocalizationStore())
    }

    var body: some Scene {
        WindowGroup(localization.string("app.name"), id: "studio") {
            PurchaseAuthorizationGate {
                StudioWindowView()
            }
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
                .preferredColorScheme(preferredColorScheme)
        }

        Settings {
            SettingsView()
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
                .preferredColorScheme(preferredColorScheme)
        }
        .commands {
            AppInfoCommands(localization: localization)
            StudioFileCommands(localization: localization)
            LanguageCommands(localization: localization)
            PreviewCommands(localization: localization)
            ArrangeCommands(localization: localization)
            DebugCommands(localization: localization)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        AppAppearanceSelection.selection(from: appearanceRawValue).colorScheme
    }
}

private struct AppInfoCommands: Commands {
    @ObservedObject var localization: LocalizationStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(localization.string("menu.aboutApp", localization.string("app.name"))) {
                AboutPanelPresenter.show()
            }
        }
    }
}

private enum AboutPanelPresenter {
    private static let badgeResourceName = "fable5verified"
    private static let badgeWidth: CGFloat = 220

    static func show() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let badge = badgeImage() {
            options[.credits] = credits(with: badge)
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    private static func badgeImage() -> NSImage? {
        if let bundleURL = Bundle.main.url(forResource: badgeResourceName, withExtension: "png") {
            return NSImage(contentsOf: bundleURL)
        }

        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/readme/\(badgeResourceName).png")
        return NSImage(contentsOf: localURL)
    }

    private static func credits(with badge: NSImage) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = scaledBadgeImage(badge)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let credits = NSMutableAttributedString(string: "\n")
        let badgeString = NSMutableAttributedString(attachment: attachment)
        badgeString.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: badgeString.length))
        credits.append(badgeString)
        credits.append(NSAttributedString(string: "\n"))
        return credits
    }

    private static func scaledBadgeImage(_ image: NSImage) -> NSImage {
        let scale = badgeWidth / max(image.size.width, 1)
        let size = NSSize(width: badgeWidth, height: max(1, image.size.height * scale))
        let output = NSImage(size: size)
        output.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        output.unlockFocus()
        return output
    }
}

private final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let path = response.notification.request.content.userInfo["exportPath"] as? String else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct LanguageCommands: Commands {
    @ObservedObject var localization: LocalizationStore

    var body: some Commands {
        CommandMenu(localization.string("menu.language")) {
            Picker(localization.string("settings.language.picker"), selection: $localization.selection) {
                ForEach(AppLanguageSelection.allCases) { selection in
                    Text(selection.nativeName).tag(selection)
                }
            }
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
            .keyboardShortcut(.space, modifiers: [])
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

private struct DebugCommands: Commands {
    @ObservedObject var localization: LocalizationStore
    @FocusedValue(\.studioCommandActions) private var actions

    var body: some Commands {
        CommandMenu(localization.string("menu.debug")) {
            Button(localization.string("menu.showDebugConsole")) {
                actions?.showDebugConsole()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button(localization.string("menu.copyDebugLogs")) {
                actions?.copyDebugLog()
            }
            .disabled(actions?.debugLogCount ?? 0 == 0)

            Button(localization.string("menu.clearDebugLogs")) {
                actions?.clearDebugLog()
            }
            .disabled(actions?.debugLogCount ?? 0 == 0)
        }
    }
}
