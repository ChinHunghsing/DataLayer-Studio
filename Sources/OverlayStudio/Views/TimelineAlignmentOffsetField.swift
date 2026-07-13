import SwiftUI

/// 对表偏移的毫秒级输入。字段只在当前活动片段仍有拍摄时间对表基准时可用。
struct TimelineAlignmentOffsetField: View {
    @ObservedObject var model: StudioModel
    let clipID: String
    var showsLabel = true

    @EnvironmentObject private var localization: LocalizationStore
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var value: Int? {
        model.timelineAlignmentOffsetMilliseconds(for: clipID)
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsLabel {
                Text(localization.string("timeline.alignment.offset"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 90, alignment: .leading)
            }

            TextField(localization.string("timeline.alignment.offset"), text: $draft)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 88)
                .focused($isFocused)
                .onSubmit(commit)

            Text(localization.string("timecode.milliseconds"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { refreshDraft() }
        .onChange(of: value) { _ in
            guard !isFocused else { return }
            refreshDraft()
        }
        .onChange(of: isFocused) { focused in
            if focused {
                refreshDraft()
            } else {
                commit()
            }
        }
    }

    private func refreshDraft() {
        draft = NumberTextFormatter.formatInt(value ?? 0)
    }

    private func commit() {
        guard let milliseconds = NumberTextFormatter.parseInt(draft),
              (-86_400_000...86_400_000).contains(milliseconds) else {
            refreshDraft()
            return
        }
        model.setTimelineAlignmentOffsetMilliseconds(clipID: clipID, milliseconds: milliseconds)
        refreshDraft()
    }
}
