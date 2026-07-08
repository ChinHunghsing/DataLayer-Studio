import AppKit
import SwiftUI

/// 标题栏右上角的“输出”按钮，点击弹出输出面板（设置 + 摘要 + 导出动作）。
struct OutputToolbarButton: View {
    @ObservedObject var model: StudioModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(localization.string("toolbar.output"), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(model.isExporting)
        .help(localization.string("toolbar.output"))
        .padding(.top, 4)
        .padding(.trailing, 12)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            OutputPanelView(model: model)
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
                .frame(width: 520)
        }
        .onChange(of: model.isExporting) { isExporting in
            if isExporting {
                isPresented = false
            }
        }
    }
}

/// 把一个 SwiftUI 视图安装为窗口标题栏右侧（trailing）配件，保证稳定出现在右上角。
struct TitlebarTrailingAccessory: NSViewRepresentable {
    var rootView: AnyView

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.rootView = rootView
        guard context.coordinator.install(from: nsView) else {
            DispatchQueue.main.async {
                _ = context.coordinator.install(from: nsView)
            }
            return
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var rootView: AnyView = AnyView(EmptyView())
        private weak var installedWindow: NSWindow?
        private var hosting: NSHostingController<AnyView>?

        @discardableResult
        func install(from view: NSView) -> Bool {
            guard let window = view.window else { return false }

            if let hosting, installedWindow === window {
                hosting.rootView = rootView
                hosting.view.frame.size = hosting.view.fittingSize
                return true
            }

            let hosting = NSHostingController(rootView: rootView)
            hosting.view.frame.size = hosting.view.fittingSize

            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = .trailing
            accessory.view = hosting.view
            window.addTitlebarAccessoryViewController(accessory)

            self.hosting = hosting
            self.installedWindow = window
            return true
        }
    }
}
