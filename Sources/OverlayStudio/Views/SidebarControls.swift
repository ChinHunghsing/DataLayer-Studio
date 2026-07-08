import Foundation
import SwiftUI
import OverlayCore

struct SidebarWorkflowSection<Content: View>: View {
    var step: String
    var title: String
    var subtitle: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(step)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(ShellStyle.tileFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarSubsectionHeader: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct SidebarDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 2)
    }
}

struct FilePickRow: View {
    enum Accessory {
        /// 素材行：已载入 / 待选 状态芯片
        case status
        /// 目标行：已设置显示对勾，否则显示 chevron
        case disclosure
    }

    var title: String
    var subtitle: String
    var systemImage: String
    var isLoaded: Bool
    var accessory: Accessory = .status
    var action: () -> Void
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ShellIconTile(systemImage: systemImage, isActive: isLoaded)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                accessoryView
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .shellGroupSurface(cornerRadius: 8)
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .status:
            if isLoaded {
                ShellStatusChip(localization.string("shell.loaded"), systemImage: "checkmark", kind: .active)
            } else {
                ShellStatusChip(localization.string("shell.pending"), kind: .pending)
            }
        case .disclosure:
            Image(systemName: isLoaded ? "checkmark.circle.fill" : "chevron.right")
                .foregroundStyle(isLoaded ? Color.accentColor : Color.secondary.opacity(0.65))
        }
    }
}

struct SidebarStepperRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .frame(width: SidebarFormMetrics.labelWidth, alignment: .leading)

            Text("\(value)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)

            Spacer(minLength: 8)

            Stepper(title, value: $value, in: range)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarControl<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LayoutPresetRow: View {
    var preset: LayoutPreset
    var isDefault: Bool
    var apply: () -> Void
    var makeDefault: () -> Void
    var delete: () -> Void
    @Environment(\.locale) private var locale
    @EnvironmentObject private var localization: LocalizationStore
    @State private var isConfirmingApply = false
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if isDefault {
                        Text(localization.string("preset.default"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                Text(localization.string("preset.createdAt", formattedCreatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isConfirmingApply = true
            } label: {
                Label(localization.string("preset.apply"), systemImage: "tray.and.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .help(localization.string("preset.applyHelp"))

            Button(action: makeDefault) {
                Label(localization.string("preset.setDefault"), systemImage: isDefault ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
            }
            .help(localization.string("preset.setDefaultHelp"))
            .disabled(isDefault)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label(localization.string("preset.delete"), systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help(localization.string("preset.deleteHelp"))
        }
        .buttonStyle(.borderless)
        .padding(10)
        .shellGroupSurface(cornerRadius: 8)
        .confirmationDialog(
            localization.string("preset.applyDialogTitle"),
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button(localization.string("preset.applyNamed", preset.name), role: .destructive, action: apply)
            Button(localization.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(localization.string("preset.applyDialogMessage"))
        }
        .confirmationDialog(
            localization.string("preset.deleteDialogTitle"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(localization.string("preset.deleteNamed", preset.name), role: .destructive, action: delete)
            Button(localization.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(localization.string("preset.deleteDialogMessage"))
        }
    }

    private var formattedCreatedAt: String {
        preset.createdAt.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
                .second()
                .locale(locale)
        )
    }
}

struct NumberField: View {
    var title: String
    var suffix: String
    @Binding var value: Double
    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .frame(width: SidebarFormMetrics.labelWidth, alignment: .leading)
            TextField(title, text: $draftText)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 96, maxWidth: .infinity)
                .focused($isFocused)
                .onSubmit(commitDraft)
            Text(suffix)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: SidebarFormMetrics.shortSuffixWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            draftText = NumberTextFormatter.formatDouble(value)
        }
        .onChange(of: value) { _ in
            guard !isFocused else { return }
            draftText = NumberTextFormatter.formatDouble(value)
        }
        .onChange(of: isFocused) { focused in
            if focused {
                draftText = NumberTextFormatter.formatDouble(value)
            } else {
                commitDraft()
            }
        }
    }

    private func commitDraft() {
        guard let parsed = NumberTextFormatter.parseDouble(draftText) else {
            draftText = NumberTextFormatter.formatDouble(value)
            return
        }
        value = parsed
        draftText = NumberTextFormatter.formatDouble(value)
    }
}

struct NumberIntField: View {
    var title: String
    var suffix: String?
    @Binding var value: Int
    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    init(title: String, suffix: String? = nil, value: Binding<Int>) {
        self.title = title
        self.suffix = suffix
        self._value = value
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .frame(width: SidebarFormMetrics.labelWidth, alignment: .leading)
            TextField(title, text: $draftText)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 96, maxWidth: .infinity)
                .focused($isFocused)
                .onSubmit(commitDraft)
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: SidebarFormMetrics.longSuffixWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            draftText = NumberTextFormatter.formatInt(value)
        }
        .onChange(of: value) { _ in
            guard !isFocused else { return }
            draftText = NumberTextFormatter.formatInt(value)
        }
        .onChange(of: isFocused) { focused in
            if focused {
                draftText = NumberTextFormatter.formatInt(value)
            } else {
                commitDraft()
            }
        }
    }

    private func commitDraft() {
        guard let parsed = NumberTextFormatter.parseInt(draftText) else {
            draftText = NumberTextFormatter.formatInt(value)
            return
        }
        value = parsed
        draftText = NumberTextFormatter.formatInt(value)
    }
}

struct CompactNumberIntField: View {
    var title: String
    var suffix: String
    @Binding var value: Int
    @State private var draftText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                TextField(title, text: $draftText)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 92)
                    .focused($isFocused)
                    .onSubmit(commitDraft)

                Text(suffix)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: SidebarFormMetrics.shortSuffixWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            draftText = NumberTextFormatter.formatInt(value)
        }
        .onChange(of: value) { _ in
            guard !isFocused else { return }
            draftText = NumberTextFormatter.formatInt(value)
        }
        .onChange(of: isFocused) { focused in
            if focused {
                draftText = NumberTextFormatter.formatInt(value)
            } else {
                commitDraft()
            }
        }
    }

    private func commitDraft() {
        guard let parsed = NumberTextFormatter.parseInt(draftText) else {
            draftText = NumberTextFormatter.formatInt(value)
            return
        }
        value = parsed
        draftText = NumberTextFormatter.formatInt(value)
    }
}

private enum SidebarFormMetrics {
    static let labelWidth: CGFloat = 94
    static let shortSuffixWidth: CGFloat = 34
    static let longSuffixWidth: CGFloat = 54
}
