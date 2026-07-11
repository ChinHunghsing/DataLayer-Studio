import SwiftUI

struct StudioCommandActions {
    var isExporting: Bool
    var canExport: Bool
    var canPlayPreview: Bool
    var isPlayingPreview: Bool
    var debugLogCount: Int
    var canMarkSportStart: Bool
    var canMoveSelectionForward: Bool
    var canMoveSelectionBackward: Bool
    var canSplitTimelineClips: Bool
    var canDeleteTimelineClip: Bool
    var canJumpToTimelineEditPoints: Bool
    var canUndo: Bool
    var canRedo: Bool
    var chooseVideo: () -> Void
    var chooseFIT: () -> Void
    var openTimelineProject: () -> Void
    var saveTimelineProject: () -> Void
    var export: () -> Void
    var cancelExport: () -> Void
    var refreshPreview: () -> Void
    var togglePlayback: () -> Void
    var markSportStart: () -> Void
    var moveSelectionForward: () -> Void
    var moveSelectionBackward: () -> Void
    var splitTimelineClips: () -> Void
    var deleteTimelineClip: () -> Void
    var rippleDeleteTimelineClip: () -> Void
    var jumpToPreviousEditPoint: () -> Void
    var jumpToNextEditPoint: () -> Void
    var undo: () -> Void
    var redo: () -> Void
    var showDebugConsole: () -> Void
    var copyDebugLog: () -> Void
    var clearDebugLog: () -> Void
}

struct PreviewCommandActions {
    var isFullscreen: Bool
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var resetZoom: () -> Void
    var toggleFullscreen: () -> Void
}

private struct PreviewCommandActionsKey: FocusedValueKey {
    typealias Value = PreviewCommandActions
}

extension FocusedValues {
    var previewCommandActions: PreviewCommandActions? {
        get { self[PreviewCommandActionsKey.self] }
        set { self[PreviewCommandActionsKey.self] = newValue }
    }

    var studioCommandActions: StudioCommandActions? {
        get { self[StudioCommandActionsKey.self] }
        set { self[StudioCommandActionsKey.self] = newValue }
    }
}

private struct StudioCommandActionsKey: FocusedValueKey {
    typealias Value = StudioCommandActions
}
