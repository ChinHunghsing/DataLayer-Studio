import SwiftUI

/// 标题栏右上角的“输出”按钮，点击弹出输出面板（设置 + 摘要 + 导出动作）。
struct OutputToolbarButton: View {
    @ObservedObject var model: StudioModel
    var action: () -> Void
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward")
                    .font(.subheadline.weight(.bold))
                Text(localization.string("toolbar.output"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isExporting)
        .help(localization.string("toolbar.output"))
        .accessibilityLabel(localization.string("toolbar.output"))
    }
}
