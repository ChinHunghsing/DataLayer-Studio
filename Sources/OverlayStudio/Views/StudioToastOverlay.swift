import SwiftUI

struct StudioToastOverlay: View {
    var toasts: [StudioToast]
    var dismiss: (UUID) -> Void
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: ShellStyle.spacing2) {
            ForEach(toasts) { toast in
                HStack(spacing: ShellStyle.spacing3) {
                    Image(systemName: systemImage(for: toast.kind))
                        .foregroundStyle(color(for: toast.kind))
                    Text(toast.message)
                        .font(.callout)
                        .lineLimit(3)
                    Button {
                        dismiss(toast.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(localization.string("toast.dismiss"))
                }
                .padding(.horizontal, ShellStyle.spacing3)
                .padding(.vertical, 10)
                .frame(maxWidth: 360, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ShellStyle.largeRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ShellStyle.largeRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.18), value: toasts)
    }

    private func systemImage(for kind: StudioToast.Kind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: StudioToast.Kind) -> Color {
        switch kind {
        case .success: .green
        case .info: .accentColor
        case .warning: .orange
        }
    }
}
