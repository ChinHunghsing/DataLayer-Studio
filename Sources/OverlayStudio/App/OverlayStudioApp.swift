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
            EditCommands(localization: localization)
            StudioFileCommands(localization: localization)
            LanguageCommands(localization: localization)
            PreviewCommands(localization: localization)
            TimelineCommands(localization: localization)
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
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = appName
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.contentView = contentView()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window = panel
    }

    private static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "DataLayer Studio"
    }

    private static var versionText: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        return [version, build.isEmpty ? nil : "(\(build))"].compactMap { $0 }.joined(separator: " ")
    }

    private static func badgeImage() -> NSImage? {
        if let bundleURL = Bundle.main.url(forResource: badgeResourceName, withExtension: "png") {
            return NSImage(contentsOf: bundleURL)
        }

        let localURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/readme/\(badgeResourceName).png")
        return NSImage(contentsOf: localURL)
    }

    private static func contentView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView(image: NSApplication.shared.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: appName)
        nameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        nameLabel.alignment = .center

        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        let badgeView = NSImageView(image: badgeImage() ?? NSImage())
        badgeView.imageScaling = .scaleProportionallyUpOrDown
        badgeView.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(versionLabel)
        stack.addArrangedSubview(badgeView)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),
            badgeView.widthAnchor.constraint(equalToConstant: 220),
            badgeView.heightAnchor.constraint(equalToConstant: 70)
        ])

        return view
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

/// Replaces the responder-chain Undo/Redo with model-routed commands so timeline and layout
/// undo works whenever the window is key, regardless of which track or clip has keyboard focus.
private struct EditCommands: Commands {
    @ObservedObject var localization: LocalizationStore
    @FocusedValue(\.studioCommandActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(localization.string("menu.undo")) {
                actions?.undo()
            }
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(actions?.canUndo != true)

            Button(localization.string("menu.redo")) {
                actions?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(actions?.canRedo != true)
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

            Button(localization.string("menu.openTimelineProject")) {
                actions?.openTimelineProject()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(actions == nil || actions?.isExporting == true)

            Menu(localization.string("menu.openRecentTimelineProjects")) {
                if let projects = actions?.recentTimelineProjects, !projects.isEmpty {
                    ForEach(projects) { project in
                        Button(project.displayName) {
                            actions?.openRecentTimelineProject(project)
                        }
                    }
                } else {
                    Text(localization.string("menu.noRecentTimelineProjects"))
                }
            }
            .disabled(actions == nil || actions?.isExporting == true)

            Button(localization.string("menu.saveTimelineProject")) {
                actions?.saveTimelineProject()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(actions == nil || actions?.isExporting == true)

            Button(localization.string("menu.saveTimelineProjectAs")) {
                actions?.saveTimelineProjectAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
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

private struct TimelineCommands: Commands {
    @ObservedObject var localization: LocalizationStore
    @FocusedValue(\.studioCommandActions) private var actions

    var body: some Commands {
        CommandMenu(localization.string("menu.timeline")) {
            Button(localization.string("menu.previousEditPoint")) {
                actions?.jumpToPreviousEditPoint()
            }
            .keyboardShortcut(.upArrow, modifiers: [])
            .disabled(actions?.canJumpToTimelineEditPoints != true)

            Button(localization.string("menu.nextEditPoint")) {
                actions?.jumpToNextEditPoint()
            }
            .keyboardShortcut(.downArrow, modifiers: [])
            .disabled(actions?.canJumpToTimelineEditPoints != true)

            Divider()

            Button(localization.string("menu.splitTimelineClips")) {
                actions?.splitTimelineClips()
            }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(actions?.canSplitTimelineClips != true)

            Button(localization.string("menu.toggleTimelineClips")) {
                actions?.toggleTimelineClips()
            }
            .keyboardShortcut("d", modifiers: [])
            .disabled(actions?.canToggleTimelineClips != true)

            Divider()

            Button(localization.string("menu.deleteTimelineClip")) {
                actions?.deleteTimelineClip()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(actions?.canDeleteTimelineClip != true)

            Button(localization.string("menu.rippleDeleteTimelineClip")) {
                actions?.rippleDeleteTimelineClip()
            }
            .keyboardShortcut(.delete, modifiers: [.shift])
            .disabled(actions?.canDeleteTimelineClip != true)
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
