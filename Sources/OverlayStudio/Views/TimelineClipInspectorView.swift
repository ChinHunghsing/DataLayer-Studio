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

    private var currentClip: TimelineClip {
        model.selectedTimelineClip ?? clip
    }

    private var currentAsset: MediaAsset? {
        model.selectedTimelineClipAsset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.selectedTimelineClipIsEditable {
                TimelineClipNotice(
                    title: localization.string("timelineClip.inspector.readOnlyTitle"),
                    message: localization.string("timelineClip.inspector.readOnlyMessage")
                )
            }

            section(title: localization.string("timelineClip.inspector.timing"), systemImage: "timeline.selection") {
                TimelineClipNumberField(
                    title: localization.string("timelineClip.inspector.timelineStart"),
                    value: timingBinding(.timelineStart),
                    unit: "s"
                )

                TimelineClipNumberField(
                    title: localization.string("timelineClip.inspector.sourceIn"),
                    value: timingBinding(.sourceIn),
                    unit: "s"
                )

                TimelineClipNumberField(
                    title: localization.string("timelineClip.inspector.duration"),
                    value: timingBinding(.duration),
                    unit: "s"
                )
            }
            .disabled(!model.selectedTimelineClipIsEditable)

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

                    HStack(spacing: 10) {
                        Button {
                            model.setTimelineClipLayout(id: clip.id, model.layout)
                        } label: {
                            Label(localization.string("timelineClip.inspector.useCurrentLayout"), systemImage: "square.on.square")
                        }

                        Button {
                            model.setTimelineClipLayout(id: clip.id, nil)
                        } label: {
                            Label(localization.string("timelineClip.inspector.useDefaultLayout"), systemImage: "arrow.uturn.backward")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!model.selectedTimelineClipIsEditable)
            }
        }
    }

    private func section<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func timingBinding(_ field: TimelineClipTimingField) -> Binding<Double> {
        Binding(
            get: {
                switch field {
                case .timelineStart:
                    return currentClip.timelineStart
                case .sourceIn:
                    return currentClip.sourceIn
                case .duration:
                    return currentClip.duration
                }
            },
            set: { value in
                switch field {
                case .timelineStart:
                    model.setTimelineClipTiming(id: clip.id, timelineStart: value)
                case .sourceIn:
                    model.setTimelineClipTiming(id: clip.id, sourceIn: value)
                case .duration:
                    model.setTimelineClipTiming(id: clip.id, duration: value)
                }
            }
        )
    }

    private var distanceUnitBinding: Binding<OverlayDistanceUnit> {
        Binding(
            get: {
                currentClip.distanceUnit ?? model.distanceUnit
            },
            set: { unit in
                model.setTimelineClipDistanceUnit(id: clip.id, unit)
            }
        )
    }
}

private enum TimelineClipTimingField {
    case timelineStart
    case sourceIn
    case duration
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

private struct TimelineClipNumberField: View {
    let title: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 90, alignment: .leading)

            TextField(
                title,
                value: $value,
                format: .number.precision(.fractionLength(3))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(unit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
        }
    }
}
