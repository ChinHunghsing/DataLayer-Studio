import SwiftUI

/// 对表偏移的毫秒级输入。字段只在当前活动片段仍有拍摄时间对表基准时可用。
struct TimelineAlignmentOffsetField: View {
    @ObservedObject var model: StudioModel
    let clipID: String
    var showsLabel = true

    @EnvironmentObject private var localization: LocalizationStore

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

            IntegerTextField(
                title: localization.string("timeline.alignment.offset"),
                value: value ?? 0,
                range: -86_400_000...86_400_000,
                width: 88
            ) { milliseconds in
                model.setTimelineAlignmentOffsetMilliseconds(clipID: clipID, milliseconds: milliseconds)
            }

            Text(localization.string("timecode.milliseconds"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
