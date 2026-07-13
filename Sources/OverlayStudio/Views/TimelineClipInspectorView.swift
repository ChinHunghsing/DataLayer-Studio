import Foundation
import SwiftUI
import OverlayCore

struct TimelineClipInspectorHeader: View {
    @ObservedObject var model: StudioModel
    let clip: TimelineClip
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        let asset = model.selectedTimelineClipAsset

        HStack(alignment: .center, spacing: 12) {
            Image(systemName: asset?.kind == .video ? "film" : "waveform.path.ecg")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(ShellStyle.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(localization.string("timelineClip.inspector.title"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(asset?.displayName ?? clip.assetID)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
    }
}

struct TimelineClipInspectorView: View {
    @ObservedObject var model: StudioModel
    let clip: TimelineClip
    @EnvironmentObject private var localization: LocalizationStore
    @SceneStorage("inspector.timelineSyncExpanded") private var isAdvancedAlignmentExpanded = false

    private var currentClip: TimelineClip {
        model.selectedTimelineClip ?? clip
    }

    private var currentAsset: MediaAsset? {
        model.selectedTimelineClipAsset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ShellStyle.spacing3) {
            if !model.selectedTimelineClipIsEditable {
                TimelineClipNotice(
                    title: localization.string("timelineClip.inspector.readOnlyTitle"),
                    message: localization.string("timelineClip.inspector.readOnlyMessage")
                )
            }

            section(title: localization.string("timelineClip.inspector.timing"), systemImage: "timeline.selection") {
                TimecodeField(
                    title: localization.string("timelineClip.inspector.timelineStart"),
                    value: timelineStartBinding,
                    range: timelineStartRange
                )
                .disabled(!model.selectedTimelineClipIsEditable)

                TimelineClipTimeValue(
                    title: localization.string("timelineClip.inspector.duration"),
                    value: currentClip.duration
                )
            }

            if currentAsset?.kind == .activity {
                section(title: localization.string("timelineClip.inspector.activity"), systemImage: "figure.run") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localization.string("sidebar.distanceUnit"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Picker(localization.string("sidebar.distanceUnit"), selection: distanceUnitBinding) {
                            ForEach(OverlayDistanceUnit.allCases) { unit in
                                Text(localization.string(unit.localizationKey)).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .disabled(!model.selectedTimelineClipIsEditable)

                DisclosureGroup(isExpanded: $isAdvancedAlignmentExpanded) {
                    VStack(alignment: .leading, spacing: ShellStyle.spacing3) {
                        if model.wallClockAlignmentMarkerTime != nil {
                            Label(localization.string("timeline.alignment.wallClock"), systemImage: "clock.badge.checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if model.timelineAlignmentOffsetMilliseconds(for: currentClip.id) != nil {
                            TimelineAlignmentOffsetField(model: model, clipID: currentClip.id)
                                .disabled(!model.selectedTimelineClipIsEditable)
                        }

                        Button {
                            model.reapplyWallClockAutoSync()
                        } label: {
                            Label(localization.string("timeline.alignment.reapply"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            !model.canReapplyWallClockAutoSync
                                || model.timelineAlignmentOffsetMilliseconds(for: currentClip.id) == nil
                        )
                        .help(localization.string("timeline.alignment.reapplyHelp"))
                    }
                    .padding(.top, ShellStyle.spacing2)
                } label: {
                    Label(localization.string("timelineClip.inspector.advancedAlignment"), systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(ShellStyle.spacing3)
                .background(ShellStyle.controlFill, in: RoundedRectangle(cornerRadius: ShellStyle.largeRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ShellStyle.largeRadius, style: .continuous)
                        .strokeBorder(ShellStyle.cardStroke, lineWidth: 1)
                )
                .controlSize(.small)
            }
        }
    }

    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ShellStyle.spacing3) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            content()
        }
        .padding(ShellStyle.spacing3)
        .background(ShellStyle.controlFill, in: RoundedRectangle(cornerRadius: ShellStyle.largeRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ShellStyle.largeRadius, style: .continuous)
                .strokeBorder(ShellStyle.cardStroke, lineWidth: 1)
        )
    }

    private var distanceUnitBinding: Binding<OverlayDistanceUnit> {
        Binding(
            get: { model.distanceUnitForCurrentSelection },
            set: { model.setDistanceUnitForCurrentSelection($0) }
        )
    }

    private var timelineStartBinding: Binding<Double> {
        Binding(
            get: { currentClip.timelineStart },
            set: { model.setTimelineClipTiming(id: currentClip.id, timelineStart: $0) }
        )
    }

    private var timelineStartRange: ClosedRange<Double> {
        0...max(86_400, model.currentTimelineProject.duration + currentClip.duration)
    }

    static func formatTimecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00.000" }

        let totalMilliseconds = Int((seconds * 1_000).rounded())
        let milliseconds = totalMilliseconds % 1_000
        let totalSeconds = totalMilliseconds / 1_000
        let secondsComponent = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutesComponent = totalMinutes % 60
        let hours = totalMinutes / 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d.%03d",
                hours,
                minutesComponent,
                secondsComponent,
                milliseconds
            )
        }
        return String(
            format: "%02d:%02d.%03d",
            minutesComponent,
            secondsComponent,
            milliseconds
        )
    }
}

private struct TimelineClipNotice: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct TimelineClipTimeValue: View {
    let title: String
    let value: TimeInterval

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 90, alignment: .leading)

            Spacer(minLength: 12)

            Text(TimelineClipInspectorView.formatTimecode(value))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}
