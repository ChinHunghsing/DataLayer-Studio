import AppKit
import AVFoundation
import CoreImage
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

enum TimelinePendingAction: Equatable {
    case selectVideoAsset(id: String)
    case selectActivityAsset(id: String)
    case removeVideoAsset(id: String)
    case removeActivityAsset(id: String)
    case openTimelineProject
    case closeWindow
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
    @Published private(set) var videoWaveformPeaksByAssetID: [String: [Float]] = [:]
    @Published private(set) var timeline = TimelineProject(
        outputWidth: 1920,
        outputHeight: 1080,
        framesPerSecond: 30,
        distanceUnit: .kilometers
    ) {
        didSet {
            repairSelectedTimelineTrackIfNeeded()
            updateTimelineDirtyState()
            updateDefaultExportRangeForTimelineChange()
            scheduleTimelinePlayerRefreshIfNeeded()
        }
    }
    @Published private(set) var hasUnsavedTimelineChanges = false
    @Published private(set) var pendingTimelineAction: TimelinePendingAction?
    @Published private(set) var confirmedWindowCloseGeneration = 0

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
    @Published var exportTrimStartSeconds: TimeInterval = 0
    @Published var exportTrimEndSeconds: TimeInterval = 0
    @Published var activityTrim: ActivityTrim = .none
    @Published var bitRateKbps = 12_000
    @Published var exportMode: OverlayExportMode = .overlay {
        didSet {
            guard oldValue != exportMode else { return }
            normalizeCodecForExportMode()
            refreshSuggestedOutputURLForCurrentSource()
        }
    }
    @Published var codec: OverlayVideoCodec = .hevcAlpha
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
    @Published var selectedElementID: String?
    @Published var selectedTimelineClipID: String?
    @Published private(set) var selectedTimelineTrackIDs: Set<String> = []
    @Published var layoutPresets: [LayoutPreset]
    @Published var defaultLayoutPresetID: String?
    @Published var layoutPresetSyncStatus: LayoutPresetSyncStatus = .localOnly

    @Published var showGrid = false {
        didSet { persistStudioPreferences() }
    }
    @Published var gridColumns = 12 {
        didSet { persistStudioPreferences() }
    }
    @Published var gridRows = 8 {
        didSet { persistStudioPreferences() }
    }
    @Published var snapGaugeToGrid = false {
        didSet { persistStudioPreferences() }
    }

    @Published var status = AppLocalizer.currentString("status.chooseVideoAndFit")
    @Published private(set) var videoLoadFailure: SourceLoadFailure?
    @Published private(set) var fitLoadFailure: SourceLoadFailure?
    @Published var previewWarning: String?
    @Published var isExporting = false
    @Published private(set) var isWeatherExportConfirmationPresented = false
    @Published var exportProgress = 0.0
    @Published private(set) var exportETASeconds: TimeInterval?
    @Published private(set) var lastExportedURL: URL?
    @Published private(set) var lastExportElapsedSeconds: TimeInterval?
    @Published private(set) var lastExportErrorMessage: String?
    @Published private(set) var lastExportWasCancelled = false
    @Published var openWeatherAPIKey = OpenWeatherKeyStore.load()
    @Published var weatherRefreshMessage: String?
    @Published var debugLogEntries: [DebugLogEntry] = []

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
    private var previewRenderGeneration = 0
    private var videoLoadGeneration = 0
    private var fitLoadGeneration = 0
    private var previewOverlayRenderSize: CGSize?
    private var lastOverlayRefresh = Date.distantPast
    private let maximumPreviewRenderDimension: CGFloat = 3_200
    private var previewRenderTask: Task<Void, Never>?
    private var pendingPreviewSizeRefreshTask: Task<Void, Never>?
    private var scrubInteractionTask: Task<Void, Never>?
    private var isPreviewLiveResizing = false
    private var pendingPreviewLiveResizeSize: CGSize?
    private var scrubInteractionExpiresAt = Date.distantPast
    private var videoLoadTask: Task<Void, Never>?
    private var fitLoadTask: Task<Void, Never>?
    private var weatherLoadTask: Task<Void, Never>?
    private var videoWaveformLoadTasks: [String: Task<Void, Never>] = [:]
    private var pendingVideoTimelineImportIDs: [String] = []
    private var pendingActivityTimelineImportIDs: [String] = []
    private var pendingOverlayRefreshAfterCurrentRender = false
    private var pendingOverlayRefreshDisplaysIntermediateResult = false
    private var isScrubbingPreview = false
    private var isGaugeDragActive = false
    private var exportProgressSamples: [(date: Date, progress: Double)] = []
    private static let exportETASampleWindow: TimeInterval = 10
    private static let minimumExportTrimDuration: TimeInterval = 0.1
    weak var undoManager: UndoManager? {
        didSet { undoManager?.levelsOfUndo = 100 }
    }
    private var layoutUndoTransaction: (layout: OverlayLayout, selectedElementID: String?, actionKey: String)?
    private var lastCoalescedLayoutUndo: (actionKey: String, date: Date)?
    private static let layoutUndoCoalescingInterval: TimeInterval = 0.8
    private var lastCoalescedTimelineUndo: (actionKey: String, date: Date)?
    private var exportTask: Task<Void, Never>?
    private var exportCancellationToken: ExportCancellationToken?
    private var outputURLWasAutoGenerated = false
    private var exportTrimRangeWasManuallyEdited = false
    private var timelineUsesSingleSourceMigration = true
    private var isRestoringTimelineSourceMatchPoint = false
    private var activitySeriesByAssetID: [String: TelemetrySeries] = [:]
    private var timelineSecurityScopedURLs: [URL] = []
    private var cleanTimelineSnapshot: TimelineProject?
    private var allowsNextWindowClose = false

    init(
        layoutPresetStore: LayoutPresetStore = LayoutPresetStore(),
        preferenceStore: StudioPreferenceStore = StudioPreferenceStore(),
        openWeatherService: OpenWeatherService = OpenWeatherService()
    ) {
        self.layoutPresetStore = layoutPresetStore
        self.preferenceStore = preferenceStore
        self.openWeatherService = openWeatherService
        let presetState = layoutPresetStore.loadIncludingSharedAppDomains()
        let preferenceState = preferenceStore.load()
        let validDefaultPresetID = presetState.presets.contains { $0.id == presetState.defaultPresetID } ? presetState.defaultPresetID : nil
        self.layoutPresets = presetState.presets
        self.defaultLayoutPresetID = validDefaultPresetID
        self.layout = presetState.presets.first { $0.id == validDefaultPresetID }?.layout.sanitized ?? .default
        self.selectedElementID = Self.firstSelectableElementID(in: layout)
        self.distanceUnit = preferenceState.distanceUnit
        self.showGrid = preferenceState.showGrid
        self.gridColumns = preferenceState.gridColumns
        self.gridRows = preferenceState.gridRows
        self.snapGaugeToGrid = preferenceState.snapGaugeToGrid
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
        exportReadinessMessageKey(for: mode, codec: mode.defaultCodec) == nil
    }

    var needsOutputSelectionBeforeExport: Bool {
        outputURL == nil || outputURLWasAutoGenerated
    }

    var layoutPresetsForDisplay: [LayoutPreset] {
        Self.sortedLayoutPresets(layoutPresets, defaultPresetID: defaultLayoutPresetID)
    }

    func setResolvedLanguage(_ language: AppResolvedLanguage) {
        guard resolvedLanguage != language else { return }
        resolvedLanguage = language
        refreshLocalizedStatus()
    }

    var exportReadinessMessage: String? {
        exportReadinessMessageKey.map { localized($0) }
    }

    func exportReadinessMessage(for mode: OverlayExportMode) -> String? {
        exportReadinessMessageKey(for: mode, codec: mode.defaultCodec).map { localized($0) }
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

    var usesCustomTimelinePreview: Bool {
        guard timelineUsesSingleSourceMigration else { return true }
        guard videoURL != nil else { return false }

        let videoClips = timeline.tracks
            .filter { $0.kind == .video && $0.isEnabled }
            .flatMap(\.clips)
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
        Task.detached {
            do {
                let loaded = try await VideoMetadata.loadAsync(from: url)
                await MainActor.run { [weak self] in
                    self?.upsertVideoAsset(url: url, metadata: loaded)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.discardPendingVideoTimelineImport(id: url.path)
                }
            }
        }
    }

    /// Parse an activity file off the main thread and add it to the pool without changing the
    /// active source. Used when multiple files are imported at once.
    private func addActivityAssetToPool(_ url: URL) {
        Task.detached {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let parsed = try TelemetryFileParser().parse(url: url)
                await MainActor.run { [weak self] in
                    self?.upsertActivityAsset(url: url, series: parsed)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.discardPendingActivityTimelineImport(id: url.path)
                }
            }
        }
    }

    func openActivityFile(_ url: URL) {
        guard ["fit", "gpx"].contains(url.pathExtension.lowercased()) else { return }
        setFIT(url)
    }

    func chooseOutput() {
        guard !isExporting else { return }
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

    func setOutputHeight(_ value: Int) {
        outputHeight = Self.sanitizedOutputDimension(value)
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
        setStatus("status.weatherRefreshing", fitURL.lastPathComponent)
        weatherRefreshMessage = status
        addDebugLog(.weather, "Refresh started: \(fitURL.lastPathComponent), samples=\(currentSeries.samples.count), key=\(redactedKeySummary(openWeatherAPIKey))")
        loadOpenWeatherIfPossible(
            for: currentSeries,
            sourceName: fitURL.lastPathComponent,
            generation: fitLoadGeneration,
            forceRefresh: true
        )
    }

    func setGridColumns(_ value: Int) {
        gridColumns = Self.sanitizedGridDivision(value)
    }

    func setGridRows(_ value: Int) {
        gridRows = Self.sanitizedGridDivision(value)
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
            setStatus("status.updatedPreset", name)
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
        setStatus("status.savedPreset", name)
        return true
    }

    func applyLayoutPreset(id: String) {
        guard !isExporting else { return }
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        performLayoutChange("undo.applyPreset") {
            layout = preset.layout.sanitized
            selectedElementID = Self.firstSelectableElementID(in: layout)
        }
        setStatus("status.appliedPreset", preset.name)
        refreshOverlayOrPreview()
    }

    func setDefaultLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        defaultLayoutPresetID = id
        persistLayoutPresets()
        setStatus("status.defaultPreset", preset.name)
    }

    func deleteLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        layoutPresets.removeAll { $0.id == id }
        if defaultLayoutPresetID == id {
            defaultLayoutPresetID = nil
        }
        persistLayoutPresets()
        setStatus("status.deletedPreset", preset.name)
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
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "datalayer-studio-layout-presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let state = LayoutPresetState(presets: layoutPresets, defaultPresetID: defaultLayoutPresetID)
            let data = try encoder.encode(state.sanitized)
            try data.write(to: url, options: .atomic)
            setStatus("status.exportedPresets", layoutPresets.count)
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
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

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
                setStatus("status.importedPresets", importedCount)
            }
        } catch {
            setStatus("status.presetImportError", error.localizedDescription)
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

    private func presentOpenTimelineProjectPanel() {
        let panel = NSOpenPanel()
        panel.title = localized("panel.openTimelineProject")
        panel.message = localized("panel.openTimelineProject.message")
        panel.prompt = localized("panel.open")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            try loadTimelineProject(from: data, loadAssets: true)
            setStatus("status.timelineProjectLoaded", url.lastPathComponent)
        } catch {
            setStatus("status.timelineProjectLoadError", error.localizedDescription)
        }
    }

    func saveTimelineProject() {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.title = localized("panel.saveTimelineProject")
        panel.message = localized("panel.saveTimelineProject.message")
        panel.prompt = localized("panel.save")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "datalayer-studio-project.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try timelineProjectJSONData()
            try data.write(to: url, options: .atomic)
            markTimelineProjectClean()
            setStatus("status.timelineProjectSaved", url.lastPathComponent)
        } catch {
            setStatus("status.timelineProjectSaveError", error.localizedDescription)
        }
    }

    func timelineProjectJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(timelineProjectForSaving())
    }

    func loadTimelineProject(from data: Data, loadAssets: Bool = true) throws {
        guard !isExporting else { return }
        let decoded = try JSONDecoder().decode(TimelineProject.self, from: data)
        let project = resolvedTimelineProject(decoded)
        stopTimelineSecurityScopedAccess()
        startTimelineSecurityScopedAccess(for: project.assets)
        applyTimelineProject(project, loadAssets: loadAssets)
    }

    func applyTimelineProject(_ project: TimelineProject, loadAssets: Bool = true) {
        guard !isExporting else { return }
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

        var sanitizedProject = project
        sanitizedProject.outputWidth = Self.sanitizedOutputDimension(project.outputWidth)
        sanitizedProject.outputHeight = Self.sanitizedOutputDimension(project.outputHeight)
        sanitizedProject.framesPerSecond = Self.sanitizedOutputFrameRate(project.framesPerSecond)

        timelineUsesSingleSourceMigration = false
        outputWidth = sanitizedProject.outputWidth
        outputHeight = sanitizedProject.outputHeight
        outputFPS = sanitizedProject.framesPerSecond
        distanceUnit = sanitizedProject.distanceUnit
        exportTrimRangeWasManuallyEdited = false
        timeline = sanitizedProject
        videoAssets = sanitizedProject.assets.filter { $0.kind == .video }
        activityAssets = sanitizedProject.assets.filter { $0.kind == .activity }
        activitySeriesByAssetID.removeAll()

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
        exportTrimStartSeconds = 0
        exportTrimEndSeconds = exportTrimEditingDuration
        activityTrim = .none
        backgroundImage = nil
        overlayImage = nil
        previewWarning = nil
        videoLoadFailure = nil
        fitLoadFailure = nil
        selectedTimelineClipID = nil
        selectedTimelineTrackIDs.removeAll()
        previewTime = clampedPreviewTime(previewTime)
        if let sourceURL = activeVideo?.url ?? activeActivity?.url {
            applySuggestedOutputURLIfNeeded(for: sourceURL)
        }
        refreshOverlayOrPreview()
        markTimelineProjectClean()

        guard loadAssets else { return }
        loadTimelineProjectAssets(sanitizedProject.assets)
    }

    private func timelineProjectForSaving() -> TimelineProject {
        var project = currentTimelineProject
        project.assets = project.assets.map { asset in
            var updated = asset
            updated.bookmarkData = securityScopedBookmarkData(for: asset.url) ?? asset.bookmarkData
            return updated
        }
        return project
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

    private func resolvedTimelineProject(_ project: TimelineProject) -> TimelineProject {
        var resolved = project
        resolved.assets = project.assets.map { asset in
            guard let bookmarkData = asset.bookmarkData else { return asset }
            var isStale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return asset
            }
            var updated = asset
            updated.url = resolvedURL
            return updated
        }
        return resolved
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
        for asset in assets {
            switch asset.kind {
            case .video:
                addVideoAssetToPool(asset.url)
            case .activity:
                addActivityAssetToPool(asset.url)
            }
        }
    }

    var pendingTimelineActionTitle: String {
        guard let pendingTimelineAction else { return "" }
        switch pendingTimelineAction {
        case .selectVideoAsset, .selectActivityAsset:
            return localized("timeline.confirmReplace.title")
        case .removeVideoAsset, .removeActivityAsset:
            return localized("timeline.confirmRemove.title")
        case .openTimelineProject, .closeWindow:
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
        case .openTimelineProject:
            return localized("timeline.unsaved.openProject")
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
        case .openTimelineProject, .closeWindow:
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
                    self.refreshPreview()
                    self.videoLoadTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.videoLoadGeneration == loadGeneration else { return }
                    self.discardPendingVideoTimelineImport(id: url.path)
                    self.videoLoadTask = nil
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
                }
            }
        }
    }

    func configurePlayer(url: URL) {
        pausePlayback()
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
                guard !self.isScrubbingPreview else { return }
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
                box = CompositionBox(composition: built.composition, failureMessage: nil)
            } catch {
                box = CompositionBox(composition: nil, failureMessage: error.localizedDescription)
            }
            await MainActor.run { [weak self] in
                guard let self,
                      generation == self.timelinePlayerBuildGeneration,
                      !self.isExporting,
                      self.usesCustomTimelinePreview else { return }
                if let composition = box.composition {
                    self.applyTimelinePlayerComposition(composition, signature: signature)
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
        signature: TimelinePlayerSignature?
    ) {
        let item = AVPlayerItem(asset: composition)
        let wasPlaying = isPlaying
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            // Switch drivers: the overlay clock hands playback over to the player.
            stopOverlayPlaybackTimer()
            let player = AVPlayer(playerItem: item)
            self.player = player
            attachPlayerTimeObserver(to: player)
        }
        timelinePlayerBuiltSignature = signature
        backgroundImage = nil
        player?.seek(
            to: CMTime(seconds: previewTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if wasPlaying {
            player?.play()
        }
        refreshOverlayOnly()
    }

    private func tearDownTimelinePlayer(signature: TimelinePlayerSignature?) {
        timelinePlayerBuiltSignature = signature
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
        case .hevcAlpha, .hevc, .h264:
            estimatedBitRateKbps = Double(max(0, bitRateKbps))
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
                player.currentItem?.cancelPendingSeeks()
            }
            player.seek(
                to: CMTime(seconds: clamped, preferredTimescale: 600),
                toleranceBefore: isScrubbing ? scrubSeekTolerance : .zero,
                toleranceAfter: isScrubbing ? scrubSeekTolerance : .zero
            )
            if !isScrubbing {
                refreshOverlayOnly(coalesceIfBusy: coalesceOverlayRefresh)
            }
            return
        }
        if let player {
            if isScrubbing {
                refreshOverlayOnly(coalesceIfBusy: coalesceOverlayRefresh, displayIntermediateResults: true)
            }
            let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
            if isScrubbing {
                player.currentItem?.cancelPendingSeeks()
            }
            player.seek(
                to: targetTime,
                toleranceBefore: isScrubbing ? scrubSeekTolerance : .zero,
                toleranceAfter: isScrubbing ? scrubSeekTolerance : .zero
            )
            if !isScrubbing {
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
        let asset = MediaAsset(
            id: url.path,
            kind: .video,
            url: url,
            displayName: url.lastPathComponent,
            duration: metadata.duration,
            width: Int(metadata.size.width.rounded()),
            height: Int(metadata.size.height.rounded()),
            framesPerSecond: metadata.framesPerSecond
        )
        if let index = videoAssets.firstIndex(where: { $0.id == asset.id }) {
            videoAssets[index] = asset
        } else {
            videoAssets.append(asset)
        }
        drainPendingVideoTimelineImports()
    }

    /// Add or refresh an activity in the pool (called once its telemetry has parsed). Deduplicated by path.
    func upsertActivityAsset(url: URL, series: TelemetrySeries) {
        let asset = MediaAsset(
            id: url.path,
            kind: .activity,
            url: url,
            displayName: url.lastPathComponent,
            duration: series.duration
        )
        activitySeriesByAssetID[asset.id] = series
        if let index = activityAssets.firstIndex(where: { $0.id == asset.id }) {
            activityAssets[index] = asset
        } else {
            activityAssets.append(asset)
        }
        drainPendingActivityTimelineImports()
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
        drainPendingVideoTimelineImports()
    }

    private func discardPendingActivityTimelineImport(id: String) {
        pendingActivityTimelineImportIDs.removeAll { $0 == id }
        drainPendingActivityTimelineImports()
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
            clearUndoStackForTimelineReplacement()
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
            clearUndoStackForTimelineReplacement()
        }
        timelineUsesSingleSourceMigration = true
        setFIT(asset.url)
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
        videoWaveformLoadTasks[id]?.cancel()
        videoWaveformLoadTasks[id] = nil
        videoWaveformPeaksByAssetID[id] = nil
        videoAssets.removeAll { $0.id == id }
        removeTimelineAsset(id: id)
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
        activityAssets.removeAll { $0.id == id }
        activitySeriesByAssetID.removeValue(forKey: id)
        removeTimelineAsset(id: id)
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
    func addActivityAssetToTimeline(id: String, targetTrackID: String?, timelineStart: TimeInterval?) {
        guard !isExporting,
              let asset = activityAssets.first(where: { $0.id == id }),
              activitySeriesByAssetID[id] != nil,
              asset.duration > 0 else { return }

        let previousUndoState = timelineUndoSnapshotNow
        defer {
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

        var clip = TimelineClip(
            id: "overlay.clip.\(UUID().uuidString)",
            assetID: asset.id,
            timelineStart: max(0, timelineStart ?? timeline.duration),
            duration: asset.duration,
            sourceIn: 0,
            layout: layout.sanitized,
            distanceUnit: distanceUnit
        )

        let targetTrackIndex = targetTrackID.flatMap { targetTrackID in
            timeline.tracks.firstIndex {
                $0.id == targetTrackID && $0.kind == .overlay && !$0.isLocked
            }
        }
        if let trackIndex = targetTrackIndex
            ?? timeline.tracks.firstIndex(where: { $0.kind == .overlay && !$0.isLocked }) {
            // Land in the nearest gap that fits so the track stays overlap-free.
            clip.timelineStart = timeline.tracks[trackIndex].nonOverlappingStart(
                forClipID: clip.id,
                duration: clip.duration,
                proposedStart: clip.timelineStart
            )
            timeline.tracks[trackIndex].clips.append(clip)
            setStatus("status.timelineAddedActivity", asset.displayName)
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
        setStatus("status.timelineAddedActivity", asset.displayName)
    }

    /// Add a pooled video as the next clip on the base video track.
    func addVideoAssetToTimeline(id: String) {
        addVideoAssetToTimeline(id: id, targetTrackID: nil, timelineStart: nil)
    }

    /// Add a pooled video to a chosen video lane at a relative timeline position. Button-based
    /// insertion keeps appending to the end of the base lane; a drop uses the nearest free gap.
    func addVideoAssetToTimeline(id: String, targetTrackID: String?, timelineStart: TimeInterval?) {
        guard !isExporting,
              let asset = videoAssets.first(where: { $0.id == id }),
              asset.duration > 0 else { return }

        let previousUndoState = timelineUndoSnapshotNow
        defer {
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

        var clip = TimelineClip(
            id: "video.clip.\(UUID().uuidString)",
            assetID: asset.id,
            timelineStart: max(0, timelineStart ?? timeline.duration),
            duration: asset.duration,
            sourceIn: 0
        )

        let targetTrackIndex = targetTrackID.flatMap { targetTrackID in
            timeline.tracks.firstIndex {
                $0.id == targetTrackID && $0.kind == .video && !$0.isLocked
            }
        }
        if let trackIndex = targetTrackIndex
            ?? timeline.tracks.firstIndex(where: { $0.kind == .video && !$0.isLocked }) {
            clip.timelineStart = timeline.tracks[trackIndex].nonOverlappingStart(
                forClipID: clip.id,
                duration: clip.duration,
                proposedStart: clip.timelineStart
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
        setStatus("status.timelineAddedActivity", asset.displayName)
    }

    func removeEmptyTimelineTrack(id: String) {
        guard !isExporting,
              let trackIndex = timeline.tracks.firstIndex(where: { $0.id == id }),
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

    /// Add an empty video lane above the existing video stack and below overlay lanes.
    @discardableResult
    func addVideoTimelineTrack() -> String? {
        guard !isExporting else { return nil }

        let previousUndoState = timelineUndoSnapshotNow
        beginTimelineClipEditingIfNeeded()
        let track = TimelineTrack(
            id: "video.track.\(UUID().uuidString)",
            kind: .video,
            name: nextTimelineTrackName(kind: .video)
        )
        let insertionIndex = timeline.tracks.firstIndex(where: { $0.kind == .overlay })
            ?? timeline.tracks.endIndex
        timeline.tracks.insert(track, at: insertionIndex)
        registerTimelineUndoIfChanged(
            previous: previousUndoState,
            actionKey: "undo.timeline.addTrack",
            coalescing: false
        )
        return track.id
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
            return
        }
        let video = videoURL.flatMap { url in videoAssets.first { $0.url == url } }
        let activity = fitURL.flatMap { url in activityAssets.first { $0.url == url } }
        timeline = TimelineProject.migratingSingleSource(
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            framesPerSecond: outputFPS,
            distanceUnit: distanceUnit,
            videoAsset: video,
            activityAsset: activity,
            sync: timeSync,
            layout: layout
        )
        if isPlaying, usesCustomTimelinePreview {
            pausePlayback()
        }
    }

    /// Match-point inputs describe source time against source time. In the initial single-source
    /// project they rebuild the relative placement from scratch. After manual timeline editing,
    /// they re-align only the active video/activity pair while preserving the video's timeline
    /// position whenever both clips can stay at or after timeline zero.
    private func updateTimelineForSyncChange() {
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
        guard let selectedTimelineClipID else { return }
        if timelineClip(id: selectedTimelineClipID) == nil {
            self.selectedTimelineClipID = nil
        }
    }

    private func repairSelectedTimelineTrackIfNeeded() {
        let validTrackIDs = Set(timeline.tracks.map(\.id))
        let repairedTrackIDs = selectedTimelineTrackIDs.intersection(validTrackIDs)
        if repairedTrackIDs != selectedTimelineTrackIDs {
            selectedTimelineTrackIDs = repairedTrackIDs
        }
    }

    private func removeTimelineAsset(id: String) {
        guard !timelineUsesSingleSourceMigration else { return }
        clearUndoStackForTimelineReplacement()
        timeline.assets.removeAll { $0.id == id }
        timeline.tracks = timeline.tracks.compactMap { track in
            var updated = track
            updated.clips.removeAll { $0.assetID == id }
            return updated.clips.isEmpty ? nil : updated
        }
        repairSelectedTimelineClipIfNeeded()
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
        !isExporting && player != nil && currentVideoSourceTimeForSync != nil
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
        guard !isExporting else { return }
        let sanitizedStart = max(0, timelineStart)
        let previousUndoState = timelineUndoSnapshotNow

        for trackIndex in timeline.tracks.indices {
            guard !timeline.tracks[trackIndex].isLocked else { continue }
            guard let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) else {
                continue
            }
            let clip = timeline.tracks[trackIndex].clips[clipIndex]
            let constrainedStart = timeline.tracks[trackIndex].nonOverlappingStart(
                forClipID: id,
                duration: clip.duration,
                proposedStart: sanitizedStart
            )
            guard abs(clip.timelineStart - constrainedStart) > 1e-6 else { return }
            beginTimelineClipEditingIfNeeded()
            timeline.tracks[trackIndex].clips[clipIndex].timelineStart = constrainedStart
            registerTimelineUndoIfChanged(
                previous: previousUndoState,
                actionKey: "undo.timeline.moveClip",
                coalescing: true
            )
            refreshOverlayOrPreview()
            return
        }
    }

    /// Whether the blade (⌘B) has anything to cut at the playhead.
    var canSplitTimelineClipsAtPlayhead: Bool {
        guard !isExporting else { return false }
        let trackIDs = selectedTimelineTrackIDs.isEmpty ? nil : selectedTimelineTrackIDs
        return !currentTimelineProject.splittableClipIDs(
            atTimelineTime: previewTime,
            trackIDs: trackIDs
        ).isEmpty
    }

    /// Split the selected tracks under the playhead, or every unlocked track when none is selected.
    func splitTimelineClipsAtPlayhead() {
        guard !isExporting else { return }
        let previousUndoState = timelineUndoSnapshotNow
        var updated = timeline
        let trackIDs = selectedTimelineTrackIDs.isEmpty ? nil : selectedTimelineTrackIDs
        guard updated.splitClips(
            atTimelineTime: previewTime,
            trackIDs: trackIDs
        ) > 0 else { return }
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
            selectedTimelineClipID = nil
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
        guard let selectedTimelineClipID else { return }
        deleteTimelineClip(id: selectedTimelineClipID, ripple: ripple)
    }

    func selectTimelineClip(id: String) {
        guard timelineClip(id: id) != nil else {
            selectedTimelineClipID = nil
            return
        }
        selectedTimelineClipID = id
        selectedElementID = nil
    }

    func selectTimelineTrack(id: String) {
        guard !isExporting, timeline.tracks.contains(where: { $0.id == id }) else { return }
        if selectedTimelineTrackIDs.contains(id) {
            selectedTimelineTrackIDs.remove(id)
        } else {
            selectedTimelineTrackIDs.insert(id)
        }
    }

    func selectElement(id: String) {
        selectedTimelineClipID = nil
        if selectedElementID != id {
            selectedElementID = id
        }
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
            clip.timelineStart = track.nonOverlappingStart(
                forClipID: clip.id,
                duration: minimumDuration,
                proposedStart: max(0, timelineStart ?? clip.timelineStart)
            )
            if let gapLimit = track.maximumNonOverlappingDuration(
                forClipID: clip.id,
                startingAt: clip.timelineStart
            ) {
                clip.duration = min(clip.duration, max(minimumDuration, gapLimit))
            }
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
                let parsedSeries = try TelemetryFileParser().parse(url: url)
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
                    self.upsertActivityAsset(url: url, series: parsedSeries)
                    if self.videoURL == nil {
                        self.resetExportTrimRangeToFullDuration()
                        self.applySuggestedOutputURLIfNeeded(for: url)
                    }
                    self.setStatus("status.loadedFit", url.lastPathComponent)
                    self.addDebugLog(.input, "Loaded activity file: \(url.lastPathComponent), samples=\(parsedSeries.samples.count), duration=\(Self.formatDebugSeconds(parsedSeries.duration))")
                    self.refreshOverlayOrPreview()
                    self.loadOpenWeatherIfPossible(
                        for: parsedSeries,
                        sourceName: url.lastPathComponent,
                        generation: loadGeneration
                    )
                    self.fitLoadTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.fitLoadGeneration == loadGeneration else { return }
                    self.discardPendingActivityTimelineImport(id: url.path)
                    self.fitLoadTask = nil
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
                    if weatherSampleCount > 0 {
                        self.setStatus("status.loadedFitWithWeather", sourceName)
                    } else {
                        self.setStatus("status.weatherUnavailable", sourceName)
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
        guard !isExporting else { return }
        performLayoutChange("undo.addElement") {
            let existingCount = layout.elements.filter { $0.kind == kind }.count
            var element = OverlayElement.defaultElement(kind: kind, id: "\(kind.rawValue)-\(UUID().uuidString)")
            let offset = min(0.20, Double(existingCount) * 0.035)
            element.frame.x = PreviewLayoutLimits.clampPosition(element.frame.x + offset)
            element.frame.y = PreviewLayoutLimits.clampPosition(element.frame.y + offset)
            layout.elements.append(element)
            selectedElementID = element.id
            selectedTimelineClipID = nil
        }
        refreshOverlayOrPreview()
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
            selectedTimelineClipID = nil
        }
        refreshOverlayOrPreview()
    }

    func deleteSelectedElement() {
        guard !isExporting else { return }
        guard let selectedElementID else { return }
        performLayoutChange("undo.deleteElement") {
            layout.removeElement(id: selectedElementID)
            self.selectedElementID = layout.elements.first?.id
        }
        refreshOverlayOrPreview()
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
        performLayoutChange("undo.editElement", coalescing: true) {
            layout.updateElement(id: id, update)
        }
        if shouldRefreshPreview, !layout.elements.contains(where: { $0.id == selectedElementID }) {
            selectedElementID = layout.elements.first?.id
        }
        if shouldRefreshPreview {
            refreshOverlayOrPreview()
        }
    }

    func nudgeElement(_ id: String, deltaX: Double, deltaY: Double) {
        guard !isExporting else { return }
        if selectedElementID != id {
            selectedElementID = id
        }
        selectedTimelineClipID = nil
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

    private struct TimelineUndoSnapshot {
        var timeline: TimelineProject
        var usesSingleSourceMigration: Bool
        var selectedClipID: String?
        var selectedTrackIDs: Set<String>
    }

    private var timelineUndoSnapshotNow: TimelineUndoSnapshot {
        TimelineUndoSnapshot(
            timeline: timeline,
            usesSingleSourceMigration: timelineUsesSingleSourceMigration,
            selectedClipID: selectedTimelineClipID,
            selectedTrackIDs: selectedTimelineTrackIDs
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
            registerTimelineUndo(previous: timelineUndoSnapshotNow, actionKey: actionKey, undoManager: undoManager)
        }
        lastCoalescedTimelineUndo = nil
        pausePlayback()
        timeline = previous.timeline
        timelineUsesSingleSourceMigration = previous.usesSingleSourceMigration
        if let selectedClipID = previous.selectedClipID, timelineClip(id: selectedClipID) != nil {
            selectedTimelineClipID = selectedClipID
        } else {
            repairSelectedTimelineClipIfNeeded()
        }
        selectedTimelineTrackIDs = previous.selectedTrackIDs
        repairSelectedTimelineTrackIfNeeded()
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
        let weatherClips = project.enabledClips(kind: .overlay).filter { clip in
            guard clip.timelineEnd > timelineStart,
                  clip.timelineStart < timelineEnd else { return false }
            return (clip.layout ?? .default).visibleElements.contains { $0.kind == .weather }
        }
        guard !weatherClips.isEmpty else { return false }
        if isWeatherLoading { return true }

        return weatherClips.contains { clip in
            guard let series = telemetrySeriesByAssetID[clip.assetID] else { return true }
            return !series.samples.contains { sample in
                sample.weatherTemperatureCelsius != nil
                    || sample.weatherHumidityPercent != nil
                    || sample.weatherSummary != nil
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
        guard confirmOverwriteIfNeeded(outputURL) else { return }

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
        addDebugLog(.export, "Export started: \(outputURL.lastPathComponent), \(exportSettings.width)x\(exportSettings.height), start=\(Self.formatDebugSeconds(exportSettings.startTime)), duration=\(Self.formatDebugSeconds(exportSettings.duration))")
        let cancellationToken = ExportCancellationToken()
        exportCancellationToken = cancellationToken

        let currentExportMode = exportMode
        let currentCodec = codec
        let currentActivityTrim = self.currentActivityTrim
        let progressHandler: (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in
                self?.updateExportProgress(total > 0 ? Double(completed) / Double(total) : 0)
            }
        }

        exportTask = Task.detached {
            do {
                switch currentExportMode {
                case .overlay:
                    try TimelineVideoWriter(
                        outputURL: outputURL,
                        project: timelineProject,
                        telemetrySeriesByAssetID: timelineTelemetrySeries,
                        config: TimelineVideoWriterConfig(
                            width: exportSettings.width,
                            height: exportSettings.height,
                            framesPerSecond: exportSettings.framesPerSecond,
                            timelineStart: exportSettings.startTime,
                            duration: exportSettings.duration,
                            averageBitRate: exportSettings.averageBitRate,
                            codec: currentCodec,
                            activityTrim: currentActivityTrim,
                            progressHandler: progressHandler,
                            cancellationHandler: { cancellationToken.isCancelled }
                        )
                    ).write()
                case .video:
                    try TimelineVideoWriter(
                        outputURL: outputURL,
                        project: timelineProject,
                        telemetrySeriesByAssetID: timelineTelemetrySeries,
                        config: TimelineVideoWriterConfig(
                            width: exportSettings.width,
                            height: exportSettings.height,
                            framesPerSecond: exportSettings.framesPerSecond,
                            timelineStart: exportSettings.startTime,
                            duration: exportSettings.duration,
                            averageBitRate: exportSettings.averageBitRate,
                            codec: currentCodec,
                            activityTrim: currentActivityTrim,
                            progressHandler: progressHandler,
                            cancellationHandler: { cancellationToken.isCancelled },
                            diagnosticsHandler: { message in
                                studioDebugLogger.info("[export] \(message, privacy: .public)")
                            }
                        )
                    ).write()
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportProgress = 1
                    self.exportETASeconds = nil
                    self.lastExportedURL = outputURL
                    self.lastExportElapsedSeconds = Date().timeIntervalSince(exportStartedAt)
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.setStatus("status.wroteFile", outputURL.path)
                    self.addDebugLog(.export, "Export finished: \(outputURL.lastPathComponent)")
                    self.notifyExportCompleted(outputURL)
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

    private func notifyExportCompleted(_ outputURL: URL) {
        let title = localized("notification.exportCompleted.title")
        let body = localized("notification.exportCompleted.body", outputURL.lastPathComponent)
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

    private func confirmOverwriteIfNeeded(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        let alert = NSAlert()
        alert.messageText = localized("alert.overwriteOutput.title")
        alert.informativeText = localized("alert.overwriteOutput.message", url.lastPathComponent)
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("alert.overwriteOutput.confirm"))
        alert.addButton(withTitle: localized("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func refreshLocalizedStatus() {
        status = AppLocalizer.string(statusMessage.key, language: resolvedLanguage, arguments: statusMessage.arguments)
    }

    private func setStatus(_ key: String, _ arguments: CVarArg...) {
        statusMessage = (key, arguments)
        status = AppLocalizer.string(key, language: resolvedLanguage, arguments: arguments)
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
            gridColumns: gridColumns,
            gridRows: gridRows,
            snapGaugeToGrid: snapGaugeToGrid,
            distanceUnit: distanceUnit
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

    static func sanitizedGridDivision(_ value: Int) -> Int {
        min(64, max(2, value))
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
