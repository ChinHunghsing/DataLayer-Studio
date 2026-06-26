import SwiftUI
import AppKit

struct StudioWindowView: View {
    @StateObject private var model = StudioModel()
    @EnvironmentObject private var localization: LocalizationStore
    @State private var didApplyLaunchOptions = false

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 1320, minHeight: 760)
            .background(WindowCenterTitle(centerTitle: centerTitle, windowTitle: windowTitle))
            .onAppear(perform: applyLaunchOptionsIfNeeded)
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

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(centerTitle: centerTitle, windowTitle: windowTitle, from: view)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var label: NSTextField?
        private weak var installedSuperview: NSView?

        func update(centerTitle: String, windowTitle: String, from view: NSView) {
            guard let window = view.window else { return }
            window.title = windowTitle
            window.titleVisibility = centerTitle.isEmpty ? .visible : .hidden

            guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
            let label = label(in: titlebar, closeButton: window.standardWindowButton(.closeButton))
            label.stringValue = centerTitle
            label.isHidden = centerTitle.isEmpty
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
