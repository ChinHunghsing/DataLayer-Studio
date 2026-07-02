import AppKit
import AVFoundation
import Foundation
import OSLog
import OverlayCore
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

private let studioDebugLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "run.libo.datalayer-studio",
    category: "Debug"
)

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

@MainActor
final class StudioModel: ObservableObject {
    static let playerTimeObserverInterval: TimeInterval = 1.0 / 12.0
    static let playbackOverlayRefreshInterval: TimeInterval = 0.20
    static let scrubInteractionHoldInterval: TimeInterval = 0.16
    static let previewResizeRefreshDelay: TimeInterval = 0.16
    static let gaugeDragMaximumPreviewRenderDimension: CGFloat = 1_600

    @Published var videoURL: URL?
    @Published var fitURL: URL?
    @Published var outputURL: URL?
    @Published var metadata: VideoMetadata?
    @Published var series: TelemetrySeries?

    @Published var outputWidth = 1920
    @Published var outputHeight = 1080
    @Published var outputFPS = 30.0
    @Published var sourceDuration: TimeInterval = 0
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
        didSet { persistStudioPreferences() }
    }

    @Published var syncMode: SyncMode = .syncPoint
    @Published var offsetSeconds = 0.0
    @Published var fitStartSeconds = 0.0
    @Published var syncVideoSeconds = 0.0
    @Published var syncFITSeconds = 0.0

    @Published var previewTime: TimeInterval = 0
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var backgroundImage: NSImage?
    @Published var overlayImage: NSImage?
    @Published var layout: OverlayLayout
    @Published var selectedElementID: String?
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
    @Published var previewWarning: String?
    @Published var isExporting = false
    @Published var exportProgress = 0.0
    @Published var openWeatherAPIKey = OpenWeatherKeyStore.load()
    @Published var weatherRefreshMessage: String?
    @Published var debugLogEntries: [DebugLogEntry] = []

    private var resolvedLanguage = AppLocalizer.resolvedLanguage(for: AppLocalizer.storedSelection())
    private let videoFrameService = VideoFrameService()
    private let previewRenderer = OverlayPreviewRenderer()
    private let openWeatherService = OpenWeatherService()
    private let layoutPresetStore: LayoutPresetStore
    private let preferenceStore: StudioPreferenceStore
    private var layoutPresetCloudObserver: NSObjectProtocol?
    private var playerTimeObserver: PlayerTimeObserver?
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
    private var pendingOverlayRefreshAfterCurrentRender = false
    private var pendingOverlayRefreshDisplaysIntermediateResult = false
    private var isScrubbingPreview = false
    private var isGaugeDragActive = false
    private var exportTask: Task<Void, Never>?
    private var exportCancellationToken: ExportCancellationToken?
    private var outputURLWasAutoGenerated = false

    init(
        layoutPresetStore: LayoutPresetStore = LayoutPresetStore(),
        preferenceStore: StudioPreferenceStore = StudioPreferenceStore()
    ) {
        self.layoutPresetStore = layoutPresetStore
        self.preferenceStore = preferenceStore
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
        observeLayoutPresetCloudChanges()
    }

    deinit {
        if let layoutPresetCloudObserver {
            NotificationCenter.default.removeObserver(layoutPresetCloudObserver)
        }
        playerTimeObserver?.remove()
        videoLoadTask?.cancel()
        fitLoadTask?.cancel()
        weatherLoadTask?.cancel()
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

    var canExport: Bool {
        exportReadinessMessage == nil
    }

    var needsOutputSelectionBeforeExport: Bool {
        outputURL == nil || outputURLWasAutoGenerated
    }

    func setResolvedLanguage(_ language: AppResolvedLanguage) {
        guard resolvedLanguage != language else { return }
        resolvedLanguage = language
        refreshLocalizedStatus()
    }

    var exportReadinessMessage: String? {
        if series == nil {
            return localized("status.chooseFitFile")
        }
        if exportMode == .video, videoURL == nil {
            return localized("status.chooseVideoForCompositedExport")
        }
        if codec.exportMode != exportMode {
            return localized("status.codecExportModeMismatch")
        }
        if outputWidth < 2 || outputWidth > 16_384 {
            return localized("status.outputWidthRange")
        }
        if outputWidth % 2 != 0 {
            return localized("status.outputWidthEven")
        }
        if outputHeight < 2 || outputHeight > 16_384 {
            return localized("status.outputHeightRange")
        }
        if outputHeight % 2 != 0 {
            return localized("status.outputHeightEven")
        }
        if !outputFPS.isFinite || outputFPS < 1 || outputFPS > 240 {
            return localized("status.frameRateRange")
        }
        if exportDuration == nil {
            return localized("status.sourceDurationRange")
        }
        if bitRateKbps < 1 || bitRateKbps > 1_000_000 {
            return localized("status.bitrateRange")
        }
        if bitRateKbps > Int.max / 1000 {
            return localized("status.bitrateTooLarge")
        }
        return nil
    }

    var availableCodecs: [OverlayVideoCodec] {
        OverlayVideoCodec.allCases.filter { $0.exportMode == exportMode }
    }

    var selectedElement: OverlayElement? {
        guard let selectedElementID else { return layout.elements.first }
        return layout.elements.first { $0.id == selectedElementID } ?? layout.elements.first
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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setVideo(url)
    }

    func chooseFIT() {
        guard !isExporting else { return }
        let panel = NSOpenPanel()
        panel.title = localized("panel.chooseFitActivity")
        panel.message = localized("panel.chooseFitActivity.message")
        panel.prompt = localized("panel.open")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["fit", "gpx"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
            status = localized("status.exportCancelled")
        }
        videoFrameService.clearCache()
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
            status = localized("status.weatherKeyRequired")
            weatherRefreshMessage = status
            addDebugLog(.weather, "Refresh skipped: missing OpenWeather key")
            return
        }
        guard let currentSeries = series,
              let fitURL else {
            status = localized("status.weatherFitRequired")
            weatherRefreshMessage = status
            addDebugLog(.weather, "Refresh skipped: missing FIT series")
            return
        }
        status = localized("status.weatherRefreshing", fitURL.lastPathComponent)
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
            status = localized("status.presetNameRequired")
            return false
        }

        let now = Date()
        if let index = layoutPresets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            layoutPresets[index].name = name
            layoutPresets[index].layout = layout.sanitized
            layoutPresets[index].updatedAt = now
            persistLayoutPresets()
            status = localized("status.updatedPreset", name)
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
        status = localized("status.savedPreset", name)
        return true
    }

    func applyLayoutPreset(id: String) {
        guard !isExporting else { return }
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        layout = preset.layout.sanitized
        selectedElementID = Self.firstSelectableElementID(in: layout)
        status = localized("status.appliedPreset", preset.name)
        refreshOverlayOrPreview()
    }

    func setDefaultLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        defaultLayoutPresetID = id
        persistLayoutPresets()
        status = localized("status.defaultPreset", preset.name)
    }

    func deleteLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        layoutPresets.removeAll { $0.id == id }
        if defaultLayoutPresetID == id {
            defaultLayoutPresetID = nil
        }
        persistLayoutPresets()
        status = localized("status.deletedPreset", preset.name)
    }

    func exportLayoutPresets() {
        guard !layoutPresets.isEmpty else {
            status = localized("status.noPresetsToExport")
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
            status = localized("status.exportedPresets", layoutPresets.count)
        } catch {
            status = localized("status.presetExportError", error.localizedDescription)
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
            status = importedCount == 0
                ? localized("status.noPresetsImported")
                : localized("status.importedPresets", importedCount)
        } catch {
            status = localized("status.presetImportError", error.localizedDescription)
        }
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
        status = localized("status.loadingVideo", url.lastPathComponent)

        videoLoadTask = Task.detached {
            do {
                let loaded = try await VideoMetadata.loadAsync(from: url)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.videoLoadGeneration == loadGeneration else { return }
                    self.videoURL = url
                    self.metadata = loaded
                    self.setOutputWidth(Int(loaded.size.width.rounded()))
                    self.setOutputHeight(Int(loaded.size.height.rounded()))
                    self.setOutputFPS(loaded.framesPerSecond)
                    if let sourceBitRateKbps = Self.sourceVideoBitRateKbps(from: loaded) {
                        self.setBitRateKbps(sourceBitRateKbps)
                    }
                    self.sourceDuration = Self.sanitizedSourceDuration(loaded.duration)
                    self.applySuggestedOutputURLIfNeeded(for: url, replacingManualSelection: true)
                    self.previewTime = 0
                    self.configurePlayer(url: url)
                    self.status = self.localized("status.loadedVideo", url.lastPathComponent)
                    self.refreshPreview()
                    self.videoLoadTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.videoLoadGeneration == loadGeneration else { return }
                    self.videoLoadTask = nil
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.videoLoadGeneration == loadGeneration else { return }
                    self.status = self.localized("status.videoError", message)
                    self.videoLoadTask = nil
                }
            }
        }
    }

    func configurePlayer(url: URL) {
        playerTimeObserver?.remove()
        playerTimeObserver = nil

        let player = AVPlayer(url: url)
        self.player = player
        let observerToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: Self.playerTimeObserverInterval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isScrubbingPreview else { return }
                let seconds = CMTimeGetSeconds(time)
                guard seconds.isFinite else { return }
                self.previewTime = min(max(0, seconds), max(0, self.sourceDuration))
                self.refreshOverlayOnly(
                    minimumInterval: Self.playbackOverlayRefreshInterval,
                    coalesceIfBusy: true
                )
                if self.sourceDuration > 0, self.previewTime >= self.sourceDuration {
                    self.pausePlayback()
                }
            }
        }
        playerTimeObserver = PlayerTimeObserver(player: player, token: observerToken)
    }

    func togglePlayback() {
        isPlaying ? pausePlayback() : startPlayback()
    }

    func startPlayback() {
        guard !isExporting else { return }
        guard let player else { return }
        isPlaying = true
        player.play()
    }

    func pausePlayback() {
        isPlaying = false
        player?.pause()
    }

    func stopPlayback() {
        pausePlayback()
        playerTimeObserver?.remove()
        playerTimeObserver = nil
        self.player = nil
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
        if sourceDuration > 0 {
            return sourceDuration
        }
        return series?.duration ?? 0
    }

    private func seekPreview(to time: TimeInterval, coalesceOverlayRefresh: Bool, isScrubbing: Bool = false) {
        guard !isExporting else { return }
        let clamped = min(max(0, time), max(previewDuration, 0))
        if isScrubbing, abs(previewTime - clamped) < 0.000_5 {
            return
        }
        previewTime = clamped
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
        isGaugeDragActive = true
    }

    func endGaugeDragInteraction() {
        guard isGaugeDragActive else { return }
        isGaugeDragActive = false
        guard !isExporting, series != nil else { return }
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    func markSportStart() {
        guard !isExporting else { return }
        syncMode = .syncPoint
        syncVideoSeconds = previewTime
        syncFITSeconds = 0
        status = localized("status.sportStartSet", formatTime(previewTime))
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
        overlayImage = nil
        previewWarning = nil
        status = localized("status.loadingFit", url.lastPathComponent)
        addDebugLog(.input, "Loading activity file: \(url.lastPathComponent)")

        fitLoadTask = Task.detached {
            do {
                let parsedSeries = try TelemetryFileParser().parse(url: url)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.fitLoadGeneration == loadGeneration else { return }
                    self.fitURL = url
                    self.series = parsedSeries
                    if self.videoURL == nil {
                        self.applySuggestedOutputURLIfNeeded(for: url)
                    }
                    self.status = self.localized("status.loadedFit", url.lastPathComponent)
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
                    self.status = self.localized("status.fitError", message)
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
                    let weatherSampleCount = enrichedSeries.samples.filter { $0.weatherTemperatureCelsius != nil || $0.weatherHumidityPercent != nil || $0.weatherSummary != nil }.count
                    self.status = weatherSampleCount > 0
                        ? self.localized("status.loadedFitWithWeather", sourceName)
                        : self.localized("status.weatherUnavailable", sourceName)
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
                    self.status = self.localized("status.weatherError", sourceName, details)
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
        let videoPreviewFailedTitle = localized("status.previewVideoFailed")
        let overlayPreviewFailedTitle = localized("status.previewOverlayFailed")

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached(priority: .userInitiated) { [videoFrameService, previewRenderer] in
            guard !Task.isCancelled else { return }
            let background: NSImage?
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
            let overlay: NSImage?
            if let currentSeries {
                do {
                    overlay = try Self.renderOverlayImage(
                        previewRenderer: previewRenderer,
                        series: currentSeries,
                        size: outputSize,
                        videoTime: time,
                        timeSync: currentSync,
                        layout: currentLayout,
                        distanceUnit: currentDistanceUnit
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

    func refreshOverlayOnly(
        previewSize: CGSize? = nil,
        minimumInterval: TimeInterval = 0,
        coalesceIfBusy: Bool = false,
        displayIntermediateResults: Bool = false
    ) {
        guard !isExporting else { return }
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
        let overlayPreviewFailedTitle = localized("status.previewOverlayFailed")

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached(priority: .userInitiated) { [previewRenderer] in
            guard !Task.isCancelled else { return }
            let overlay: NSImage?
            let warningMessage: String?
            do {
                overlay = try Self.renderOverlayImage(
                    previewRenderer: previewRenderer,
                    series: currentSeries,
                    size: renderSize,
                    videoTime: time,
                    timeSync: currentSync,
                    layout: currentLayout,
                    distanceUnit: currentDistanceUnit
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
        distanceUnit: OverlayDistanceUnit
    ) throws -> NSImage {
        try NSImage(
            cgImage: previewRenderer.renderOverlayImage(
                series: series,
                size: size,
                videoTime: videoTime,
                timeSync: timeSync,
                layout: layout,
                distanceUnit: distanceUnit
            ),
            size: NSSize(width: size.width, height: size.height)
        )
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
        let existingCount = layout.elements.filter { $0.kind == kind }.count
        var element = OverlayElement.defaultElement(kind: kind, id: "\(kind.rawValue)-\(UUID().uuidString)")
        let offset = min(0.20, Double(existingCount) * 0.035)
        element.frame.x = PreviewLayoutLimits.clampPosition(element.frame.x + offset)
        element.frame.y = PreviewLayoutLimits.clampPosition(element.frame.y + offset)
        layout.elements.append(element)
        selectedElementID = element.id
        refreshOverlayOrPreview()
    }

    func duplicateSelectedElement() {
        guard !isExporting else { return }
        guard var element = selectedElement else { return }
        element.id = "\(element.kind.rawValue)-\(UUID().uuidString)"
        element.frame.x = PreviewLayoutLimits.clampPosition(element.frame.x + 0.035)
        element.frame.y = PreviewLayoutLimits.clampPosition(element.frame.y + 0.035)
        layout.elements.append(element)
        selectedElementID = element.id
        refreshOverlayOrPreview()
    }

    func deleteSelectedElement() {
        guard !isExporting else { return }
        guard let selectedElementID else { return }
        layout.removeElement(id: selectedElementID)
        self.selectedElementID = layout.elements.first?.id
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
        layout.moveElement(id: selectedElementID, by: offset)
        self.selectedElementID = selectedElementID
        refreshOverlayOrPreview()
    }

    func updateElement(_ id: String, refreshPreview shouldRefreshPreview: Bool = true, _ update: (inout OverlayElement) -> Void) {
        guard !isExporting else { return }
        layout.updateElement(id: id, update)
        if shouldRefreshPreview, !layout.elements.contains(where: { $0.id == selectedElementID }) {
            selectedElementID = layout.elements.first?.id
        }
        if shouldRefreshPreview {
            refreshOverlayOrPreview()
        }
    }

    func updateComponent(_ id: OverlayComponentID, _ update: (inout OverlayComponentFrame) -> Void) {
        guard !isExporting else { return }
        layout.updateFirstElement(kind: id) { element in
            update(&element.frame)
        }
        refreshOverlayOrPreview()
    }

    func export() {
        guard !isExporting else { return }
        if let exportReadinessMessage {
            status = exportReadinessMessage
            return
        }
        guard let exportSettings = validatedExportSettings else {
            status = localized("status.checkOutputSettings")
            return
        }
        if needsOutputSelectionBeforeExport {
            chooseOutput()
        }
        guard !needsOutputSelectionBeforeExport, let outputURL else {
            status = localized("status.chooseOutputFile")
            return
        }
        guard confirmOverwriteIfNeeded(outputURL) else { return }
        guard let series else {
            status = localized("status.chooseFitBeforeExport")
            return
        }

        pausePlayback()
        cancelPreviewRenderTasks()
        isExporting = true
        exportProgress = 0
        status = localized("status.exporting")
        addDebugLog(.export, "Export started: \(outputURL.lastPathComponent), \(exportSettings.width)x\(exportSettings.height), \(Self.formatDebugSeconds(exportSettings.duration))")
        let cancellationToken = ExportCancellationToken()
        exportCancellationToken = cancellationToken

        let currentExportMode = exportMode
        let currentCodec = codec
        let currentTimeSync = timeSync
        let currentLayout = layout
        let currentDistanceUnit = distanceUnit
        let sourceVideoURL = videoURL
        let progressHandler: (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in
                self?.exportProgress = total > 0 ? Double(completed) / Double(total) : 0
            }
        }

        exportTask = Task.detached {
            do {
                switch currentExportMode {
                case .overlay:
                    try TransparentVideoWriter(
                        outputURL: outputURL,
                        series: series,
                        config: TransparentVideoWriterConfig(
                            width: exportSettings.width,
                            height: exportSettings.height,
                            framesPerSecond: exportSettings.framesPerSecond,
                            duration: exportSettings.duration,
                            averageBitRate: exportSettings.averageBitRate,
                            timeSync: currentTimeSync,
                            codec: currentCodec,
                            overlayLayout: currentLayout,
                            distanceUnit: currentDistanceUnit,
                            progressHandler: progressHandler,
                            cancellationHandler: { cancellationToken.isCancelled }
                        )
                    ).write()
                case .video:
                    guard let sourceVideoURL else {
                        throw OverlayVideoError.invalidConfiguration("Choose a source video before exporting composited video.")
                    }
                    try CompositedVideoWriter(
                        outputURL: outputURL,
                        sourceVideoURL: sourceVideoURL,
                        series: series,
                        config: CompositedVideoWriterConfig(
                            width: exportSettings.width,
                            height: exportSettings.height,
                            framesPerSecond: exportSettings.framesPerSecond,
                            duration: exportSettings.duration,
                            averageBitRate: exportSettings.averageBitRate,
                            timeSync: currentTimeSync,
                            codec: currentCodec,
                            overlayLayout: currentLayout,
                            distanceUnit: currentDistanceUnit,
                            progressHandler: progressHandler,
                            cancellationHandler: { cancellationToken.isCancelled }
                        )
                    ).write()
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportProgress = 1
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.status = self.localized("status.wroteFile", outputURL.path)
                    self.addDebugLog(.export, "Export finished: \(outputURL.lastPathComponent)")
                    self.notifyExportCompleted(outputURL)
                    self.refreshOverlayOrPreview()
                }
            } catch OverlayVideoError.cancelled {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportProgress = 0
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.status = self.localized("status.exportCancelled")
                    self.addDebugLog(.export, "Export cancelled")
                    self.refreshOverlayOrPreview()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.status = self.localized("status.exportError", error.localizedDescription)
                    self.addDebugLog(.export, "Export failed: \(error.localizedDescription)")
                    self.refreshOverlayOrPreview()
                }
            }
        }
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
        status = localized("status.cancellingExport")
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
        guard !isExporting else { return }
        if series == nil && videoURL == nil {
            status = localized("status.chooseVideoAndFit")
        } else if series == nil {
            status = localized("status.chooseFitFile")
        } else if videoURL == nil, let fitURL {
            status = localized("status.loadedFit", fitURL.lastPathComponent)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        String(format: "%.3f", time)
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
        videoLoadTask = nil
        fitLoadTask = nil
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
            duration: duration,
            averageBitRate: bitRateKbps * 1000
        )
    }

    private var exportDuration: TimeInterval? {
        let duration = videoURL == nil ? series?.duration ?? 0 : sourceDuration
        guard duration.isFinite, duration >= 0.1, duration <= 86_400 else { return nil }
        return duration
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
