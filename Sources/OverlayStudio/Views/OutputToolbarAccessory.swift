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
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(model.isExporting)
        .help(localization.string("toolbar.output"))
        .sheet(isPresented: $isPresented) {
            OutputPanelView(model: model)
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
        }
        .onChange(of: model.isExporting) { isExporting in
            if isExporting {
                isPresented = false
            }
        }
    }
}
