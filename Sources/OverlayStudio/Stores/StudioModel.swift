import AppKit
import AVFoundation
import CoreImage
import Darwin
import Foundation
import OSLog
import OverlayCore
import OverlayStudioKit
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

private let studioDebugLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "run.libo.datalayer-studio",
    category: "Debug"
)

struct SourceLoadFailure: Equatable {
    var url: URL
    var messageKey: String
    var detail: String
}

enum LayoutPresetSyncStatus: Equatable {
    case localOnly
    case ready
    case uploadRequested(Date)
    case receivedUpdate(Date)
}

private final class PlayerTimeObserver {
    private weak var player: AVPlayer?
    private var token: Any?

    init(player: AVPlayer, token: Any) {
        self.player = player
        self.token = token
    }

    deinit {
        remove()
    }

    func remove() {
        guard let token else { return }
        player?.removeTimeObserver(token)
        self.token = nil
        player = nil
    }
}

private struct TimelinePreviewOverlayLayer {
    var series: TelemetrySeries
    var timeSync: TelemetryTimeSync
    var layout: OverlayLayout
    var distanceUnit: OverlayDistanceUnit
}

private struct TimelinePreviewSnapshot {
    var videoURL: URL?
    var videoTime: TimeInterval
    var overlayLayers: [TimelinePreviewOverlayLayer]
}

private struct TimelineClipboardItem {
    var trackID: String
    var clip: TimelineClip
}

enum TimelinePendingAction: Equatable {
    case selectVideoAsset(id: String)
    case selectActivityAsset(id: String)
    case removeVideoAsset(id: String)
    case removeActivityAsset(id: String)
    case openTimelineProject
    case openTimelineProjectFile(URL)
    case newTimelineProject(layoutPresetID: String?, mediaURLs: [URL])
    case closeWindow
}

enum TimelineAssetOfflineReason: String, Equatable {
    case fileMissing
    case permissionDenied
    case unreadableMedia
    case invalidFormat

    var localizationKey: String {
        "mediapool.offline.\(rawValue)"
    }
}

@MainActor
final class StudioModel: ObservableObject {
    static let playerTimeObserverInterval: TimeInterval = 1.0 / 12.0
    static let playbackOverlayRefreshInterval: TimeInterval = 0.20
    static let overlayPlaybackTickInterval: TimeInterval = 1.0 / 30.0
    static let scrubInteractionHoldInterval: TimeInterval = 0.16
    static let previewResizeRefreshDelay: TimeInterval = 0.16
    nonisolated static let gaugeDragMaximumPreviewRenderDimension: CGFloat = 1_600

    @Published var videoURL: URL? {
        didSet { rebuildCurrentTimelineProject() }
    }
    @Published var fitURL: URL? {
        didSet { rebuildCurrentTimelineProject() }
    }
    @Published var outputURL: URL?
    @Published var metadata: VideoMetadata?
    @Published var series: TelemetrySeries?

    /// Project media pool (timeline groundwork). Imported sources are kept here so a project can
    /// hold multiple videos and activities; the currently loaded `videoURL`/`fitURL` is the active one.
    @Published var videoAssets: [MediaAsset] = [] {
        didSet { rebuildCurrentTimelineProject() }
    }
    @Published var activityAssets: [MediaAsset] = [] {
        didSet { rebuildCurrentTimelineProject() }
    }
    @Published private(set) var offlineTimelineAssetReasons: [String: TimelineAssetOfflineReason] = [:]
    var offlineTimelineAssetIDs: Set<String> {
        Set(offlineTimelineAssetReasons.keys)
    }
    @Published private(set) var videoWaveformPeaksByAssetID: [String: [Float]] = [:]
    @Published private(set) var timeline = TimelineProject(
        outputWidth: 1920,
        outputHeight: 1080,
        framesPerSecond: 30,
        distanceUnit: .kilometers
    ) {
        didSet {
            updateTimelineDirtyState()
            updateDefaultExportRangeForTimelineChange()
            scheduleTimelinePlayerRefreshIfNeeded()
        }
    }
    @Published private(set) var hasUnsavedTimelineChanges = false
    @Published private(set) var pendingTimelineAction: TimelinePendingAction?
    @Published private(set) var confirmedWindowCloseGeneration = 0
    @Published private(set) var currentTimelineProjectURL: URL?
    @Published private(set) var recentTimelineProjects: [RecentTimelineProject] = []
    @Published private(set) var studioSessionRevision = 0
    @Published private(set) var studioEntryErrorMessage: String?

    @Published var outputWidth = 1920 {
        didSet { rebuildCurrentTimelineProject() }
    }
    @Published var outputHeight = 1080 {
        didSet { rebuildCurrentTimelineProject() }
    }
    @Published var outputFPS = 30.0 {
        didSet { rebuildCurrentTimelineProject() }
    }
    @Published var sourceDuration: TimeInterval = 0
    @Published var exportTrimStartSeconds: TimeInterval = 0 {
        didSet { updateTimelineProjectExportSettings() }
    }
    @Published var exportTrimEndSeconds: TimeInterval = 0 {
        didSet { updateTimelineProjectExportSettings() }
    }
    @Published var activityTrim: ActivityTrim = .none {
        didSet { updateTimelineProjectExportSettings() }
    }
    @Published var bitRateKbps = 12_000 {
        didSet { updateTimelineProjectExportSettings() }
    }
    @Published var exportMode: OverlayExportMode = .overlay {
        didSet {
            guard oldValue != exportMode else { return }
            normalizeCodecForExportMode()
            refreshSuggestedOutputURLForCurrentSource()
            updateTimelineProjectExportSettings()
        }
    }
    @Published var codec: OverlayVideoCodec = .hevcAlpha {
        didSet { updateTimelineProjectExportSettings() }
    }
    /// DaVinci-style render scope: one file for the whole export range, or one file per clip.
    @Published var exportRenderScope: ExportRenderScope = .singleClip {
        didSet {
            if oldValue != exportRenderScope {
                outputDirectoryWasExplicitlySelected = false
                outputSecurityScopedURL = nil
            }
            updateTimelineProjectExportSettings()
        }
    }
    /// Horizontal timeline zoom (1 = fit the whole timeline in the lane width).
    @Published private(set) var timelineZoom: Double = 1
    /// Incremented when edit-point navigation asks the timeline viewport to reveal the playhead.
    @Published private(set) var timelinePlayheadFocusGeneration = 0

    static let timelineZoomRange: ClosedRange<Double> = 1...16

    func setTimelineZoom(_ value: Double) {
        let clamped = min(
            Self.timelineZoomRange.upperBound,
            max(Self.timelineZoomRange.lowerBound, value.isFinite ? value : 1)
        )
        guard abs(clamped - timelineZoom) > 1e-9 else { return }
        timelineZoom = clamped
    }
    @Published var distanceUnit: OverlayDistanceUnit = .kilometers {
        didSet {
            persistStudioPreferences()
            rebuildCurrentTimelineProject()
        }
    }

    @Published var syncMode: SyncMode = .syncPoint {
        didSet { updateTimelineForSyncChange() }
    }
    @Published var offsetSeconds = 0.0 {
        didSet { updateTimelineForSyncChange() }
    }
    @Published var fitStartSeconds = 0.0 {
        didSet { updateTimelineForSyncChange() }
    }
    @Published var syncVideoSeconds = 0.0 {
        didSet { updateTimelineForSyncChange() }
    }
    @Published var syncFITSeconds = 0.0 {
        didSet { updateTimelineForSyncChange() }
    }

    @Published var previewTime: TimeInterval = 0
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var backgroundImage: CGImage?
    @Published var overlayImage: CGImage?
    @Published var layout: OverlayLayout {
        didSet { rebuildCurrentTimelineProject() }
    }
    private var layoutEditingTimelineClipID: String?
    @Published private(set) var selectedElementIDs: Set<String> = []
    @Published private(set) var selectedElementPart: OverlayElementPart?
    @Published var selectedElementID: String? {
        didSet {
            if oldValue != selectedElementID, selectedElementPart != nil {
                selectedElementPart = nil
            }
            if let selectedElementID {
                if !selectedElementIDs.contains(selectedElementID) {
                    selectedElementIDs = [selectedElementID]
                }
            } else if !selectedElementIDs.isEmpty {
                selectedElementIDs = []
            }
        }
    }
    @Published private(set) var selectedMediaAssetID: String?
    @Published private(set) var selectedTimelineClipIDs: Set<String> = []
    @Published private var timelineClipboard: [TimelineClipboardItem] = []
    @Published var selectedTimelineClipID: String? {
        didSet {
            if let selectedTimelineClipID {
                if !selectedTimelineClipIDs.contains(selectedTimelineClipID) {
                    selectedTimelineClipIDs = [selectedTimelineClipID]
                }
            } else if !selectedTimelineClipIDs.isEmpty {
                selectedTimelineClipIDs = []
            }
        }
    }
    @Published var layoutPresets: [LayoutPreset]
    @Published var defaultLayoutPresetID: String?
    @Published var layoutPresetSyncStatus: LayoutPresetSyncStatus = .localOnly
    @Published private(set) var userExportPresets: [ExportPreset] = []

    @Published var showGrid = false {
        didSet { persistStudioPreferences() }
    }
    @Published var canvasSafeAreaInsetPercent = StudioPreferenceState.default.safeAreaInsetPercent {
        didSet { persistStudioPreferences() }
    }

    @Published var status = AppLocalizer.currentString("status.chooseVideoAndFit")
    @Published private(set) var videoLoadFailure: SourceLoadFailure?
    @Published private(set) var fitLoadFailure: SourceLoadFailure?
    @Published var previewWarning: String?
    @Published var isExporting = false
    @Published private(set) var isWeatherExportConfirmationPresented = false
    @Published private(set) var isWeatherAPIKeyPromptPresented = false
    @Published var exportProgress = 0.0
    @Published private(set) var exportETASeconds: TimeInterval?
    @Published private(set) var lastExportedURL: URL?
    @Published private(set) var lastExportElapsedSeconds: TimeInterval?
    @Published private(set) var lastExportErrorMessage: String?
    @Published private(set) var lastExportWasCancelled = false
    @Published var openWeatherAPIKey = OpenWeatherKeyStore.load()
    @Published var weatherRefreshMessage: String?
    @Published var debugLogEntries: [DebugLogEntry] = []
    @Published private(set) var toasts: [StudioToast] = []

    private var resolvedLanguage = AppLocalizer.resolvedLanguage(for: AppLocalizer.storedSelection())
    private var statusMessage: (key: String, arguments: [CVarArg]) = ("status.chooseVideoAndFit", [])
    private let videoFrameService = VideoFrameService()
    private let previewRenderer = OverlayPreviewRenderer()
    private let openWeatherService: OpenWeatherService
    private let layoutPresetStore: LayoutPresetStore
    private let preferenceStore: StudioPreferenceStore
    private var layoutPresetCloudObserver: NSObjectProtocol?
    private var playerTimeObserver: PlayerTimeObserver?
    private var overlayPlaybackTimer: Timer?
    private var overlayPlaybackLastTick: Date?
    private var timelinePlayerRebuildTask: Task<Void, Never>?
    private var timelinePlayerBuildGeneration = 0
    private var timelinePlayerBuiltSignature: TimelinePlayerSignature?
    private var timelinePlayerItemReplacementGeneration = 0
    private var isReplacingTimelinePlayerItem = false
    private var previewRenderGeneration = 0
    private var videoLoadGeneration = 0
    private var fitLoadGeneration = 0
    private var mediaPoolImportGeneration = 0
    private var previewOverlayRenderSize: CGSize?
    private var lastOverlayRefresh = Date.distantPast
    private let maximumPreviewRenderDimension: CGFloat = 3_200
    private var previewRenderTask: Task<Void, Never>?
    private var pendingPreviewSizeRefreshTask: Task<Void, Never>?
    private var scrubInteractionTask: Task<Void, Never>?
    /// Smooth scrubbing: at most one AVPlayer seek is in flight; later drag events only record
    /// the newest target here and the in-flight completion catches up, instead of cancelling and
    /// re-issuing a seek on every input event (which stutters the main thread on large files).
    private weak var scrubSeekInFlightPlayer: AVPlayer?
    private var pendingScrubSeekSeconds: TimeInterval?
    private var isPreviewLiveResizing = false
    private var pendingPreviewLiveResizeSize: CGSize?
    private var scrubInteractionExpiresAt = Date.distantPast
    private var videoLoadTask: Task<Void, Never>?
    private var fitLoadTask: Task<Void, Never>?
    private var weatherLoadTask: Task<Void, Never>?
    private var videoWaveformLoadTasks: [String: Task<Void, Never>] = [:]
    private var pendingVideoTimelineImportIDs: [String] = []
    private var pendingActivityTimelineImportIDs: [String] = []
    /// Timeline Finder drops waiting for their asset to finish importing. Separate queues preserve
    /// Finder order even when metadata/parsing finishes out of order.
    private struct PositionedTimelineImport {
        var assetID: String
        var trackID: String?
        var timelineStart: TimeInterval?
    }
    private var pendingVideoPositionedTimelineImports: [PositionedTimelineImport] = []
    private var pendingActivityPositionedTimelineImports: [PositionedTimelineImport] = []
    private var pendingOverlayRefreshAfterCurrentRender = false
    private var pendingOverlayRefreshDisplaysIntermediateResult = false
    private var isScrubbingPreview = false
    private var isGaugeDragActive = false
    private var exportProgressSamples: [(date: Date, progress: Double)] = []
    private var singleSourceAlignmentIsPending = false
    private static let exportETASampleWindow: TimeInterval = 10
    private static let minimumExportTrimDuration: TimeInterval = 0.1
    weak var undoManager: UndoManager? {
        didSet { undoManager?.levelsOfUndo = 100 }
    }

    /// Undo/redo availability surfaced to the menu commands. Routing undo/redo through the model
    /// (instead of the responder-chain Edit menu) lets it fire whenever the window is key, so it no
    /// longer depends on which timeline track or clip currently holds keyboard focus.
    var canPerformUndo: Bool { !isExporting && (undoManager?.canUndo ?? false) }
    var canPerformRedo: Bool { !isExporting && (undoManager?.canRedo ?? false) }

    func performUndo() {
        guard canPerformUndo else { return }
        undoManager?.undo()
    }

    func performRedo() {
        guard canPerformRedo else { return }
        undoManager?.redo()
    }
    private var layoutUndoTransaction: (layout: OverlayLayout, selectedElementID: String?, actionKey: String)?
    private var lastCoalescedLayoutUndo: (actionKey: String, date: Date)?
    private static let layoutUndoCoalescingInterval: TimeInterval = 0.8
    private var lastCoalescedTimelineUndo: (actionKey: String, date: Date)?
    private var pendingRelinkUndoSnapshots: [String: TimelineMediaUndoSnapshot] = [:]
    private var pendingSourceReplacementUndoSnapshot: TimelineMediaUndoSnapshot?
    private var pendingSourceReplacementKind: MediaAsset.Kind?
    private var exportTask: Task<Void, Never>?
    private var exportCancellationToken: ExportCancellationToken?
    private var outputURLWasAutoGenerated = false
    private var outputDirectoryWasExplicitlySelected = false
    private var outputSecurityScopedURL: URL?
    private var exportTrimRangeWasManuallyEdited = false
    private var timelineUsesSingleSourceMigration = true
    private var isRestoringTimelineSourceMatchPoint = false
    private var activitySeriesByAssetID: [String: TelemetrySeries] = [:]
    /// Sport per activity asset (id = file path). File-level metadata, kept out of the hot
    /// `TelemetrySeries` value type and restored together with media-pool undo snapshots.
    private var activitySportByAssetID: [String: TelemetrySport] = [:]
    private var timelineSecurityScopedURLs: [URL] = []
    private var currentTimelineProjectSecurityScopedURL: URL?
    private var cleanTimelineSnapshot: TimelineProject?
    private var allowsNextWindowClose = false
    private var isApplyingTimelineProject = false
    private var isUpdatingTimelineProjectExportSettings = false
    private let recentTimelineProjectStore: RecentTimelineProjectStore

    init(
        layoutPresetStore: LayoutPresetStore = LayoutPresetStore(),
        preferenceStore: StudioPreferenceStore = StudioPreferenceStore(),
        openWeatherService: OpenWeatherService = OpenWeatherService(),
        recentTimelineProjectStore: RecentTimelineProjectStore = RecentTimelineProjectStore()
    ) {
        self.layoutPresetStore = layoutPresetStore
        self.preferenceStore = preferenceStore
        self.openWeatherService = openWeatherService
        self.recentTimelineProjectStore = recentTimelineProjectStore
        self.recentTimelineProjects = recentTimelineProjectStore.load()
        let presetState = layoutPresetStore.loadIncludingSharedAppDomains()
        let preferenceState = preferenceStore.load()
        let validDefaultPresetID = presetState.presets.contains { $0.id == presetState.defaultPresetID } ? presetState.defaultPresetID : nil
        self.layoutPresets = presetState.presets
        self.defaultLayoutPresetID = validDefaultPresetID
        self.layout = presetState.presets.first { $0.id == validDefaultPresetID }?.layout.sanitized ?? .default
        self.selectedElementID = Self.firstSelectableElementID(in: layout)
        self.distanceUnit = preferenceState.distanceUnit
        self.showGrid = preferenceState.showGrid
        self.canvasSafeAreaInsetPercent = preferenceState.safeAreaInsetPercent
        self.userExportPresets = preferenceState.userExportPresets
        rebuildCurrentTimelineProject()
        markTimelineProjectClean()
        observeLayoutPresetCloudChanges()
    }

    deinit {
        undoManager?.removeAllActions(withTarget: self)
        if let layoutPresetCloudObserver {
            NotificationCenter.default.removeObserver(layoutPresetCloudObserver)
        }
        playerTimeObserver?.remove()
        videoLoadTask?.cancel()
        fitLoadTask?.cancel()
        weatherLoadTask?.cancel()
        videoWaveformLoadTasks.values.forEach { $0.cancel() }
        previewRenderTask?.cancel()
        pendingPreviewSizeRefreshTask?.cancel()
        scrubInteractionTask?.cancel()
        exportCancellationToken?.cancel()
        exportTask?.cancel()
        currentTimelineProjectSecurityScopedURL?.stopAccessingSecurityScopedResource()
        videoFrameService.clearCache()
    }

    var canPreview: Bool {
        series != nil
    }

    func canAddElement(kind: OverlayComponentID) -> Bool {
        guard let samples = series?.samples, !samples.isEmpty else { return true }

        func hasDouble(_ keyPath: KeyPath<TelemetrySample, Double?>) -> Bool {
            samples.contains { $0[keyPath: keyPath]?.isFinite == true }
        }

        func hasInt(_ keyPath: KeyPath<TelemetrySample, Int?>) -> Bool {
            samples.contains { $0[keyPath: keyPath] != nil }
        }

        func hasRoutePoint(_ sample: TelemetrySample) -> Bool {
            sample.latitude?.isFinite == true && sample.longitude?.isFinite == true
        }

        switch kind {
        case .speed, .pace:
            return hasDouble(\.speedMetersPerSecond) || hasDouble(\.distanceMeters)
        case .heartRate:
            return hasInt(\.heartRate)
        case .cadence:
            return hasInt(\.cadence)
        case .calories:
            return hasDouble(\.totalCalories)
        case .ascent:
            return hasDouble(\.totalAscentMeters)
        case .strideLength:
            return hasDouble(\.stepLengthMeters)
        case .power:
            return hasInt(\.powerWatts)
        case .verticalOscillation:
            return hasDouble(\.verticalOscillationCentimeters)
        case .groundContactTime:
            return hasDouble(\.groundContactTimeMilliseconds)
        case .groundContactTimePercent:
            return hasDouble(\.groundContactTimePercent)
        case .groundContactTimeBalance:
            return hasDouble(\.groundContactTimeBalancePercent)
        case .verticalRatio:
            return hasDouble(\.verticalRatioPercent)
        case .respirationRate:
            return hasDouble(\.respirationRateBreathsPerMinute)
        case .stepSpeedLoss:
            return hasDouble(\.stepSpeedLossPercent)
        case .formPower:
            return hasInt(\.formPowerWatts)
        case .airPower:
            return hasInt(\.airPowerWatts)
        case .legSpringStiffness:
            return hasDouble(\.legSpringStiffnessKilonewtonsPerMeter)
        case .weather:
            return true
        case .distance, .topProgress:
            return hasDouble(\.distanceMeters)
        case .route:
            return samples.contains(where: hasRoutePoint)
        case .timeDate:
            return true
        }
    }

    var canExport: Bool {
        exportReadinessMessage == nil
    }

    var hasExportResult: Bool {
        lastExportedURL != nil || lastExportErrorMessage != nil || lastExportWasCancelled
    }

    func canExport(as mode: OverlayExportMode) -> Bool {
        offlineAssetNamesForExport(mode: mode).isEmpty
            && exportReadinessMessageKey(for: mode, codec: mode.defaultCodec) == nil
    }

    var needsOutputSelectionBeforeExport: Bool {
        outputURL == nil
            || outputURLWasAutoGenerated
            || (exportRenderScope == .individualClips && !outputDirectoryWasExplicitlySelected)
    }

    var layoutPresetsForDisplay: [LayoutPreset] {
        Self.sortedLayoutPresets(layoutPresets, defaultPresetID: defaultLayoutPresetID)
    }

    func setResolvedLanguage(_ language: AppResolvedLanguage) {
        guard resolvedLanguage != language else { return }
        resolvedLanguage = language
        refreshLocalizedStatus()
    }

    /// 窗口标题与状态用「活动日期 + 运动类型」（如「2026-07-05 跑步」）代替原始 FIT 文件名；
    /// 文件名保留在素材池与调试日志。
    var activityDisplayName: String? {
        Self.makeActivityDisplayName(
            startDate: series?.activityStartDate,
            sport: activeActivityAssetID.flatMap { activitySportByAssetID[$0] },
            language: resolvedLanguage
        )
    }

    static func makeActivityDisplayName(
        startDate: Date?,
        sport: TelemetrySport?,
        language: AppResolvedLanguage
    ) -> String? {
        guard startDate != nil || sport != nil else { return nil }
        let sportName = AppLocalizer.string("sport.\((sport ?? .generic).rawValue)", language: language)
        guard let startDate else { return sportName }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: startDate)) \(sportName)"
    }

    var exportReadinessMessage: String? {
        exportReadinessMessage(for: exportMode)
    }

    func exportReadinessMessage(for mode: OverlayExportMode) -> String? {
        let offlineNames = offlineAssetNamesForExport(mode: mode)
        if !offlineNames.isEmpty {
            return localized("status.timelineOfflineAssets", offlineNames.joined(separator: ", "))
        }
        return exportReadinessMessageKey(for: mode, codec: mode.defaultCodec).map { localized($0) }
    }

    private func offlineAssetNamesForExport(mode: OverlayExportMode) -> [String] {
        guard !timelineUsesSingleSourceMigration else { return [] }
        let rangeStart = sourceExportTrimStart
        let rangeEnd = rangeStart + effectiveExportTrimDuration
        let relevantKinds: Set<TimelineTrack.Kind> = mode == .video ? [.video, .overlay] : [.overlay]
        let assetIDs = Set(currentTimelineProject.tracks
            .filter { $0.isEnabled && relevantKinds.contains($0.kind) }
            .flatMap(\.clips)
            .filter { $0.timelineEnd > rangeStart && $0.timelineStart < rangeEnd }
            .map(\.assetID))
        return currentTimelineProject.assets
            .filter { assetIDs.contains($0.id) && offlineTimelineAssetIDs.contains($0.id) }
            .map(\.displayName)
            .sorted()
    }

    private var exportReadinessMessageKey: String? {
        exportReadinessMessageKey(for: exportMode, codec: codec)
    }

    private func exportReadinessMessageKey(for mode: OverlayExportMode, codec checkedCodec: OverlayVideoCodec) -> String? {
        if timelineUsesSingleSourceMigration {
            if series == nil {
                return "status.chooseFitFile"
            }
        }
        if checkedCodec.exportMode != mode {
            return "status.codecExportModeMismatch"
        }
        if outputWidth < 2 || outputWidth > 16_384 {
            return "status.outputWidthRange"
        }
        if outputWidth % 2 != 0 {
            return "status.outputWidthEven"
        }
        if outputHeight < 2 || outputHeight > 16_384 {
            return "status.outputHeightRange"
        }
        if outputHeight % 2 != 0 {
            return "status.outputHeightEven"
        }
        if !outputFPS.isFinite || outputFPS < 1 || outputFPS > 240 {
            return "status.frameRateRange"
        }
        if exportDuration == nil {
            return "status.sourceDurationRange"
        }
        if bitRateKbps < 1 || bitRateKbps > 1_000_000 {
            return "status.bitrateRange"
        }
        if bitRateKbps > Int.max / 1000 {
            return "status.bitrateTooLarge"
        }
        if !timelineUsesSingleSourceMigration {
            let project = currentTimelineProject
            let telemetryAssetIDs = Set(timelineTelemetrySeriesForExport(project: project).keys)
            if let issue = project.firstExportValidationIssue(
                mode: mode,
                timelineStart: sourceExportTrimStart,
                duration: effectiveExportTrimDuration,
                availableTelemetryAssetIDs: telemetryAssetIDs
            ) {
                return timelineExportValidationMessageKey(issue)
            }
        }
        return nil
    }

    private func timelineExportValidationMessageKey(_ issue: TimelineExportValidationIssue) -> String {
        switch issue {
        case .invalidRange:
            return "status.sourceDurationRange"
        case .missingOverlayClip:
            return "status.chooseFitFile"
        case .missingActivityAsset:
            return "status.timelineMissingActivityAsset"
        case .missingTelemetry:
            return "status.timelineMissingTelemetry"
        case .missingVideoAsset:
            return "status.timelineMissingVideoAsset"
        case .invalidVideoSourceRange:
            return "status.timelineVideoSourceRange"
        }
    }

    var availableCodecs: [OverlayVideoCodec] {
        OverlayVideoCodec.allCases.filter { $0.exportMode == exportMode }
    }

    var selectedElement: OverlayElement? {
        guard selectedTimelineClipID == nil else { return nil }
        guard let selectedElementID else { return layout.elements.first }
        return layout.elements.first { $0.id == selectedElementID } ?? layout.elements.first
    }

    var selectedTimelineClip: TimelineClip? {
        guard let selectedTimelineClipID else { return nil }
        return timelineClip(id: selectedTimelineClipID)
    }

    var selectedTimelineClipAsset: MediaAsset? {
        selectedTimelineClip.flatMap { timeline.asset(id: $0.assetID) }
    }

    var distanceUnitForCurrentSelection: OverlayDistanceUnit {
        guard selectedTimelineClipAsset?.kind == .activity,
              let selectedTimelineClip else {
            return distanceUnit
        }
        return selectedTimelineClip.distanceUnit ?? distanceUnit
    }

    func setDistanceUnitForCurrentSelection(_ unit: OverlayDistanceUnit) {
        guard selectedTimelineClipAsset?.kind == .activity,
              let selectedTimelineClip else {
            distanceUnit = unit
            return
        }
        setTimelineClipDistanceUnit(id: selectedTimelineClip.id, unit)
    }

    var selectedTimelineClipIsEditable: Bool {
        guard let selectedTimelineClipID, !isExporting else { return false }
        return timeline.tracks.contains { track in
            !track.isLocked && track.clips.contains { $0.id == selectedTimelineClipID }
        }
    }

    var canToggleSelectedTimelineClipsEnabled: Bool {
        !editableSelectedTimelineClipIDs.isEmpty
    }

    var canPlayPreview: Bool {
        guard !isExporting else { return false }
        if player != nil || series != nil { return true }
        return usesCustomTimelinePreview && timelinePreviewSnapshot(at: previewTime) != nil
    }

    var usesCustomTimelinePreview: Bool {
        guard timelineUsesSingleSourceMigration else { return true }
        guard videoURL != nil else { return false }

        let videoClips = timeline.enabledClips(kind: .video)
        if videoClips.isEmpty { return false }
        guard videoClips.count == 1, let videoClip = videoClips.first else { return true }
        let tolerance = 1e-6
        guard abs(videoClip.timelineStart) <= tolerance,
              abs(videoClip.sourceIn) <= tolerance else {
            return true
        }

        let legacyDuration = sourceDuration > 0
            ? sourceDuration
            : (timeline.asset(id: videoClip.assetID)?.duration ?? 0)
        guard timeline.duration <= legacyDuration + tolerance else { return true }

        let overlayClips = timeline.tracks
            .filter { $0.kind == .overlay && $0.isEnabled }
            .flatMap(\.clips)
        guard overlayClips.count <= 1 else { return true }
        if let overlayClip = overlayClips.first {
            let timelineOffset = overlayClip.sourceIn - overlayClip.timelineStart
            let syncOffset = timeSync.rawFitElapsed(forVideoTime: 0)
            guard abs(timelineOffset - syncOffset) <= tolerance else { return true }
        }
        return false
    }

    var timeSync: TelemetryTimeSync {
        guard videoURL != nil else { return .identity }
        switch syncMode {
        case .offset:
            return .legacyOffset(finiteTime(offsetSeconds))
        case .fitStart:
            return TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: nonNegativeTime(fitStartSeconds))
        case .syncPoint:
            return TelemetryTimeSync(
                videoSyncTime: nonNegativeTime(syncVideoSeconds),
                fitSyncTime: nonNegativeTime(syncFITSeconds)
            )
        }
    }

    func useMatchPointSyncMode() {
        guard syncMode != .syncPoint else { return }
        let fitOffset: TimeInterval
        switch syncMode {
        case .offset:
            fitOffset = -finiteTime(offsetSeconds)
        case .fitStart:
            fitOffset = nonNegativeTime(fitStartSeconds)
        case .syncPoint:
            return
        }
        syncMode = .syncPoint
        syncVideoSeconds = max(0, -fitOffset)
        syncFITSeconds = max(0, fitOffset)
    }

    func applyLaunchOptions(_ options: StudioLaunchOptions) {
        if let offsetSeconds = options.offsetSeconds {
            syncMode = .offset
            self.offsetSeconds = offsetSeconds
        }
        if let videoURL = options.videoURL {
            setVideo(videoURL)
        }
        if let fitURL = options.fitURL {
            setFIT(fitURL)
        }
    }

    var sourceResolutionPresetTitle: String? {
        guard let sourceDimensions else { return nil }
        return localized(
            "sidebar.sourceResolutionPreset",
            String(sourceDimensions.width),
            String(sourceDimensions.height)
        )
    }

    var selectedResolutionPresetID: String {
        if let sourceDimensions,
           outputWidth == sourceDimensions.width,
           outputHeight == sourceDimensions.height {
            return OutputResolutionPreset.sourceID
        }

        if let preset = OutputResolutionPreset.fixed.first(where: { preset in
            preset.width == outputWidth && preset.height == outputHeight
        }) {
            return preset.id
        }

        return OutputResolutionPreset.customID
    }

    var sourceFrameRatePresetTitle: String? {
        guard let sourceFrameRate else { return nil }
        return localized("sidebar.sourceFrameRatePreset", formatFrameRate(sourceFrameRate))
    }

    var selectedFrameRatePresetID: String {
        if let sourceFrameRate, frameRatesMatch(outputFPS, sourceFrameRate) {
            return OutputFrameRatePreset.sourceID
        }

        if let preset = OutputFrameRatePreset.fixed.first(where: { preset in
            frameRatesMatch(outputFPS, preset.framesPerSecond)
        }) {
            return preset.id
        }

        return OutputFrameRatePreset.customID
    }

    func chooseVideo() {
        guard !isExporting else { return }
        let panel = NSOpenPanel()
        panel.title = localized("panel.chooseSourceVideo")
        panel.message = localized("panel.chooseSourceVideo.message")
        panel.prompt = localized("panel.open")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let first = panel.urls.first else { return }
        queueImportedVideosForTimeline(panel.urls)
        setVideo(first)
        for url in panel.urls.dropFirst() { addVideoAssetToPool(url) }
    }

    func chooseFIT() {
        guard !isExporting else { return }
        let panel = NSOpenPanel()
        panel.title = localized("panel.chooseFitActivity")
        panel.message = localized("panel.chooseFitActivity.message")
        panel.prompt = localized("panel.open")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["fit", "gpx"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let first = panel.urls.first else { return }
        queueImportedActivitiesForTimeline(panel.urls)
        setFIT(first)
        for url in panel.urls.dropFirst() { addActivityAssetToPool(url) }
    }

    /// Load a video's metadata off the main thread and add it to the pool without changing the
    /// active source. Used when multiple files are imported at once.
    private func addVideoAssetToPool(_ url: URL) {
        let importGeneration = mediaPoolImportGeneration
        Task.detached {
            do {
                let loaded = try await VideoMetadata.loadAsync(from: url)
                await MainActor.run { [weak self] in
                    guard let self, self.mediaPoolImportGeneration == importGeneration else { return }
                    self.upsertVideoAsset(url: url, metadata: loaded)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.mediaPoolImportGeneration == importGeneration else { return }
                    self.discardPendingVideoTimelineImport(id: url.path)
                    self.setStatusAndToast(.warning, "status.videoError", error.localizedDescription)
                }
            }
        }
    }

    /// Parse an activity file off the main thread and add it to the pool without changing the
    /// active source. Used when multiple files are imported at once.
    private func addActivityAssetToPool(_ url: URL) {
        let importGeneration = mediaPoolImportGeneration
        Task.detached {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let parsed = try TelemetryFileParser().parseActivity(url: url)
                await MainActor.run { [weak self] in
                    guard let self, self.mediaPoolImportGeneration == importGeneration else { return }
                    self.upsertActivityAsset(url: url, series: parsed.series, sport: parsed.sport)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.mediaPoolImportGeneration == importGeneration else { return }
                    self.discardPendingActivityTimelineImport(id: url.path)
                    self.setStatusAndToast(.warning, "status.fitError", error.localizedDescription)
                }
            }
        }
    }

    func openActivityFile(_ url: URL) {
        guard ["fit", "gpx"].contains(url.pathExtension.lowercased()) else { return }
        setFIT(url)
    }

    func openExternalFiles(_ urls: [URL]) -> StudioEntryRequestResult {
        guard !urls.isEmpty else { return .cancelled }
        studioEntryErrorMessage = nil
        let kinds = urls.map(StudioExternalFileKind.classify)

        if urls.count == 1, let url = urls.first, let kind = kinds.first {
            switch kind {
            case .timelineProject:
                openTimelineProjectFile(url)
                return studioEntryErrorMessage.map(StudioEntryRequestResult.failed) ?? .accepted
            case .layoutPreset:
                guard importLayoutPresets(from: url) != nil else {
                    let message = localized("status.presetImportError", url.lastPathComponent)
                    studioEntryErrorMessage = message
                    return .failed(message)
                }
                return .accepted
            case .legacyJSON:
                if let data = try? Data(contentsOf: url),
                   (try? JSONDecoder().decode(TimelineProject.self, from: data)) != nil {
                    openTimelineProjectFile(url)
                    return studioEntryErrorMessage.map(StudioEntryRequestResult.failed) ?? .accepted
                }
                guard importLayoutPresets(from: url) != nil else {
                    let message = localized("welcome.error.unsupportedFile", url.lastPathComponent)
                    studioEntryErrorMessage = message
                    return .failed(message)
                }
                return .accepted
            case .video, .activity:
                return requestNewTimelineProject(importing: [url])
            case .unsupported:
                let message = localized("welcome.error.unsupportedFile", url.lastPathComponent)
                studioEntryErrorMessage = message
                return .failed(message)
            }
        }

        guard kinds.allSatisfy({ $0 == .video || $0 == .activity }) else {
            let message = localized("welcome.error.mixedDrop")
            studioEntryErrorMessage = message
            return .failed(message)
        }
        return requestNewTimelineProject(importing: urls)
    }

    func chooseOutput() {
        guard !isExporting else { return }
        if exportRenderScope == .individualClips {
            chooseOutputDirectory()
            return
        }
        let panel = NSSavePanel()
        panel.title = localized(exportMode == .video ? "panel.saveCompositedVideo" : "panel.saveOverlayVideo")
        panel.message = localized(exportMode == .video ? "panel.saveCompositedVideo.message" : "panel.saveOverlayVideo.message")
        panel.prompt = localized("panel.export")
        panel.allowedContentTypes = [.quickTimeMovie]
        let suggestedOutputURL = suggestedOutputURL()
        panel.directoryURL = outputURL?.deletingLastPathComponent() ?? suggestedOutputURL?.deletingLastPathComponent()
        panel.nameFieldStringValue = outputURL?.lastPathComponent ?? suggestedOutputURL?.lastPathComponent ?? "datalayer-overlay.mov"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
        outputURLWasAutoGenerated = false
        outputDirectoryWasExplicitlySelected = false
        outputSecurityScopedURL = url
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = localized(exportMode == .video ? "panel.saveCompositedVideo" : "panel.saveOverlayVideo")
        panel.message = localized(exportMode == .video ? "panel.saveCompositedVideo.message" : "panel.saveOverlayVideo.message")
        panel.prompt = localized("panel.export")
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        let suggestedOutputURL = suggestedOutputURL()
        panel.directoryURL = outputURL?.deletingLastPathComponent() ?? suggestedOutputURL?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
        let fileName = outputURL?.lastPathComponent
            ?? suggestedOutputURL?.lastPathComponent
            ?? "datalayer-overlay.mov"
        outputURL = directoryURL.appendingPathComponent(fileName)
        outputURLWasAutoGenerated = false
        outputDirectoryWasExplicitlySelected = true
        outputSecurityScopedURL = directoryURL
    }

    func shutdown() {
        cancelLoadTasks()
        cancelPreviewRenderTasks()
        exportCancellationToken?.cancel()
        exportTask?.cancel()
        exportTask = nil
        exportCancellationToken = nil
        if isExporting {
            isExporting = false
            exportProgress = 0
            setStatus("status.exportCancelled")
        }
        videoFrameService.clearCache()
        stopTimelineSecurityScopedAccess()
        stopPlayback()
    }

    func applyResolutionPreset(id: String) {
        guard !isExporting else { return }
        if id == OutputResolutionPreset.sourceID, let sourceDimensions {
            setOutputWidth(sourceDimensions.width)
            setOutputHeight(sourceDimensions.height)
            return
        }

        guard let preset = OutputResolutionPreset.fixed.first(where: { $0.id == id }) else { return }
        setOutputWidth(preset.width)
        setOutputHeight(preset.height)
    }

    func setOutputWidth(_ value: Int) {
        outputWidth = Self.sanitizedOutputDimension(value)
    }

    func setOutputWidth(_ value: Int, lockedAspectRatio: Double?) {
        setOutputWidth(value)
        if let aspectRatio = lockedAspectRatio, aspectRatio.isFinite, aspectRatio > 0 {
            setOutputHeight(Int((Double(outputWidth) / aspectRatio).rounded()))
        }
    }

    func setOutputHeight(_ value: Int) {
        outputHeight = Self.sanitizedOutputDimension(value)
    }

    func setOutputHeight(_ value: Int, lockedAspectRatio: Double?) {
        setOutputHeight(value)
        if let aspectRatio = lockedAspectRatio, aspectRatio.isFinite, aspectRatio > 0 {
            setOutputWidth(Int((Double(outputHeight) * aspectRatio).rounded()))
        }
    }

    func setOutputFPS(_ value: Double) {
        outputFPS = Self.sanitizedOutputFrameRate(value)
    }

    func setBitRateKbps(_ value: Int) {
        bitRateKbps = Self.sanitizedBitRateKbps(value)
    }

    func setOpenWeatherAPIKey(_ value: String) {
        openWeatherAPIKey = value
        OpenWeatherKeyStore.save(value)
        addDebugLog(.weather, "OpenWeather key updated: \(redactedKeySummary(value))")
    }

    func dismissWeatherAPIKeyPrompt() {
        isWeatherAPIKeyPromptPresented = false
    }

    func refreshOpenWeatherForCurrentFIT() {
        guard !openWeatherAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("status.weatherKeyRequired")
            weatherRefreshMessage = status
            addDebugLog(.weather, "Refresh skipped: missing OpenWeather key")
            return
        }
        guard let currentSeries = series,
              let fitURL else {
            setStatus("status.weatherFitRequired")
            weatherRefreshMessage = status
            addDebugLog(.weather, "Refresh skipped: missing FIT series")
            return
        }
        setStatus("status.weatherRefreshing", activityDisplayName ?? fitURL.lastPathComponent)
        weatherRefreshMessage = status
        addDebugLog(.weather, "Refresh started: \(fitURL.lastPathComponent), samples=\(currentSeries.samples.count), key=\(redactedKeySummary(openWeatherAPIKey))")
        loadOpenWeatherIfPossible(
            for: currentSeries,
            sourceName: fitURL.lastPathComponent,
            generation: fitLoadGeneration,
            forceRefresh: true
        )
    }

    func setCanvasSafeAreaInsetPercent(_ value: Double) {
        canvasSafeAreaInsetPercent = StudioPreferenceState.sanitizedSafeAreaInsetPercent(value)
    }

    func applyFrameRatePreset(id: String) {
        guard !isExporting else { return }
        if id == OutputFrameRatePreset.sourceID, let sourceFrameRate {
            setOutputFPS(sourceFrameRate)
            return
        }

        guard let preset = OutputFrameRatePreset.fixed.first(where: { $0.id == id }) else { return }
        setOutputFPS(preset.framesPerSecond)
    }

    var exportPresetsForDisplay: [ExportPreset] {
        ExportPreset.builtIn + userExportPresets.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func applyExportPreset(id: String) {
        guard !isExporting,
              let preset = exportPresetsForDisplay.first(where: { $0.id == id }) else { return }

        exportMode = preset.exportMode
        codec = preset.codec.exportMode == preset.exportMode ? preset.codec : preset.exportMode.defaultCodec
        switch preset.resolution {
        case .source:
            applyResolutionPreset(id: OutputResolutionPreset.sourceID)
        case let .fixed(width, height):
            setOutputWidth(width)
            setOutputHeight(height)
        }
        switch preset.frameRate {
        case .source:
            applyFrameRatePreset(id: OutputFrameRatePreset.sourceID)
        case let .fixed(framesPerSecond):
            setOutputFPS(framesPerSecond)
        }
        setBitRateKbps(preset.bitRateKbps)
        exportRenderScope = preset.renderScope
    }

    @discardableResult
    func saveCurrentExportPreset(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        let existingID = userExportPresets.first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }?.id
        let preset = ExportPreset(
            id: existingID ?? UUID().uuidString,
            name: name,
            resolution: .fixed(width: outputWidth, height: outputHeight),
            frameRate: .fixed(outputFPS),
            exportMode: exportMode,
            codec: codec,
            bitRateKbps: bitRateKbps,
            renderScope: exportRenderScope
        )
        userExportPresets.removeAll { $0.id == preset.id }
        userExportPresets.append(preset)
        persistStudioPreferences()
        setStatusAndToast(
            .success,
            existingID == nil ? "status.savedExportPreset" : "status.updatedExportPreset",
            name
        )
        return true
    }

    func deleteUserExportPreset(id: String) {
        guard userExportPresets.contains(where: { $0.id == id }) else { return }
        let name = userExportPresets.first { $0.id == id }?.name ?? ""
        userExportPresets.removeAll { $0.id == id }
        persistStudioPreferences()
        setStatusAndToast(.success, "status.deletedExportPreset", name)
    }

    @discardableResult
    func saveLayoutPreset(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            setStatus("status.presetNameRequired")
            return false
        }

        let now = Date()
        if let index = layoutPresets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            layoutPresets[index].name = name
            layoutPresets[index].layout = layout.sanitized
            layoutPresets[index].updatedAt = now
            persistLayoutPresets()
            setStatusAndToast(.success, "status.updatedPreset", name)
            return true
        }

        let preset = LayoutPreset(
            id: UUID().uuidString,
            name: name,
            layout: layout.sanitized,
            createdAt: now,
            updatedAt: now
        )
        layoutPresets.append(preset)
        persistLayoutPresets()
        setStatusAndToast(.success, "status.savedPreset", name)
        return true
    }

    func applyLayoutPreset(id: String) {
        guard !isExporting else { return }
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        performLayoutChange("undo.applyPreset") {
            layout = preset.layout.sanitized
            selectedElementID = Self.firstSelectableElementID(in: layout)
            selectedMediaAssetID = nil
        }
        setStatusAndToast(.success, "status.appliedPreset", preset.name)
        refreshOverlayOrPreview()
    }

    func setDefaultLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        defaultLayoutPresetID = id
        persistLayoutPresets()
        setStatusAndToast(.success, "status.defaultPreset", preset.name)
    }

    func deleteLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        layoutPresets.removeAll { $0.id == id }
        if defaultLayoutPresetID == id {
            defaultLayoutPresetID = nil
        }
        persistLayoutPresets()
        setStatusAndToast(.success, "status.deletedPreset", preset.name)
    }

    func exportLayoutPresets() {
        guard !layoutPresets.isEmpty else {
            setStatus("status.noPresetsToExport")
            return
        }

        let panel = NSSavePanel()
        panel.title = localized("panel.exportLayoutPresets")
        panel.message = localized("panel.exportLayoutPresets.message")
        panel.prompt = localized("panel.export")
        panel.allowedContentTypes = [LayoutPresetFileType.contentType]
        panel.nameFieldStringValue = "datalayer-studio-layout-presets.\(LayoutPresetFileType.filenameExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let state = LayoutPresetState(presets: layoutPresets, defaultPresetID: defaultLayoutPresetID)
            let data = try encoder.encode(state.sanitized)
            try data.write(to: url, options: .atomic)
            setStatusAndToast(.success, "status.exportedPresets", layoutPresets.count)
        } catch {
            setStatus("status.presetExportError", error.localizedDescription)
        }
    }

    func importLayoutPresets() {
        let panel = NSOpenPanel()
        panel.title = localized("panel.importLayoutPresets")
        panel.message = localized("panel.importLayoutPresets.message")
        panel.prompt = localized("panel.import")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = LayoutPresetFileType.importContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }

        importLayoutPresets(from: url)
    }

    @discardableResult
    func importLayoutPresets(from url: URL) -> Int? {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let state: LayoutPresetState
            if let decodedState = try? decoder.decode(LayoutPresetState.self, from: data) {
                state = decodedState.sanitized
            } else {
                let preset = try decoder.decode(LayoutPreset.self, from: data)
                state = LayoutPresetState(presets: [preset], defaultPresetID: preset.id).sanitized
            }

            let importedCount = mergeImportedLayoutPresets(state)
            if importedCount == 0 {
                setStatus("status.noPresetsImported")
            } else {
                setStatusAndToast(.success, "status.importedPresets", importedCount)
            }
            return importedCount
        } catch {
            setStatus("status.presetImportError", error.localizedDescription)
            return nil
        }
    }

    func openTimelineProject() {
        guard !isExporting else { return }
        guard !hasUnsavedTimelineChanges else {
            requestTimelineConfirmation(.openTimelineProject)
            return
        }
        presentOpenTimelineProjectPanel()
    }

    func requestOpenTimelineProject() -> StudioEntryRequestResult {
        guard !isExporting else { return .cancelled }
        studioEntryErrorMessage = nil
        guard !hasUnsavedTimelineChanges else {
            requestTimelineConfirmation(.openTimelineProject)
            return .accepted
        }
        return presentOpenTimelineProjectPanel() ? .accepted : .cancelled
    }

    func requestNewTimelineProject(
        layoutPresetID: String? = nil,
        importing mediaURLs: [URL] = []
    ) -> StudioEntryRequestResult {
        guard !isExporting else { return .cancelled }
        studioEntryErrorMessage = nil
        let supportedMedia = mediaURLs.filter {
            let kind = StudioExternalFileKind.classify($0)
            return kind == .video || kind == .activity
        }
        guard supportedMedia.count == mediaURLs.count else {
            let message = localized("welcome.error.unsupportedDrop")
            studioEntryErrorMessage = message
            return .failed(message)
        }
        let action = TimelinePendingAction.newTimelineProject(
            layoutPresetID: layoutPresetID,
            mediaURLs: supportedMedia
        )
        guard !hasUnsavedTimelineChanges else {
            requestTimelineConfirmation(action)
            return .accepted
        }
        performNewTimelineProject(layoutPresetID: layoutPresetID, mediaURLs: supportedMedia)
        return .accepted
    }

    func chooseMediaForNewTimelineProject(kind: MediaAsset.Kind) -> StudioEntryRequestResult {
        guard !isExporting else { return .cancelled }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        switch kind {
        case .video:
            panel.title = localized("panel.chooseSourceVideo")
            panel.message = localized("panel.chooseSourceVideo.message")
            panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        case .activity:
            panel.title = localized("panel.chooseFitActivity")
            panel.message = localized("panel.chooseFitActivity.message")
            panel.allowedContentTypes = ["fit", "gpx"].compactMap { UTType(filenameExtension: $0) }
        }
        panel.prompt = localized("panel.open")
        guard panel.runModal() == .OK else { return .cancelled }
        return requestNewTimelineProject(importing: panel.urls)
    }

    func openRecentTimelineProject(_ project: RecentTimelineProject) {
        openTimelineProjectFile(project.url)
    }

    func removeRecentTimelineProject(_ project: RecentTimelineProject) {
        recentTimelineProjects = recentTimelineProjectStore.remove(project.url)
    }

    func locateRecentTimelineProject(_ project: RecentTimelineProject) -> StudioEntryRequestResult {
        let panel = NSOpenPanel()
        panel.title = localized("welcome.locateProject")
        panel.message = localized("welcome.locateProject.message", project.displayName)
        panel.prompt = localized("welcome.locate")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = TimelineProjectFileType.openContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        recentTimelineProjects = recentTimelineProjectStore.replace(project, with: url)
        openTimelineProjectFile(url)
        return studioEntryErrorMessage == nil ? .accepted : .failed(studioEntryErrorMessage ?? "")
    }

    func openTimelineProjectFile(_ url: URL) {
        guard !isExporting else { return }
        studioEntryErrorMessage = nil
        guard !hasUnsavedTimelineChanges else {
            requestTimelineConfirmation(.openTimelineProjectFile(url))
            return
        }
        openTimelineProject(at: url)
    }

    @discardableResult
    private func presentOpenTimelineProjectPanel() -> Bool {
        let panel = NSOpenPanel()
        panel.title = localized("panel.openTimelineProject")
        panel.message = localized("panel.openTimelineProject.message")
        panel.prompt = localized("panel.open")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = TimelineProjectFileType.openContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        return openTimelineProject(at: url)
    }

    func saveTimelineProject() {
        guard !isExporting else { return }
        guard let currentTimelineProjectURL else {
            saveTimelineProjectAs()
            return
        }
        saveTimelineProject(to: currentTimelineProjectURL)
    }

    func saveTimelineProjectAs() {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.title = localized("panel.saveTimelineProject")
        panel.message = localized("panel.saveTimelineProject.message")
        panel.prompt = localized("panel.save")
        panel.allowedContentTypes = [TimelineProjectFileType.contentType]
        panel.directoryURL = currentTimelineProjectURL?.deletingLastPathComponent()
        panel.nameFieldStringValue = currentTimelineProjectURL?
            .deletingPathExtension()
            .appendingPathExtension(TimelineProjectFileType.filenameExtension)
            .lastPathComponent
            ?? "datalayer-studio-project.\(TimelineProjectFileType.filenameExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        saveTimelineProject(to: url)
    }

    @discardableResult
    func saveTimelineProject(to url: URL) -> Bool {
        guard !isExporting else { return false }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        do {
            let data = try timelineProjectJSONData(relativeTo: url)
            try data.write(to: url, options: .atomic)
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            adoptTimelineProjectURL(url)
            markTimelineProjectClean()
            setStatusAndToast(.success, "status.timelineProjectSaved", url.lastPathComponent)
            return true
        } catch {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            setStatus("status.timelineProjectSaveError", error.localizedDescription)
            return false
        }
    }

    var currentTimelineProjectDisplayName: String? {
        currentTimelineProjectURL?.deletingPathExtension().lastPathComponent
    }

    @discardableResult
    private func openTimelineProject(at url: URL) -> Bool {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        do {
            let data = try Data(contentsOf: url)
            try loadTimelineProject(from: data, loadAssets: true, projectURL: url)
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            adoptTimelineProjectURL(url)
            setStatus("status.timelineProjectLoaded", url.lastPathComponent)
            studioEntryErrorMessage = nil
            studioSessionRevision &+= 1
            return true
        } catch {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            setStatus("status.timelineProjectLoadError", error.localizedDescription)
            studioEntryErrorMessage = localized("status.timelineProjectLoadError", error.localizedDescription)
            return false
        }
    }

    private func adoptTimelineProjectURL(_ url: URL) {
        currentTimelineProjectSecurityScopedURL?.stopAccessingSecurityScopedResource()
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        currentTimelineProjectSecurityScopedURL = standardizedURL.startAccessingSecurityScopedResource()
            ? standardizedURL
            : nil
        currentTimelineProjectURL = standardizedURL
        recentTimelineProjects = recentTimelineProjectStore.record(standardizedURL)
    }

    private func performNewTimelineProject(layoutPresetID: String?, mediaURLs: [URL]) {
        guard !isExporting else { return }
        studioEntryErrorMessage = nil
        currentTimelineProjectSecurityScopedURL?.stopAccessingSecurityScopedResource()
        currentTimelineProjectSecurityScopedURL = nil
        currentTimelineProjectURL = nil
        outputSecurityScopedURL = nil
        outputURL = nil
        outputURLWasAutoGenerated = false
        outputDirectoryWasExplicitlySelected = false
        clearExportResult()

        let project = TimelineProject(
            outputWidth: 1920,
            outputHeight: 1080,
            framesPerSecond: 30,
            distanceUnit: distanceUnit
        )
        applyTimelineProject(project, loadAssets: false)
        timelineUsesSingleSourceMigration = true
        layout = (layoutPresetID ?? defaultLayoutPresetID)
            .flatMap { id in layoutPresets.first(where: { $0.id == id })?.layout.sanitized }
            ?? .default
        selectedElementID = Self.firstSelectableElementID(in: layout)
        selectedMediaAssetID = nil
        clearTimelineClipSelection()
        rebuildCurrentTimelineProject()
        markTimelineProjectClean()
        studioSessionRevision &+= 1
        setStatus("status.chooseVideoAndFit")

        importMediaFilesIntoCurrentTimeline(mediaURLs)
    }

    private func importMediaFilesIntoCurrentTimeline(_ urls: [URL]) {
        let videos = urls.filter { StudioExternalFileKind.classify($0) == .video }
        let activities = urls.filter { StudioExternalFileKind.classify($0) == .activity }

        if let firstVideo = videos.first {
            queueImportedVideosForTimeline(videos)
            setVideo(firstVideo)
            for url in videos.dropFirst() { addVideoAssetToPool(url) }
        }
        if let firstActivity = activities.first {
            queueImportedActivitiesForTimeline(activities)
            setFIT(firstActivity)
            for url in activities.dropFirst() { addActivityAssetToPool(url) }
        }
    }

    /// Finder drops onto the media library only join the pool — like DaVinci's media pool, they
    /// never touch the timeline or replace the active sources, even for the first video/activity.
    @discardableResult
    func importDroppedMediaFilesIntoPool(_ urls: [URL]) -> Bool {
        guard !isExporting else { return false }
        var imported = false
        for url in urls {
            switch StudioExternalFileKind.classify(url) {
            case .video:
                addVideoAssetToPool(url)
                imported = true
            case .activity:
                addActivityAssetToPool(url)
                imported = true
            default:
                continue
            }
        }
        return imported
    }

    /// Finder drops onto the timeline join the pool and land on the timeline. Files matching the
    /// target lane's kind land there — the first one at the drop position, the rest appended after
    /// the lane's own last clip. Other supported files append to their default track kind. The
    /// active sources are never replaced.
    @discardableResult
    func importDroppedMediaFiles(
        _ urls: [URL],
        targetTrackID: String? = nil,
        timelineStart: TimeInterval? = nil
    ) -> Bool {
        guard !isExporting else { return false }
        var targetTrack: TimelineTrack?
        if let targetTrackID {
            guard let track = timeline.tracks.first(where: { $0.id == targetTrackID }),
                  !track.isLocked else { return false }
            targetTrack = track
        }

        var imported = false
        var usedDropPosition = false
        for url in urls {
            let kind = StudioExternalFileKind.classify(url)
            guard kind == .video || kind == .activity else { continue }
            let matchesTargetTrack = targetTrack.map {
                ($0.kind == .video) == (kind == .video)
            } ?? false
            let clipTrackID = matchesTargetTrack ? targetTrack?.id : nil
            var clipStart: TimeInterval?
            if matchesTargetTrack, !usedDropPosition, let timelineStart {
                clipStart = max(0, timelineStart)
                usedDropPosition = true
            }

            let assetID = url.path
            switch kind {
            case .video:
                let needsLoad = !videoAssets.contains(where: { $0.id == assetID })
                    && !pendingVideoPositionedTimelineImports.contains(where: { $0.assetID == assetID })
                pendingVideoPositionedTimelineImports.append(PositionedTimelineImport(
                    assetID: assetID,
                    trackID: clipTrackID,
                    timelineStart: clipStart
                ))
                if needsLoad {
                    addVideoAssetToPool(url)
                }
            case .activity:
                let needsLoad = (!activityAssets.contains(where: { $0.id == assetID })
                    || activitySeriesByAssetID[assetID] == nil)
                    && !pendingActivityPositionedTimelineImports.contains(where: { $0.assetID == assetID })
                pendingActivityPositionedTimelineImports.append(PositionedTimelineImport(
                    assetID: assetID,
                    trackID: clipTrackID,
                    timelineStart: clipStart
                ))
                if needsLoad {
                    addActivityAssetToPool(url)
                }
            default:
                continue
            }
            imported = true
        }
        drainPendingPositionedVideoTimelineImports()
        drainPendingPositionedActivityTimelineImports()
        return imported
    }

    func timelineProjectJSONData(relativeTo projectURL: URL? = nil) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(timelineProjectForSaving(relativeTo: projectURL))
    }

    func loadTimelineProject(from data: Data, loadAssets: Bool = true, projectURL: URL? = nil) throws {
        guard !isExporting else { return }
        let decoded = try JSONDecoder().decode(TimelineProject.self, from: data)
        let project = resolvedTimelineProject(decoded, relativeTo: projectURL)
        stopTimelineSecurityScopedAccess()
        startTimelineSecurityScopedAccess(for: project.assets)
        applyTimelineProject(project, loadAssets: loadAssets)
    }

    func applyTimelineProject(_ project: TimelineProject, loadAssets: Bool = true) {
        guard !isExporting else { return }
        isApplyingTimelineProject = true
        clearUndoStackForTimelineReplacement()
        stopPlayback()
        cancelPreviewRenderTasks()
        videoLoadTask?.cancel()
        fitLoadTask?.cancel()
        weatherLoadTask?.cancel()
        videoFrameService.clearCache()
        previewRenderGeneration += 1
        videoLoadGeneration += 1
        fitLoadGeneration += 1
        mediaPoolImportGeneration += 1
        pendingVideoTimelineImportIDs.removeAll()
        pendingActivityTimelineImportIDs.removeAll()
        pendingVideoPositionedTimelineImports.removeAll()
        pendingActivityPositionedTimelineImports.removeAll()
        singleSourceAlignmentIsPending = false

        var sanitizedProject = project
        sanitizedProject.outputWidth = Self.sanitizedOutputDimension(project.outputWidth)
        sanitizedProject.outputHeight = Self.sanitizedOutputDimension(project.outputHeight)
        sanitizedProject.framesPerSecond = Self.sanitizedOutputFrameRate(project.framesPerSecond)

        timelineUsesSingleSourceMigration = false
        layoutEditingTimelineClipID = nil
        outputWidth = sanitizedProject.outputWidth
        outputHeight = sanitizedProject.outputHeight
        outputFPS = sanitizedProject.framesPerSecond
        distanceUnit = sanitizedProject.distanceUnit
        timeline = sanitizedProject
        videoAssets = sanitizedProject.assets.filter { $0.kind == .video }
        activityAssets = sanitizedProject.assets.filter { $0.kind == .activity }
        offlineTimelineAssetReasons = loadAssets
            ? Dictionary(uniqueKeysWithValues: sanitizedProject.assets.compactMap { asset in
                Self.initialOfflineReason(for: asset.url).map { (asset.id, $0) }
            })
            : [:]
        activitySeriesByAssetID.removeAll()
        activitySportByAssetID.removeAll()
        pendingRelinkUndoSnapshots.removeAll()

        let activeVideo = sanitizedProject.sourceMatchPoint.flatMap { matchPoint in
            videoAssets.first { $0.id == matchPoint.videoAssetID }
        } ?? videoAssets.first
        let activeActivity = sanitizedProject.sourceMatchPoint.flatMap { matchPoint in
            activityAssets.first { $0.id == matchPoint.activityAssetID }
        } ?? activityAssets.first
        videoURL = activeVideo?.url
        fitURL = activeActivity?.url
        restoreTimelineSourceMatchPoint(
            sanitizedProject.sourceMatchPoint,
            activeVideoAssetID: activeVideo?.id,
            activeActivityAssetID: activeActivity?.id
        )
        metadata = nil
        series = nil
        sourceDuration = Self.sanitizedSourceDuration(max(sanitizedProject.duration, activeVideo?.duration ?? 0, activeActivity?.duration ?? 0))
        restoreTimelineProjectExportSettings(sanitizedProject.exportSettings)
        backgroundImage = nil
        overlayImage = nil
        previewWarning = nil
        videoLoadFailure = nil
        fitLoadFailure = nil
        clearTimelineClipSelection()
        selectedMediaAssetID = nil
        previewTime = clampedPreviewTime(previewTime)
        if let sourceURL = activeVideo?.url ?? activeActivity?.url {
            applySuggestedOutputURLIfNeeded(for: sourceURL)
        }
        refreshOverlayOrPreview()
        isApplyingTimelineProject = false
        updateTimelineProjectExportSettings()
        markTimelineProjectClean()

        guard loadAssets else { return }
        loadTimelineProjectAssets(sanitizedProject.assets)
    }

    private func timelineProjectForSaving(relativeTo projectURL: URL?) -> TimelineProject {
        var project = currentTimelineProject
        project.schemaVersion = TimelineProject.currentSchemaVersion
        project.exportSettings = currentTimelineProjectExportSettings
        project.assets = project.assets.map { asset in
            var updated = asset
            updated.bookmarkData = securityScopedBookmarkData(for: asset.url) ?? asset.bookmarkData
            updated.relativePath = projectURL.flatMap {
                Self.projectRelativeMediaPath(for: asset.url, projectURL: $0)
            } ?? asset.relativePath
            return updated
        }
        return project
    }

    private var currentTimelineProjectExportSettings: TimelineProjectExportSettings {
        TimelineProjectExportSettings(
            timelineStart: effectiveExportTrimStart,
            timelineEnd: effectiveExportTrimEnd,
            activityTrim: activityTrim,
            renderScope: exportRenderScope == .individualClips ? .individualClips : .singleClip,
            exportMode: exportMode,
            codec: codec,
            bitRateKbps: bitRateKbps
        )
    }

    private func restoreTimelineProjectExportSettings(_ settings: TimelineProjectExportSettings?) {
        guard let settings else {
            exportTrimRangeWasManuallyEdited = false
            exportTrimStartSeconds = 0
            exportTrimEndSeconds = exportTrimEditingDuration
            activityTrim = .none
            exportRenderScope = .singleClip
            return
        }

        exportMode = settings.exportMode
        codec = settings.codec.exportMode == settings.exportMode ? settings.codec : settings.exportMode.defaultCodec
        bitRateKbps = Self.sanitizedBitRateKbps(settings.bitRateKbps)
        exportRenderScope = settings.renderScope == .individualClips ? .individualClips : .singleClip
        activityTrim = settings.activityTrim
        exportTrimRangeWasManuallyEdited = true
        exportTrimStartSeconds = sanitizedExportTrimStart(
            settings.timelineStart,
            sourceDuration: exportTrimEditingDuration
        )
        exportTrimEndSeconds = sanitizedExportTrimEnd(
            settings.timelineEnd ?? exportTrimEditingDuration,
            start: exportTrimStartSeconds,
            sourceDuration: exportTrimEditingDuration
        )
    }

    private func updateTimelineProjectExportSettings() {
        guard !isApplyingTimelineProject, !isUpdatingTimelineProjectExportSettings else { return }
        isUpdatingTimelineProjectExportSettings = true
        timeline.schemaVersion = TimelineProject.currentSchemaVersion
        timeline.exportSettings = currentTimelineProjectExportSettings
        isUpdatingTimelineProjectExportSettings = false
    }

    private func securityScopedBookmarkData(for url: URL) -> Data? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func resolvedTimelineProject(_ project: TimelineProject, relativeTo projectURL: URL?) -> TimelineProject {
        var resolved = project
        resolved.assets = project.assets.map { asset in
            var candidates: [URL] = []
            if let bookmarkData = asset.bookmarkData {
                var isStale = false
                if let bookmarkURL = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    candidates.append(bookmarkURL)
                }
            }
            candidates.append(asset.url)
            if let projectURL,
               let relativePath = asset.relativePath,
               !relativePath.isEmpty {
                candidates.append(
                    projectURL.deletingLastPathComponent()
                        .appendingPathComponent(relativePath)
                        .standardizedFileURL
                )
            }
            guard let resolvedURL = candidates.first(where: Self.isReadableMediaURL) else { return asset }
            var updated = asset
            updated.url = resolvedURL
            return updated
        }
        return resolved
    }

    private nonisolated static func projectRelativeMediaPath(for mediaURL: URL, projectURL: URL) -> String? {
        let directoryPath = projectURL.deletingLastPathComponent().standardizedFileURL.path
        let mediaPath = mediaURL.standardizedFileURL.path
        let prefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        guard mediaPath.hasPrefix(prefix) else { return nil }
        let relative = String(mediaPath.dropFirst(prefix.count))
        return relative.isEmpty ? nil : relative
    }

    private func startTimelineSecurityScopedAccess(for assets: [MediaAsset]) {
        for asset in assets where asset.bookmarkData != nil {
            if asset.url.startAccessingSecurityScopedResource() {
                timelineSecurityScopedURLs.append(asset.url)
            }
        }
    }

    private func stopTimelineSecurityScopedAccess() {
        for url in timelineSecurityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        timelineSecurityScopedURLs.removeAll()
    }

    private func loadTimelineProjectAssets(_ assets: [MediaAsset]) {
        for asset in assets where !offlineTimelineAssetIDs.contains(asset.id) {
            switch asset.kind {
            case .video:
                loadTimelineVideoAsset(asset)
            case .activity:
                loadTimelineActivityAsset(asset)
            }
        }
    }

    private nonisolated static func isReadableMediaURL(_ url: URL) -> Bool {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    private nonisolated static func initialOfflineReason(for url: URL) -> TimelineAssetOfflineReason? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .fileMissing }
        return isReadableMediaURL(url) ? nil : .permissionDenied
    }

    func isTimelineAssetOffline(id: String) -> Bool {
        offlineTimelineAssetIDs.contains(id)
    }

    func chooseReplacementForTimelineAsset(id: String) {
        guard !isExporting,
              let asset = currentTimelineProject.asset(id: id) else { return }
        let panel = NSOpenPanel()
        panel.title = localized("panel.relinkMedia", asset.displayName)
        panel.message = localized("panel.relinkMedia.message", asset.displayName)
        panel.prompt = localized("mediapool.relink")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        switch asset.kind {
        case .video:
            panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        case .activity:
            panel.allowedContentTypes = ["fit", "gpx"].compactMap { UTType(filenameExtension: $0) }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relinkTimelineAsset(id: id, to: url)
    }

    func relinkTimelineAsset(id: String, to url: URL) {
        guard !isExporting,
              let asset = currentTimelineProject.asset(id: id) else { return }
        pendingRelinkUndoSnapshots[id] = timelineMediaUndoSnapshotNow
        switch asset.kind {
        case .video:
            loadTimelineVideoAsset(asset, replacementURL: url, reportsRelinkStatus: true)
        case .activity:
            loadTimelineActivityAsset(asset, replacementURL: url, reportsRelinkStatus: true)
        }
    }

    private func loadTimelineVideoAsset(
        _ asset: MediaAsset,
        replacementURL: URL? = nil,
        reportsRelinkStatus: Bool = false
    ) {
        let url = replacementURL ?? asset.url
        Task.detached {
            do {
                let loaded = try await VideoMetadata.loadAsync(from: url)
                await MainActor.run { [weak self] in
                    self?.applyLoadedTimelineVideoAsset(
                        id: asset.id,
                        url: url,
                        metadata: loaded,
                        reportsRelinkStatus: reportsRelinkStatus
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.markTimelineAssetLoadFailed(
                        id: asset.id,
                        displayName: asset.displayName,
                        error: error,
                        reportsRelinkStatus: reportsRelinkStatus
                    )
                }
            }
        }
    }

    private func loadTimelineActivityAsset(
        _ asset: MediaAsset,
        replacementURL: URL? = nil,
        reportsRelinkStatus: Bool = false
    ) {
        let url = replacementURL ?? asset.url
        Task.detached {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let parsed = try TelemetryFileParser().parseActivity(url: url)
                await MainActor.run { [weak self] in
                    self?.applyLoadedTimelineActivityAsset(
                        id: asset.id,
                        url: url,
                        activity: parsed,
                        reportsRelinkStatus: reportsRelinkStatus
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.markTimelineAssetLoadFailed(
                        id: asset.id,
                        displayName: asset.displayName,
                        error: error,
                        reportsRelinkStatus: reportsRelinkStatus
                    )
                }
            }
        }
    }

    private func applyLoadedTimelineVideoAsset(
        id: String,
        url: URL,
        metadata loaded: VideoMetadata,
        reportsRelinkStatus: Bool
    ) {
        guard let existing = currentTimelineProject.asset(id: id), existing.kind == .video else { return }
        let wallClockStart = existing.wallClockSource == .manual ? existing.wallClockStart : loaded.creationDate
        let wallClockSource = existing.wallClockSource == .manual ? .manual : loaded.creationDateSource
        if reportsRelinkStatus {
            replaceTimelineAssetLocation(
                id: id,
                url: url,
                duration: loaded.duration,
                width: Int(loaded.size.width.rounded()),
                height: Int(loaded.size.height.rounded()),
                framesPerSecond: loaded.framesPerSecond,
                wallClockStart: wallClockStart,
                wallClockSource: wallClockSource
            )
        } else {
            var updated = existing
            updated.duration = loaded.duration
            updated.width = Int(loaded.size.width.rounded())
            updated.height = Int(loaded.size.height.rounded())
            updated.framesPerSecond = loaded.framesPerSecond
            updated.wallClockStart = wallClockStart
            updated.wallClockSource = wallClockSource
            if let index = timeline.assets.firstIndex(where: { $0.id == id }) {
                timeline.assets[index] = updated
            }
            if let index = videoAssets.firstIndex(where: { $0.id == id }) {
                videoAssets[index] = updated
            }
            offlineTimelineAssetReasons.removeValue(forKey: id)
        }
        if wallClockSource == .untrustedExport,
           reportsRelinkStatus || existing.wallClockSource != .untrustedExport {
            for trackIndex in timeline.tracks.indices {
                for clipIndex in timeline.tracks[trackIndex].clips.indices
                where timeline.tracks[trackIndex].clips[clipIndex].assetID == id {
                    timeline.tracks[trackIndex].clips[clipIndex].isAlignmentPending = true
                }
            }
        }
        if videoURL == existing.url || preferredActiveAssetID(kind: .video) == id {
            videoURL = url
            metadata = loaded
            if usesCustomTimelinePreview { configureTimelinePlayer() } else { configurePlayer(url: url) }
        }
        if reportsRelinkStatus { setStatus("status.timelineMediaRelinked", url.lastPathComponent) }
        if reportsRelinkStatus, let previous = pendingRelinkUndoSnapshots.removeValue(forKey: id) {
            registerTimelineMediaUndo(previous: previous, actionKey: "undo.timeline.relinkAsset")
        }
    }

    private func applyLoadedTimelineActivityAsset(
        id: String,
        url: URL,
        activity loaded: ParsedActivity,
        reportsRelinkStatus: Bool
    ) {
        guard let existing = currentTimelineProject.asset(id: id), existing.kind == .activity else { return }
        activitySeriesByAssetID[id] = loaded.series
        activitySportByAssetID[id] = loaded.sport
        if reportsRelinkStatus {
            replaceTimelineAssetLocation(
                id: id,
                url: url,
                duration: loaded.series.duration,
                wallClockStart: loaded.series.activityStartDate,
                wallClockSource: loaded.series.activityStartDate == nil ? nil : .activityMetadata
            )
        } else {
            var updated = existing
            updated.duration = loaded.series.duration
            updated.wallClockStart = loaded.series.activityStartDate
            updated.wallClockSource = loaded.series.activityStartDate == nil ? nil : .activityMetadata
            if let index = timeline.assets.firstIndex(where: { $0.id == id }) {
                timeline.assets[index] = updated
            }
            if let index = activityAssets.firstIndex(where: { $0.id == id }) {
                activityAssets[index] = updated
            }
            offlineTimelineAssetReasons.removeValue(forKey: id)
        }
        if fitURL == existing.url || preferredActiveAssetID(kind: .activity) == id {
            fitURL = url
            series = loaded.series
        }
        refreshOverlayOrPreview()
        if reportsRelinkStatus { setStatus("status.timelineMediaRelinked", url.lastPathComponent) }
        if reportsRelinkStatus, let previous = pendingRelinkUndoSnapshots.removeValue(forKey: id) {
            registerTimelineMediaUndo(previous: previous, actionKey: "undo.timeline.relinkAsset")
        }
    }

    private func replaceTimelineAssetLocation(
        id: String,
        url: URL,
        duration: TimeInterval,
        width: Int? = nil,
        height: Int? = nil,
        framesPerSecond: Double? = nil,
        wallClockStart: Date?,
        wallClockSource: MediaWallClockSource?
    ) {
        guard let index = timeline.assets.firstIndex(where: { $0.id == id }) else { return }
        var updated = timeline.assets[index]
        updated.url = url
        updated.displayName = url.lastPathComponent
        updated.duration = duration
        updated.width = width ?? updated.width
        updated.height = height ?? updated.height
        updated.framesPerSecond = framesPerSecond ?? updated.framesPerSecond
        updated.wallClockStart = wallClockStart
        updated.wallClockSource = wallClockSource
        updated.bookmarkData = securityScopedBookmarkData(for: url)
        timeline.assets[index] = updated
        if let poolIndex = videoAssets.firstIndex(where: { $0.id == id }) { videoAssets[poolIndex] = updated }
        if let poolIndex = activityAssets.firstIndex(where: { $0.id == id }) { activityAssets[poolIndex] = updated }
        offlineTimelineAssetReasons.removeValue(forKey: id)
        videoWaveformPeaksByAssetID[id] = nil
        stopTimelineSecurityScopedAccess()
        startTimelineSecurityScopedAccess(for: timeline.assets)
    }

    private func markTimelineAssetLoadFailed(
        id: String,
        displayName: String,
        error: Error,
        reportsRelinkStatus: Bool
    ) {
        offlineTimelineAssetReasons[id] = Self.offlineReason(for: error, asset: timeline.asset(id: id))
        pendingRelinkUndoSnapshots.removeValue(forKey: id)
        if reportsRelinkStatus {
            setStatus("status.timelineMediaRelinkError", displayName, error.localizedDescription)
        }
    }

    private nonisolated static func offlineReason(
        for error: Error,
        asset: MediaAsset?
    ) -> TimelineAssetOfflineReason {
        let nsError = error as NSError
        if (nsError.domain == NSCocoaErrorDomain
                && nsError.code == CocoaError.fileNoSuchFile.rawValue)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOENT) {
            return .fileMissing
        }
        if (nsError.domain == NSCocoaErrorDomain
                && nsError.code == CocoaError.fileReadNoPermission.rawValue)
            || (nsError.domain == NSPOSIXErrorDomain && (nsError.code == EACCES || nsError.code == EPERM)) {
            return .permissionDenied
        }
        return asset?.kind == .activity ? .invalidFormat : .unreadableMedia
    }

    private func preferredActiveAssetID(kind: MediaAsset.Kind) -> String? {
        switch kind {
        case .video:
            return timeline.sourceMatchPoint?.videoAssetID ?? videoAssets.first?.id
        case .activity:
            return timeline.sourceMatchPoint?.activityAssetID ?? activityAssets.first?.id
        }
    }

    var pendingTimelineActionTitle: String {
        guard let pendingTimelineAction else { return "" }
        switch pendingTimelineAction {
        case .selectVideoAsset, .selectActivityAsset:
            return localized("timeline.confirmReplace.title")
        case .removeVideoAsset, .removeActivityAsset:
            return localized("timeline.confirmRemove.title")
        case .openTimelineProject, .openTimelineProjectFile, .newTimelineProject, .closeWindow:
            return localized("timeline.unsaved.title")
        }
    }

    var pendingTimelineActionMessage: String {
        guard let pendingTimelineAction else { return "" }
        switch pendingTimelineAction {
        case let .selectVideoAsset(id):
            return localized("timeline.confirmReplace.video", timelineAssetDisplayName(id: id))
        case let .selectActivityAsset(id):
            return localized("timeline.confirmReplace.activity", timelineAssetDisplayName(id: id))
        case let .removeVideoAsset(id):
            return localized("timeline.confirmRemove.video", timelineAssetDisplayName(id: id))
        case let .removeActivityAsset(id):
            return localized("timeline.confirmRemove.activity", timelineAssetDisplayName(id: id))
        case .openTimelineProject, .openTimelineProjectFile:
            return localized("timeline.unsaved.openProject")
        case .newTimelineProject:
            return localized("timeline.unsaved.newProject")
        case .closeWindow:
            return localized("timeline.unsaved.closeWindow")
        }
    }

    var pendingTimelineActionConfirmationTitle: String {
        guard let pendingTimelineAction else { return "" }
        switch pendingTimelineAction {
        case .selectVideoAsset, .selectActivityAsset:
            return localized("timeline.confirmReplace.action")
        case .removeVideoAsset, .removeActivityAsset:
            return localized("timeline.confirmRemove.action")
        case .openTimelineProject, .openTimelineProjectFile, .newTimelineProject, .closeWindow:
            return localized("timeline.unsaved.discard")
        }
    }

    @discardableResult
    func confirmPendingTimelineAction() -> TimelinePendingAction? {
        guard let action = pendingTimelineAction else { return nil }
        pendingTimelineAction = nil

        switch action {
        case let .selectVideoAsset(id):
            performSelectVideoAsset(id: id)
        case let .selectActivityAsset(id):
            performSelectActivityAsset(id: id)
        case let .removeVideoAsset(id):
            performRemoveVideoAsset(id: id)
        case let .removeActivityAsset(id):
            performRemoveActivityAsset(id: id)
        case .openTimelineProject:
            DispatchQueue.main.async { [weak self] in
                self?.presentOpenTimelineProjectPanel()
            }
        case let .openTimelineProjectFile(url):
            openTimelineProject(at: url)
        case let .newTimelineProject(layoutPresetID, mediaURLs):
            performNewTimelineProject(layoutPresetID: layoutPresetID, mediaURLs: mediaURLs)
        case .closeWindow:
            allowsNextWindowClose = true
            confirmedWindowCloseGeneration &+= 1
        }
        return action
    }

    func cancelPendingTimelineAction() {
        pendingTimelineAction = nil
    }

    func requestWindowClose() -> Bool {
        if allowsNextWindowClose {
            allowsNextWindowClose = false
            return true
        }
        guard hasUnsavedTimelineChanges else { return true }
        requestTimelineConfirmation(.closeWindow)
        return false
    }

    private func requestTimelineConfirmation(_ action: TimelinePendingAction) {
        guard pendingTimelineAction == nil else { return }
        pendingTimelineAction = action
    }

    private func timelineAssetDisplayName(id: String) -> String {
        timeline.asset(id: id)?.displayName
            ?? videoAssets.first { $0.id == id }?.displayName
            ?? activityAssets.first { $0.id == id }?.displayName
            ?? id
    }

    private func updateTimelineDirtyState() {
        guard let cleanTimelineSnapshot else { return }
        hasUnsavedTimelineChanges = timeline != cleanTimelineSnapshot
    }

    private func markTimelineProjectClean() {
        cleanTimelineSnapshot = timeline
        hasUnsavedTimelineChanges = false
    }

    func setVideo(_ url: URL) {
        guard !isExporting else { return }
        singleSourceAlignmentIsPending = false
        stopPlayback()
        cancelPreviewRenderTasks()
        videoLoadTask?.cancel()
        videoFrameService.clearCache()
        previewRenderGeneration += 1
        videoLoadGeneration += 1
        let loadGeneration = videoLoadGeneration
        previewOverlayRenderSize = nil
        videoURL = nil
        metadata = nil
        sourceDuration = 0
        backgroundImage = nil
        overlayImage = nil
        previewWarning = nil
        videoLoadFailure = nil
        setStatus("status.loadingVideo", url.lastPathComponent)

        videoLoadTask = Task.detached {
            do {
                let loaded = try await VideoMetadata.loadAsync(from: url)
                if Task.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self, self.videoLoadGeneration == loadGeneration else { return }
                        self.discardPendingVideoTimelineImport(id: url.path)
                    }
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.videoLoadGeneration == loadGeneration else { return }
                    self.videoURL = url
                    self.metadata = loaded
                    self.upsertVideoAsset(url: url, metadata: loaded)
                    self.setOutputWidth(Int(loaded.size.width.rounded()))
                    self.setOutputHeight(Int(loaded.size.height.rounded()))
                    self.setOutputFPS(loaded.framesPerSecond)
                    if let sourceBitRateKbps = Self.sourceVideoBitRateKbps(from: loaded) {
                        self.setBitRateKbps(sourceBitRateKbps)
                    }
                    self.sourceDuration = Self.sanitizedSourceDuration(loaded.duration)
                    self.resetExportTrimRangeToFullDuration()
                    self.applySuggestedOutputURLIfNeeded(for: url, replacingManualSelection: true)
                    self.previewTime = 0
                    if self.timelineUsesSingleSourceMigration {
                        self.configurePlayer(url: url)
                    } else {
                        self.configureTimelinePlayer()
                    }
                    self.setStatus("status.loadedVideo", url.lastPathComponent)
                    self.applyWallClockAutoSyncIfPossible()
                    self.refreshPreview()
                    self.videoLoadTask = nil
                    self.completeSourceReplacementUndoIfNeeded(kind: .video)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.videoLoadGeneration == loadGeneration else { return }
                    self.discardPendingVideoTimelineImport(id: url.path)
                    self.videoLoadTask = nil
                    self.cancelSourceReplacementUndoIfNeeded(kind: .video)
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.videoLoadGeneration == loadGeneration else { return }
                    self.videoLoadFailure = SourceLoadFailure(url: url, messageKey: "status.videoError", detail: message)
                    self.discardPendingVideoTimelineImport(id: url.path)
                    self.setStatus("status.videoError", message)
                    self.videoLoadTask = nil
                    self.cancelSourceReplacementUndoIfNeeded(kind: .video)
                }
            }
        }
    }

    func configurePlayer(url: URL) {
        pausePlayback()
        timelinePlayerItemReplacementGeneration += 1
        isReplacingTimelinePlayerItem = false
        playerTimeObserver?.remove()
        playerTimeObserver = nil
        timelinePlayerBuiltSignature = nil

        let player = AVPlayer(url: url)
        self.player = player
        attachPlayerTimeObserver(to: player)
    }

    private func attachPlayerTimeObserver(to player: AVPlayer) {
        let observerToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: Self.playerTimeObserverInterval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard self.isPlaying,
                      !self.isScrubbingPreview,
                      !self.isReplacingTimelinePlayerItem else { return }
                let seconds = CMTimeGetSeconds(time)
                guard seconds.isFinite else { return }
                let clamped = self.clampedPreviewTime(seconds)
                self.previewTime = clamped
                self.refreshPlaybackPreview(
                    minimumInterval: Self.playbackOverlayRefreshInterval,
                    coalesceIfBusy: true
                )
                if seconds >= self.previewTimeRange.upperBound {
                    self.pausePlayback()
                    self.player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
                }
            }
        }
        playerTimeObserver = PlayerTimeObserver(player: player, token: observerToken)
    }

    // MARK: - Custom timeline preview player

    /// Video geometry that determines the preview composition. Rebuilds are skipped while it is
    /// unchanged, so overlay-only edits never disturb playback.
    private struct TimelinePlayerSignature: Equatable {
        var clips: [TimelineClip]
        var assetURLs: [String: URL]
        var endTime: TimeInterval
    }

    private var currentTimelinePlayerSignature: TimelinePlayerSignature? {
        guard usesCustomTimelinePreview else { return nil }
        let clips = timeline.enabledClips(kind: .video)
        var assetURLs: [String: URL] = [:]
        for clip in clips {
            if let asset = timeline.asset(id: clip.assetID) {
                assetURLs[clip.assetID] = asset.url
            }
        }
        return TimelinePlayerSignature(clips: clips, assetURLs: assetURLs, endTime: timeline.duration)
    }

    /// Debounced rebuild so a clip drag's rapid timeline updates produce one rebuild at the end.
    private func scheduleTimelinePlayerRefreshIfNeeded() {
        guard !isExporting, usesCustomTimelinePreview else { return }
        guard currentTimelinePlayerSignature != timelinePlayerBuiltSignature else { return }
        timelinePlayerRebuildTask?.cancel()
        timelinePlayerRebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            self.timelinePlayerRebuildTask = nil
            self.configureTimelinePlayer()
        }
    }

    /// Point the shared AVPlayer at a composition assembled from the timeline's video clips, so
    /// custom-timeline playback gets smooth video and audio instead of timer-driven frame
    /// extraction. Gaps in the composition play as black frames with silent audio.
    private func configureTimelinePlayer() {
        guard !isExporting, usesCustomTimelinePreview else { return }
        timelinePlayerRebuildTask?.cancel()
        timelinePlayerRebuildTask = nil
        let signature = currentTimelinePlayerSignature
        timelinePlayerBuildGeneration += 1
        let generation = timelinePlayerBuildGeneration

        let project = currentTimelineProject
        let endTime = project.duration
        guard !project.enabledClips(kind: .video).isEmpty, endTime > 0 else {
            tearDownTimelinePlayer(signature: signature)
            return
        }

        Task.detached(priority: .userInitiated) {
            // AVMutableComposition is not Sendable; it is built here and then handed to the main
            // actor without further touches from this task.
            struct CompositionBox: @unchecked Sendable {
                let composition: AVMutableComposition?
                let videoComposition: AVVideoComposition?
                let failureMessage: String?
            }
            let box: CompositionBox
            do {
                let videoClips = try project.validatedVideoClipsForExport(
                    timelineStart: 0,
                    duration: endTime
                )
                let built = try TimelineVideoCompositionBuilder.make(
                    project: project,
                    videoClips: videoClips,
                    requiredEnd: endTime
                )
                box = CompositionBox(
                    composition: built.composition,
                    videoComposition: built.videoComposition,
                    failureMessage: nil
                )
            } catch {
                box = CompositionBox(
                    composition: nil,
                    videoComposition: nil,
                    failureMessage: error.localizedDescription
                )
            }
            await MainActor.run { [weak self] in
                guard let self,
                      generation == self.timelinePlayerBuildGeneration,
                      !self.isExporting,
                      self.usesCustomTimelinePreview else { return }
                if let composition = box.composition {
                    self.applyTimelinePlayerComposition(
                        composition,
                        videoComposition: box.videoComposition,
                        signature: signature
                    )
                } else {
                    // Unreadable/missing source: fall back to frame-extraction preview.
                    self.tearDownTimelinePlayer(signature: signature)
                    self.addDebugLog(
                        .preview,
                        "Timeline preview player unavailable: \(box.failureMessage ?? "unknown error")"
                    )
                }
            }
        }
    }

    private func applyTimelinePlayerComposition(
        _ composition: AVMutableComposition,
        videoComposition: AVVideoComposition?,
        signature: TimelinePlayerSignature?
    ) {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        replaceTimelinePlayerItem(item, resumePlayback: isPlaying)
        timelinePlayerBuiltSignature = signature
        backgroundImage = nil
        refreshOverlayOnly()
    }

    /// Replacing an AVPlayer item briefly resets its clock to zero. Ignore that transient clock
    /// update and seek the new item back to the exact timeline position the user was viewing.
    func replaceTimelinePlayerItem(_ item: AVPlayerItem, resumePlayback: Bool) {
        let preservedPreviewTime = previewTime
        timelinePlayerItemReplacementGeneration += 1
        let replacementGeneration = timelinePlayerItemReplacementGeneration
        isReplacingTimelinePlayerItem = true
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            // Switch drivers: the overlay clock hands playback over to the player.
            stopOverlayPlaybackTimer()
            let player = AVPlayer(playerItem: item)
            self.player = player
            attachPlayerTimeObserver(to: player)
        }
        guard let player else {
            isReplacingTimelinePlayerItem = false
            return
        }
        player.seek(
            to: CMTime(seconds: preservedPreviewTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      replacementGeneration == self.timelinePlayerItemReplacementGeneration else { return }
                guard abs(self.previewTime - preservedPreviewTime) < 0.000_5 else {
                    self.isReplacingTimelinePlayerItem = false
                    return
                }
                self.previewTime = preservedPreviewTime
                self.isReplacingTimelinePlayerItem = false
            }
        }
        if resumePlayback {
            player.play()
        }
    }

    private func tearDownTimelinePlayer(signature: TimelinePlayerSignature?) {
        timelinePlayerBuiltSignature = signature
        timelinePlayerItemReplacementGeneration += 1
        isReplacingTimelinePlayerItem = false
        guard player != nil else { return }
        pausePlayback()
        playerTimeObserver?.remove()
        playerTimeObserver = nil
        player = nil
        refreshPreview()
    }

    func togglePlayback() {
        isPlaying ? pausePlayback() : startPlayback()
    }

    func startPlayback() {
        guard !isExporting else { return }
        if usesCustomTimelinePreview,
           currentTimelinePlayerSignature != timelinePlayerBuiltSignature {
            // Stale or missing composition: rebuild in the background; if a player already
            // exists it keeps playing and picks up the fresh item when the build lands.
            configureTimelinePlayer()
        }
        if let player {
            if previewTime < previewTimeRange.lowerBound || previewTime >= previewTimeRange.upperBound {
                seekPreview(to: previewTimeRange.lowerBound)
            }
            isPlaying = true
            player.play()
        } else if series != nil || usesCustomTimelinePreview {
            startOverlayPlayback()
        }
    }

    func pausePlayback() {
        isPlaying = false
        player?.pause()
        stopOverlayPlaybackTimer()
    }

    func stopPlayback() {
        pausePlayback()
        playerTimeObserver?.remove()
        playerTimeObserver = nil
        timelinePlayerBuiltSignature = nil
        self.player = nil
    }

    /// 仅有运动数据、无视频时，用一个时钟推进 previewTime 驱动叠加层预览播放。
    private func startOverlayPlayback() {
        let range = previewTimeRange
        guard range.upperBound > range.lowerBound else { return }
        if previewTime < range.lowerBound || previewTime >= range.upperBound {
            seekPreview(to: range.lowerBound)
        }
        isPlaying = true
        overlayPlaybackLastTick = Date()
        let timer = Timer(timeInterval: Self.overlayPlaybackTickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.advanceOverlayPlayback() }
        }
        RunLoop.main.add(timer, forMode: .common)
        overlayPlaybackTimer = timer
    }

    private func advanceOverlayPlayback() {
        guard isPlaying, player == nil else {
            stopOverlayPlaybackTimer()
            return
        }
        let now = Date()
        let lastTick = overlayPlaybackLastTick ?? now
        overlayPlaybackLastTick = now
        // 拖动期间让位给用户，恢复后从新位置继续
        guard !isScrubbingPreview else { return }
        let range = previewTimeRange
        let delta = max(0, now.timeIntervalSince(lastTick))
        let next = previewTime + delta
        if next >= range.upperBound {
            previewTime = range.upperBound
            refreshPlaybackPreview(minimumInterval: Self.playbackOverlayRefreshInterval, coalesceIfBusy: true)
            pausePlayback()
            return
        }
        previewTime = next
        refreshPlaybackPreview(minimumInterval: Self.playbackOverlayRefreshInterval, coalesceIfBusy: true)
    }

    private func refreshPlaybackPreview(minimumInterval: TimeInterval, coalesceIfBusy: Bool) {
        guard !usesCustomTimelinePreview else {
            if player != nil {
                // The composition player shows the video; only the overlay needs re-rendering.
                refreshOverlayOnly(minimumInterval: minimumInterval, coalesceIfBusy: coalesceIfBusy)
                return
            }
            let now = Date()
            if minimumInterval > 0, now.timeIntervalSince(lastOverlayRefresh) < minimumInterval {
                return
            }
            lastOverlayRefresh = now
            refreshPreview()
            return
        }
        refreshOverlayOnly(minimumInterval: minimumInterval, coalesceIfBusy: coalesceIfBusy)
    }

    private func stopOverlayPlaybackTimer() {
        overlayPlaybackTimer?.invalidate()
        overlayPlaybackTimer = nil
        overlayPlaybackLastTick = nil
    }

    func seekPreview(to time: TimeInterval) {
        seekPreview(to: time, coalesceOverlayRefresh: true)
    }

    func scrubPreview(to time: TimeInterval) {
        beginPreviewScrubInteraction()
        seekPreview(to: time, coalesceOverlayRefresh: true, isScrubbing: true)
    }

    func stepPreviewFrame(by frameOffset: Int) {
        guard frameOffset != 0 else { return }
        scrubPreview(to: previewTime + Double(frameOffset) * previewFrameDuration)
    }

    var previewFrameDuration: TimeInterval {
        1 / previewFrameRate
    }

    var previewFrameRate: Double {
        Self.sanitizedOutputFrameRate(sourceFrameRate ?? outputFPS)
    }

    var previewDuration: TimeInterval {
        if usesCustomTimelinePreview {
            let duration = currentTimelineProject.duration
            if duration.isFinite, duration > 0 {
                return duration
            }
        }
        if videoURL == nil, let series {
            return series.duration
        }
        if sourceDuration > 0 {
            return sourceDuration
        }
        return series?.duration ?? 0
    }

    var previewTimeRange: ClosedRange<TimeInterval> {
        let duration = max(0, previewDuration)
        guard duration > 0 else { return 0...0 }
        let lowerBound = min(duration, max(0, effectiveExportTrimStart))
        let upperBound = max(lowerBound, min(duration, effectiveExportTrimEnd))
        return lowerBound...upperBound
    }

    var activityTrimSourceDuration: TimeInterval {
        guard let duration = series?.duration, duration.isFinite, duration > 0 else { return 0 }
        return min(duration, 86_400)
    }

    var effectiveActivityTrimStart: TimeInterval {
        sanitizedActivityTrimStart(activityTrim.startSeconds, sourceDuration: activityTrimSourceDuration)
    }

    var effectiveActivityTrimEnd: TimeInterval {
        sanitizedActivityTrimEnd(
            activityTrim.endSeconds,
            start: effectiveActivityTrimStart,
            sourceDuration: activityTrimSourceDuration
        )
    }

    var effectiveActivityTrimDuration: TimeInterval {
        max(0, effectiveActivityTrimEnd - effectiveActivityTrimStart)
    }

    var currentActivityElapsedForTrim: TimeInterval {
        guard activityTrimSourceDuration > 0 else { return 0 }
        let rawActivityTime = timeSync.fitElapsed(forVideoTime: previewTime)
        return min(activityTrimSourceDuration, max(0, rawActivityTime))
    }

    var currentActivityTrim: ActivityTrim {
        ActivityTrim(startSeconds: effectiveActivityTrimStart, endSeconds: effectiveActivityTrimEnd)
    }

    func setActivityTrimStart(_ value: TimeInterval) {
        guard !isExporting else { return }
        let sourceDuration = activityTrimSourceDuration
        let start = sanitizedActivityTrimStart(value, sourceDuration: sourceDuration)
        let end = sanitizedActivityTrimEnd(activityTrim.endSeconds, start: start, sourceDuration: sourceDuration)
        activityTrim = ActivityTrim(startSeconds: start, endSeconds: end)
        refreshOverlayOrPreview()
    }

    func setActivityTrimEnd(_ value: TimeInterval) {
        guard !isExporting else { return }
        let sourceDuration = activityTrimSourceDuration
        let start = effectiveActivityTrimStart
        let end = sanitizedActivityTrimEnd(value, start: start, sourceDuration: sourceDuration)
        activityTrim = ActivityTrim(startSeconds: start, endSeconds: end)
        refreshOverlayOrPreview()
    }

    func resetActivityTrimRange() {
        guard !isExporting else { return }
        activityTrim = .none
        refreshOverlayOrPreview()
    }

    func displayTelemetrySample(forVideoTime videoTime: TimeInterval) -> TelemetrySample {
        let rawActivityTime = timeSync.fitElapsed(forVideoTime: videoTime)
        let displayElapsed = activityTrim.displayElapsed(
            forRawElapsed: rawActivityTime,
            sourceDuration: series?.duration ?? 0
        )
        return series?.trimmed(by: activityTrim).sample(at: displayElapsed) ?? TelemetrySample(elapsed: displayElapsed)
    }

    func absoluteActivityDate(forVideoTime videoTime: TimeInterval) -> Date? {
        let rawActivityTime = timeSync.rawFitElapsed(forVideoTime: videoTime)
        return series?.date(atElapsed: rawActivityTime)
    }

    var exportTrimSourceDuration: TimeInterval {
        let duration: TimeInterval
        if usesCustomTimelinePreview {
            duration = currentTimelineProject.duration
        } else {
            duration = videoURL == nil ? series?.duration ?? 0 : sourceDuration
        }
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(duration, 86_400)
    }

    private var exportTrimEditingDuration: TimeInterval {
        let duration = exportTrimSourceDuration > 0 ? exportTrimSourceDuration : previewDuration
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(duration, 86_400)
    }

    var effectiveExportTrimStart: TimeInterval {
        sanitizedExportTrimStart(exportTrimStartSeconds, sourceDuration: exportTrimEditingDuration)
    }

    var effectiveExportTrimEnd: TimeInterval {
        sanitizedExportTrimEnd(
            exportTrimEndSeconds,
            start: effectiveExportTrimStart,
            sourceDuration: exportTrimEditingDuration
        )
    }

    var effectiveExportTrimDuration: TimeInterval {
        max(0, effectiveExportTrimEnd - effectiveExportTrimStart)
    }

    var estimatedExportFileSizeBytes: Int64 {
        Self.estimatedExportFileSizeBytes(
            duration: effectiveExportTrimDuration,
            width: outputWidth,
            height: outputHeight,
            framesPerSecond: outputFPS,
            bitRateKbps: bitRateKbps,
            codec: codec
        )
    }

    static func estimatedExportFileSizeBytes(
        duration: TimeInterval,
        width: Int,
        height: Int,
        framesPerSecond: Double,
        bitRateKbps: Int,
        codec: OverlayVideoCodec
    ) -> Int64 {
        guard duration.isFinite, duration > 0 else { return 0 }

        // Composited-video exports (HEVC/H.264) mux the source audio through, so add a nominal
        // AAC allowance on top of the video bitrate. Transparent overlay codecs carry no audio.
        let muxedAudioKbps: Double = 256

        let estimatedBitRateKbps: Double
        switch codec {
        case .proRes4444:
            // ProRes 4444 is a fixed-profile codec. Its nominal 1080p30 data rate is
            // about 330 Mb/s and scales with the number of pixels encoded per second.
            let bitsPerPixelPerFrame = 5.3
            estimatedBitRateKbps = Double(max(0, width))
                * Double(max(0, height))
                * max(0, framesPerSecond)
                * bitsPerPixelPerFrame
                / 1_000
        case .hevcAlpha:
            estimatedBitRateKbps = Double(max(0, bitRateKbps))
        case .hevc, .h264:
            // The encoder targets the chosen average bitrate regardless of resolution/frame rate,
            // so the video size tracks bitrate × duration; audio adds a small fixed overhead.
            estimatedBitRateKbps = Double(max(0, bitRateKbps)) + muxedAudioKbps
        }

        let estimatedBytes = duration * estimatedBitRateKbps * 125
        guard estimatedBytes.isFinite else { return Int64.max }
        return Int64(min(Double(Int64.max), max(0, estimatedBytes)).rounded())
    }

    func setExportTrimStart(_ value: TimeInterval) {
        guard !isExporting else { return }
        exportTrimRangeWasManuallyEdited = true
        let sourceDuration = exportTrimEditingDuration
        exportTrimStartSeconds = sanitizedExportTrimStart(value, sourceDuration: sourceDuration)
        exportTrimEndSeconds = sanitizedExportTrimEnd(
            exportTrimEndSeconds,
            start: exportTrimStartSeconds,
            sourceDuration: sourceDuration
        )
        clampPreviewToExportTrimRange()
    }

    func setExportTrimEnd(_ value: TimeInterval) {
        guard !isExporting else { return }
        exportTrimRangeWasManuallyEdited = true
        exportTrimEndSeconds = sanitizedExportTrimEnd(
            value,
            start: effectiveExportTrimStart,
            sourceDuration: exportTrimEditingDuration
        )
        clampPreviewToExportTrimRange()
    }

    func resetExportTrimRange() {
        guard !isExporting else { return }
        resetExportTrimRangeToFullDuration()
    }

    private func seekPreview(to time: TimeInterval, coalesceOverlayRefresh: Bool, isScrubbing: Bool = false) {
        guard !isExporting else { return }
        let clamped = clampedPreviewTime(time)
        if isScrubbing, abs(previewTime - clamped) < 0.000_5 {
            return
        }
        previewTime = clamped
        guard !usesCustomTimelinePreview else {
            guard let player else {
                refreshPreview()
                return
            }
            if isScrubbing {
                refreshOverlayOnly(coalesceIfBusy: coalesceOverlayRefresh, displayIntermediateResults: true)
                performScrubSeek(to: clamped, player: player)
            } else {
                pendingScrubSeekSeconds = nil
                player.seek(
                    to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                refreshOverlayOnly(coalesceIfBusy: coalesceOverlayRefresh)
            }
            return
        }
        if let player {
            if isScrubbing {
                refreshOverlayOnly(coalesceIfBusy: coalesceOverlayRefresh, displayIntermediateResults: true)
                performScrubSeek(to: clamped, player: player)
            } else {
                pendingScrubSeekSeconds = nil
                player.seek(
                    to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                refreshOverlayOnly(coalesceIfBusy: coalesceOverlayRefresh)
            }
        } else if series != nil {
            if isScrubbing {
                refreshOverlayOnly(coalesceIfBusy: coalesceOverlayRefresh, displayIntermediateResults: true)
            } else {
                refreshOverlayOnly(coalesceIfBusy: coalesceOverlayRefresh)
            }
        } else {
            refreshPreview()
        }
    }

    private func clampedPreviewTime(_ time: TimeInterval) -> TimeInterval {
        let range = previewTimeRange
        let finiteTime = time.isFinite ? time : range.lowerBound
        return min(range.upperBound, max(range.lowerBound, finiteTime))
    }

    private func clampPreviewToExportTrimRange() {
        let clamped = clampedPreviewTime(previewTime)
        guard abs(previewTime - clamped) >= 0.000_5 else { return }
        seekPreview(to: clamped)
    }

    private var scrubSeekTolerance: CMTime {
        let seconds = min(0.08, max(1.0 / 120.0, previewFrameDuration))
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    /// Issue a tolerant scrub seek only when none is in flight for this player; otherwise stash
    /// the newest target and let the in-flight completion chase it. A player swap drops the stale
    /// pending target via the identity checks.
    private func performScrubSeek(to seconds: TimeInterval, player: AVPlayer) {
        if scrubSeekInFlightPlayer === player {
            pendingScrubSeekSeconds = seconds
            return
        }
        scrubSeekInFlightPlayer = player
        pendingScrubSeekSeconds = nil
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: scrubSeekTolerance,
            toleranceAfter: scrubSeekTolerance
        ) { [weak self, weak player] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.scrubSeekInFlightPlayer === player {
                    self.scrubSeekInFlightPlayer = nil
                }
                guard let pending = self.pendingScrubSeekSeconds,
                      let player,
                      player === self.player else { return }
                self.pendingScrubSeekSeconds = nil
                self.performScrubSeek(to: pending, player: player)
            }
        }
    }

    private func beginPreviewScrubInteraction() {
        isScrubbingPreview = true
        scrubInteractionExpiresAt = Date().addingTimeInterval(Self.scrubInteractionHoldInterval)
        guard scrubInteractionTask == nil else { return }
        scrubInteractionTask = Task { @MainActor [weak self] in
            while let self {
                let remaining = self.scrubInteractionExpiresAt.timeIntervalSinceNow
                guard remaining > 0 else {
                    self.isScrubbingPreview = false
                    self.scrubInteractionTask = nil
                    return
                }
                do {
                    try await Task.sleep(nanoseconds: UInt64(max(1, remaining * 1_000_000_000)))
                } catch {
                    return
                }
            }
        }
    }

    func beginGaugeDragInteraction() {
        guard !isGaugeDragActive else { return }
        isGaugeDragActive = true
        beginLayoutUndoTransaction("undo.moveElement")
    }

    func endGaugeDragInteraction() {
        guard isGaugeDragActive else { return }
        isGaugeDragActive = false
        endLayoutUndoTransaction()
        guard !isExporting, series != nil else { return }
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    // MARK: - Media pool

    /// The pool asset currently loaded as the active video, if any.
    var activeVideoAssetID: String? {
        guard let videoURL else { return nil }
        return videoAssets.first { $0.url == videoURL }?.id
    }

    /// The pool asset currently loaded as the active activity, if any.
    var activeActivityAssetID: String? {
        guard let fitURL else { return nil }
        return activityAssets.first { $0.url == fitURL }?.id
    }

    var timelineAssetIDsInUse: Set<String> {
        Set(timeline.tracks.flatMap(\.clips).map(\.assetID))
    }

    var selectedMediaAsset: MediaAsset? {
        guard let selectedMediaAssetID else { return nil }
        return videoAssets.first { $0.id == selectedMediaAssetID }
            ?? activityAssets.first { $0.id == selectedMediaAssetID }
    }

    func selectMediaAsset(id: String) {
        guard videoAssets.contains(where: { $0.id == id })
                || activityAssets.contains(where: { $0.id == id }) else { return }
        selectedMediaAssetID = id
        selectedElementID = nil
        clearTimelineClipSelection()
    }

    func chooseManualRecordingDate(forAssetID id: String) {
        guard !isExporting,
              let asset = videoAssets.first(where: { $0.id == id }),
              asset.kind == .video else { return }

        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        picker.dateValue = asset.wallClockStart
            ?? activityAssets.compactMap(\.wallClockStart).first
            ?? Date()

        let alert = NSAlert()
        alert.messageText = localized("timeline.alignment.setRecordingTime")
        alert.informativeText = localized("timeline.alignment.setRecordingTimeMessage")
        alert.alertStyle = .informational
        alert.accessoryView = picker
        alert.addButton(withTitle: localized("timeline.alignment.applyRecordingTime"))
        alert.addButton(withTitle: localized("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setManualRecordingDate(picker.dateValue, forAssetID: id)
    }

    func setManualRecordingDate(_ date: Date, forAssetID id: String) {
        guard !isExporting,
              date.timeIntervalSinceReferenceDate.isFinite,
              let index = videoAssets.firstIndex(where: { $0.id == id }) else { return }

        if timelineUsesSingleSourceMigration, activeVideoAssetID == id {
            singleSourceAlignmentIsPending = true
        }
        var updated = videoAssets[index]
        updated.wallClockStart = date
        updated.wallClockSource = .manual
        videoAssets[index] = updated
        if let timelineIndex = timeline.assets.firstIndex(where: { $0.id == id }) {
            timeline.assets[timelineIndex].wallClockStart = date
            timeline.assets[timelineIndex].wallClockSource = .manual
        }
        for trackIndex in timeline.tracks.indices {
            for clipIndex in timeline.tracks[trackIndex].clips.indices
            where timeline.tracks[trackIndex].clips[clipIndex].assetID == id {
                timeline.tracks[trackIndex].clips[clipIndex].isAlignmentPending = true
            }
        }
        if activeVideoAssetID == id {
            if var activeMetadata = metadata {
                activeMetadata.creationDate = date
                activeMetadata.creationDateSource = .manual
                metadata = activeMetadata
            }
            applyWallClockAutoSync(force: true)
        }
        setStatus("status.manualRecordingTimeSet", updated.displayName)
    }

    func clearMediaAssetSelection() {
        selectedMediaAssetID = nil
    }

    func loadVideoWaveformIfNeeded(assetID: String) {
        guard videoWaveformPeaksByAssetID[assetID] == nil,
              videoWaveformLoadTasks[assetID] == nil,
              let asset = videoAssets.first(where: { $0.id == assetID }),
              asset.kind == .video,
              asset.duration > 0 else {
            return
        }

        let task = Task.detached(priority: .utility) { [weak self] in
            let peaks = (try? await AudioWaveformLoader.loadPeaks(
                from: asset.url,
                duration: asset.duration
            )) ?? []
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.videoWaveformLoadTasks[assetID] != nil else { return }
                self.videoWaveformPeaksByAssetID[assetID] = peaks
                self.videoWaveformLoadTasks[assetID] = nil
            }
        }
        videoWaveformLoadTasks[assetID] = task
    }

    /// Add or refresh a video in the pool (called once its metadata has loaded). Deduplicated by path.
    func upsertVideoAsset(url: URL, metadata: VideoMetadata) {
        var asset = MediaAsset(
            id: url.path,
            kind: .video,
            url: url,
            displayName: url.lastPathComponent,
            duration: metadata.duration,
            width: Int(metadata.size.width.rounded()),
            height: Int(metadata.size.height.rounded()),
            framesPerSecond: metadata.framesPerSecond,
            wallClockStart: metadata.creationDate,
            wallClockSource: metadata.creationDateSource
        )
        if let index = videoAssets.firstIndex(where: { $0.id == asset.id }) {
            if videoAssets[index].wallClockSource == .manual {
                asset.wallClockStart = videoAssets[index].wallClockStart
                asset.wallClockSource = .manual
            }
            videoAssets[index] = asset
        } else {
            videoAssets.append(asset)
        }
        drainPendingVideoTimelineImports()
        drainPendingPositionedVideoTimelineImports()
    }

    /// Add or refresh an activity in the pool (called once its telemetry has parsed). Deduplicated by path.
    func upsertActivityAsset(url: URL, series: TelemetrySeries, sport: TelemetrySport? = nil) {
        let asset = MediaAsset(
            id: url.path,
            kind: .activity,
            url: url,
            displayName: url.lastPathComponent,
            duration: series.duration,
            wallClockStart: series.activityStartDate,
            wallClockSource: series.activityStartDate == nil ? nil : .activityMetadata
        )
        activitySeriesByAssetID[asset.id] = series
        activitySportByAssetID[asset.id] = sport
        if let index = activityAssets.firstIndex(where: { $0.id == asset.id }) {
            activityAssets[index] = asset
        } else {
            activityAssets.append(asset)
        }
        drainPendingActivityTimelineImports()
        drainPendingPositionedActivityTimelineImports()
    }

    /// Keep the Finder selection order even though metadata loading can finish out of order.
    func queueImportedVideosForTimeline(_ urls: [URL]) {
        preserveExistingTimelineForImportedAppendIfNeeded()
        pendingVideoTimelineImportIDs.removeAll(keepingCapacity: true)
        for id in urls.map(\.path) where !pendingVideoTimelineImportIDs.contains(id) {
            pendingVideoTimelineImportIDs.append(id)
        }
        drainPendingVideoTimelineImports()
    }

    /// Keep the Finder selection order even though telemetry parsing can finish out of order.
    func queueImportedActivitiesForTimeline(_ urls: [URL]) {
        preserveExistingTimelineForImportedAppendIfNeeded()
        pendingActivityTimelineImportIDs.removeAll(keepingCapacity: true)
        for id in urls.map(\.path) where !pendingActivityTimelineImportIDs.contains(id) {
            pendingActivityTimelineImportIDs.append(id)
        }
        drainPendingActivityTimelineImports()
    }

    private func preserveExistingTimelineForImportedAppendIfNeeded() {
        guard timelineUsesSingleSourceMigration,
              timeline.tracks.contains(where: { !$0.clips.isEmpty }) else { return }
        rebuildCurrentTimelineProject()
        timelineUsesSingleSourceMigration = false
    }

    private func drainPendingVideoTimelineImports() {
        while let id = pendingVideoTimelineImportIDs.first,
              videoAssets.contains(where: { $0.id == id }) {
            pendingVideoTimelineImportIDs.removeFirst()
            if !timelineContainsAsset(id: id) {
                addVideoAssetToTimeline(id: id)
            }
        }
    }

    private func drainPendingActivityTimelineImports() {
        while let id = pendingActivityTimelineImportIDs.first,
              activityAssets.contains(where: { $0.id == id }),
              activitySeriesByAssetID[id] != nil {
            pendingActivityTimelineImportIDs.removeFirst()
            if !timelineContainsAsset(id: id) {
                addActivityAssetToTimeline(id: id)
            }
        }
    }

    private func discardPendingVideoTimelineImport(id: String) {
        pendingVideoTimelineImportIDs.removeAll { $0 == id }
        pendingVideoPositionedTimelineImports.removeAll { $0.assetID == id }
        drainPendingVideoTimelineImports()
        drainPendingPositionedVideoTimelineImports()
    }

    private func discardPendingActivityTimelineImport(id: String) {
        pendingActivityTimelineImportIDs.removeAll { $0 == id }
        pendingActivityPositionedTimelineImports.removeAll { $0.assetID == id }
        drainPendingActivityTimelineImports()
        drainPendingPositionedActivityTimelineImports()
    }

    private func drainPendingPositionedVideoTimelineImports() {
        while let pending = pendingVideoPositionedTimelineImports.first,
              videoAssets.contains(where: { $0.id == pending.assetID }) {
            pendingVideoPositionedTimelineImports.removeFirst()
            addVideoAssetToTimeline(
                id: pending.assetID,
                targetTrackID: pending.trackID,
                timelineStart: pending.timelineStart,
                autoAlignsWhenStartMissing: false
            )
        }
    }

    private func drainPendingPositionedActivityTimelineImports() {
        while let pending = pendingActivityPositionedTimelineImports.first,
              activityAssets.contains(where: { $0.id == pending.assetID }),
              activitySeriesByAssetID[pending.assetID] != nil {
            pendingActivityPositionedTimelineImports.removeFirst()
            addActivityAssetToTimeline(
                id: pending.assetID,
                targetTrackID: pending.trackID,
                timelineStart: pending.timelineStart,
                autoAlignsWhenStartMissing: false
            )
        }
    }

    /// Make a pooled video the active source.
    func selectVideoAsset(id: String) {
        guard !isExporting, let asset = videoAssets.first(where: { $0.id == id }), asset.url != videoURL else { return }
        guard timelineUsesSingleSourceMigration else {
            requestTimelineConfirmation(.selectVideoAsset(id: id))
            return
        }
        performSelectVideoAsset(id: id)
    }

    private func performSelectVideoAsset(id: String) {
        guard !isExporting, let asset = videoAssets.first(where: { $0.id == id }), asset.url != videoURL else { return }
        if !timelineUsesSingleSourceMigration {
            pendingSourceReplacementUndoSnapshot = timelineMediaUndoSnapshotNow
            pendingSourceReplacementKind = .video
        }
        timelineUsesSingleSourceMigration = true
        setVideo(asset.url)
    }

    /// Make a pooled activity the active source.
    func selectActivityAsset(id: String) {
        guard !isExporting, let asset = activityAssets.first(where: { $0.id == id }), asset.url != fitURL else { return }
        guard timelineUsesSingleSourceMigration else {
            requestTimelineConfirmation(.selectActivityAsset(id: id))
            return
        }
        performSelectActivityAsset(id: id)
    }

    private func performSelectActivityAsset(id: String) {
        guard !isExporting, let asset = activityAssets.first(where: { $0.id == id }), asset.url != fitURL else { return }
        if !timelineUsesSingleSourceMigration {
            pendingSourceReplacementUndoSnapshot = timelineMediaUndoSnapshotNow
            pendingSourceReplacementKind = .activity
        }
        timelineUsesSingleSourceMigration = true
        setFIT(asset.url)
    }

    private func completeSourceReplacementUndoIfNeeded(kind: MediaAsset.Kind) {
        guard pendingSourceReplacementKind == kind,
              let previous = pendingSourceReplacementUndoSnapshot else { return }
        pendingSourceReplacementKind = nil
        pendingSourceReplacementUndoSnapshot = nil
        registerTimelineMediaUndo(previous: previous, actionKey: "undo.timeline.replaceSource")
    }

    private func cancelSourceReplacementUndoIfNeeded(kind: MediaAsset.Kind) {
        guard pendingSourceReplacementKind == kind else { return }
        pendingSourceReplacementKind = nil
        pendingSourceReplacementUndoSnapshot = nil
    }

    /// Remove a pooled video. The active video cannot be removed.
    func removeVideoAsset(id: String) {
        guard id != activeVideoAssetID else { return }
        guard !timelineContainsAsset(id: id) else {
            requestTimelineConfirmation(.removeVideoAsset(id: id))
            return
        }
        performRemoveVideoAsset(id: id)
    }

    private func performRemoveVideoAsset(id: String) {
        guard id != activeVideoAssetID else { return }
        let previousUndoState = timelineMediaUndoSnapshotNow
        videoWaveformLoadTasks[id]?.cancel()
        videoWaveformLoadTasks[id] = nil
        videoWaveformPeaksByAssetID[id] = nil
        videoAssets.removeAll { $0.id == id }
        if selectedMediaAssetID == id { selectedMediaAssetID = nil }
        removeTimelineAsset(id: id)
        registerTimelineMediaUndo(previous: previousUndoState, actionKey: "undo.timeline.removeAsset")
    }

    /// Remove a pooled activity. The active activity cannot be removed.
    func removeActivityAsset(id: String) {
        guard id != activeActivityAssetID else { return }
        guard !timelineContainsAsset(id: id) else {
            requestTimelineConfirmation(.removeActivityAsset(id: id))
            return
        }
        performRemoveActivityAsset(id: id)
    }

    private func performRemoveActivityAsset(id: String) {
        guard id != activeActivityAssetID else { return }
        let previousUndoState = timelineMediaUndoSnapshotNow
        activityAssets.removeAll { $0.id == id }
        if selectedMediaAssetID == id { selectedMediaAssetID = nil }
        activitySeriesByAssetID.removeValue(forKey: id)
        activitySportByAssetID.removeValue(forKey: id)
        removeTimelineAsset(id: id)
        registerTimelineMediaUndo(previous: previousUndoState, actionKey: "undo.timeline.removeAsset")
    }

    private func timelineContainsAsset(id: String) -> Bool {
        timeline.tracks.contains { track in
            track.clips.contains { $0.assetID == id }
        }
    }

    func addActivityAssetToTimeline(id: String) {
        addActivityAssetToTimeline(id: id, targetTrackID: nil, timelineStart: nil)
    }

    /// Add a pooled activity as an overlay clip. Button-based insertion appends at the end of the
    /// project on the first available overlay lane; drops can target a lane and relative time.
    func addActivityAssetToTimeline(
        id: String,
        targetTrackID: String?,
        timelineStart: TimeInterval?,
        autoAlignsWhenStartMissing: Bool = true
    ) {
        guard !isExporting,
              let asset = activityAssets.first(where: { $0.id == id }),
              activitySeriesByAssetID[id] != nil,
              asset.duration > 0 else { return }

        var previousUndoState = timelineUndoSnapshotNow
        let previousTimelinePositionState = timelinePositionUndoStateNow
        var autoAlignmentShiftedTimeline = false
        defer {
            if autoAlignmentShiftedTimeline {
                previousUndoState.timelinePositionState = previousTimelinePositionState
            }
            registerTimelineUndoIfChanged(
                previous: previousUndoState,
                actionKey: "undo.timeline.addClip",
                coalescing: false
            )
            configureTimelinePlayer()
        }

        if timelineUsesSingleSourceMigration {
            rebuildCurrentTimelineProject()
            timelineUsesSingleSourceMigration = false
        }

        if !timeline.assets.contains(where: { $0.id == asset.id }) {
            timeline.assets.append(asset)
        }

        let placement: (
            start: TimeInterval?,
            statusKey: String,
            shiftedTimeline: Bool,
            isAlignmentPending: Bool
        )
        if autoAlignsWhenStartMissing {
            placement = resolveAutoAlignedTimelineStart(
                explicitStart: timelineStart,
                assetWallClockStart: asset.wallClockStart,
                assetWallClockSource: asset.wallClockSource,
                assetKind: asset.kind
            )
        } else {
            placement = (timelineStart, "status.timelineAddedActivity", false, false)
        }
        autoAlignmentShiftedTimeline = placement.shiftedTimeline

        var clip = TimelineClip(
            id: "overlay.clip.\(UUID().uuidString)",
            assetID: asset.id,
            timelineStart: max(0, placement.start ?? 0),
            duration: asset.duration,
            sourceIn: 0,
            layout: layout.sanitized,
            distanceUnit: distanceUnit,
            isAlignmentPending: placement.isAlignmentPending
        )

        let targetTrackIndex = targetTrackID.flatMap { targetTrackID in
            timeline.tracks.firstIndex {
                $0.id == targetTrackID && $0.kind == .overlay && !$0.isLocked
            }
        }
        if let trackIndex = targetTrackIndex
            ?? timeline.tracks.firstIndex(where: { $0.kind == .overlay && !$0.isLocked }) {
            // Default append lands after the lane's own last clip (0 on an empty lane) —
            // other tracks' content must not push it later. Land in the nearest gap that
            // fits so the track stays overlap-free.
            let laneEnd = timeline.tracks[trackIndex].clips.map(\.timelineEnd).max() ?? 0
            let proposedStart = max(0, placement.start ?? laneEnd)
            clip.timelineStart = placement.isAlignmentPending
                ? timeline.tracks[trackIndex].nonOverlappingStartAtOrAfter(
                    forClipID: clip.id,
                    duration: clip.duration,
                    proposedStart: proposedStart
                )
                : timeline.tracks[trackIndex].nonOverlappingStart(
                    forClipID: clip.id,
                    duration: clip.duration,
                    proposedStart: proposedStart
                )
            timeline.tracks[trackIndex].clips.append(clip)
            setStatus(placement.statusKey, asset.displayName)
            return
        }

        timeline.tracks.append(
            TimelineTrack(
                id: "overlay.track.\(UUID().uuidString)",
                kind: .overlay,
                name: nextTimelineTrackName(kind: .overlay),
                clips: [clip]
            )
        )
        setStatus(placement.statusKey, asset.displayName)
    }

    /// Wall-clock placement for imports without an explicit drop position. An explicit position
    /// (a drop) always wins; otherwise recording times decide regardless of import order — an
    /// asset recorded before the current timeline zero shifts the existing content right and
    /// lands at zero. A missing or implausible result falls back to the lane-end default
    /// near the selected counterpart or playhead and marks the clip as awaiting confirmation.
    private func resolveAutoAlignedTimelineStart(
        explicitStart: TimeInterval?,
        assetWallClockStart: Date?,
        assetWallClockSource: MediaWallClockSource?,
        assetKind: MediaAsset.Kind
    ) -> (
        start: TimeInterval?,
        statusKey: String,
        shiftedTimeline: Bool,
        isAlignmentPending: Bool
    ) {
        if let explicitStart {
            return (explicitStart, "status.timelineAddedActivity", false, false)
        }
        let pendingStart = pendingAlignmentTimelineStart(for: assetKind)
        let pendingStatusKey = assetWallClockSource == .untrustedExport
            ? "status.timelineExportDateRejected"
            : "status.timelineAlignmentPending"
        let trustedWallClockStart = assetWallClockSource == .untrustedExport ? nil : assetWallClockStart
        switch TimelineAutoAlignment.placement(forAssetWallClockStart: trustedWallClockStart, in: timeline) {
        case let .aligned(start):
            guard start < 0 else { return (start, "status.timelineAutoAligned", false, false) }
            // Shifting must move every track to keep relative alignment; a locked track
            // cannot move, so fall back instead of silently breaking its sync.
            guard !timeline.tracks.contains(where: { $0.isLocked && !$0.clips.isEmpty }) else {
                return (pendingStart, "status.timelineAutoAlignLocked", false, true)
            }
            shiftTimelineContent(by: -start)
            return (0, "status.timelineAutoAligned", true, false)
        case .missingWallClock:
            return (pendingStart, pendingStatusKey, false, true)
        case .unreasonable:
            return (pendingStart, "status.timelineAutoAlignGapTooLarge", false, true)
        case .noReference:
            let hasPlacedClips = timeline.tracks.contains { !$0.clips.isEmpty }
            guard hasPlacedClips else {
                if assetWallClockSource == .untrustedExport {
                    return (pendingStart, pendingStatusKey, false, true)
                }
                return (nil, "status.timelineAddedActivity", false, false)
            }
            return (pendingStart, pendingStatusKey, false, true)
        }
    }

    private func pendingAlignmentTimelineStart(for assetKind: MediaAsset.Kind) -> TimeInterval {
        guard timeline.tracks.contains(where: { !$0.clips.isEmpty }) else { return 0 }
        if let selectedTimelineClip,
           let selectedAsset = timeline.asset(id: selectedTimelineClip.assetID),
           selectedAsset.kind != assetKind {
            return selectedTimelineClip.timelineStart
        }
        return max(0, previewTime.isFinite ? previewTime : 0)
    }

    /// Move every clip later by `delta` so an earlier-recorded asset can land at timeline
    /// zero. Relative positions are untouched; a manually set export range and the playhead
    /// shift along so they keep pointing at the same content. Callers register the enclosing
    /// timeline undo step, which restores the shifted clips together with the added one.
    private func shiftTimelineContent(by delta: TimeInterval) {
        guard delta > 0 else { return }
        for trackIndex in timeline.tracks.indices {
            for clipIndex in timeline.tracks[trackIndex].clips.indices {
                timeline.tracks[trackIndex].clips[clipIndex].timelineStart += delta
            }
        }
        if exportTrimRangeWasManuallyEdited {
            exportTrimStartSeconds += delta
            exportTrimEndSeconds += delta
        }
        previewTime += delta
    }

    /// Add a pooled video as the next clip on the base video track.
    func addVideoAssetToTimeline(id: String) {
        addVideoAssetToTimeline(id: id, targetTrackID: nil, timelineStart: nil)
    }

    /// Add a pooled video to a chosen video lane at a relative timeline position. Button-based
    /// insertion keeps appending to the end of the base lane; a drop uses the nearest free gap.
    func addVideoAssetToTimeline(
        id: String,
        targetTrackID: String?,
        timelineStart: TimeInterval?,
        autoAlignsWhenStartMissing: Bool = true
    ) {
        guard !isExporting,
              let asset = videoAssets.first(where: { $0.id == id }),
              asset.duration > 0 else { return }

        var previousUndoState = timelineUndoSnapshotNow
        let previousTimelinePositionState = timelinePositionUndoStateNow
        var autoAlignmentShiftedTimeline = false
        defer {
            if autoAlignmentShiftedTimeline {
                previousUndoState.timelinePositionState = previousTimelinePositionState
            }
            registerTimelineUndoIfChanged(
                previous: previousUndoState,
                actionKey: "undo.timeline.addClip",
                coalescing: false
            )
            configureTimelinePlayer()
        }

        if timelineUsesSingleSourceMigration {
            rebuildCurrentTimelineProject()
            timelineUsesSingleSourceMigration = false
        }

        if !timeline.assets.contains(where: { $0.id == asset.id }) {
            timeline.assets.append(asset)
        }

        let placement: (
            start: TimeInterval?,
            statusKey: String,
            shiftedTimeline: Bool,
            isAlignmentPending: Bool
        )
        if autoAlignsWhenStartMissing {
            placement = resolveAutoAlignedTimelineStart(
                explicitStart: timelineStart,
                assetWallClockStart: asset.wallClockStart,
                assetWallClockSource: asset.wallClockSource,
                assetKind: asset.kind
            )
        } else {
            placement = (timelineStart, "status.timelineAddedActivity", false, false)
        }
        autoAlignmentShiftedTimeline = placement.shiftedTimeline

        var clip = TimelineClip(
            id: "video.clip.\(UUID().uuidString)",
            assetID: asset.id,
            timelineStart: max(0, placement.start ?? 0),
            duration: asset.duration,
            sourceIn: 0,
            isAlignmentPending: placement.isAlignmentPending
        )

        let targetTrackIndex = targetTrackID.flatMap { targetTrackID in
            timeline.tracks.firstIndex {
                $0.id == targetTrackID && $0.kind == .video && !$0.isLocked
            }
        }
        let proposedStart = max(0, placement.start ?? 0)
        let isAutoAligned = !placement.isAlignmentPending
            && targetTrackIndex == nil
            && timelineStart == nil
            && placement.start != nil
        let availableTrackIndex = timeline.tracks.firstIndex { track in
            guard track.kind == .video, !track.isLocked else { return false }
            guard isAutoAligned else { return true }
            return abs(track.nonOverlappingStart(
                forClipID: clip.id,
                duration: clip.duration,
                proposedStart: proposedStart
            ) - proposedStart) < 1e-6
        }
        if let trackIndex = targetTrackIndex
            ?? availableTrackIndex {
            // Default append lands after the lane's own last clip (0 on an empty lane) —
            // overlay-track content must not push a new video later.
            let laneEnd = timeline.tracks[trackIndex].clips.map(\.timelineEnd).max() ?? 0
            let proposedStart = max(0, placement.start ?? laneEnd)
            clip.timelineStart = placement.isAlignmentPending
                ? timeline.tracks[trackIndex].nonOverlappingStartAtOrAfter(
                    forClipID: clip.id,
                    duration: clip.duration,
                    proposedStart: proposedStart
                )
                : timeline.tracks[trackIndex].nonOverlappingStart(
                    forClipID: clip.id,
                    duration: clip.duration,
                    proposedStart: proposedStart
                )
            timeline.tracks[trackIndex].clips.append(clip)
        } else {
            timeline.tracks.insert(
                TimelineTrack(
                    id: "video.track.\(UUID().uuidString)",
                    kind: .video,
                    name: nextTimelineTrackName(kind: .video),
                    clips: [clip]
                ),
                at: 0
            )
        }
        setStatus(placement.statusKey, asset.displayName)
    }

    func removeEmptyTimelineTrack(id: String) {
        guard !isExporting,
              let trackIndex = timeline.tracks.firstIndex(where: { $0.id == id }),
              !timeline.tracks[trackIndex].isLocked,
              timeline.tracks[trackIndex].clips.isEmpty else {
            return
        }

        let previousUndoState = timelineUndoSnapshotNow
        beginTimelineClipEditingIfNeeded()
        timeline.tracks.remove(at: trackIndex)
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.deleteTrack",
            coalescing: false
        )
    }

    /// Add an empty lane while preserving bottom-to-top video/overlay stacking.
    @discardableResult
    private func addTimelineTrack(kind: TimelineTrack.Kind) -> String? {
        guard !isExporting else { return nil }

        let previousUndoState = timelineUndoSnapshotNow
        beginTimelineClipEditingIfNeeded()
        let track = TimelineTrack(
            id: "\(kind.rawValue).track.\(UUID().uuidString)",
            kind: kind,
            name: nextTimelineTrackName(kind: kind)
        )
        let insertionIndex = kind == .video
            ? (timeline.tracks.firstIndex(where: { $0.kind == .overlay }) ?? timeline.tracks.endIndex)
            : timeline.tracks.endIndex
        timeline.tracks.insert(track, at: insertionIndex)
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.addTrack",
            coalescing: false
        )
        return track.id
    }

    @discardableResult
    func addVideoTimelineTrack() -> String? {
        addTimelineTrack(kind: .video)
    }

    @discardableResult
    func addOverlayTimelineTrack() -> String? {
        addTimelineTrack(kind: .overlay)
    }

    func renameTimelineTrack(id: String, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isExporting,
              !trimmedName.isEmpty,
              let trackIndex = timeline.tracks.firstIndex(where: { $0.id == id }),
              timeline.tracks[trackIndex].name != trimmedName else {
            return
        }

        let previousUndoState = timelineUndoSnapshotNow
        beginTimelineClipEditingIfNeeded()
        timeline.tracks[trackIndex].name = trimmedName
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.renameTrack",
            coalescing: false
        )
    }

    func setTimelineTrackEnabled(id: String, isEnabled: Bool) {
        guard !isExporting,
              let trackIndex = timeline.tracks.firstIndex(where: { $0.id == id }),
              timeline.tracks[trackIndex].isEnabled != isEnabled else {
            return
        }

        let previousUndoState = timelineUndoSnapshotNow
        beginTimelineClipEditingIfNeeded()
        timeline.tracks[trackIndex].isEnabled = isEnabled
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.toggleTrack",
            coalescing: false
        )
        configureTimelinePlayer()
        refreshOverlayOrPreview()
    }

    func setTimelineClipEnabled(id: String, isEnabled: Bool) {
        guard !isExporting else { return }
        for trackIndex in timeline.tracks.indices {
            guard !timeline.tracks[trackIndex].isLocked,
                  let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }),
                  timeline.tracks[trackIndex].clips[clipIndex].isEnabled != isEnabled else {
                continue
            }

            let previousUndoState = timelineUndoSnapshotNow
            beginTimelineClipEditingIfNeeded()
            timeline.tracks[trackIndex].clips[clipIndex].isEnabled = isEnabled
            registerTimelineUndoIfChanged(
                previous: previousUndoState,
                actionKey: "undo.timeline.toggleClip",
                coalescing: false
            )
            configureTimelinePlayer()
            refreshOverlayOrPreview()
            return
        }
    }

    func toggleSelectedTimelineClipsEnabled() {
        let selectedIDs = editableSelectedTimelineClipIDs
        guard !selectedIDs.isEmpty else { return }
        let shouldEnable = timeline.tracks
            .flatMap(\.clips)
            .filter { selectedIDs.contains($0.id) }
            .contains { !$0.isEnabled }
        let previousUndoState = timelineUndoSnapshotNow
        beginTimelineClipEditingIfNeeded()

        for trackIndex in timeline.tracks.indices where !timeline.tracks[trackIndex].isLocked {
            for clipIndex in timeline.tracks[trackIndex].clips.indices
            where selectedIDs.contains(timeline.tracks[trackIndex].clips[clipIndex].id) {
                timeline.tracks[trackIndex].clips[clipIndex].isEnabled = shouldEnable
            }
        }
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.toggleClip",
            coalescing: false
        )
        configureTimelinePlayer()
        refreshOverlayOrPreview()
    }

    func setTimelineTrackLocked(id: String, isLocked: Bool) {
        guard !isExporting,
              let trackIndex = timeline.tracks.firstIndex(where: { $0.id == id }),
              timeline.tracks[trackIndex].isLocked != isLocked else {
            return
        }

        let previousUndoState = timelineUndoSnapshotNow
        beginTimelineClipEditingIfNeeded()
        timeline.tracks[trackIndex].isLocked = isLocked
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.lockTrack",
            coalescing: false
        )
    }

    private func nextTimelineTrackName(kind: TimelineTrack.Kind) -> String {
        let prefix = kind == .video ? "V" : "O"
        let usedNames = Set(timeline.tracks.filter { $0.kind == kind }.map(\.name))
        var number = 1
        while usedNames.contains("\(prefix)\(number)") {
            number += 1
        }
        return "\(prefix)\(number)"
    }

    /// Timeline representation of the currently active source(s), used by preview/export.
    /// Stored on the model so timeline editing has one place to write into.
    var currentTimelineProject: TimelineProject {
        timeline
    }

    private func rebuildCurrentTimelineProject() {
        guard timelineUsesSingleSourceMigration else {
            updateTimelineOutputSettings()
            guard let clipID = layoutEditingTimelineClipID else { return }
            for trackIndex in timeline.tracks.indices where !timeline.tracks[trackIndex].isLocked {
                guard let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) else {
                    continue
                }
                timeline.tracks[trackIndex].clips[clipIndex].layout = layout.sanitized
                return
            }
            layoutEditingTimelineClipID = nil
            return
        }
        let video = videoURL.flatMap { url in videoAssets.first { $0.url == url } }
        let activity = fitURL.flatMap { url in activityAssets.first { $0.url == url } }
        var project = TimelineProject.migratingSingleSource(
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            framesPerSecond: outputFPS,
            distanceUnit: distanceUnit,
            videoAsset: video,
            activityAsset: activity,
            sync: timeSync,
            layout: layout,
            isAlignmentPending: singleSourceAlignmentIsPending
        )
        project.exportSettings = currentTimelineProjectExportSettings
        timeline = project
        if isPlaying, usesCustomTimelinePreview {
            pausePlayback()
        }
    }

    /// Match-point inputs describe source time against source time. In the initial single-source
    /// project they rebuild the relative placement from scratch. After manual timeline editing,
    /// they re-align only the active video/activity pair while preserving the video's timeline
    /// position whenever both clips can stay at or after timeline zero.
    /// Whether the current match point came from `applyWallClockAutoSyncIfPossible`. An
    /// auto-derived sync may be replaced by a newer auto-alignment (e.g. after loading a
    /// different activity), but any other sync source is treated as user intent and kept.
    private var syncWasAutoAlignedByWallClock = false
    private var isApplyingWallClockAutoSync = false

    /// Single-source auto alignment: when the active video and activity both carry recording
    /// times and the user has not set a match point, derive the sync from the wall clocks so
    /// the migrated timeline places both clips at their real relative positions.
    func applyWallClockAutoSyncIfPossible() {
        applyWallClockAutoSync(force: false)
    }

    var canReapplyWallClockAutoSync: Bool {
        guard !isExporting, canEditTimelineSync else { return false }
        if case .aligned = wallClockAlignmentForActiveSources {
            return true
        }
        return false
    }

    func reapplyWallClockAutoSyncUnavailableReasonKey(for clipID: String) -> String? {
        if isExporting {
            return "timeline.alignment.unavailable.exporting"
        }
        guard canEditTimelineSync else {
            return "timeline.alignment.unavailable.singlePair"
        }
        switch wallClockAlignmentForActiveSources {
        case .missingWallClock:
            return "status.autoSyncMissingWallClock"
        case .gapTooLarge:
            return "status.autoSyncGapTooLarge"
        case .aligned:
            guard timelineAlignmentOffsetMilliseconds(for: clipID) != nil else {
                return "timeline.alignment.unavailable.matchedClip"
            }
            return nil
        }
    }

    func reapplyWallClockAutoSync() {
        applyWallClockAutoSync(force: true)
    }

    private func applyWallClockAutoSync(force: Bool) {
        guard videoURL != nil, let fitURL else { return }
        if force {
            guard canEditTimelineSync else { return }
        } else {
            guard timelineUsesSingleSourceMigration else { return }
        }
        let syncIsUntouched = syncMode == .syncPoint && syncVideoSeconds == 0 && syncFITSeconds == 0
        guard force || syncIsUntouched || syncWasAutoAlignedByWallClock else { return }
        switch wallClockAlignmentForActiveSources {
        case let .aligned(videoSourceTime, activitySourceTime):
            setActiveSourceAlignmentPending(false)
            guard force || syncVideoSeconds != videoSourceTime || syncFITSeconds != activitySourceTime else {
                syncWasAutoAlignedByWallClock = true
                return
            }
            isApplyingWallClockAutoSync = true
            syncMode = .syncPoint
            syncVideoSeconds = videoSourceTime
            syncFITSeconds = activitySourceTime
            isApplyingWallClockAutoSync = false
            syncWasAutoAlignedByWallClock = true
            setStatusAndToast(.success, "status.timelineAutoAligned", fitURL.lastPathComponent)
        case .gapTooLarge:
            setActiveSourceAlignmentPending(true)
            setStatusAndToast(.warning, "status.autoSyncGapTooLarge")
        case .missingWallClock:
            setActiveSourceAlignmentPending(true)
            if force {
                setStatusAndToast(.warning, "status.autoSyncMissingWallClock")
            }
        }
    }

    private func setActiveSourceAlignmentPending(_ isPending: Bool) {
        singleSourceAlignmentIsPending = isPending
        guard !timelineUsesSingleSourceMigration else {
            rebuildCurrentTimelineProject()
            return
        }
        let activeAssetIDs = Set([activeVideoAssetID, activeActivityAssetID].compactMap { $0 })
        guard !activeAssetIDs.isEmpty else { return }
        var updatedTimeline = timeline
        for trackIndex in updatedTimeline.tracks.indices {
            for clipIndex in updatedTimeline.tracks[trackIndex].clips.indices
            where activeAssetIDs.contains(updatedTimeline.tracks[trackIndex].clips[clipIndex].assetID) {
                updatedTimeline.tracks[trackIndex].clips[clipIndex].isAlignmentPending = isPending
            }
        }
        if updatedTimeline != timeline {
            timeline = updatedTimeline
        }
    }

    private var wallClockAlignmentForActiveSources: TimelineAutoAlignment.SingleSourceAlignment {
        let project = currentTimelineProject
        let activeVideoAsset = activeVideoAssetID.flatMap { project.asset(id: $0) }
        let videoStart = activeVideoAsset?.wallClockSource == .manual
                || activeVideoAsset?.wallClockSource == .untrustedExport
            ? activeVideoAsset?.wallClockStart
            : metadata?.creationDate ?? activeVideoAsset?.wallClockStart
        let activityStart = series?.activityStartDate
            ?? activeActivityAssetID.flatMap { project.asset(id: $0)?.wallClockStart }
        return TimelineAutoAlignment.singleSourceAlignment(
            videoWallClockStart: videoStart,
            activityWallClockStart: activityStart
        )
    }

    var wallClockAlignmentMarkerTime: TimeInterval? {
        Self.wallClockAlignmentMarkerTime(in: currentTimelineProject)
    }

    static func wallClockAlignmentMarkerTime(in project: TimelineProject) -> TimeInterval? {
        guard let matchPoint = project.sourceMatchPoint,
              let videoAsset = project.asset(id: matchPoint.videoAssetID),
              let activityAsset = project.asset(id: matchPoint.activityAssetID),
              case let .aligned(expectedVideoTime, expectedActivityTime) = TimelineAutoAlignment.singleSourceAlignment(
                  videoWallClockStart: videoAsset.wallClockStart,
                  activityWallClockStart: activityAsset.wallClockStart
              ),
              abs(matchPoint.videoSourceTime - expectedVideoTime) < 0.001,
              abs(matchPoint.activitySourceTime - expectedActivityTime) < 0.001,
              let videoClip = project.tracks
                  .filter({ $0.kind == .video })
                  .flatMap(\.clips)
                  .first(where: { $0.assetID == matchPoint.videoAssetID }) else {
            return nil
        }
        return videoClip.timelineTime(forSourceTime: matchPoint.videoSourceTime)
    }

    func timelineAlignmentOffsetMilliseconds(for clipID: String) -> Int? {
        let project = currentTimelineProject
        guard let markerTime = Self.wallClockAlignmentMarkerTime(in: project),
              let matchPoint = project.sourceMatchPoint,
              let clip = project.tracks
                  .filter({ $0.kind == .overlay })
                  .flatMap(\.clips)
                  .first(where: { $0.id == clipID && $0.assetID == matchPoint.activityAssetID }) else {
            return nil
        }
        let activityMatchTime = clip.timelineTime(forSourceTime: matchPoint.activitySourceTime)
        return Int(((activityMatchTime - markerTime) * 1_000).rounded())
    }

    func setTimelineAlignmentOffsetMilliseconds(clipID: String, milliseconds: Int) {
        guard let current = timelineAlignmentOffsetMilliseconds(for: clipID),
              let clip = timelineClip(id: clipID) else { return }
        let timelineStart = clip.timelineStart + Double(milliseconds - current) / 1_000
        moveTimelineClip(id: clipID, toTimelineStart: timelineStart)
    }

    private func updateTimelineForSyncChange() {
        let clearsPendingAlignment = !isApplyingWallClockAutoSync
        if clearsPendingAlignment {
            // Any other sync write (launch options, project restore) is user/state intent;
            // stop auto-alignment from overriding it later.
            syncWasAutoAlignedByWallClock = false
            singleSourceAlignmentIsPending = false
        }
        guard !isRestoringTimelineSourceMatchPoint else { return }
        guard !timelineUsesSingleSourceMigration else {
            rebuildCurrentTimelineProject()
            return
        }
        guard let videoAssetID = activeVideoAssetID,
              let activityAssetID = activeActivityAssetID,
              let videoClipID = timelineClipID(kind: .video, assetID: videoAssetID),
              let activityClipID = timelineClipID(kind: .overlay, assetID: activityAssetID) else {
            return
        }

        let sync = timeSync
        var updatedTimeline = timeline
        updatedTimeline.sourceMatchPoint = TimelineSourceMatchPoint(
            videoAssetID: videoAssetID,
            activityAssetID: activityAssetID,
            videoSourceTime: sync.videoSyncTime,
            activitySourceTime: sync.fitSyncTime
        )
        updatedTimeline.alignMatchPoint(
            anchorClipID: videoClipID,
            anchorSourceTime: sync.videoSyncTime,
            movingClipID: activityClipID,
            movingSourceTime: sync.fitSyncTime
        )
        if clearsPendingAlignment {
            for trackIndex in updatedTimeline.tracks.indices {
                for clipIndex in updatedTimeline.tracks[trackIndex].clips.indices
                where updatedTimeline.tracks[trackIndex].clips[clipIndex].assetID == videoAssetID
                    || updatedTimeline.tracks[trackIndex].clips[clipIndex].assetID == activityAssetID {
                    updatedTimeline.tracks[trackIndex].clips[clipIndex].isAlignmentPending = false
                }
            }
        }
        guard updatedTimeline != timeline else { return }
        timeline = updatedTimeline
        refreshOverlayOrPreview()
    }

    private func restoreTimelineSourceMatchPoint(
        _ matchPoint: TimelineSourceMatchPoint?,
        activeVideoAssetID: String?,
        activeActivityAssetID: String?
    ) {
        let matchesActiveSources = matchPoint.map { point in
            point.videoAssetID == activeVideoAssetID && point.activityAssetID == activeActivityAssetID
        } ?? false
        isRestoringTimelineSourceMatchPoint = true
        syncMode = .syncPoint
        syncVideoSeconds = matchesActiveSources ? nonNegativeTime(matchPoint?.videoSourceTime ?? 0) : 0
        syncFITSeconds = matchesActiveSources ? nonNegativeTime(matchPoint?.activitySourceTime ?? 0) : 0
        isRestoringTimelineSourceMatchPoint = false
    }

    private func timelineClipID(kind: TimelineTrack.Kind, assetID: String) -> String? {
        timeline.tracks
            .filter { $0.kind == kind }
            .flatMap(\.clips)
            .first { $0.assetID == assetID }?
            .id
    }

    private func updateTimelineOutputSettings() {
        timeline.outputWidth = outputWidth
        timeline.outputHeight = outputHeight
        timeline.framesPerSecond = outputFPS
        timeline.distanceUnit = distanceUnit
    }

    private func timelineClip(id: String) -> TimelineClip? {
        timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == id }
    }

    private func repairSelectedTimelineClipIfNeeded() {
        selectedTimelineClipIDs = selectedTimelineClipIDs.filter { timelineClip(id: $0) != nil }
        guard let selectedTimelineClipID else { return }
        if timelineClip(id: selectedTimelineClipID) == nil {
            self.selectedTimelineClipID = firstSelectedTimelineClipID
        }
    }

    private func removeTimelineAsset(id: String) {
        guard !timelineUsesSingleSourceMigration else { return }
        timeline.assets.removeAll { $0.id == id }
        timeline.tracks = timeline.tracks.compactMap { track in
            var updated = track
            updated.clips.removeAll { $0.assetID == id }
            return updated.clips.isEmpty ? nil : updated
        }
        repairSelectedTimelineClipIfNeeded()
    }

    /// Telemetry series backing an activity asset: a loaded pool entry, or the active source.
    func activitySeries(forAssetID id: String) -> TelemetrySeries? {
        if let loaded = activitySeriesByAssetID[id] {
            return loaded
        }
        if let activeActivityAssetID, activeActivityAssetID == id {
            return series
        }
        return nil
    }

    func timelineTelemetrySeriesForExport(project: TimelineProject) -> [String: TelemetrySeries] {
        project.tracks
            .filter { $0.kind == .overlay }
            .flatMap(\.clips)
            .reduce(into: [:]) { partialResult, clip in
                if let loadedSeries = activitySeriesByAssetID[clip.assetID] {
                    partialResult[clip.assetID] = loadedSeries
                } else if let activeSeries = series,
                          let activeActivityAssetID,
                          clip.assetID == activeActivityAssetID {
                    partialResult[clip.assetID] = activeSeries
                }
            }
    }

    private func timelinePreviewSnapshot(at timelineTime: TimeInterval) -> TimelinePreviewSnapshot? {
        let project = currentTimelineProject
        let activeVideoClip = project.activeClips(kind: .video, atTimelineTime: timelineTime).last
        let videoURL = activeVideoClip.flatMap { clip -> URL? in
            guard let asset = project.asset(id: clip.assetID), asset.kind == .video else { return nil }
            return asset.url
        }
        let videoTime = activeVideoClip?.sourceTime(atTimelineTime: timelineTime) ?? timelineTime

        let overlayLayers: [TimelinePreviewOverlayLayer] = project
            .activeClips(kind: .overlay, atTimelineTime: timelineTime)
            .compactMap { clip -> TimelinePreviewOverlayLayer? in
                guard let asset = project.asset(id: clip.assetID),
                      asset.kind == .activity else { return nil }
                let loadedSeries: TelemetrySeries?
                if let series = activitySeriesByAssetID[asset.id] {
                    loadedSeries = series
                } else if let activeSeries = series,
                          let activeActivityAssetID,
                          activeActivityAssetID == asset.id {
                    loadedSeries = activeSeries
                } else {
                    loadedSeries = nil
                }
                guard let loadedSeries else { return nil }
                return TimelinePreviewOverlayLayer(
                    series: loadedSeries,
                    timeSync: TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: clip.sourceIn - clip.timelineStart),
                    layout: clip.layout ?? .default,
                    distanceUnit: clip.distanceUnit ?? project.distanceUnit
                )
            }

        guard videoURL != nil || !overlayLayers.isEmpty else { return nil }
        return TimelinePreviewSnapshot(
            videoURL: videoURL,
            videoTime: videoTime,
            overlayLayers: overlayLayers
        )
    }

    /// Source-video time under the playhead for the pair edited by the Sync panel.
    /// In a custom timeline, blank canvas and clips from other video assets are not sync frames.
    var currentVideoSourceTimeForSync: TimeInterval? {
        guard videoURL != nil else { return nil }
        guard usesCustomTimelinePreview else { return previewTime }
        guard let activeVideoAssetID else { return nil }
        return currentTimelineProject
            .activeClips(kind: .video, atTimelineTime: previewTime)
            .last { $0.assetID == activeVideoAssetID }?
            .sourceTime(atTimelineTime: previewTime)
    }

    var canMarkSportStart: Bool {
        !isExporting && canEditTimelineSync && player != nil && currentVideoSourceTimeForSync != nil
    }

    /// Sync edits are intentionally limited to the unambiguous single-pair workflow. Moving the
    /// complete clips is allowed; splitting, source trimming, adding clips, or locking either track
    /// disables the panel.
    var canEditTimelineSync: Bool {
        let project = currentTimelineProject
        let videoTracks = project.tracks.filter { $0.kind == .video }
        let overlayTracks = project.tracks.filter { $0.kind == .overlay }
        let videoClips = videoTracks.flatMap(\.clips)
        let overlayClips = overlayTracks.flatMap(\.clips)
        guard videoClips.count == 1,
              overlayClips.count == 1,
              let videoClip = videoClips.first,
              let overlayClip = overlayClips.first,
              let videoTrack = videoTracks.first(where: { !$0.clips.isEmpty }),
              let overlayTrack = overlayTracks.first(where: { !$0.clips.isEmpty }),
              let videoAsset = project.asset(id: videoClip.assetID),
              let overlayAsset = project.asset(id: overlayClip.assetID),
              videoAsset.kind == .video,
              overlayAsset.kind == .activity,
              videoClip.assetID == activeVideoAssetID,
              overlayClip.assetID == activeActivityAssetID,
              !videoTrack.isLocked,
              !overlayTrack.isLocked else {
            return false
        }
        let epsilon = 1e-6
        return abs(videoClip.sourceIn) <= epsilon
            && abs(overlayClip.sourceIn) <= epsilon
            && abs(videoClip.duration - videoAsset.duration) <= epsilon
            && abs(overlayClip.duration - overlayAsset.duration) <= epsilon
    }

    /// Video time at which activity elapsed 0 currently lands (the overlay clip's zero point on the timeline).
    var activitySyncZeroVideoTime: TimeInterval {
        timeSync.videoSyncTime - timeSync.fitSyncTime
    }

    /// Set a canonical source match point where activity elapsed 0 corresponds to `videoTime`.
    /// Clip dragging no longer calls this; it remains the model-level helper for match-point controls.
    func setActivitySyncZeroVideoTime(_ videoTime: TimeInterval) {
        guard !isExporting, videoURL != nil, fitURL != nil else { return }
        syncMode = .syncPoint
        if videoTime >= 0 {
            syncVideoSeconds = videoTime
            syncFITSeconds = 0
        } else {
            syncVideoSeconds = 0
            syncFITSeconds = -videoTime
        }
    }

    /// Move one timeline clip without changing the source match-point inputs.
    func moveTimelineClip(id: String, toTimelineStart timelineStart: TimeInterval) {
        guard let sourceTrackID = timeline.tracks.first(where: { track in
            track.clips.contains { $0.id == id }
        })?.id else {
            return
        }
        moveTimelineClip(id: id, toTrackID: sourceTrackID, toTimelineStart: timelineStart)
    }

    /// Move a clip horizontally and, when requested, into another unlocked track of the same kind.
    func moveTimelineClip(id: String, toTrackID targetTrackID: String, toTimelineStart timelineStart: TimeInterval) {
        let selectedIDs = effectiveSelectedTimelineClipIDs
        if selectedIDs.count > 1, selectedIDs.contains(id) {
            moveTimelineClipGroup(
                anchorID: id,
                selectedIDs: selectedIDs,
                toTrackID: targetTrackID,
                toTimelineStart: timelineStart
            )
            return
        }
        guard !isExporting,
              let sourceTrackIndex = timeline.tracks.firstIndex(where: { track in
                  track.clips.contains { $0.id == id }
              }),
              let sourceClipIndex = timeline.tracks[sourceTrackIndex].clips.firstIndex(where: { $0.id == id }),
              let targetTrackIndex = timeline.tracks.firstIndex(where: { $0.id == targetTrackID }),
              !timeline.tracks[sourceTrackIndex].isLocked,
              !timeline.tracks[targetTrackIndex].isLocked,
              timeline.tracks[sourceTrackIndex].kind == timeline.tracks[targetTrackIndex].kind else {
            return
        }

        let sanitizedStart = max(0, timelineStart.isFinite ? timelineStart : 0)
        let previousUndoState = timelineUndoSnapshotNow
        var clip = timeline.tracks[sourceTrackIndex].clips[sourceClipIndex]
        let constrainedStart = timeline.tracks[targetTrackIndex].nonOverlappingStart(
            forClipID: id,
            duration: clip.duration,
            proposedStart: sanitizedStart
        )
        guard sourceTrackIndex != targetTrackIndex
                || abs(clip.timelineStart - constrainedStart) > 1e-6
                || clip.isAlignmentPending else {
            return
        }

        beginTimelineClipEditingIfNeeded()
        clip.timelineStart = constrainedStart
        clip.isAlignmentPending = false
        if sourceTrackIndex == targetTrackIndex {
            timeline.tracks[sourceTrackIndex].clips[sourceClipIndex] = clip
        } else {
            timeline.tracks[sourceTrackIndex].clips.remove(at: sourceClipIndex)
            timeline.tracks[targetTrackIndex].clips.append(clip)
        }
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.moveClip",
            coalescing: true
        )
        refreshOverlayOrPreview()
    }

    private func moveTimelineClipGroup(
        anchorID: String,
        selectedIDs: Set<String>,
        toTrackID targetTrackID: String,
        toTimelineStart timelineStart: TimeInterval
    ) {
        let movingClips = timeline.tracks.indices.flatMap { trackIndex in
            timeline.tracks[trackIndex].clips.compactMap { clip in
                selectedIDs.contains(clip.id) ? (trackIndex: trackIndex, clip: clip) : nil
            }
        }
        guard !isExporting,
              movingClips.count == selectedIDs.count,
              let anchor = movingClips.first(where: { $0.clip.id == anchorID }),
              let targetTrackIndex = timeline.tracks.firstIndex(where: { $0.id == targetTrackID }),
              movingClips.allSatisfy({ !timeline.tracks[$0.trackIndex].isLocked }) else {
            return
        }

        let sourceTrackIndices = Set(movingClips.map(\.trackIndex))
        let singleSourceTrackIndex = sourceTrackIndices.count == 1 ? sourceTrackIndices.first : nil
        let movesToTargetTrack = singleSourceTrackIndex != nil && singleSourceTrackIndex != targetTrackIndex
        if let sourceTrackIndex = singleSourceTrackIndex, movesToTargetTrack {
            guard !timeline.tracks[targetTrackIndex].isLocked,
                  timeline.tracks[sourceTrackIndex].kind == timeline.tracks[targetTrackIndex].kind else {
                return
            }
        }

        let sanitizedStart = max(0, timelineStart.isFinite ? timelineStart : 0)
        let desiredDelta = sanitizedStart - anchor.clip.timelineStart
        let minimumDelta = -(movingClips.map { $0.clip.timelineStart }.min() ?? 0)
        var candidates: Set<TimeInterval> = [max(minimumDelta, desiredDelta), minimumDelta, 0]

        func plannedTrackIndex(for movingClip: (trackIndex: Int, clip: TimelineClip)) -> Int {
            movesToTargetTrack ? targetTrackIndex : movingClip.trackIndex
        }

        for movingClip in movingClips {
            let targetIndex = plannedTrackIndex(for: movingClip)
            for obstacle in timeline.tracks[targetIndex].clips where !selectedIDs.contains(obstacle.id) {
                candidates.insert(obstacle.timelineStart - movingClip.clip.timelineEnd)
                candidates.insert(obstacle.timelineEnd - movingClip.clip.timelineStart)
            }
        }

        let epsilon = 1e-9
        func isValid(delta: TimeInterval) -> Bool {
            guard delta.isFinite, delta >= minimumDelta - epsilon else { return false }
            for movingClip in movingClips {
                let movedStart = movingClip.clip.timelineStart + delta
                let movedEnd = movingClip.clip.timelineEnd + delta
                let targetIndex = plannedTrackIndex(for: movingClip)
                for obstacle in timeline.tracks[targetIndex].clips where !selectedIDs.contains(obstacle.id) {
                    if movedStart < obstacle.timelineEnd - epsilon,
                       movedEnd > obstacle.timelineStart + epsilon {
                        return false
                    }
                }
            }
            return true
        }

        guard let constrainedDelta = candidates.filter(isValid).min(by: { lhs, rhs in
            let leftDistance = abs(lhs - desiredDelta)
            let rightDistance = abs(rhs - desiredDelta)
            return abs(leftDistance - rightDistance) > epsilon
                ? leftDistance < rightDistance
                : lhs < rhs
        }), abs(constrainedDelta) > 1e-6
                || movesToTargetTrack
                || movingClips.contains(where: { $0.clip.isAlignmentPending }) else {
            return
        }

        let previousUndoState = timelineUndoSnapshotNow
        var updated = timeline
        if let sourceTrackIndex = singleSourceTrackIndex, movesToTargetTrack {
            let moved = movingClips.map { movingClip -> TimelineClip in
                var clip = movingClip.clip
                clip.timelineStart += constrainedDelta
                clip.isAlignmentPending = false
                return clip
            }
            updated.tracks[sourceTrackIndex].clips.removeAll { selectedIDs.contains($0.id) }
            updated.tracks[targetTrackIndex].clips.append(contentsOf: moved)
        } else {
            for trackIndex in updated.tracks.indices {
                for clipIndex in updated.tracks[trackIndex].clips.indices
                where selectedIDs.contains(updated.tracks[trackIndex].clips[clipIndex].id) {
                    updated.tracks[trackIndex].clips[clipIndex].timelineStart += constrainedDelta
                    updated.tracks[trackIndex].clips[clipIndex].isAlignmentPending = false
                }
            }
        }

        beginTimelineClipEditingIfNeeded()
        timeline = updated
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.moveClip",
            coalescing: true
        )
        refreshOverlayOrPreview()
    }

    var canNudgeSelectedTimelineClips: Bool {
        !editableSelectedTimelineClipIDs.isEmpty
    }

    /// `,` / `.` shortcuts: move the selected clips left/right by whole preview frames.
    func nudgeSelectedTimelineClips(byFrames frameOffset: Int) {
        guard frameOffset != 0, !isExporting else { return }
        let selectedIDs = effectiveSelectedTimelineClipIDs
        guard let anchor = timeline.tracks
            .flatMap(\.clips)
            .first(where: { selectedIDs.contains($0.id) }) else { return }
        moveTimelineClip(
            id: anchor.id,
            toTimelineStart: anchor.timelineStart
                + Double(frameOffset) / Self.sanitizedOutputFrameRate(outputFPS)
        )
    }

    /// Clip boundaries (edit points) across enabled tracks, sorted ascending and including 0.
    private var timelineEditPoints: [TimeInterval] {
        var points: Set<TimeInterval> = [0]
        for track in timeline.tracks where track.isEnabled {
            for clip in track.clips {
                points.insert(clip.timelineStart)
                points.insert(clip.timelineEnd)
            }
        }
        return points.sorted()
    }

    var canJumpToTimelineEditPoints: Bool {
        guard !isExporting else { return false }
        return timeline.tracks.contains { $0.isEnabled && !$0.clips.isEmpty }
    }

    /// Move the playhead to the nearest clip boundary after it (DaVinci down-arrow).
    func jumpToNextTimelineEditPoint() {
        guard canJumpToTimelineEditPoints else { return }
        if let next = timelineEditPoints.first(where: { $0 > previewTime + 1e-3 }) {
            seekPreview(to: next)
            timelinePlayheadFocusGeneration &+= 1
        }
    }

    /// Move the playhead to the nearest clip boundary before it (DaVinci up-arrow).
    func jumpToPreviousTimelineEditPoint() {
        guard canJumpToTimelineEditPoints else { return }
        if let previous = timelineEditPoints.last(where: { $0 < previewTime - 1e-3 }) {
            seekPreview(to: previous)
            timelinePlayheadFocusGeneration &+= 1
        }
    }

    /// Whether the blade (⌘B) has anything to cut at the playhead.
    var canSplitTimelineClipsAtPlayhead: Bool {
        guard !isExporting else { return false }
        let selectedIDs = effectiveSelectedTimelineClipIDs
        if selectedIDs.isEmpty {
            return !currentTimelineProject.splittableClipIDs(atTimelineTime: previewTime).isEmpty
        }
        return !currentTimelineProject
            .splittableClipIDs(atTimelineTime: previewTime)
            .filter(selectedIDs.contains)
            .isEmpty
    }

    /// Split the selected clip under the playhead, or every unlocked track when no clip is selected.
    func splitTimelineClipsAtPlayhead() {
        guard !isExporting else { return }
        let previousUndoState = timelineUndoSnapshotNow
        var updated = timeline
        let selectedIDs = effectiveSelectedTimelineClipIDs
        let splitCount: Int
        if selectedIDs.isEmpty {
            splitCount = updated.splitClips(atTimelineTime: previewTime)
        } else {
            splitCount = selectedIDs.reduce(into: 0) { count, clipID in
                count += updated.splitClips(atTimelineTime: previewTime, clipID: clipID)
            }
        }
        guard splitCount > 0 else { return }
        beginTimelineClipEditingIfNeeded()
        timeline = updated
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.splitClips",
            coalescing: false
        )
        refreshOverlayOrPreview()
        setStatus("status.timelineClipsSplit", formatStatusDuration(previewTime))
    }

    func canDeleteTimelineClip(id: String) -> Bool {
        guard !isExporting else { return false }
        return timeline.tracks.contains { track in
            !track.isLocked && track.clips.contains { $0.id == id }
        }
    }

    /// Delete one clip. A plain delete leaves a gap (black frames in composited export,
    /// transparent in overlay-only export); a ripple delete also closes the removed time
    /// range on every unlocked track.
    func deleteTimelineClip(id: String, ripple: Bool) {
        guard canDeleteTimelineClip(id: id) else { return }
        let previousUndoState = timelineUndoSnapshotNow
        var updated = timeline
        let removed = ripple ? updated.rippleRemoveClip(id: id) : updated.removeClip(id: id)
        guard removed else { return }
        beginTimelineClipEditingIfNeeded()
        timeline = updated
        if selectedTimelineClipID == id {
            selectedTimelineClipIDs.remove(id)
            selectedTimelineClipID = firstSelectedTimelineClipID
        } else {
            selectedTimelineClipIDs.remove(id)
        }
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: ripple ? "undo.timeline.rippleDeleteClip" : "undo.timeline.deleteClip",
            coalescing: false
        )
        previewTime = clampedPreviewTime(previewTime)
        refreshOverlayOrPreview()
        setStatus(ripple ? "status.timelineClipRippleDeleted" : "status.timelineClipDeleted")
    }

    func deleteSelectedTimelineClip(ripple: Bool) {
        let selectedIDs = effectiveSelectedTimelineClipIDs.filter(canDeleteTimelineClip)
        guard !selectedIDs.isEmpty else { return }
        if selectedIDs.count == 1, let id = selectedIDs.first {
            deleteTimelineClip(id: id, ripple: ripple)
            return
        }

        let previousUndoState = timelineUndoSnapshotNow
        var updated = timeline
        let orderedIDs = selectedIDs.sorted { lhs, rhs in
            let lhsStart = timelineClip(id: lhs)?.timelineStart ?? 0
            let rhsStart = timelineClip(id: rhs)?.timelineStart ?? 0
            return lhsStart > rhsStart
        }
        let removed = orderedIDs.reduce(into: false) { didRemove, id in
            let currentRemoved = ripple ? updated.rippleRemoveClip(id: id) : updated.removeClip(id: id)
            didRemove = currentRemoved || didRemove
        }
        guard removed else { return }

        beginTimelineClipEditingIfNeeded()
        timeline = updated
        clearTimelineClipSelection()
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: ripple ? "undo.timeline.rippleDeleteClip" : "undo.timeline.deleteClip",
            coalescing: false
        )
        previewTime = clampedPreviewTime(previewTime)
        refreshOverlayOrPreview()
        setStatus(ripple ? "status.timelineClipRippleDeleted" : "status.timelineClipDeleted")
    }

    var canCopySelectedTimelineClips: Bool {
        !effectiveSelectedTimelineClipIDs.isEmpty
    }

    var canCutSelectedTimelineClips: Bool {
        !editableSelectedTimelineClipIDs.isEmpty
    }

    var canPasteTimelineClips: Bool {
        guard !isExporting, !timelineClipboard.isEmpty else { return false }
        let assetIDs = Set(timeline.assets.map(\.id))
        return timelineClipboard.allSatisfy { item in
            assetIDs.contains(item.clip.assetID)
                && timeline.tracks.contains { $0.id == item.trackID && !$0.isLocked }
        }
    }

    func copySelectedTimelineClips() {
        let items = timelineClipboardItems(for: effectiveSelectedTimelineClipIDs)
        guard !items.isEmpty else { return }
        timelineClipboard = items
        setStatus("status.timelineClipsCopied")
    }

    func cutSelectedTimelineClips() {
        let selectedIDs = editableSelectedTimelineClipIDs
        let items = timelineClipboardItems(for: selectedIDs)
        guard !items.isEmpty else { return }

        let previousUndoState = timelineUndoSnapshotNow
        var updated = timeline
        let removed = selectedIDs.reduce(into: false) { didRemove, id in
            didRemove = updated.removeClip(id: id) || didRemove
        }
        guard removed else { return }

        timelineClipboard = items
        beginTimelineClipEditingIfNeeded()
        timeline = updated
        clearTimelineClipSelection()
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.cutClips",
            coalescing: false
        )
        previewTime = clampedPreviewTime(previewTime)
        refreshOverlayOrPreview()
        setStatus("status.timelineClipsCut")
    }

    func pasteTimelineClips() {
        pasteTimelineClips(inserting: false)
    }

    func pasteInsertTimelineClips() {
        pasteTimelineClips(inserting: true)
    }

    private func pasteTimelineClips(inserting: Bool) {
        guard canPasteTimelineClips,
              let clipboardStart = timelineClipboard.map(\.clip.timelineStart).min(),
              let clipboardEnd = timelineClipboard.map(\.clip.timelineEnd).max() else { return }

        let pasteTime = max(0, previewTime.isFinite ? previewTime : 0)
        let previousUndoState = timelineUndoSnapshotNow
        var updated = timeline
        if inserting {
            updated.insertEmptyTimeRange(at: pasteTime, duration: clipboardEnd - clipboardStart)
        }

        var pastedIDs: Set<String> = []
        for item in timelineClipboard {
            guard let trackIndex = updated.tracks.firstIndex(where: { $0.id == item.trackID }) else { return }
            var clip = item.clip
            clip.id = "\(updated.tracks[trackIndex].kind.rawValue).clip.\(UUID().uuidString)"
            clip.timelineStart = pasteTime + item.clip.timelineStart - clipboardStart
            clip.isAlignmentPending = false
            updated.tracks[trackIndex].overwrite(with: clip)
            pastedIDs.insert(clip.id)
        }
        guard !pastedIDs.isEmpty else { return }

        beginTimelineClipEditingIfNeeded()
        timeline = updated
        setTimelineClipSelection(pastedIDs)
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: inserting ? "undo.timeline.pasteInsertClips" : "undo.timeline.pasteClips",
            coalescing: false
        )
        refreshOverlayOrPreview()
        setStatus(inserting ? "status.timelineClipsPasteInserted" : "status.timelineClipsPasted")
    }

    private func timelineClipboardItems(for selectedIDs: Set<String>) -> [TimelineClipboardItem] {
        timeline.tracks.flatMap { track in
            track.clips
                .filter { selectedIDs.contains($0.id) }
                .sorted { $0.timelineStart < $1.timelineStart }
                .map { TimelineClipboardItem(trackID: track.id, clip: $0) }
        }
    }

    func selectTimelineClip(id: String, extendingSelection: Bool = false) {
        guard timelineClip(id: id) != nil else {
            clearTimelineClipSelection()
            return
        }
        if extendingSelection {
            if selectedTimelineClipIDs.contains(id) {
                selectedTimelineClipIDs.remove(id)
                selectedTimelineClipID = firstSelectedTimelineClipID
            } else {
                selectedTimelineClipIDs.insert(id)
                selectedTimelineClipID = id
            }
        } else {
            selectedTimelineClipIDs = [id]
            selectedTimelineClipID = id
        }
        selectedElementID = nil
        selectedMediaAssetID = nil
    }

    func setTimelineClipSelection(_ ids: Set<String>) {
        let validIDs = ids.filter { timelineClip(id: $0) != nil }
        if validIDs != selectedTimelineClipIDs {
            selectedTimelineClipIDs = validIDs
            selectedTimelineClipID = firstSelectedTimelineClipID
        }
        if selectedElementID != nil {
            selectedElementID = nil
        }
        if selectedMediaAssetID != nil {
            selectedMediaAssetID = nil
        }
    }

    func isTimelineClipSelected(id: String) -> Bool {
        selectedTimelineClipIDs.contains(id) || selectedTimelineClipID == id
    }

    private var effectiveSelectedTimelineClipIDs: Set<String> {
        if !selectedTimelineClipIDs.isEmpty {
            return selectedTimelineClipIDs
        }
        return selectedTimelineClipID.map { [$0] } ?? []
    }

    private var editableSelectedTimelineClipIDs: Set<String> {
        guard !isExporting else { return [] }
        let selectedIDs = effectiveSelectedTimelineClipIDs
        return Set(timeline.tracks
            .filter { !$0.isLocked }
            .flatMap(\.clips)
            .map(\.id)
            .filter(selectedIDs.contains))
    }

    private var firstSelectedTimelineClipID: String? {
        timeline.tracks
            .flatMap(\.clips)
            .first { selectedTimelineClipIDs.contains($0.id) }?
            .id
    }

    func clearTimelineClipSelection() {
        selectedTimelineClipIDs = []
        selectedTimelineClipID = nil
    }

    func selectElement(id: String) {
        clearTimelineClipSelection()
        selectedMediaAssetID = nil
        if selectedElementIDs != [id] {
            selectedElementIDs = [id]
        }
        if selectedElementID != id {
            selectedElementID = id
        }
    }

    /// Shift-click semantics: adds the element to the selection or removes it again.
    func toggleElementInSelection(id: String) {
        clearTimelineClipSelection()
        selectedMediaAssetID = nil
        var ids = selectedElementIDs
        if ids.isEmpty, let selectedElementID {
            ids = [selectedElementID]
        }
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        selectedElementIDs = ids
        if ids.contains(id) {
            selectedElementID = id
        } else if selectedElementID.map(ids.contains) != true {
            selectedElementID = layout.elements.first { ids.contains($0.id) }?.id
        }
        if ids.count != 1, selectedElementPart != nil {
            selectedElementPart = nil
        }
    }

    /// Marquee semantics: replaces the selection with the given element ids.
    func setElementSelection(_ ids: Set<String>) {
        let validIDs = Set(layout.elements.map(\.id)).intersection(ids)
        if !validIDs.isEmpty {
            clearTimelineClipSelection()
            selectedMediaAssetID = nil
        }
        if selectedElementIDs != validIDs {
            selectedElementIDs = validIDs
        }
        if let selectedElementID, validIDs.contains(selectedElementID) {
            // keep the primary selection stable while the marquee grows
        } else {
            selectedElementID = layout.elements.first { validIDs.contains($0.id) }?.id
        }
        if validIDs.count != 1, selectedElementPart != nil {
            selectedElementPart = nil
        }
    }

    func isElementSelected(id: String) -> Bool {
        selectedElementIDs.contains(id) || selectedElementID == id
    }

    // MARK: - Element part sub-selection

    /// Sets the styled part of the currently selected element; `nil` returns to
    /// whole-element selection. Invalid parts (hidden rows, unsupported kinds) clear.
    func selectElementPart(_ part: OverlayElementPart?) {
        let validated = validatedElementPart(part, elementID: selectedElementID)
        if selectedElementPart != validated {
            selectedElementPart = validated
        }
    }

    /// Canvas tap state machine: the first click selects the element; a second click on the
    /// already (solely) selected element selects the part under the pointer, or clears the
    /// part when the click lands outside every part zone.
    func handleCanvasElementTap(id: String, part: OverlayElementPart?) {
        let wasSoleSelection = selectedElementID == id && effectiveSelectedElementIDs == [id]
        selectElement(id: id)
        guard wasSoleSelection else { return }
        selectElementPart(part)
    }

    /// Esc walks the selection back one level: part → element → nothing.
    func escapeCanvasSelection() {
        if selectedElementPart != nil {
            selectedElementPart = nil
            return
        }
        if selectedElementID != nil || !selectedElementIDs.isEmpty {
            selectedElementIDs = []
            selectedElementID = nil
        }
    }

    private func validatedElementPart(_ part: OverlayElementPart?, elementID: String?) -> OverlayElementPart? {
        guard let part,
              let elementID,
              effectiveSelectedElementIDs == [elementID],
              let element = layout.elements.first(where: { $0.id == elementID }),
              OverlayElementPart.availableParts(for: element).contains(part) else {
            return nil
        }
        return part
    }

    private var effectiveSelectedElementIDs: Set<String> {
        if !selectedElementIDs.isEmpty {
            return selectedElementIDs
        }
        return selectedElementID.map { [$0] } ?? []
    }

    /// Selected elements in layout (z-)order.
    private var selectedElements: [OverlayElement] {
        let ids = effectiveSelectedElementIDs
        return layout.elements.filter { ids.contains($0.id) }
    }

    func setTimelineClipDistanceUnit(id: String, _ unit: OverlayDistanceUnit?) {
        updateTimelineClip(id: id) { clip, _, _ in
            clip.distanceUnit = unit
        }
    }

    func setTimelineClipLayout(id: String, _ layout: OverlayLayout?) {
        updateTimelineClip(id: id) { clip, _, _ in
            clip.layout = layout?.sanitized
        }
    }

    func setTimelineClipTiming(
        id: String,
        timelineStart: TimeInterval? = nil,
        sourceIn: TimeInterval? = nil,
        duration: TimeInterval? = nil
    ) {
        updateTimelineClip(id: id) { clip, asset, track in
            let minimumDuration: TimeInterval = 0.1
            let sourceDuration = max(minimumDuration, asset.duration)
            let maxSourceIn = max(0, sourceDuration - minimumDuration)
            clip.sourceIn = min(maxSourceIn, max(0, sourceIn ?? clip.sourceIn))
            let maxDuration = max(minimumDuration, sourceDuration - clip.sourceIn)
            clip.duration = min(maxDuration, max(minimumDuration, duration ?? clip.duration))
            // Keep the track overlap-free: place the start in the nearest fitting gap, then cap
            // the duration at the next clip on the track.
            let isMovingWholeClip = timelineStart != nil && sourceIn == nil && duration == nil
            clip.timelineStart = track.nonOverlappingStart(
                forClipID: clip.id,
                duration: isMovingWholeClip ? clip.duration : minimumDuration,
                proposedStart: max(0, timelineStart ?? clip.timelineStart)
            )
            if timelineStart != nil {
                clip.isAlignmentPending = false
            }
            if let gapLimit = track.maximumNonOverlappingDuration(
                forClipID: clip.id,
                startingAt: clip.timelineStart
            ) {
                clip.duration = min(clip.duration, max(minimumDuration, gapLimit))
            }
        }
    }

    func confirmTimelineClipAlignment(id: String) {
        updateTimelineClip(id: id) { clip, _, _ in
            clip.isAlignmentPending = false
        }
    }

    private func updateTimelineClip(
        id: String,
        _ update: (inout TimelineClip, MediaAsset, TimelineTrack) -> Void
    ) {
        guard !isExporting else { return }
        let previousUndoState = timelineUndoSnapshotNow

        for trackIndex in timeline.tracks.indices {
            guard !timeline.tracks[trackIndex].isLocked else { continue }
            guard let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) else {
                continue
            }
            guard let asset = timeline.asset(id: timeline.tracks[trackIndex].clips[clipIndex].assetID),
                  asset.duration > 0 else { return }

            let oldClip = timeline.tracks[trackIndex].clips[clipIndex]
            var updatedClip = oldClip
            update(&updatedClip, asset, timeline.tracks[trackIndex])
            guard updatedClip != oldClip else { return }
            beginTimelineClipEditingIfNeeded()
            timeline.tracks[trackIndex].clips[clipIndex] = updatedClip
            registerTimelineUndoIfChanged(
                previous: previousUndoState,
                actionKey: "undo.timeline.editClip",
                coalescing: true
            )
            refreshOverlayOrPreview()
            return
        }
    }

    func trimTimelineClipStart(id: String, toTimelineTime timelineTime: TimeInterval) {
        trimTimelineClip(id: id, startTime: timelineTime, endTime: nil)
    }

    func trimTimelineClipEnd(id: String, toTimelineTime timelineTime: TimeInterval) {
        trimTimelineClip(id: id, startTime: nil, endTime: timelineTime)
    }

    private func trimTimelineClip(id: String, startTime: TimeInterval?, endTime: TimeInterval?) {
        guard !isExporting else { return }
        let minimumDuration: TimeInterval = 0.1
        let previousUndoState = timelineUndoSnapshotNow

        for trackIndex in timeline.tracks.indices {
            guard !timeline.tracks[trackIndex].isLocked else { continue }
            guard let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) else {
                continue
            }
            guard let asset = timeline.asset(id: timeline.tracks[trackIndex].clips[clipIndex].assetID),
                  asset.duration > 0 else { return }

            var clip = timeline.tracks[trackIndex].clips[clipIndex]
            let neighborBounds = timeline.tracks[trackIndex].neighborBounds(aroundClipID: id)
            let earliestStart = max(clip.timelineStart - clip.sourceIn, neighborBounds.lower)
            let latestEnd = min(
                clip.timelineStart + max(0, asset.duration - clip.sourceIn),
                neighborBounds.upper ?? .infinity
            )

            if let startTime {
                let newStart = min(clip.timelineEnd - minimumDuration, max(earliestStart, startTime))
                let delta = newStart - clip.timelineStart
                clip.timelineStart = newStart
                clip.sourceIn = max(0, clip.sourceIn + delta)
                clip.duration = max(minimumDuration, clip.duration - delta)
            }

            if let endTime {
                let newEnd = min(latestEnd, max(clip.timelineStart + minimumDuration, endTime))
                clip.duration = max(minimumDuration, newEnd - clip.timelineStart)
            }

            guard clip != timeline.tracks[trackIndex].clips[clipIndex] else { return }
            beginTimelineClipEditingIfNeeded()
            timeline.tracks[trackIndex].clips[clipIndex] = clip
            registerTimelineUndoIfChanged(
                previous: previousUndoState,
                actionKey: "undo.timeline.trimClip",
                coalescing: true
            )
            refreshOverlayOrPreview()
            return
        }
    }

    private func beginTimelineClipEditingIfNeeded() {
        guard timelineUsesSingleSourceMigration else { return }
        pausePlayback()
        timelineUsesSingleSourceMigration = false
        // Entering custom-timeline mode: swap the raw-video player item for the timeline
        // composition so playback and scrubbing follow clip geometry (with audio).
        configureTimelinePlayer()
    }

    func retryVideoLoad() {
        guard let failure = videoLoadFailure else { return }
        setVideo(failure.url)
    }

    func retryFITLoad() {
        guard let failure = fitLoadFailure else { return }
        setFIT(failure.url)
    }

    func markSportStart() {
        guard !isExporting else { return }
        let videoSourceTime = currentVideoSourceTimeForSync ?? previewTime
        syncMode = .syncPoint
        syncVideoSeconds = videoSourceTime
        syncFITSeconds = 0
        setStatus("status.sportStartSet", formatStatusDuration(videoSourceTime))
        refreshOverlayOrPreview()
    }

    func setFIT(_ url: URL) {
        guard !isExporting else { return }
        singleSourceAlignmentIsPending = false
        cancelPreviewRenderTasks()
        fitLoadTask?.cancel()
        weatherLoadTask?.cancel()
        previewRenderGeneration += 1
        fitLoadGeneration += 1
        let loadGeneration = fitLoadGeneration
        fitURL = nil
        series = nil
        activityTrim = .none
        overlayImage = nil
        previewWarning = nil
        fitLoadFailure = nil
        setStatus("status.loadingFit", url.lastPathComponent)
        addDebugLog(.input, "Loading activity file: \(url.lastPathComponent)")

        fitLoadTask = Task.detached {
            do {
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let parsed = try TelemetryFileParser().parseActivity(url: url)
                let parsedSeries = parsed.series
                if Task.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self, self.fitLoadGeneration == loadGeneration else { return }
                        self.discardPendingActivityTimelineImport(id: url.path)
                    }
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.fitLoadGeneration == loadGeneration else { return }
                    self.fitURL = url
                    self.series = parsedSeries
                    self.upsertActivityAsset(url: url, series: parsedSeries, sport: parsed.sport)
                    if self.videoURL == nil {
                        self.resetExportTrimRangeToFullDuration()
                        self.applySuggestedOutputURLIfNeeded(for: url)
                    }
                    self.setStatus("status.loadedFit", self.activityDisplayName ?? url.lastPathComponent)
                    self.addDebugLog(.input, "Loaded activity file: \(url.lastPathComponent), samples=\(parsedSeries.samples.count), duration=\(Self.formatDebugSeconds(parsedSeries.duration))")
                    self.applyWallClockAutoSyncIfPossible()
                    self.refreshOverlayOrPreview()
                    self.loadOpenWeatherIfPossible(
                        for: parsedSeries,
                        sourceName: url.lastPathComponent,
                        generation: loadGeneration
                    )
                    self.fitLoadTask = nil
                    self.completeSourceReplacementUndoIfNeeded(kind: .activity)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.fitLoadGeneration == loadGeneration else { return }
                    self.discardPendingActivityTimelineImport(id: url.path)
                    self.fitLoadTask = nil
                    self.cancelSourceReplacementUndoIfNeeded(kind: .activity)
                }
            } catch {
                let message: String
                if let fitError = error as? FITError {
                    message = fitError.description
                } else if let gpxError = error as? GPXError {
                    message = gpxError.description
                } else if let telemetryFileError = error as? TelemetryFileError {
                    message = telemetryFileError.description
                } else {
                    message = error.localizedDescription
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.fitLoadGeneration == loadGeneration else { return }
                    self.fitLoadFailure = SourceLoadFailure(url: url, messageKey: "status.fitError", detail: message)
                    self.discardPendingActivityTimelineImport(id: url.path)
                    self.setStatus("status.fitError", message)
                    self.addDebugLog(.input, "Activity file error: \(message)")
                    self.fitLoadTask = nil
                    self.refreshOverlayOnly()
                    self.cancelSourceReplacementUndoIfNeeded(kind: .activity)
                }
            }
        }
    }

    private func loadOpenWeatherIfPossible(
        for parsedSeries: TelemetrySeries,
        sourceName: String,
        generation: Int,
        forceRefresh: Bool = false
    ) {
        let apiKey = openWeatherAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        let service = openWeatherService
        let language = openWeatherLanguageCode
        weatherLoadTask?.cancel()
        addDebugLog(.weather, "Weather request queued: language=\(language), force=\(forceRefresh)")
        weatherLoadTask = Task { [weak self] in
            do {
                let enrichedSeries = try await service.enrichedSeries(
                    parsedSeries,
                    apiKey: apiKey,
                    language: language,
                    forceRefresh: forceRefresh
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.fitLoadGeneration == generation else { return }
                    self.series = enrichedSeries
                    if let activeActivityAssetID = self.activeActivityAssetID {
                        self.activitySeriesByAssetID[activeActivityAssetID] = enrichedSeries
                    }
                    let weatherSampleCount = enrichedSeries.samples.filter { $0.weatherTemperatureCelsius != nil || $0.weatherHumidityPercent != nil || $0.weatherSummary != nil }.count
                    let displayName = self.activityDisplayName ?? sourceName
                    if weatherSampleCount > 0 {
                        self.setStatus("status.loadedFitWithWeather", displayName)
                    } else {
                        self.setStatus("status.weatherUnavailable", displayName)
                    }
                    self.weatherRefreshMessage = self.status
                    self.addDebugLog(.weather, "Weather request finished: weatherSamples=\(weatherSampleCount)/\(enrichedSeries.samples.count)")
                    self.refreshOverlayOrPreview()
                    self.weatherLoadTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self,
                          self.fitLoadGeneration == generation else { return }
                    let details: String
                    if let weatherError = error as? OpenWeatherError,
                       case .requestFailed(statusCode: 401) = weatherError {
                        details = self.localized("status.weatherOneCallAccessDenied")
                    } else {
                        details = error.localizedDescription
                    }
                    self.setStatus("status.weatherError", sourceName, details)
                    self.weatherRefreshMessage = self.status
                    self.addDebugLog(.weather, "Weather request failed: \(details)")
                    self.weatherLoadTask = nil
                }
            }
        }
    }

    private var openWeatherLanguageCode: String {
        switch resolvedLanguage {
        case .simplifiedChinese:
            return "zh_cn"
        case .traditionalChinese:
            return "zh_tw"
        case .japanese:
            return "ja"
        case .english:
            return "en"
        }
    }

    func refreshPreview() {
        guard !isExporting else { return }
        guard !usesCustomTimelinePreview else {
            refreshTimelinePreview()
            return
        }
        guard let videoURL else {
            backgroundImage = nil
            overlayImage = nil
            previewWarning = nil
            return
        }

        pendingOverlayRefreshAfterCurrentRender = false
        previewRenderGeneration += 1
        let generation = previewRenderGeneration
        let time = previewTime
        let outputSize = sanitizedPreviewSize(currentPreviewOverlayRenderSize())
        let currentSeries = series
        let currentSync = timeSync
        let currentLayout = layout
        let currentDistanceUnit = distanceUnit
        let currentActivityTrim = self.currentActivityTrim
        let videoPreviewFailedTitle = localized("status.previewVideoFailed")
        let overlayPreviewFailedTitle = localized("status.previewOverlayFailed")

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached(priority: .userInitiated) { [videoFrameService, previewRenderer] in
            guard !Task.isCancelled else { return }
            let background: CGImage?
            var warningMessage: String?
            do {
                background = try videoFrameService.frameImage(videoURL: videoURL, time: time)
            } catch is CancellationError {
                return
            } catch {
                background = nil
                warningMessage = Self.previewWarningMessage(videoPreviewFailedTitle, error: error)
            }
            guard !Task.isCancelled else { return }
            let overlay: CGImage?
            if let currentSeries {
                do {
                    overlay = try Self.renderOverlayImage(
                        previewRenderer: previewRenderer,
                        series: currentSeries,
                        size: outputSize,
                        videoTime: time,
                        timeSync: currentSync,
                        layout: currentLayout,
                        distanceUnit: currentDistanceUnit,
                        activityTrim: currentActivityTrim
                    )
                } catch is CancellationError {
                    return
                } catch {
                    overlay = nil
                    warningMessage = Self.previewWarningMessage(overlayPreviewFailedTitle, error: error)
                }
            } else {
                overlay = nil
            }
            guard !Task.isCancelled else { return }
            let finalWarningMessage = warningMessage

            await Self.performPreviewUpdateOnMainRunLoop { [weak self] in
                guard let self else { return }
                guard self.previewRenderGeneration == generation,
                      self.previewRenderTask != nil else { return }
                self.backgroundImage = background
                self.overlayImage = overlay
                self.previewWarning = finalWarningMessage
                if let finalWarningMessage {
                    self.addDebugLog(.preview, finalWarningMessage)
                }
                self.previewRenderTask = nil
            }
        }
    }

    private func refreshTimelinePreview() {
        if player != nil {
            // The composition player renders the video surface; only draw the overlay layers.
            backgroundImage = nil
            refreshTimelineOverlayOnly(
                previewSize: nil,
                minimumInterval: 0,
                coalesceIfBusy: false,
                displayIntermediateResults: false
            )
            return
        }
        guard let snapshot = timelinePreviewSnapshot(at: previewTime) else {
            backgroundImage = nil
            overlayImage = nil
            previewWarning = nil
            return
        }

        pendingOverlayRefreshAfterCurrentRender = false
        previewRenderGeneration += 1
        let generation = previewRenderGeneration
        let timelineTime = previewTime
        let outputSize = sanitizedPreviewSize(currentPreviewOverlayRenderSize())
        let currentActivityTrim = self.currentActivityTrim
        let videoPreviewFailedTitle = localized("status.previewVideoFailed")
        let overlayPreviewFailedTitle = localized("status.previewOverlayFailed")

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached(priority: .userInitiated) { [videoFrameService, previewRenderer] in
            guard !Task.isCancelled else { return }
            let background: CGImage?
            var warningMessage: String?
            if let videoURL = snapshot.videoURL {
                do {
                    background = try videoFrameService.frameImage(videoURL: videoURL, time: snapshot.videoTime)
                } catch is CancellationError {
                    return
                } catch {
                    background = nil
                    warningMessage = Self.previewWarningMessage(videoPreviewFailedTitle, error: error)
                }
            } else {
                background = nil
            }
            guard !Task.isCancelled else { return }

            let overlay: CGImage?
            if snapshot.overlayLayers.isEmpty {
                overlay = nil
            } else {
                do {
                    overlay = try Self.renderTimelineOverlayImage(
                        previewRenderer: previewRenderer,
                        size: outputSize,
                        timelineTime: timelineTime,
                        layers: snapshot.overlayLayers,
                        activityTrim: currentActivityTrim
                    )
                } catch is CancellationError {
                    return
                } catch {
                    overlay = nil
                    warningMessage = Self.previewWarningMessage(overlayPreviewFailedTitle, error: error)
                }
            }
            guard !Task.isCancelled else { return }
            let finalWarningMessage = warningMessage

            await Self.performPreviewUpdateOnMainRunLoop { [weak self] in
                guard let self else { return }
                guard self.previewRenderGeneration == generation,
                      self.previewRenderTask != nil else { return }
                self.backgroundImage = background
                self.overlayImage = overlay
                self.previewWarning = finalWarningMessage
                if let finalWarningMessage {
                    self.addDebugLog(.preview, finalWarningMessage)
                }
                self.previewRenderTask = nil
            }
        }
    }

    func refreshOverlayOnly(
        previewSize: CGSize? = nil,
        minimumInterval: TimeInterval = 0,
        coalesceIfBusy: Bool = false,
        displayIntermediateResults: Bool = false
    ) {
        guard !isExporting else { return }
        guard !usesCustomTimelinePreview else {
            refreshTimelineOverlayOnly(
                previewSize: previewSize,
                minimumInterval: minimumInterval,
                coalesceIfBusy: coalesceIfBusy,
                displayIntermediateResults: displayIntermediateResults
            )
            return
        }
        guard let currentSeries = series else {
            overlayImage = nil
            previewWarning = nil
            return
        }
        if coalesceIfBusy, previewRenderTask != nil {
            pendingOverlayRefreshAfterCurrentRender = true
            pendingOverlayRefreshDisplaysIntermediateResult = pendingOverlayRefreshDisplaysIntermediateResult || displayIntermediateResults
            return
        }
        pendingOverlayRefreshAfterCurrentRender = false
        pendingOverlayRefreshDisplaysIntermediateResult = false

        let now = Date()
        if minimumInterval > 0, now.timeIntervalSince(lastOverlayRefresh) < minimumInterval {
            return
        }
        lastOverlayRefresh = now
        previewRenderGeneration += 1
        let generation = previewRenderGeneration

        let time = previewTime
        let renderSize = sanitizedPreviewSize(previewSize ?? currentPreviewOverlayRenderSize())
        let currentSync = timeSync
        let currentLayout = layout
        let currentDistanceUnit = distanceUnit
        let currentActivityTrim = self.currentActivityTrim
        let overlayPreviewFailedTitle = localized("status.previewOverlayFailed")

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached(priority: .userInitiated) { [previewRenderer] in
            guard !Task.isCancelled else { return }
            let overlay: CGImage?
            let warningMessage: String?
            do {
                overlay = try Self.renderOverlayImage(
                    previewRenderer: previewRenderer,
                    series: currentSeries,
                    size: renderSize,
                    videoTime: time,
                    timeSync: currentSync,
                    layout: currentLayout,
                    distanceUnit: currentDistanceUnit,
                    activityTrim: currentActivityTrim
                )
                warningMessage = nil
            } catch is CancellationError {
                return
            } catch {
                overlay = nil
                warningMessage = Self.previewWarningMessage(overlayPreviewFailedTitle, error: error)
            }
            guard !Task.isCancelled else { return }

            await Self.performPreviewUpdateOnMainRunLoop { [weak self] in
                guard let self else { return }
                guard self.previewRenderGeneration == generation,
                      self.previewRenderTask != nil else { return }
                if self.pendingOverlayRefreshAfterCurrentRender {
                    let shouldDisplayIntermediateResult = displayIntermediateResults
                        || self.pendingOverlayRefreshDisplaysIntermediateResult
                    self.pendingOverlayRefreshAfterCurrentRender = false
                    self.pendingOverlayRefreshDisplaysIntermediateResult = false
                    if shouldDisplayIntermediateResult {
                        self.overlayImage = overlay
                        self.previewWarning = warningMessage
                        if let warningMessage {
                            self.addDebugLog(.preview, warningMessage)
                        }
                    }
                    self.previewRenderTask = nil
                    self.refreshOverlayOnly(
                        coalesceIfBusy: true,
                        displayIntermediateResults: shouldDisplayIntermediateResult
                    )
                    return
                }
                self.overlayImage = overlay
                self.previewWarning = warningMessage
                if let warningMessage {
                    self.addDebugLog(.preview, warningMessage)
                }
                self.previewRenderTask = nil
            }
        }
    }

    private func refreshTimelineOverlayOnly(
        previewSize: CGSize? = nil,
        minimumInterval: TimeInterval = 0,
        coalesceIfBusy: Bool = false,
        displayIntermediateResults: Bool = false
    ) {
        guard let snapshot = timelinePreviewSnapshot(at: previewTime),
              !snapshot.overlayLayers.isEmpty else {
            overlayImage = nil
            previewWarning = nil
            return
        }
        if coalesceIfBusy, previewRenderTask != nil {
            pendingOverlayRefreshAfterCurrentRender = true
            pendingOverlayRefreshDisplaysIntermediateResult = pendingOverlayRefreshDisplaysIntermediateResult || displayIntermediateResults
            return
        }
        pendingOverlayRefreshAfterCurrentRender = false
        pendingOverlayRefreshDisplaysIntermediateResult = false

        let now = Date()
        if minimumInterval > 0, now.timeIntervalSince(lastOverlayRefresh) < minimumInterval {
            return
        }
        lastOverlayRefresh = now
        previewRenderGeneration += 1
        let generation = previewRenderGeneration

        let timelineTime = previewTime
        let renderSize = sanitizedPreviewSize(previewSize ?? currentPreviewOverlayRenderSize())
        let currentActivityTrim = self.currentActivityTrim
        let overlayPreviewFailedTitle = localized("status.previewOverlayFailed")

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached(priority: .userInitiated) { [previewRenderer] in
            guard !Task.isCancelled else { return }
            let overlay: CGImage?
            let warningMessage: String?
            do {
                overlay = try Self.renderTimelineOverlayImage(
                    previewRenderer: previewRenderer,
                    size: renderSize,
                    timelineTime: timelineTime,
                    layers: snapshot.overlayLayers,
                    activityTrim: currentActivityTrim
                )
                warningMessage = nil
            } catch is CancellationError {
                return
            } catch {
                overlay = nil
                warningMessage = Self.previewWarningMessage(overlayPreviewFailedTitle, error: error)
            }
            guard !Task.isCancelled else { return }

            await Self.performPreviewUpdateOnMainRunLoop { [weak self] in
                guard let self else { return }
                guard self.previewRenderGeneration == generation,
                      self.previewRenderTask != nil else { return }
                if self.pendingOverlayRefreshAfterCurrentRender {
                    let shouldDisplayIntermediateResult = displayIntermediateResults
                        || self.pendingOverlayRefreshDisplaysIntermediateResult
                    self.pendingOverlayRefreshAfterCurrentRender = false
                    self.pendingOverlayRefreshDisplaysIntermediateResult = false
                    if shouldDisplayIntermediateResult {
                        self.overlayImage = overlay
                        self.previewWarning = warningMessage
                        if let warningMessage {
                            self.addDebugLog(.preview, warningMessage)
                        }
                    }
                    self.previewRenderTask = nil
                    self.refreshTimelineOverlayOnly(
                        coalesceIfBusy: true,
                        displayIntermediateResults: shouldDisplayIntermediateResult
                    )
                    return
                }
                self.overlayImage = overlay
                self.previewWarning = warningMessage
                if let warningMessage {
                    self.addDebugLog(.preview, warningMessage)
                }
                self.previewRenderTask = nil
            }
        }
    }

    func refreshOverlayOrPreview() {
        if videoURL != nil, backgroundImage == nil {
            refreshPreview()
        } else {
            refreshOverlayOnly(coalesceIfBusy: true)
        }
    }

    func updatePreviewOverlayRenderSize(_ size: CGSize) {
        let sanitized = sanitizedPreviewSize(size)
        guard sanitized.width.isFinite,
              sanitized.height.isFinite,
              sanitized.width > 0,
              sanitized.height > 0 else {
            return
        }

        if let previewOverlayRenderSize,
           abs(previewOverlayRenderSize.width - sanitized.width) < 1,
           abs(previewOverlayRenderSize.height - sanitized.height) < 1 {
            return
        }
        previewOverlayRenderSize = sanitized
        guard !isExporting else { return }
        if isPreviewLiveResizing {
            pendingPreviewLiveResizeSize = sanitized
            pendingPreviewSizeRefreshTask?.cancel()
            pendingPreviewSizeRefreshTask = nil
            return
        }
        schedulePreviewSizeRefresh(sanitized)
    }

    func setPreviewLiveResizing(_ isResizing: Bool) {
        guard isPreviewLiveResizing != isResizing else { return }
        isPreviewLiveResizing = isResizing
        if isResizing {
            pendingPreviewSizeRefreshTask?.cancel()
            pendingPreviewSizeRefreshTask = nil
            return
        }

        guard let size = pendingPreviewLiveResizeSize else { return }
        pendingPreviewLiveResizeSize = nil
        guard !isExporting else { return }
        schedulePreviewSizeRefresh(size)
    }

    private func currentPreviewOverlayRenderSize() -> CGSize {
        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        let resolvedSize: CGSize
        if let previewOverlayRenderSize {
            let outputAspect = outputSize.width / max(1, outputSize.height)
            let previewAspect = previewOverlayRenderSize.width / max(1, previewOverlayRenderSize.height)
            if abs(outputAspect - previewAspect) <= max(0.01, outputAspect * 0.02) {
                resolvedSize = previewOverlayRenderSize
            } else {
                resolvedSize = outputSize
            }
        } else {
            resolvedSize = outputSize
        }
        guard isGaugeDragActive else { return resolvedSize }
        return Self.gaugeDragPreviewRenderSize(for: resolvedSize)
    }

    nonisolated static func gaugeDragPreviewRenderSize(for size: CGSize) -> CGSize {
        let longestSide = max(size.width, size.height)
        guard longestSide > gaugeDragMaximumPreviewRenderDimension else { return size }
        let scale = gaugeDragMaximumPreviewRenderDimension / longestSide
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func sanitizedPreviewSize(_ size: CGSize) -> CGSize {
        var width = sanitizedPreviewDimension(size.width, fallback: CGFloat(outputWidth))
        var height = sanitizedPreviewDimension(size.height, fallback: CGFloat(outputHeight))

        let longestSide = max(width, height)
        if longestSide > maximumPreviewRenderDimension {
            let scale = maximumPreviewRenderDimension / longestSide
            width *= scale
            height *= scale
        }

        return CGSize(width: max(2, width.rounded()), height: max(2, height.rounded()))
    }

    private func sanitizedPreviewDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        let resolved = value.isFinite && value > 0 ? value : fallback
        return max(2, resolved.isFinite ? resolved : 2)
    }

    private func schedulePreviewSizeRefresh(_ size: CGSize) {
        pendingPreviewSizeRefreshTask?.cancel()

        pendingPreviewSizeRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.previewResizeRefreshDelay * 1_000_000_000))
            } catch {
                return
            }

            guard let self else { return }
            self.pendingPreviewSizeRefreshTask = nil
            guard let previewOverlayRenderSize = self.previewOverlayRenderSize,
                  abs(previewOverlayRenderSize.width - size.width) < 1,
                  abs(previewOverlayRenderSize.height - size.height) < 1 else {
                return
            }
            self.refreshOverlayOnly(previewSize: size)
        }
    }

    nonisolated private static func renderOverlayImage(
        previewRenderer: OverlayPreviewRenderer,
        series: TelemetrySeries,
        size: CGSize,
        videoTime: TimeInterval,
        timeSync: TelemetryTimeSync,
        layout: OverlayLayout,
        distanceUnit: OverlayDistanceUnit,
        activityTrim: ActivityTrim
    ) throws -> CGImage {
        try previewRenderer.renderOverlayImage(
            series: series,
            size: size,
            videoTime: videoTime,
            timeSync: timeSync,
            layout: layout,
            distanceUnit: distanceUnit,
            activityTrim: activityTrim
        )
    }

    nonisolated private static func renderTimelineOverlayImage(
        previewRenderer: OverlayPreviewRenderer,
        size: CGSize,
        timelineTime: TimeInterval,
        layers: [TimelinePreviewOverlayLayer],
        activityTrim: ActivityTrim
    ) throws -> CGImage {
        guard let firstLayer = layers.first else {
            throw OverlayPreviewError.cannotCreatePreviewImage
        }
        if layers.count == 1 {
            return try renderOverlayImage(
                previewRenderer: previewRenderer,
                series: firstLayer.series,
                size: size,
                videoTime: timelineTime,
                timeSync: firstLayer.timeSync,
                layout: firstLayer.layout,
                distanceUnit: firstLayer.distanceUnit,
                activityTrim: activityTrim
            )
        }

        let width = max(2, Int(size.width.rounded()))
        let height = max(2, Int(size.height.rounded()))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        var composed = CIImage(color: .clear).cropped(to: rect)
        for layer in layers {
            let image = try renderOverlayImage(
                previewRenderer: previewRenderer,
                series: layer.series,
                size: CGSize(width: width, height: height),
                videoTime: timelineTime,
                timeSync: layer.timeSync,
                layout: layer.layout,
                distanceUnit: layer.distanceUnit,
                activityTrim: activityTrim
            )
            composed = CIImage(cgImage: image).composited(over: composed)
        }
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        guard let image = context.createCGImage(composed, from: rect) else {
            throw OverlayPreviewError.cannotCreatePreviewImage
        }
        return image
    }

    nonisolated private static func performPreviewUpdateOnMainRunLoop(_ update: @escaping @MainActor () -> Void) async {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.default, .eventTracking]) {
                MainActor.assumeIsolated {
                    update()
                }
                continuation.resume()
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    nonisolated private static func previewWarningMessage(_ prefix: String, error: Error) -> String {
        let message: String
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            message = errorDescription
        } else {
            message = error.localizedDescription
        }
        return "\(prefix): \(message)"
    }

    func addElement(kind: OverlayComponentID) {
        addElement(kind: kind, atNormalizedPosition: nil)
    }

    func addElementCentered(kind: OverlayComponentID) {
        let baseSize = ComponentBaseSize.size(for: kind)
        addElement(
            kind: kind,
            atNormalizedPosition: CGPoint(
                x: 0.5 - baseSize.width / CGFloat(max(1, outputWidth)) / 2,
                y: 0.5 - baseSize.height / CGFloat(max(1, outputHeight)) / 2
            )
        )
    }

    func addElement(kind: OverlayComponentID, atNormalizedPosition position: CGPoint?) {
        guard !isExporting else { return }
        performLayoutChange("undo.addElement") {
            let existingCount = layout.elements.filter { $0.kind == kind }.count
            var element = OverlayElement.defaultElement(kind: kind, id: "\(kind.rawValue)-\(UUID().uuidString)")
            if let position {
                element.frame.x = PreviewLayoutLimits.clampPosition(Double(position.x))
                element.frame.y = PreviewLayoutLimits.clampPosition(Double(position.y))
            } else {
                let offset = min(0.20, Double(existingCount) * 0.035)
                element.frame.x = PreviewLayoutLimits.clampPosition(element.frame.x + offset)
                element.frame.y = PreviewLayoutLimits.clampPosition(element.frame.y + offset)
            }
            layout.elements.append(element)
            selectedElementID = element.id
            selectedMediaAssetID = nil
            clearTimelineClipSelection()
        }
        refreshOverlayOrPreview()
    }

    private func prepareActiveTimelineOverlayLayoutForEditing() {
        guard usesCustomTimelinePreview else { return }
        for track in timeline.tracks.reversed()
        where track.kind == .overlay && track.isEnabled && !track.isLocked {
            guard let clip = track.clips.last(where: {
                $0.isEnabled && $0.contains(timelineTime: previewTime)
            }) else { continue }
            layoutEditingTimelineClipID = clip.id
            let clipLayout = (clip.layout ?? .default).sanitized
            if layout != clipLayout {
                layout = clipLayout
            }
            return
        }
        layoutEditingTimelineClipID = nil
    }

    func duplicateSelectedElement() {
        guard !isExporting else { return }
        guard var element = selectedElement else { return }
        performLayoutChange("undo.duplicateElement") {
            element.id = "\(element.kind.rawValue)-\(UUID().uuidString)"
            element.frame.x = PreviewLayoutLimits.clampPosition(element.frame.x + 0.035)
            element.frame.y = PreviewLayoutLimits.clampPosition(element.frame.y + 0.035)
            layout.elements.append(element)
            selectedElementID = element.id
            clearTimelineClipSelection()
        }
        refreshOverlayOrPreview()
    }

    func deleteSelectedElement() {
        guard !isExporting else { return }
        let ids = effectiveSelectedElementIDs
        guard !ids.isEmpty else { return }
        performLayoutChange("undo.deleteElement") {
            for id in ids {
                layout.removeElement(id: id)
            }
            self.selectedElementID = layout.elements.first?.id
        }
        refreshOverlayOrPreview()
    }

    // MARK: - Arrange commands

    /// Selected elements that participate in align/distribute, in layout order.
    private var arrangeableSelectedElements: [OverlayElement] {
        let ids = effectiveSelectedElementIDs
        return layout.visibleElements.filter { ids.contains($0.id) }
    }

    var canAlignSelectedElements: Bool {
        !isExporting && arrangeableSelectedElements.count >= 2
    }

    var canDistributeSelectedElements: Bool {
        !isExporting && arrangeableSelectedElements.count >= 3
    }

    func alignSelectedElements(_ alignment: CanvasElementAlignment) {
        guard canAlignSelectedElements else { return }
        let elements = arrangeableSelectedElements
        let offsets = CanvasArrangement.alignmentOffsets(
            rects: arrangeUnitRects(for: elements),
            alignment: alignment
        )
        applyArrangeOffsets(offsets, to: elements, actionKey: "undo.alignElements")
    }

    func distributeSelectedElements(_ distribution: CanvasElementDistribution) {
        guard canDistributeSelectedElements else { return }
        let elements = arrangeableSelectedElements
        let offsets = CanvasArrangement.distributionOffsets(
            rects: arrangeUnitRects(for: elements),
            distribution: distribution
        )
        applyArrangeOffsets(offsets, to: elements, actionKey: "undo.distributeElements")
    }

    private func arrangeUnitRects(for elements: [OverlayElement]) -> [CGRect] {
        let geometry = CanvasElementGeometry(model: self)
        let alignedMetricWidth = geometry.alignedMetricOutputWidth(for: layout.visibleElements)
        return elements.map { geometry.unitRect(element: $0, alignedMetricWidth: alignedMetricWidth) }
    }

    private func applyArrangeOffsets(_ offsets: [CGVector], to elements: [OverlayElement], actionKey: String) {
        guard offsets.contains(where: { $0 != .zero }) else { return }
        performLayoutChange(actionKey) {
            for (element, offset) in zip(elements, offsets) where offset != .zero {
                layout.updateElement(id: element.id) { target in
                    target.frame.x = PreviewLayoutLimits.clampPosition(target.frame.x + Double(offset.dx))
                    target.frame.y = PreviewLayoutLimits.clampPosition(target.frame.y + Double(offset.dy))
                }
            }
        }
        refreshOverlayOrPreview()
    }

    /// Moves several elements at once (multi-selection drag) as one coalesced undoable change.
    func setElementPositions(_ positions: [String: (x: Double, y: Double)], refreshPreview shouldRefreshPreview: Bool = true) {
        guard !isExporting, !positions.isEmpty else { return }
        performLayoutChange("undo.editElement", coalescing: true) {
            for (id, position) in positions {
                layout.updateElement(id: id) { element in
                    element.frame.x = position.x
                    element.frame.y = position.y
                }
            }
        }
        if shouldRefreshPreview {
            refreshOverlayOrPreview()
        }
    }

    func bringSelectedElementToFront() {
        reorderSelectedElement(toFront: true)
    }

    func sendSelectedElementToBack() {
        reorderSelectedElement(toFront: false)
    }

    private func reorderSelectedElement(toFront: Bool) {
        guard !isExporting else { return }
        let ids = effectiveSelectedElementIDs
        guard !ids.isEmpty else { return }
        performLayoutChange("undo.reorderElement") {
            let moved = layout.elements.filter { ids.contains($0.id) }
            let remaining = layout.elements.filter { !ids.contains($0.id) }
            layout.elements = toFront ? remaining + moved : moved + remaining
        }
        refreshOverlayOrPreview()
    }

    // MARK: - Element style clipboard

    private var copiedElementStyleSource: OverlayElement?

    var canCopyElementStyle: Bool {
        selectedElement != nil && effectiveSelectedElementIDs.count <= 1
    }

    var canPasteElementStyle: Bool {
        !isExporting && copiedElementStyleSource != nil && !effectiveSelectedElementIDs.isEmpty
    }

    func copySelectedElementStyle() {
        guard let selectedElement else { return }
        copiedElementStyleSource = selectedElement
        setStatusAndToast(.info, "status.copiedElementStyle")
    }

    func copyElementStyle(id: String) {
        guard let element = layout.elements.first(where: { $0.id == id }) else { return }
        copiedElementStyleSource = element
        setStatusAndToast(.info, "status.copiedElementStyle")
    }

    func pasteCopiedElementStyle() {
        guard canPasteElementStyle, let source = copiedElementStyleSource else { return }
        let ids = effectiveSelectedElementIDs.subtracting([source.id])
        guard !ids.isEmpty else { return }
        performLayoutChange("undo.pasteElementStyle") {
            for id in ids {
                layout.updateElement(id: id) { target in
                    Self.applyElementStyle(from: source, to: &target)
                }
            }
        }
        setStatusAndToast(.success, "status.pastedElementStyle")
        refreshOverlayOrPreview()
    }

    /// Copies visual styling only: content overrides (label/unit/icon text), data settings
    /// (precision, gauge range), and position/visibility stay with the target.
    private static func applyElementStyle(from source: OverlayElement, to target: inout OverlayElement) {
        target.frame.scale = source.frame.scale
        target.frame.style = source.frame.style
        var customization = source.customization
        customization.labelOverride = target.customization.labelOverride
        customization.unitOverride = target.customization.unitOverride
        customization.iconOverride = target.customization.iconOverride
        customization.valuePrecision = target.customization.valuePrecision
        customization.gaugeMinimum = target.customization.gaugeMinimum
        customization.gaugeMaximum = target.customization.gaugeMaximum
        customization.manualWeatherTemperatureCelsius = target.customization.manualWeatherTemperatureCelsius
        customization.manualWeatherHumidityPercent = target.customization.manualWeatherHumidityPercent
        customization.showsWeatherHumidity = target.customization.showsWeatherHumidity
        target.customization = customization
    }

    func moveSelectedElementForward() {
        moveSelectedElement(by: 1)
    }

    func moveSelectedElementBackward() {
        moveSelectedElement(by: -1)
    }

    private func moveSelectedElement(by offset: Int) {
        guard !isExporting else { return }
        guard let selectedElementID else { return }
        performLayoutChange("undo.reorderElement") {
            layout.moveElement(id: selectedElementID, by: offset)
            self.selectedElementID = selectedElementID
        }
        refreshOverlayOrPreview()
    }

    func updateElement(_ id: String, refreshPreview shouldRefreshPreview: Bool = true, _ update: (inout OverlayElement) -> Void) {
        guard !isExporting else { return }
        let previousWeatherRequirements = layout.elements
            .first(where: { $0.id == id })
            .flatMap(Self.weatherFallbackRequirements)
        performLayoutChange("undo.editElement", coalescing: true) {
            layout.updateElement(id: id, update)
        }
        let updatedElement = layout.elements.first(where: { $0.id == id })
        if shouldRefreshPreview, !layout.elements.contains(where: { $0.id == selectedElementID }) {
            selectedElementID = layout.elements.first?.id
        }
        if shouldRefreshPreview {
            refreshOverlayOrPreview()
        }
        if let updatedElement,
           previousWeatherRequirements != Self.weatherFallbackRequirements(for: updatedElement) {
            loadOpenWeatherForFallbackIfNeeded(for: updatedElement)
        }
    }

    private struct WeatherFallbackRequirements: Equatable {
        var temperature: Bool
        var humidity: Bool
        var summary: Bool

        var isNeeded: Bool { temperature || humidity || summary }
    }

    private static func weatherFallbackRequirements(for element: OverlayElement) -> WeatherFallbackRequirements? {
        guard element.kind == .weather else { return nil }
        let icon = element.customization.iconOverride.flatMap(OverlayWeatherIcon.init(rawValue:)) ?? .auto
        return WeatherFallbackRequirements(
            temperature: element.customization.manualWeatherTemperatureCelsius == nil,
            humidity: element.customization.weatherHumidityIsVisible
                && element.customization.manualWeatherHumidityPercent == nil,
            summary: element.customization.showsIcon && icon == .auto
        )
    }

    private func loadOpenWeatherForFallbackIfNeeded(for element: OverlayElement) {
        guard Self.weatherFallbackRequirements(for: element)?.isNeeded == true,
              let currentSeries = series,
              let fitURL,
              !openWeatherAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loadOpenWeatherIfPossible(
            for: currentSeries,
            sourceName: fitURL.lastPathComponent,
            generation: fitLoadGeneration
        )
    }

    func nudgeElement(_ id: String, deltaX: Double, deltaY: Double) {
        guard !isExporting else { return }
        if selectedElementID != id {
            selectedElementID = id
        }
        clearTimelineClipSelection()
        updateElement(id) { element in
            element.frame.x = PreviewLayoutLimits.clampPosition(element.frame.x + deltaX)
            element.frame.y = PreviewLayoutLimits.clampPosition(element.frame.y + deltaY)
        }
    }

    func updateComponent(_ id: OverlayComponentID, _ update: (inout OverlayComponentFrame) -> Void) {
        guard !isExporting else { return }
        performLayoutChange("undo.editElement", coalescing: true) {
            layout.updateFirstElement(kind: id) { element in
                update(&element.frame)
            }
        }
        refreshOverlayOrPreview()
    }

    // MARK: - Layout undo

    private func beginLayoutUndoTransaction(_ actionKey: String) {
        guard layoutUndoTransaction == nil else { return }
        prepareActiveTimelineOverlayLayoutForEditing()
        layoutUndoTransaction = (layout, selectedElementID, actionKey)
    }

    private func endLayoutUndoTransaction() {
        guard let transaction = layoutUndoTransaction else { return }
        layoutUndoTransaction = nil
        registerLayoutUndoIfChanged(
            previousLayout: transaction.layout,
            previousSelectedElementID: transaction.selectedElementID,
            actionKey: transaction.actionKey,
            coalescing: false
        )
    }

    private func performLayoutChange(_ actionKey: String, coalescing: Bool = false, _ change: () -> Void) {
        guard layoutUndoTransaction == nil else {
            change()
            return
        }
        prepareActiveTimelineOverlayLayoutForEditing()
        let previousLayout = layout
        let previousSelectedElementID = selectedElementID
        change()
        registerLayoutUndoIfChanged(
            previousLayout: previousLayout,
            previousSelectedElementID: previousSelectedElementID,
            actionKey: actionKey,
            coalescing: coalescing
        )
    }

    private func registerLayoutUndoIfChanged(
        previousLayout: OverlayLayout,
        previousSelectedElementID: String?,
        actionKey: String,
        coalescing: Bool
    ) {
        guard previousLayout != layout, let undoManager else { return }
        let now = Date()
        if coalescing,
           !undoManager.isUndoing,
           !undoManager.isRedoing,
           let last = lastCoalescedLayoutUndo,
           last.actionKey == actionKey,
           now.timeIntervalSince(last.date) < Self.layoutUndoCoalescingInterval {
            lastCoalescedLayoutUndo = (actionKey, now)
            return
        }
        lastCoalescedLayoutUndo = coalescing ? (actionKey, now) : nil
        registerLayoutUndo(
            previousLayout: previousLayout,
            previousSelectedElementID: previousSelectedElementID,
            actionKey: actionKey,
            undoManager: undoManager
        )
    }

    private func registerLayoutUndo(
        previousLayout: OverlayLayout,
        previousSelectedElementID: String?,
        actionKey: String,
        undoManager: UndoManager
    ) {
        let opensGroup = undoManager.groupingLevel == 0
            && !undoManager.isUndoing
            && !undoManager.isRedoing
        if opensGroup {
            undoManager.beginUndoGrouping()
        }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.restoreLayoutForUndo(
                    previousLayout: previousLayout,
                    previousSelectedElementID: previousSelectedElementID,
                    actionKey: actionKey
                )
            }
        }
        undoManager.setActionName(localized(actionKey))
        if opensGroup {
            undoManager.endUndoGrouping()
        }
    }

    private func restoreLayoutForUndo(
        previousLayout: OverlayLayout,
        previousSelectedElementID: String?,
        actionKey: String
    ) {
        if let undoManager {
            registerLayoutUndo(
                previousLayout: layout,
                previousSelectedElementID: selectedElementID,
                actionKey: actionKey,
                undoManager: undoManager
            )
        }
        lastCoalescedLayoutUndo = nil
        layoutUndoTransaction = nil
        layout = previousLayout
        if let previousSelectedElementID,
           previousLayout.elements.contains(where: { $0.id == previousSelectedElementID }) {
            selectedElementID = previousSelectedElementID
        } else if !previousLayout.elements.contains(where: { $0.id == selectedElementID }) {
            selectedElementID = previousLayout.elements.first?.id
        }
        refreshOverlayOrPreview()
    }

    // MARK: - Timeline undo

    private struct TimelineMediaUndoSnapshot {
        var timeline: TimelineProject
        var videoAssets: [MediaAsset]
        var activityAssets: [MediaAsset]
        var offlineReasons: [String: TimelineAssetOfflineReason]
        var activitySeriesByAssetID: [String: TelemetrySeries]
        var activitySportByAssetID: [String: TelemetrySport]
        var waveformPeaksByAssetID: [String: [Float]]
        var usesSingleSourceMigration: Bool
        var selectedClipID: String?
        var selectedClipIDs: Set<String>
        var videoURL: URL?
        var fitURL: URL?
        var metadata: VideoMetadata?
        var series: TelemetrySeries?
        var sourceDuration: TimeInterval
        var outputWidth: Int
        var outputHeight: Int
        var outputFPS: Double
        var exportTrimStartSeconds: TimeInterval
        var exportTrimEndSeconds: TimeInterval
        var activityTrim: ActivityTrim
        var bitRateKbps: Int
        var outputURL: URL?
    }

    private var timelineMediaUndoSnapshotNow: TimelineMediaUndoSnapshot {
        TimelineMediaUndoSnapshot(
            timeline: timeline,
            videoAssets: videoAssets,
            activityAssets: activityAssets,
            offlineReasons: offlineTimelineAssetReasons,
            activitySeriesByAssetID: activitySeriesByAssetID,
            activitySportByAssetID: activitySportByAssetID,
            waveformPeaksByAssetID: videoWaveformPeaksByAssetID,
            usesSingleSourceMigration: timelineUsesSingleSourceMigration,
            selectedClipID: selectedTimelineClipID,
            selectedClipIDs: selectedTimelineClipIDs,
            videoURL: videoURL,
            fitURL: fitURL,
            metadata: metadata,
            series: series,
            sourceDuration: sourceDuration,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            outputFPS: outputFPS,
            exportTrimStartSeconds: exportTrimStartSeconds,
            exportTrimEndSeconds: exportTrimEndSeconds,
            activityTrim: activityTrim,
            bitRateKbps: bitRateKbps,
            outputURL: outputURL
        )
    }

    private func registerTimelineMediaUndo(
        previous: TimelineMediaUndoSnapshot,
        actionKey: String,
        undoManager: UndoManager? = nil
    ) {
        guard let undoManager = undoManager ?? self.undoManager else { return }
        let opensGroup = undoManager.groupingLevel == 0
            && !undoManager.isUndoing
            && !undoManager.isRedoing
        if opensGroup {
            undoManager.beginUndoGrouping()
        }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.restoreTimelineMediaForUndo(previous: previous, actionKey: actionKey)
            }
        }
        undoManager.setActionName(localized(actionKey))
        if opensGroup {
            undoManager.endUndoGrouping()
        }
    }

    private func restoreTimelineMediaForUndo(
        previous: TimelineMediaUndoSnapshot,
        actionKey: String
    ) {
        guard !isExporting else { return }
        if let undoManager {
            registerTimelineMediaUndo(
                previous: timelineMediaUndoSnapshotNow,
                actionKey: actionKey,
                undoManager: undoManager
            )
        }

        pausePlayback()
        videoLoadTask?.cancel()
        fitLoadTask?.cancel()
        weatherLoadTask?.cancel()
        videoLoadGeneration += 1
        fitLoadGeneration += 1
        pendingSourceReplacementUndoSnapshot = nil
        pendingSourceReplacementKind = nil
        let restoredMigrationState = previous.usesSingleSourceMigration
        timelineUsesSingleSourceMigration = false
        timeline = previous.timeline
        videoAssets = previous.videoAssets
        activityAssets = previous.activityAssets
        offlineTimelineAssetReasons = previous.offlineReasons
        activitySeriesByAssetID = previous.activitySeriesByAssetID
        activitySportByAssetID = previous.activitySportByAssetID
        videoWaveformPeaksByAssetID = previous.waveformPeaksByAssetID
        videoURL = previous.videoURL
        fitURL = previous.fitURL
        metadata = previous.metadata
        series = previous.series
        sourceDuration = previous.sourceDuration
        outputWidth = previous.outputWidth
        outputHeight = previous.outputHeight
        outputFPS = previous.outputFPS
        exportTrimStartSeconds = previous.exportTrimStartSeconds
        exportTrimEndSeconds = previous.exportTrimEndSeconds
        activityTrim = previous.activityTrim
        bitRateKbps = previous.bitRateKbps
        outputURL = previous.outputURL
        selectedTimelineClipIDs = previous.selectedClipIDs.filter { timelineClip(id: $0) != nil }
        selectedTimelineClipID = previous.selectedClipID.flatMap { timelineClip(id: $0) == nil ? nil : $0 }
            ?? firstSelectedTimelineClipID
        singleSourceAlignmentIsPending = previous.timeline.tracks
            .flatMap(\.clips)
            .contains(where: \.isAlignmentPending)
        timelineUsesSingleSourceMigration = restoredMigrationState
        stopTimelineSecurityScopedAccess()
        startTimelineSecurityScopedAccess(for: timeline.assets)
        if usesCustomTimelinePreview {
            configureTimelinePlayer()
        } else if let videoURL {
            configurePlayer(url: videoURL)
        } else {
            player = nil
            backgroundImage = nil
        }
        refreshOverlayOrPreview()
    }

    private struct TimelinePositionUndoState {
        var exportTrimStartSeconds: TimeInterval
        var exportTrimEndSeconds: TimeInterval
        var exportTrimRangeWasManuallyEdited: Bool
        var previewTime: TimeInterval
    }

    private struct TimelineUndoSnapshot {
        var timeline: TimelineProject
        var usesSingleSourceMigration: Bool
        var selectedClipID: String?
        var selectedClipIDs: Set<String>
        var timelinePositionState: TimelinePositionUndoState?
    }

    private var timelinePositionUndoStateNow: TimelinePositionUndoState {
        TimelinePositionUndoState(
            exportTrimStartSeconds: exportTrimStartSeconds,
            exportTrimEndSeconds: exportTrimEndSeconds,
            exportTrimRangeWasManuallyEdited: exportTrimRangeWasManuallyEdited,
            previewTime: previewTime
        )
    }

    private var timelineUndoSnapshotNow: TimelineUndoSnapshot {
        TimelineUndoSnapshot(
            timeline: timeline,
            usesSingleSourceMigration: timelineUsesSingleSourceMigration,
            selectedClipID: selectedTimelineClipID,
            selectedClipIDs: selectedTimelineClipIDs,
            timelinePositionState: nil
        )
    }

    /// Register one undo step for a timeline mutation. Coalescing merges the rapid-fire
    /// updates of a drag or stepper into a single step, mirroring layout undo.
    private func registerTimelineUndoIfChanged(
        previous: TimelineUndoSnapshot,
        actionKey: String,
        coalescing: Bool
    ) {
        guard previous.timeline != timeline, let undoManager else { return }
        let now = Date()
        if coalescing,
           !undoManager.isUndoing,
           !undoManager.isRedoing,
           let last = lastCoalescedTimelineUndo,
           last.actionKey == actionKey,
           now.timeIntervalSince(last.date) < Self.layoutUndoCoalescingInterval {
            lastCoalescedTimelineUndo = (actionKey, now)
            return
        }
        lastCoalescedTimelineUndo = coalescing ? (actionKey, now) : nil
        registerTimelineUndo(previous: previous, actionKey: actionKey, undoManager: undoManager)
    }

    private func registerTimelineUndo(
        previous: TimelineUndoSnapshot,
        actionKey: String,
        undoManager: UndoManager
    ) {
        let opensGroup = undoManager.groupingLevel == 0
            && !undoManager.isUndoing
            && !undoManager.isRedoing
        if opensGroup {
            undoManager.beginUndoGrouping()
        }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.restoreTimelineForUndo(previous: previous, actionKey: actionKey)
            }
        }
        undoManager.setActionName(localized(actionKey))
        if opensGroup {
            undoManager.endUndoGrouping()
        }
    }

    private func restoreTimelineForUndo(previous: TimelineUndoSnapshot, actionKey: String) {
        guard !isExporting else { return }
        if let undoManager {
            var redoSnapshot = timelineUndoSnapshotNow
            if previous.timelinePositionState != nil {
                redoSnapshot.timelinePositionState = timelinePositionUndoStateNow
            }
            registerTimelineUndo(previous: redoSnapshot, actionKey: actionKey, undoManager: undoManager)
        }
        lastCoalescedTimelineUndo = nil
        pausePlayback()
        timeline = previous.timeline
        singleSourceAlignmentIsPending = previous.timeline.tracks
            .flatMap(\.clips)
            .contains(where: \.isAlignmentPending)
        timelineUsesSingleSourceMigration = previous.usesSingleSourceMigration
        if let positionState = previous.timelinePositionState {
            exportTrimRangeWasManuallyEdited = positionState.exportTrimRangeWasManuallyEdited
            exportTrimStartSeconds = positionState.exportTrimStartSeconds
            exportTrimEndSeconds = positionState.exportTrimEndSeconds
            previewTime = positionState.previewTime
        }
        selectedTimelineClipIDs = previous.selectedClipIDs.filter { timelineClip(id: $0) != nil }
        if let selectedClipID = previous.selectedClipID, timelineClip(id: selectedClipID) != nil {
            selectedTimelineClipID = selectedClipID
        } else {
            repairSelectedTimelineClipIfNeeded()
        }
        if !usesCustomTimelinePreview, let videoURL {
            // Undo back into single-source mode: return the player to the raw video item.
            configurePlayer(url: videoURL)
        }
        previewTime = clampedPreviewTime(previewTime)
        refreshOverlayOrPreview()
    }

    /// Timeline undo steps restore full project snapshots; once the timeline is replaced
    /// wholesale (open project, switch active source, remove referenced assets) those
    /// snapshots reference stale assets, so the undo stack must be dropped.
    private func clearUndoStackForTimelineReplacement() {
        lastCoalescedTimelineUndo = nil
        undoManager?.removeAllActions(withTarget: self)
    }

    nonisolated static func requiresWeatherExportConfirmation(
        project: TimelineProject,
        telemetrySeriesByAssetID: [String: TelemetrySeries],
        timelineStart: TimeInterval,
        duration: TimeInterval,
        isWeatherLoading: Bool
    ) -> Bool {
        guard timelineStart.isFinite,
              timelineStart >= 0,
              duration.isFinite,
              duration > 0,
              (timelineStart + duration).isFinite else { return false }

        let timelineEnd = timelineStart + duration
        let weatherClips = project.enabledClips(kind: .overlay).compactMap { clip -> (TimelineClip, [OverlayElement])? in
            guard clip.timelineEnd > timelineStart,
                  clip.timelineStart < timelineEnd else { return nil }
            let elements = (clip.layout ?? .default).visibleElements.filter { $0.kind == .weather }
            return elements.isEmpty ? nil : (clip, elements)
        }
        guard !weatherClips.isEmpty else { return false }

        return weatherClips.contains { clip, elements in
            guard let series = telemetrySeriesByAssetID[clip.assetID] else { return true }
            return elements.contains { element in
                let needsTemperature = element.customization.manualWeatherTemperatureCelsius == nil
                let needsHumidity = element.customization.weatherHumidityIsVisible
                    && element.customization.manualWeatherHumidityPercent == nil
                if isWeatherLoading && (needsTemperature || needsHumidity) { return true }
                let hasTemperature = !needsTemperature || series.samples.contains {
                    $0.weatherTemperatureCelsius != nil || $0.temperatureCelsius != nil
                }
                let hasHumidity = !needsHumidity || series.samples.contains {
                    $0.weatherHumidityPercent != nil
                }
                return !hasTemperature || !hasHumidity
            }
        }
    }

    func export() {
        export(allowingUnreadyWeather: false)
    }

    func confirmWeatherExport() {
        guard isWeatherExportConfirmationPresented else { return }
        isWeatherExportConfirmationPresented = false
        addDebugLog(.export, "Continuing export without ready weather data")
        export(allowingUnreadyWeather: true)
    }

    func cancelWeatherExportConfirmation() {
        guard isWeatherExportConfirmationPresented else { return }
        isWeatherExportConfirmationPresented = false
        addDebugLog(.export, "Export cancelled before rendering: weather data not ready")
    }

    private func export(allowingUnreadyWeather: Bool) {
        guard !isExporting else { return }
        guard allowingUnreadyWeather || !isWeatherExportConfirmationPresented else { return }
        let offlineNames = offlineAssetNamesForExport(mode: exportMode)
        if !offlineNames.isEmpty {
            setStatus("status.timelineOfflineAssets", offlineNames.joined(separator: ", "))
            return
        }
        if let exportReadinessMessageKey {
            setStatus(exportReadinessMessageKey)
            return
        }
        guard let exportSettings = validatedExportSettings else {
            setStatus("status.checkOutputSettings")
            return
        }
        let timelineProject = currentTimelineProject
        let timelineTelemetrySeries = timelineTelemetrySeriesForExport(project: timelineProject)
        guard !timelineTelemetrySeries.isEmpty else {
            setStatus("status.chooseFitBeforeExport")
            return
        }
        if !allowingUnreadyWeather,
           Self.requiresWeatherExportConfirmation(
               project: timelineProject,
               telemetrySeriesByAssetID: timelineTelemetrySeries,
               timelineStart: exportSettings.startTime,
               duration: exportSettings.duration,
               isWeatherLoading: weatherLoadTask != nil
           ) {
            isWeatherExportConfirmationPresented = true
            addDebugLog(.export, "Export confirmation requested: weather data not ready")
            return
        }
        if needsOutputSelectionBeforeExport {
            chooseOutput()
        }
        guard !needsOutputSelectionBeforeExport, let outputURL else {
            setStatus("status.chooseOutputFile")
            return
        }

        // Resolve the files to write: the whole range as one file, or (DaVinci-style
        // "individual clips") one file per clip inside the export range.
        let currentExportMode = exportMode
        let segments: [ExportSegment]
        if exportRenderScope == .individualClips {
            let ranges = timelineProject.individualClipExportRanges(
                kind: currentExportMode == .video ? .video : .overlay,
                timelineStart: exportSettings.startTime,
                duration: exportSettings.duration
            )
            guard !ranges.isEmpty else {
                setStatus("status.noClipsInExportRange")
                return
            }
            if ranges.count == 1, let only = ranges.first {
                segments = [ExportSegment(startTime: only.start, duration: only.duration, outputURL: outputURL)]
            } else {
                segments = ranges.enumerated().map { index, range in
                    ExportSegment(
                        startTime: range.start,
                        duration: range.duration,
                        outputURL: Self.segmentOutputURL(base: outputURL, index: index + 1, count: ranges.count)
                    )
                }
            }
        } else {
            segments = [
                ExportSegment(
                    startTime: exportSettings.startTime,
                    duration: exportSettings.duration,
                    outputURL: outputURL
                )
            ]
        }
        guard confirmOverwriteIfNeeded(segments.map(\.outputURL)) else { return }

        pausePlayback()
        cancelPreviewRenderTasks()
        let exportStartedAt = Date()
        isExporting = true
        exportProgress = 0
        exportETASeconds = nil
        exportProgressSamples = [(exportStartedAt, 0)]
        lastExportedURL = nil
        lastExportElapsedSeconds = nil
        lastExportErrorMessage = nil
        lastExportWasCancelled = false
        setStatus("status.exporting")
        addDebugLog(.export, "Export started: \(segments.count) file(s), first \(segments[0].outputURL.lastPathComponent), \(exportSettings.width)x\(exportSettings.height), start=\(Self.formatDebugSeconds(exportSettings.startTime)), duration=\(Self.formatDebugSeconds(exportSettings.duration))")
        let cancellationToken = ExportCancellationToken()
        exportCancellationToken = cancellationToken

        let currentCodec = codec
        let currentActivityTrim = self.currentActivityTrim
        let outputAccessURL = outputSecurityScopedURL
            ?? (exportRenderScope == .individualClips ? outputURL.deletingLastPathComponent() : outputURL)
        let didStartOutputAccess = outputAccessURL.startAccessingSecurityScopedResource()
        let diagnosticsHandler: ((String) -> Void)? = currentExportMode == .video
            ? { message in studioDebugLogger.info("[export] \(message, privacy: .public)") }
            : nil
        // Per-segment progress handlers are built on the main actor up front; each maps its
        // segment's progress into the overall multi-file progress.
        let totalSegments = segments.count
        let segmentProgressHandlers: [(Int, Int) -> Void] = segments.indices.map { index in
            { [weak self] completed, total in
                let inner = total > 0 ? Double(completed) / Double(total) : 0
                let overall = (Double(index) + inner) / Double(totalSegments)
                Task { @MainActor in
                    self?.updateExportProgress(overall)
                }
            }
        }

        exportTask = Task.detached {
            defer {
                if didStartOutputAccess {
                    outputAccessURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                for (index, segment) in segments.enumerated() {
                    let segmentProgressHandler = segmentProgressHandlers[index]
                    try TimelineVideoWriter(
                        outputURL: segment.outputURL,
                        project: timelineProject,
                        telemetrySeriesByAssetID: timelineTelemetrySeries,
                        config: TimelineVideoWriterConfig(
                            width: exportSettings.width,
                            height: exportSettings.height,
                            framesPerSecond: exportSettings.framesPerSecond,
                            timelineStart: segment.startTime,
                            duration: segment.duration,
                            averageBitRate: exportSettings.averageBitRate,
                            codec: currentCodec,
                            activityTrim: currentActivityTrim,
                            progressHandler: segmentProgressHandler,
                            cancellationHandler: { cancellationToken.isCancelled },
                            diagnosticsHandler: diagnosticsHandler
                        )
                    ).write()
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportProgress = 1
                    self.exportETASeconds = nil
                    self.lastExportedURL = segments.first?.outputURL ?? outputURL
                    self.lastExportElapsedSeconds = Date().timeIntervalSince(exportStartedAt)
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    if segments.count == 1 {
                        self.setStatus("status.wroteFile", outputURL.path)
                    } else {
                        self.setStatus(
                            "status.wroteFiles",
                            segments.count,
                            outputURL.deletingLastPathComponent().path
                        )
                    }
                    self.addDebugLog(.export, "Export finished: \(segments.count) file(s), first \(segments[0].outputURL.lastPathComponent)")
                    self.notifyExportCompleted(
                        segments.first?.outputURL ?? outputURL,
                        fileCount: segments.count
                    )
                    self.refreshOverlayOrPreview()
                }
            } catch OverlayVideoError.cancelled {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportProgress = 0
                    self.exportETASeconds = nil
                    self.lastExportElapsedSeconds = Date().timeIntervalSince(exportStartedAt)
                    self.lastExportWasCancelled = true
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.setStatus("status.exportCancelled")
                    self.addDebugLog(.export, "Export cancelled")
                    self.refreshOverlayOrPreview()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportETASeconds = nil
                    self.lastExportElapsedSeconds = Date().timeIntervalSince(exportStartedAt)
                    self.lastExportErrorMessage = error.localizedDescription
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.setStatus("status.exportError", error.localizedDescription)
                    self.addDebugLog(.export, "Export failed: \(error.localizedDescription)")
                    self.refreshOverlayOrPreview()
                }
            }
        }
    }

    func export(as mode: OverlayExportMode) {
        exportMode = mode
        normalizeCodecForExportMode()
        export()
    }

    func updateExportProgress(_ progress: Double, at date: Date = Date()) {
        exportProgress = progress
        exportProgressSamples.append((date, progress))
        exportProgressSamples.removeAll { date.timeIntervalSince($0.date) > Self.exportETASampleWindow }
        guard progress > 0.02,
              progress < 1,
              let first = exportProgressSamples.first,
              date.timeIntervalSince(first.date) > 1,
              progress > first.progress else {
            return
        }
        let rate = (progress - first.progress) / date.timeIntervalSince(first.date)
        guard rate > 0 else { return }
        exportETASeconds = (1 - progress) / rate
    }

    func revealLastExportInFinder() {
        guard let lastExportedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastExportedURL])
    }

    func openLastExport() {
        guard let lastExportedURL else { return }
        NSWorkspace.shared.open(lastExportedURL)
    }

    func clearExportResult() {
        guard !isExporting else { return }
        lastExportedURL = nil
        lastExportElapsedSeconds = nil
        lastExportErrorMessage = nil
        lastExportWasCancelled = false
    }

    private func notifyExportCompleted(_ outputURL: URL, fileCount: Int = 1) {
        let title = localized("notification.exportCompleted.title")
        let body = fileCount > 1
            ? localized("notification.exportCompleted.bodyMultiple", fileCount)
            : localized("notification.exportCompleted.body", outputURL.lastPathComponent)
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["exportPath": outputURL.path]

            let request = UNNotificationRequest(
                identifier: "datalayer-export-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    func cancelExport() {
        guard isExporting else { return }
        exportCancellationToken?.cancel()
        exportTask?.cancel()
        setStatus("status.cancellingExport")
    }

    private func confirmOverwriteIfNeeded(_ urls: [URL]) -> Bool {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let first = existing.first else { return true }
        let alert = NSAlert()
        alert.messageText = localized("alert.overwriteOutput.title")
        alert.informativeText = existing.count == 1
            ? localized("alert.overwriteOutput.message", first.lastPathComponent)
            : localized("alert.overwriteOutput.multipleMessage", existing.count)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("alert.overwriteOutput.confirm"))
        alert.addButton(withTitle: localized("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Output URL for one segment of an "individual clips" export: `name.mov` → `name_01.mov`.
    nonisolated static func segmentOutputURL(base: URL, index: Int, count: Int) -> URL {
        let fileExtension = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        let width = max(2, String(count).count)
        let name = stem + String(format: "_%0\(width)d", index)
        var url = base.deletingLastPathComponent().appendingPathComponent(name)
        if !fileExtension.isEmpty {
            url = url.appendingPathExtension(fileExtension)
        }
        return url
    }

    func refreshLocalizedStatus() {
        status = AppLocalizer.string(statusMessage.key, language: resolvedLanguage, arguments: statusMessage.arguments)
    }

    private func setStatus(_ key: String, _ arguments: CVarArg...) {
        statusMessage = (key, arguments)
        status = AppLocalizer.string(key, language: resolvedLanguage, arguments: arguments)
    }

    private func setStatusAndToast(_ kind: StudioToast.Kind, _ key: String, _ arguments: CVarArg...) {
        statusMessage = (key, arguments)
        status = AppLocalizer.string(key, language: resolvedLanguage, arguments: arguments)
        showToast(status, kind: kind)
    }

    func showToast(_ message: String, kind: StudioToast.Kind = .info) {
        let toast = StudioToast(message: message, kind: kind)
        toasts.append(toast)
        if toasts.count > 3 {
            toasts.removeFirst(toasts.count - 3)
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.dismissToast(id: toast.id)
        }
    }

    func dismissToast(id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    private func formatStatusDuration(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60

        switch resolvedLanguage {
        case .english:
            if hours > 0 { return "\(hours) h \(minutes) min \(seconds) sec" }
            if minutes > 0 { return "\(minutes) min \(seconds) sec" }
            return "\(seconds) sec"
        case .japanese:
            if hours > 0 { return "\(hours)時間\(minutes)分\(seconds)秒" }
            if minutes > 0 { return "\(minutes)分\(seconds)秒" }
            return "\(seconds)秒"
        case .simplifiedChinese:
            if hours > 0 { return "\(hours)小时\(minutes)分\(seconds)秒" }
            if minutes > 0 { return "\(minutes)分\(seconds)秒" }
            return "\(seconds)秒"
        case .traditionalChinese:
            if hours > 0 { return "\(hours)小時\(minutes)分\(seconds)秒" }
            if minutes > 0 { return "\(minutes)分\(seconds)秒" }
            return "\(seconds)秒"
        }
    }

    private func localized(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalizer.string(key, language: resolvedLanguage, arguments: arguments)
    }

    private func persistLayoutPresets() {
        let state = LayoutPresetState(presets: layoutPresets, defaultPresetID: defaultLayoutPresetID)
        layoutPresetStore.save(state)
        layoutPresetSyncStatus = layoutPresetStore.synchronizeCloud()
            ? .uploadRequested(Date())
            : .localOnly
    }

    private func observeLayoutPresetCloudChanges() {
        layoutPresetSyncStatus = layoutPresetStore.synchronizeCloud() ? .ready : .localOnly
        let key = layoutPresetStore.cloudNotificationKey
        layoutPresetCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            guard changedKeys?.contains(key) ?? true else { return }
            MainActor.assumeIsolated {
                self?.reloadLayoutPresetsFromStore()
                self?.layoutPresetSyncStatus = .receivedUpdate(Date())
            }
        }
    }

    private func reloadLayoutPresetsFromStore() {
        let presetState = layoutPresetStore.load()
        let validDefaultPresetID = presetState.presets.contains { $0.id == presetState.defaultPresetID }
            ? presetState.defaultPresetID
            : nil
        layoutPresets = presetState.presets
        defaultLayoutPresetID = validDefaultPresetID
    }

    private func persistStudioPreferences() {
        preferenceStore.save(StudioPreferenceState(
            showGrid: showGrid,
            safeAreaInsetPercent: canvasSafeAreaInsetPercent,
            distanceUnit: distanceUnit,
            userExportPresets: userExportPresets
        ))
    }

    private func cancelPreviewRenderTasks() {
        previewRenderGeneration += 1
        previewRenderTask?.cancel()
        pendingPreviewSizeRefreshTask?.cancel()
        scrubInteractionTask?.cancel()
        previewRenderTask = nil
        pendingPreviewSizeRefreshTask = nil
        scrubInteractionTask = nil
        scrubInteractionExpiresAt = .distantPast
        isScrubbingPreview = false
        pendingOverlayRefreshAfterCurrentRender = false
        pendingOverlayRefreshDisplaysIntermediateResult = false
    }

    private func cancelLoadTasks() {
        videoLoadTask?.cancel()
        fitLoadTask?.cancel()
        videoWaveformLoadTasks.values.forEach { $0.cancel() }
        videoLoadTask = nil
        fitLoadTask = nil
        videoWaveformLoadTasks.removeAll()
    }

    private var validatedExportSettings: ExportSettings? {
        guard outputWidth >= 2, outputWidth <= 16_384 else { return nil }
        guard outputHeight >= 2, outputHeight <= 16_384 else { return nil }
        guard outputWidth % 2 == 0, outputHeight % 2 == 0 else { return nil }
        guard outputFPS.isFinite, outputFPS >= 1, outputFPS <= 240 else { return nil }
        guard let duration = exportDuration else { return nil }
        guard bitRateKbps >= 1, bitRateKbps <= 1_000_000 else { return nil }
        guard bitRateKbps <= Int.max / 1000 else { return nil }
        return ExportSettings(
            width: outputWidth,
            height: outputHeight,
            framesPerSecond: outputFPS,
            startTime: sourceExportTrimStart,
            duration: duration,
            averageBitRate: bitRateKbps * 1000
        )
    }

    private var exportDuration: TimeInterval? {
        let duration = max(0, sourceExportTrimEnd - sourceExportTrimStart)
        guard duration.isFinite, duration >= 0.1, duration <= 86_400 else { return nil }
        return duration
    }

    private var sourceExportTrimStart: TimeInterval {
        sanitizedExportTrimStart(exportTrimStartSeconds, sourceDuration: exportTrimSourceDuration)
    }

    private var sourceExportTrimEnd: TimeInterval {
        sanitizedExportTrimEnd(
            exportTrimEndSeconds,
            start: sourceExportTrimStart,
            sourceDuration: exportTrimSourceDuration
        )
    }

    private func resetExportTrimRangeToFullDuration() {
        exportTrimRangeWasManuallyEdited = false
        exportTrimStartSeconds = 0
        exportTrimEndSeconds = exportTrimEditingDuration
    }

    private func updateDefaultExportRangeForTimelineChange() {
        guard !exportTrimRangeWasManuallyEdited else { return }
        exportTrimStartSeconds = 0
        exportTrimEndSeconds = exportTrimEditingDuration
    }

    private func sanitizedActivityTrimStart(_ value: TimeInterval, sourceDuration: TimeInterval) -> TimeInterval {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return 0 }
        let upperBound = max(0, sourceDuration - Self.minimumExportTrimDuration)
        let finiteValue = value.isFinite ? value : 0
        return min(upperBound, max(0, finiteValue))
    }

    private func sanitizedActivityTrimEnd(
        _ value: TimeInterval?,
        start: TimeInterval,
        sourceDuration: TimeInterval
    ) -> TimeInterval {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return 0 }
        let fallbackEnd = value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? sourceDuration
        let minimumEnd = min(sourceDuration, start + Self.minimumExportTrimDuration)
        return min(sourceDuration, max(minimumEnd, fallbackEnd))
    }

    private func sanitizedActivityTrimEnd(
        _ value: TimeInterval,
        start: TimeInterval,
        sourceDuration: TimeInterval
    ) -> TimeInterval {
        sanitizedActivityTrimEnd(Optional(value), start: start, sourceDuration: sourceDuration)
    }

    private func sanitizedExportTrimStart(_ value: TimeInterval, sourceDuration: TimeInterval) -> TimeInterval {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return 0 }
        let upperBound = max(0, sourceDuration - Self.minimumExportTrimDuration)
        let finiteValue = value.isFinite ? value : 0
        return min(upperBound, max(0, finiteValue))
    }

    private func sanitizedExportTrimEnd(
        _ value: TimeInterval,
        start: TimeInterval,
        sourceDuration: TimeInterval
    ) -> TimeInterval {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return 0 }
        let fallbackEnd = value.isFinite && value > 0 ? value : sourceDuration
        let minimumEnd = min(sourceDuration, start + Self.minimumExportTrimDuration)
        return min(sourceDuration, max(minimumEnd, fallbackEnd))
    }

    private func mergeImportedLayoutPresets(_ importedState: LayoutPresetState) -> Int {
        var usedIDs = Set(layoutPresets.map(\.id))
        var usedNames = Set(layoutPresets.map { Self.normalizedPresetName($0.name) })
        var importedIDMap: [String: String] = [:]
        var importedCount = 0

        for preset in importedState.presets {
            let baseName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baseName.isEmpty else { continue }

            var importedPreset = preset
            importedPreset.id = uniquePresetID(preferredID: preset.id, usedIDs: &usedIDs)
            importedPreset.name = uniquePresetName(baseName, usedNames: &usedNames)
            importedPreset.layout = preset.layout.sanitized
            importedIDMap[preset.id] = importedPreset.id
            layoutPresets.append(importedPreset)
            importedCount += 1
        }

        if defaultLayoutPresetID == nil,
           let importedDefaultPresetID = importedState.defaultPresetID,
           let mappedDefaultPresetID = importedIDMap[importedDefaultPresetID] {
            defaultLayoutPresetID = mappedDefaultPresetID
        }

        if importedCount > 0 {
            persistLayoutPresets()
        }
        return importedCount
    }

    private func uniquePresetID(preferredID: String, usedIDs: inout Set<String>) -> String {
        if !preferredID.isEmpty, !usedIDs.contains(preferredID) {
            usedIDs.insert(preferredID)
            return preferredID
        }

        var id = UUID().uuidString
        while usedIDs.contains(id) {
            id = UUID().uuidString
        }
        usedIDs.insert(id)
        return id
    }

    private func uniquePresetName(_ baseName: String, usedNames: inout Set<String>) -> String {
        let normalizedBaseName = Self.normalizedPresetName(baseName)
        if !usedNames.contains(normalizedBaseName) {
            usedNames.insert(normalizedBaseName)
            return baseName
        }

        var suffix = 2
        var candidate = "\(baseName) \(suffix)"
        while usedNames.contains(Self.normalizedPresetName(candidate)) {
            suffix += 1
            candidate = "\(baseName) \(suffix)"
        }
        usedNames.insert(Self.normalizedPresetName(candidate))
        return candidate
    }

    private static func normalizedPresetName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func sanitizedOutputDimension(_ value: Int) -> Int {
        var sanitized = min(16_384, max(2, value))
        if sanitized % 2 != 0 {
            sanitized += sanitized < 16_384 ? 1 : -1
        }
        return sanitized
    }

    static func sanitizedOutputFrameRate(_ value: Double) -> Double {
        let finiteValue = value.isFinite ? value : 1
        return min(240, max(1, finiteValue))
    }

    static func sanitizedSourceDuration(_ value: TimeInterval) -> TimeInterval {
        let finiteValue = value.isFinite ? value : 0.1
        return min(86_400, max(0.1, finiteValue))
    }

    static func sanitizedBitRateKbps(_ value: Int) -> Int {
        min(1_000_000, max(1, value))
    }

    static func sortedLayoutPresets(_ presets: [LayoutPreset], defaultPresetID: String?) -> [LayoutPreset] {
        presets.sorted { lhs, rhs in
            if lhs.id == defaultPresetID, rhs.id != defaultPresetID { return true }
            if rhs.id == defaultPresetID, lhs.id != defaultPresetID { return false }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func sourceVideoBitRateKbps(from metadata: VideoMetadata) -> Int? {
        guard let bitRate = metadata.bitRateBitsPerSecond,
              bitRate.isFinite,
              bitRate > 0 else { return nil }
        return sanitizedBitRateKbps(Int((bitRate / 1000).rounded()))
    }

    private static func firstSelectableElementID(in layout: OverlayLayout) -> String? {
        layout.elements.first { $0.kind == .speed }?.id ?? layout.elements.first?.id
    }

    private var sourceDimensions: (width: Int, height: Int)? {
        guard let metadata else { return nil }
        return (
            width: Self.sanitizedOutputDimension(Int(metadata.size.width.rounded())),
            height: Self.sanitizedOutputDimension(Int(metadata.size.height.rounded()))
        )
    }

    private var sourceFrameRate: Double? {
        guard let metadata else { return nil }
        guard metadata.framesPerSecond.isFinite,
              metadata.framesPerSecond >= 1,
              metadata.framesPerSecond <= 240 else {
            return nil
        }
        return metadata.framesPerSecond
    }

    private func frameRatesMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.01
    }

    private func formatFrameRate(_ fps: Double) -> String {
        if frameRatesMatch(fps, fps.rounded()) {
            return String(format: "%.0f", fps)
        }
        return String(format: "%.3f", fps)
    }

    func applySuggestedOutputURLIfNeeded(for sourceURL: URL, replacingManualSelection: Bool = false) {
        guard replacingManualSelection || outputURL == nil || outputURLWasAutoGenerated else { return }
        let directory = replacingManualSelection ? outputURL?.deletingLastPathComponent() : nil
        outputURL = suggestedOutputURL(for: sourceURL, directory: directory)
        outputURLWasAutoGenerated = true
        outputSecurityScopedURL = nil
    }

    private func suggestedOutputURL() -> URL? {
        if let videoURL {
            return suggestedOutputURL(for: videoURL)
        }
        guard let fitURL else { return nil }
        return suggestedOutputURL(for: fitURL)
    }

    private func suggestedOutputURL(for sourceURL: URL, directory: URL? = nil) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let suffix = exportMode == .video ? "with_overlay" : "overlay"
        let outputName = baseName.isEmpty ? "datalayer-\(suffix)" : "\(baseName)_\(suffix)"
        return (directory ?? sourceURL.deletingLastPathComponent())
            .appendingPathComponent(outputName)
            .appendingPathExtension("mov")
    }

    private func normalizeCodecForExportMode() {
        if codec.exportMode != exportMode {
            codec = exportMode.defaultCodec
        }
    }

    private func refreshSuggestedOutputURLForCurrentSource() {
        if let videoURL {
            applySuggestedOutputURLIfNeeded(for: videoURL)
        } else if let fitURL {
            applySuggestedOutputURLIfNeeded(for: fitURL)
        }
    }

    private func finiteTime(_ time: TimeInterval) -> TimeInterval {
        time.isFinite ? time : 0
    }

    private func nonNegativeTime(_ time: TimeInterval) -> TimeInterval {
        max(0, finiteTime(time))
    }

    func clearDebugLog() {
        debugLogEntries.removeAll()
        studioDebugLogger.info("Debug log cleared")
    }

    func copyDebugLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(debugLogText(debugLogEntries), forType: .string)
    }

    private func addDebugLog(_ category: DebugLogCategory, _ message: String) {
        debugLogEntries.append(DebugLogEntry(date: Date(), category: category, message: message))
        if debugLogEntries.count > 200 {
            debugLogEntries.removeFirst(debugLogEntries.count - 200)
        }
        studioDebugLogger.info("[\(category.rawValue, privacy: .public)] \(message, privacy: .public)")
    }

    private func debugLogText(_ entries: [DebugLogEntry]) -> String {
        entries.map { entry in
            "\(entry.date.formatted(date: .numeric, time: .standard)) [\(entry.category.rawValue)] \(entry.message)"
        }
        .joined(separator: "\n")
    }

    private func redactedKeySummary(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "empty" }
        return "configured, \(trimmed.count) chars"
    }

    private static func formatDebugSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }
}

/// DaVinci-style render scope: render the export range as one file, or every clip in the range
/// as its own file.
enum ExportRenderScope: String, Codable, CaseIterable, Identifiable {
    case singleClip
    case individualClips

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .singleClip: return "renderScope.singleClip"
        case .individualClips: return "renderScope.individualClips"
        }
    }
}

private struct ExportSegment {
    var startTime: TimeInterval
    var duration: TimeInterval
    var outputURL: URL
}

private struct ExportSettings {
    var width: Int
    var height: Int
    var framesPerSecond: Double
    var startTime: TimeInterval
    var duration: TimeInterval
    var averageBitRate: Int
}

private final class ExportCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
