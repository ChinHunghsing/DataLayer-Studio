import SwiftUI
import AppKit

struct StudioWindowView: View {
    @StateObject private var model = StudioModel()
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.undoManager) private var windowUndoManager
    @State private var didApplyLaunchOptions = false

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 1320, minHeight: 760)
            .background(WindowCenterTitle(
                centerTitle: centerTitle,
                windowTitle: windowTitle,
                isDocumentEdited: model.hasUnsavedTimelineChanges
            ))
            .background(WindowCloseGuard(
                model: model,
                confirmedCloseGeneration: model.confirmedWindowCloseGeneration
            ))
            .background(TitlebarTrailingAccessory(rootView: AnyView(
                OutputToolbarButton(model: model)
                    .environmentObject(localization)
                    .environment(\.locale, localization.locale)
            )))
            .background(WindowLiveResizeObserver { model.setPreviewLiveResizing($0) })
            .onAppear(perform: applyLaunchOptionsIfNeeded)
            .onAppear { model.undoManager = windowUndoManager }
            .onChange(of: windowUndoManager.map(ObjectIdentifier.init)) { _ in
                model.undoManager = windowUndoManager
            }
    }

    private var centerTitle: String {
        model.videoURL?.lastPathComponent ?? model.fitURL?.lastPathComponent ?? ""
    }

    private var windowTitle: String {
        centerTitle.isEmpty ? localization.string("app.name") : centerTitle
    }

    private func applyLaunchOptionsIfNeeded() {
        guard !didApplyLaunchOptions else { return }
        didApplyLaunchOptions = true
        let options = StudioLaunchOptions(arguments: CommandLine.arguments)
        model.applyLaunchOptions(options)
    }
}

private struct WindowCenterTitle: NSViewRepresentable {
    let centerTitle: String
    let windowTitle: String
    let isDocumentEdited: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard !context.coordinator.update(
            centerTitle: centerTitle,
            windowTitle: windowTitle,
            isDocumentEdited: isDocumentEdited,
            from: view
        ) else { return }
        DispatchQueue.main.async {
            _ = context.coordinator.update(
                centerTitle: centerTitle,
                windowTitle: windowTitle,
                isDocumentEdited: isDocumentEdited,
                from: view
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var label: NSTextField?
        private weak var installedSuperview: NSView?
        private weak var installedWindow: NSWindow?
        private var lastCenterTitle: String?
        private var lastWindowTitle: String?
        private var lastIsDocumentEdited: Bool?

        @discardableResult
        func update(
            centerTitle: String,
            windowTitle: String,
            isDocumentEdited: Bool,
            from view: NSView
        ) -> Bool {
            guard let window = view.window else { return false }
            if installedWindow === window,
               lastCenterTitle == centerTitle,
               lastWindowTitle == windowTitle,
               lastIsDocumentEdited == isDocumentEdited,
               label != nil || centerTitle.isEmpty {
                return true
            }

            window.title = windowTitle
            window.titleVisibility = centerTitle.isEmpty ? .visible : .hidden
            window.isDocumentEdited = isDocumentEdited
            installedWindow = window
            lastCenterTitle = centerTitle
            lastWindowTitle = windowTitle
            lastIsDocumentEdited = isDocumentEdited

            guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return true }
            let label = label(in: titlebar, closeButton: window.standardWindowButton(.closeButton))
            label.stringValue = centerTitle
            label.isHidden = centerTitle.isEmpty
            return true
        }

        private func label(in titlebar: NSView, closeButton: NSView?) -> NSTextField {
            if let label, installedSuperview === titlebar {
                return label
            }

            label?.removeFromSuperview()
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            titlebar.addSubview(label)

            let centerYAnchor = closeButton?.centerYAnchor ?? titlebar.centerYAnchor
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: titlebar.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualTo: titlebar.widthAnchor, multiplier: 0.42)
            ])

            self.label = label
            installedSuperview = titlebar
            return label
        }
    }
}

private struct WindowCloseGuard: NSViewRepresentable {
    let model: StudioModel
    let confirmedCloseGeneration: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> CloseGuardView {
        let view = CloseGuardView(frame: .zero)
        let coordinator = context.coordinator
        coordinator.update(
            model: model,
            confirmedCloseGeneration: confirmedCloseGeneration,
            window: nil
        )
        view.onWindowChange = { [weak coordinator] window in
            coordinator?.update(
                model: model,
                confirmedCloseGeneration: confirmedCloseGeneration,
                window: window
            )
        }
        return view
    }

    func updateNSView(_ nsView: CloseGuardView, context: Context) {
        let coordinator = context.coordinator
        nsView.onWindowChange = { [weak coordinator] window in
            coordinator?.update(
                model: model,
                confirmedCloseGeneration: confirmedCloseGeneration,
                window: window
            )
        }
        coordinator.update(
            model: model,
            confirmedCloseGeneration: confirmedCloseGeneration,
            window: nsView.window
        )
    }

    static func dismantleNSView(_ nsView: CloseGuardView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        coordinator.restoreForwardingDelegate()
    }

    final class CloseGuardView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var model: StudioModel?
        private weak var installedWindow: NSWindow?
        private var forwardingDelegate: NSWindowDelegate?
        private var lastConfirmedCloseGeneration: Int?

        func update(
            model: StudioModel,
            confirmedCloseGeneration: Int,
            window: NSWindow?
        ) {
            self.model = model
            if let window {
                install(on: window)
            }

            guard let previousGeneration = lastConfirmedCloseGeneration else {
                lastConfirmedCloseGeneration = confirmedCloseGeneration
                return
            }
            guard confirmedCloseGeneration != previousGeneration else { return }
            lastConfirmedCloseGeneration = confirmedCloseGeneration
            DispatchQueue.main.async { [weak installedWindow] in
                installedWindow?.performClose(nil)
            }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard model?.requestWindowClose() ?? true else { return false }
            return forwardingDelegate?.windowShouldClose?(sender) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || forwardingDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if forwardingDelegate?.responds(to: selector) == true {
                return forwardingDelegate
            }
            return super.forwardingTarget(for: selector)
        }

        private func install(on window: NSWindow) {
            if installedWindow !== window {
                restoreForwardingDelegate()
                installedWindow = window
                forwardingDelegate = window.delegate
            } else if window.delegate !== self {
                forwardingDelegate = window.delegate
            }
            window.delegate = self
        }

        func restoreForwardingDelegate() {
            if installedWindow?.delegate === self {
                installedWindow?.delegate = forwardingDelegate
            }
            installedWindow = nil
            forwardingDelegate = nil
        }
    }
}

private struct WindowLiveResizeObserver: NSViewRepresentable {
    var onLiveResizeChange: (Bool) -> Void

    func makeNSView(context: Context) -> LiveResizeObserverView {
        let view = LiveResizeObserverView(frame: .zero)
        view.onLiveResizeChange = onLiveResizeChange
        return view
    }

    func updateNSView(_ nsView: LiveResizeObserverView, context: Context) {
        nsView.onLiveResizeChange = onLiveResizeChange
    }

    final class LiveResizeObserverView: NSView {
        var onLiveResizeChange: ((Bool) -> Void)?

        override func viewWillStartLiveResize() {
            super.viewWillStartLiveResize()
            onLiveResizeChange?(true)
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            onLiveResizeChange?(false)
        }
    }
}

struct StudioLaunchOptions: Equatable {
    var videoURL: URL?
    var fitURL: URL?
    var offsetSeconds: Double?

    init(arguments: [String]) {
        var videoURL: URL?
        var fitURL: URL?
        var offsetSeconds: Double?
        var index = 0

        while index < arguments.count {
            defer { index += 1 }
            switch arguments[index] {
            case "--video":
                guard let value = arguments[safe: index + 1] else { continue }
                videoURL = URL(fileURLWithPath: value)
                index += 1
            case "--fit":
                guard let value = arguments[safe: index + 1] else { continue }
                fitURL = URL(fileURLWithPath: value)
                index += 1
            case "--offset":
                guard let value = arguments[safe: index + 1],
                      let parsed = Double(value),
                      parsed.isFinite else {
                    continue
                }
                offsetSeconds = parsed
                index += 1
            default:
                continue
            }
        }

        self.videoURL = videoURL
        self.fitURL = fitURL
        self.offsetSeconds = offsetSeconds
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
