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
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text(step)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .background(ShellStyle.accentSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(ShellStyle.accentStroke, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Label(title, systemImage: systemImage)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
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
            .padding(.vertical, 1)
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
        .padding(9)
        .shellGroupSurface(cornerRadius: 9)
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

/// A pooled list of imported media of one kind (videos or activities). Empty shows an import row;
/// otherwise it lists each asset (timeline references highlighted, unused sources removable) with
/// an "add more" button.
struct MediaPoolList: View {
    var kindTitle: String
    var placeholder: String
    var systemImage: String
    var assets: [MediaAsset]
    var selectedID: String?
    var inUseIDs: Set<String>
    var offlineReasons: [String: TimelineAssetOfflineReason] = [:]
    var addTitle: String
    var select: (String) -> Void
    var remove: (String) -> Void
    var relink: ((String) -> Void)? = nil
    var appendToTimeline: ((String) -> Void)? = nil
    var timelineDragPayload: ((MediaAsset) -> String)? = nil
    var add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if assets.isEmpty {
                FilePickRow(
                    title: kindTitle,
                    subtitle: placeholder,
                    systemImage: systemImage,
                    isLoaded: false,
                    action: add
                )
            } else {
                ForEach(assets) { asset in
                    MediaPoolRow(
                        asset: asset,
                        systemImage: systemImage,
                        isInUse: inUseIDs.contains(asset.id),
                        isSelected: asset.id == selectedID,
                        offlineReason: offlineReasons[asset.id],
                        select: { select(asset.id) },
                        remove: { remove(asset.id) },
                        relink: relink.map { relink in { relink(asset.id) } },
                        appendToTimeline: appendToTimeline.map { append in { append(asset.id) } },
                        timelineDragPayload: timelineDragPayload?(asset)
                    )
                }

                Button(action: add) {
                    Label(addTitle, systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 2)
            }
        }
    }
}

struct MediaPoolRow: View {
    var asset: MediaAsset
    var systemImage: String
    var isInUse: Bool
    var isSelected: Bool
    var offlineReason: TimelineAssetOfflineReason? = nil
    var select: () -> Void
    var remove: () -> Void
    var relink: (() -> Void)? = nil
    var appendToTimeline: (() -> Void)? = nil
    var timelineDragPayload: String? = nil
    @EnvironmentObject private var localization: LocalizationStore

    private var isOffline: Bool { offlineReason != nil }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: isOffline ? (relink ?? select) : select) {
                HStack(spacing: 11) {
                    ShellIconTile(systemImage: isOffline ? "exclamationmark.triangle.fill" : systemImage, isActive: isInUse && !isOffline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(offlineReason.map { localization.string($0.localizationKey) } ?? subtitle)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if isOffline {
                        ShellStatusChip(localization.string("mediapool.offline"), systemImage: "exclamationmark.triangle", kind: .pending)
                    } else if isInUse {
                        ShellStatusChip(localization.string("mediapool.inUse"), systemImage: "checkmark", kind: .active)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOffline, let relink {
                Button(action: relink) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help(localization.string("mediapool.relink"))
            } else if let appendToTimeline {
                Button(action: appendToTimeline) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .foregroundStyle(.secondary.opacity(0.75))
                }
                .buttonStyle(.borderless)
                .help(localization.string("mediapool.addToTimeline"))
            }

            if !isInUse {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary.opacity(0.55))
                }
                .buttonStyle(.borderless)
                .help(localization.string("mediapool.remove"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .padding(9)
        .shellGroupSurface(cornerRadius: 9)
        .overlay {
            if isInUse {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(ShellStyle.accentStroke, lineWidth: 1)
            }
        }
        .modifier(OptionalTextDragModifier(payload: isOffline ? nil : timelineDragPayload))
    }

    private var subtitle: String {
        var parts = [Self.formatDuration(asset.duration)]
        if let width = asset.width, let height = asset.height {
            parts.append("\(width)×\(height)")
        }
        return parts.joined(separator: " · ")
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct OptionalTextDragModifier: ViewModifier {
    var payload: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let payload {
            content.onDrag {
                NSItemProvider(object: payload as NSString)
            }
        } else {
            content
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
        .padding(9)
        .shellGroupSurface(cornerRadius: 9)
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

private enum SidebarFormMetrics {
    static let labelWidth: CGFloat = 94
    static let shortSuffixWidth: CGFloat = 34
}
