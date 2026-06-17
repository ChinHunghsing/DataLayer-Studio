import AppKit
import AVFoundation
import Foundation
import OverlayCore
import UniformTypeIdentifiers

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
    @Published var videoURL: URL?
    @Published var fitURL: URL?
    @Published var outputURL: URL?
    @Published var metadata: VideoMetadata?
    @Published var series: TelemetrySeries?

    @Published var outputWidth = 1920
    @Published var outputHeight = 1080
    @Published var outputFPS = 30.0
    @Published var outputDuration: TimeInterval = 0
    @Published var bitRateKbps = 12_000
    @Published var codec: OverlayVideoCodec = .hevcAlpha
    @Published var distanceUnit: OverlayDistanceUnit = .kilometers {
        didSet { persistStudioPreferences() }
    }

    @Published var syncMode: SyncMode = .offset
    @Published var offsetSeconds = 0.0
    @Published var fitStartSeconds = 0.0
    @Published var syncVideoSeconds = 0.0
    @Published var syncFITSeconds = 0.0

    @Published var previewTime: TimeInterval = 0
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var backgroundImage: NSImage?
    @Published var overlayImage: NSImage?
    @Published var dragBaseOverlayImage: NSImage?
    @Published var dragOverlayImage: NSImage?
    @Published var layout: OverlayLayout
    @Published var selectedElementID: String?
    @Published var layoutPresets: [LayoutPreset]
    @Published var defaultLayoutPresetID: String?

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

    @Published var status = "Choose a video and a FIT file."
    @Published var previewWarning: String?
    @Published var isExporting = false
    @Published var exportProgress = 0.0

    private let videoFrameService = VideoFrameService()
    private let previewRenderer = OverlayPreviewRenderer()
    private let layoutPresetStore: LayoutPresetStore
    private let preferenceStore: StudioPreferenceStore
    private var playerTimeObserver: PlayerTimeObserver?
    private var previewRenderGeneration = 0
    private var videoLoadGeneration = 0
    private var fitLoadGeneration = 0
    private var previewOverlayRenderSize: CGSize?
    private var lastOverlayRefresh = Date.distantPast
    private let previewResizeRefreshInterval: TimeInterval = 0.08
    private let maximumPreviewRenderDimension: CGFloat = 3_200
    private var draggedElementID: String?
    private var previewRenderTask: Task<Void, Never>?
    private var dragRenderTask: Task<Void, Never>?
    private var pendingPreviewSizeRefreshTask: Task<Void, Never>?
    private var videoLoadTask: Task<Void, Never>?
    private var fitLoadTask: Task<Void, Never>?
    private var pendingOverlayRefreshAfterCurrentRender = false
    private var exportTask: Task<Void, Never>?
    private var exportCancellationToken: ExportCancellationToken?

    init(
        layoutPresetStore: LayoutPresetStore = LayoutPresetStore(),
        preferenceStore: StudioPreferenceStore = StudioPreferenceStore()
    ) {
        self.layoutPresetStore = layoutPresetStore
        self.preferenceStore = preferenceStore
        let presetState = layoutPresetStore.load()
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
    }

    deinit {
        playerTimeObserver?.remove()
        videoLoadTask?.cancel()
        fitLoadTask?.cancel()
        previewRenderTask?.cancel()
        dragRenderTask?.cancel()
        pendingPreviewSizeRefreshTask?.cancel()
        exportCancellationToken?.cancel()
        exportTask?.cancel()
        videoFrameService.clearCache()
    }

    var canPreview: Bool {
        videoURL != nil && series != nil
    }

    var canExport: Bool {
        exportReadinessMessage == nil
    }

    var exportReadinessMessage: String? {
        if videoURL == nil {
            return "Choose a source video."
        }
        if series == nil {
            return "Choose a FIT file."
        }
        if outputWidth < 2 || outputWidth > 16_384 {
            return "Set output width between 2 and 16,384 px."
        }
        if outputWidth % 2 != 0 {
            return "Set output width to an even pixel value."
        }
        if outputHeight < 2 || outputHeight > 16_384 {
            return "Set output height between 2 and 16,384 px."
        }
        if outputHeight % 2 != 0 {
            return "Set output height to an even pixel value."
        }
        if !outputFPS.isFinite || outputFPS < 1 || outputFPS > 240 {
            return "Set frame rate between 1 and 240 fps."
        }
        if !outputDuration.isFinite || outputDuration < 0.1 || outputDuration > 86_400 {
            return "Set duration between 0.1 s and 24 h."
        }
        if bitRateKbps < 1 || bitRateKbps > 1_000_000 {
            return "Set bitrate between 1 and 1,000,000 kbps."
        }
        if bitRateKbps > Int.max / 1000 {
            return "Bitrate is too large for this Mac."
        }
        return nil
    }

    var selectedElement: OverlayElement? {
        guard let selectedElementID else { return layout.elements.first }
        return layout.elements.first { $0.id == selectedElementID } ?? layout.elements.first
    }

    var timeSync: TelemetryTimeSync {
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

    var sourceResolutionPresetTitle: String? {
        guard let sourceDimensions else { return nil }
        return "Source \(sourceDimensions.width)x\(sourceDimensions.height)"
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
        return "Source \(formatFrameRate(sourceFrameRate)) fps"
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
        panel.title = "Choose source video"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setVideo(url)
    }

    func chooseFIT() {
        guard !isExporting else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose FIT activity"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let fitType = UTType(filenameExtension: "fit") {
            panel.allowedContentTypes = [fitType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFIT(url)
    }

    func chooseOutput() {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.title = "Save transparent overlay video"
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = "overlay.mov"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
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
            status = "Export cancelled."
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

    func setOutputDuration(_ value: TimeInterval) {
        outputDuration = Self.sanitizedOutputDuration(value)
    }

    func setBitRateKbps(_ value: Int) {
        bitRateKbps = Self.sanitizedBitRateKbps(value)
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
            status = "Preset name is required."
            return false
        }

        let now = Date()
        if let index = layoutPresets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            layoutPresets[index].name = name
            layoutPresets[index].layout = layout.sanitized
            layoutPresets[index].updatedAt = now
            persistLayoutPresets()
            status = "Updated layout preset: \(name)"
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
        status = "Saved layout preset: \(name)"
        return true
    }

    func applyLayoutPreset(id: String) {
        guard !isExporting else { return }
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        layout = preset.layout.sanitized
        selectedElementID = Self.firstSelectableElementID(in: layout)
        status = "Applied layout preset: \(preset.name)"
        refreshOverlayOrPreview()
    }

    func setDefaultLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        defaultLayoutPresetID = id
        persistLayoutPresets()
        status = "Default layout preset: \(preset.name)"
    }

    func deleteLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        layoutPresets.removeAll { $0.id == id }
        if defaultLayoutPresetID == id {
            defaultLayoutPresetID = nil
        }
        persistLayoutPresets()
        status = "Deleted layout preset: \(preset.name)"
    }

    func exportLayoutPresets() {
        guard !layoutPresets.isEmpty else {
            status = "No layout presets to export."
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export layout presets"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "overlay-layout-presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let state = LayoutPresetState(presets: layoutPresets, defaultPresetID: defaultLayoutPresetID)
            let data = try encoder.encode(state.sanitized)
            try data.write(to: url, options: .atomic)
            status = "Exported \(layoutPresets.count) layout presets."
        } catch {
            status = "Preset export error: \(error.localizedDescription)"
        }
    }

    func importLayoutPresets() {
        let panel = NSOpenPanel()
        panel.title = "Import layout presets"
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
                ? "No layout presets imported."
                : "Imported \(importedCount) layout presets."
        } catch {
            status = "Preset import error: \(error.localizedDescription)"
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
        draggedElementID = nil
        previewOverlayRenderSize = nil
        videoURL = nil
        metadata = nil
        outputDuration = 0
        backgroundImage = nil
        overlayImage = nil
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        previewWarning = nil
        status = "Loading video: \(url.lastPathComponent)"

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
                    self.setOutputDuration(loaded.duration)
                    self.previewTime = 0
                    self.configurePlayer(url: url)
                    self.status = "Loaded video: \(url.lastPathComponent)"
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
                    self.status = "Video error: \(message)"
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
            forInterval: CMTime(seconds: 0.10, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let seconds = CMTimeGetSeconds(time)
                guard seconds.isFinite else { return }
                self.previewTime = min(max(0, seconds), max(0, self.outputDuration))
                self.refreshOverlayOnly(coalesceIfBusy: true)
                if self.outputDuration > 0, self.previewTime >= self.outputDuration {
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
        guard !isExporting else { return }
        let clamped = min(max(0, time), max(outputDuration, 0))
        previewTime = clamped
        if let player {
            player.seek(
                to: CMTime(seconds: clamped, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            refreshOverlayOnly(coalesceIfBusy: true)
        } else {
            refreshPreview()
        }
    }

    func markSportStart() {
        guard !isExporting else { return }
        syncMode = .syncPoint
        syncVideoSeconds = previewTime
        syncFITSeconds = 0
        status = "运动开始 set at video \(formatTime(previewTime)); FIT starts at 0.000s."
        refreshOverlayOrPreview()
    }

    func setFIT(_ url: URL) {
        guard !isExporting else { return }
        cancelPreviewRenderTasks()
        fitLoadTask?.cancel()
        previewRenderGeneration += 1
        fitLoadGeneration += 1
        let loadGeneration = fitLoadGeneration
        draggedElementID = nil
        fitURL = nil
        series = nil
        overlayImage = nil
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        previewWarning = nil
        status = "Loading FIT: \(url.lastPathComponent)"

        fitLoadTask = Task.detached {
            do {
                let parsedSeries = try FITParser().parse(url: url)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.fitLoadGeneration == loadGeneration else { return }
                    self.fitURL = url
                    self.series = parsedSeries
                    self.status = "Loaded FIT: \(url.lastPathComponent)"
                    self.refreshOverlayOrPreview()
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
                } else {
                    message = error.localizedDescription
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !Task.isCancelled,
                          self.fitLoadGeneration == loadGeneration else { return }
                    self.status = "FIT error: \(message)"
                    self.fitLoadTask = nil
                    self.refreshOverlayOnly()
                }
            }
        }
    }

    func refreshPreview() {
        guard !isExporting else { return }
        guard draggedElementID == nil else { return }
        guard let videoURL else {
            backgroundImage = nil
            overlayImage = nil
            dragBaseOverlayImage = nil
            dragOverlayImage = nil
            previewWarning = nil
            return
        }

        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        pendingOverlayRefreshAfterCurrentRender = false
        previewRenderGeneration += 1
        let generation = previewRenderGeneration
        let time = previewTime
        let outputSize = sanitizedPreviewSize(currentPreviewOverlayRenderSize())
        let currentSeries = series
        let currentSync = timeSync
        let currentLayout = layout
        let currentDistanceUnit = distanceUnit

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached { [videoFrameService, previewRenderer] in
            guard !Task.isCancelled else { return }
            let background: NSImage?
            var warningMessage: String?
            do {
                background = try videoFrameService.frameImage(videoURL: videoURL, time: time)
            } catch is CancellationError {
                return
            } catch {
                background = nil
                warningMessage = Self.previewWarningMessage("Video frame preview failed", error: error)
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
                    warningMessage = Self.previewWarningMessage("Overlay preview failed", error: error)
                }
            } else {
                overlay = nil
            }
            guard !Task.isCancelled else { return }
            let finalWarningMessage = warningMessage

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !Task.isCancelled,
                      self.previewRenderGeneration == generation else { return }
                self.backgroundImage = background
                self.overlayImage = overlay
                self.previewWarning = finalWarningMessage
                self.previewRenderTask = nil
            }
        }
    }

    func refreshOverlayOnly(
        previewSize: CGSize? = nil,
        minimumInterval: TimeInterval = 0,
        coalesceIfBusy: Bool = false
    ) {
        guard !isExporting else { return }
        guard draggedElementID == nil else { return }
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        guard videoURL != nil else {
            overlayImage = nil
            previewWarning = nil
            return
        }
        guard let currentSeries = series else {
            overlayImage = nil
            previewWarning = nil
            return
        }
        if coalesceIfBusy, previewRenderTask != nil {
            pendingOverlayRefreshAfterCurrentRender = true
            return
        }
        pendingOverlayRefreshAfterCurrentRender = false

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

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached { [previewRenderer] in
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
                warningMessage = Self.previewWarningMessage("Overlay preview failed", error: error)
            }
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !Task.isCancelled,
                      self.previewRenderGeneration == generation else { return }
                if self.pendingOverlayRefreshAfterCurrentRender {
                    self.pendingOverlayRefreshAfterCurrentRender = false
                    self.previewRenderTask = nil
                    self.refreshOverlayOnly(coalesceIfBusy: true)
                    return
                }
                self.overlayImage = overlay
                self.previewWarning = warningMessage
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
        schedulePreviewSizeRefresh(sanitized)
    }

    private func currentPreviewOverlayRenderSize() -> CGSize {
        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        guard let previewOverlayRenderSize else { return outputSize }

        let outputAspect = outputSize.width / max(1, outputSize.height)
        let previewAspect = previewOverlayRenderSize.width / max(1, previewOverlayRenderSize.height)
        guard abs(outputAspect - previewAspect) <= max(0.01, outputAspect * 0.02) else {
            return outputSize
        }
        return previewOverlayRenderSize
    }

    func beginElementDrag(id: String, previewSize: CGSize) {
        guard videoURL != nil,
              let currentSeries = series,
              let element = layout.elements.first(where: { $0.id == id }) else {
            return
        }

        previewRenderGeneration += 1
        let generation = previewRenderGeneration

        let time = previewTime
        let renderSize = sanitizedPreviewSize(previewSize)
        let currentSync = timeSync
        let currentDistanceUnit = distanceUnit
        let baseLayout = OverlayLayout(elements: layout.elements.filter { $0.id != id }, style: layout.style)
        let dragLayout = OverlayLayout(elements: [element], style: layout.style)

        previewRenderTask?.cancel()
        dragRenderTask?.cancel()
        draggedElementID = id
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        dragRenderTask = Task.detached { [previewRenderer] in
            guard !Task.isCancelled else { return }
            let baseOverlay = try? Self.renderOverlayImage(
                previewRenderer: previewRenderer,
                series: currentSeries,
                size: renderSize,
                videoTime: time,
                timeSync: currentSync,
                layout: baseLayout,
                distanceUnit: currentDistanceUnit
            )
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !Task.isCancelled,
                      self.previewRenderGeneration == generation else { return }
                self.dragBaseOverlayImage = baseOverlay
            }

            guard !Task.isCancelled else { return }
            let dragOverlay = try? Self.renderOverlayImage(
                previewRenderer: previewRenderer,
                series: currentSeries,
                size: renderSize,
                videoTime: time,
                timeSync: currentSync,
                layout: dragLayout,
                distanceUnit: currentDistanceUnit
            )
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !Task.isCancelled,
                      self.previewRenderGeneration == generation else { return }
                self.dragOverlayImage = dragOverlay
                self.dragRenderTask = nil
            }
        }
    }

    func endElementDrag() {
        previewRenderGeneration += 1
        dragRenderTask?.cancel()
        dragRenderTask = nil
        draggedElementID = nil
        overlayImage = nil
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        refreshOverlayOnly()
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

        let delay = max(0, previewResizeRefreshInterval - Date().timeIntervalSince(lastOverlayRefresh))
        if delay <= 0.001 {
            pendingPreviewSizeRefreshTask = nil
            refreshOverlayOnly(previewSize: size)
            return
        }

        pendingPreviewSizeRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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
            status = "Check output settings: width/height, fps, duration, and bitrate must be in range."
            return
        }
        if outputURL == nil {
            chooseOutput()
        }
        guard let outputURL else {
            status = "Choose an output file to export."
            return
        }
        guard let series else {
            status = "Choose a FIT file before exporting."
            return
        }

        pausePlayback()
        cancelPreviewRenderTasks()
        isExporting = true
        exportProgress = 0
        status = "Exporting..."
        let cancellationToken = ExportCancellationToken()
        exportCancellationToken = cancellationToken

        let config = TransparentVideoWriterConfig(
            width: exportSettings.width,
            height: exportSettings.height,
            framesPerSecond: exportSettings.framesPerSecond,
            duration: exportSettings.duration,
            averageBitRate: exportSettings.averageBitRate,
            timeSync: timeSync,
            codec: codec,
            overlayLayout: layout,
            distanceUnit: distanceUnit,
            progressHandler: { [weak self] completed, total in
                Task { @MainActor in
                    self?.exportProgress = total > 0 ? Double(completed) / Double(total) : 0
                }
            },
            cancellationHandler: {
                cancellationToken.isCancelled
            }
        )

        exportTask = Task.detached {
            do {
                try TransparentVideoWriter(outputURL: outputURL, series: series, config: config).write()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportProgress = 1
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.status = "Wrote \(outputURL.path)"
                    self.refreshOverlayOrPreview()
                }
            } catch OverlayVideoError.cancelled {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportProgress = 0
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.status = "Export cancelled."
                    self.refreshOverlayOrPreview()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isExporting = false
                    self.exportTask = nil
                    self.exportCancellationToken = nil
                    self.status = "Export error: \(error.localizedDescription)"
                    self.refreshOverlayOrPreview()
                }
            }
        }
    }

    func cancelExport() {
        guard isExporting else { return }
        exportCancellationToken?.cancel()
        exportTask?.cancel()
        status = "Cancelling export..."
    }

    private func formatTime(_ time: TimeInterval) -> String {
        String(format: "%.3f", time)
    }

    private func persistLayoutPresets() {
        let state = LayoutPresetState(presets: layoutPresets, defaultPresetID: defaultLayoutPresetID)
        layoutPresetStore.save(state)
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
        dragRenderTask?.cancel()
        pendingPreviewSizeRefreshTask?.cancel()
        previewRenderTask = nil
        dragRenderTask = nil
        pendingPreviewSizeRefreshTask = nil
        draggedElementID = nil
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        pendingOverlayRefreshAfterCurrentRender = false
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
        guard outputDuration.isFinite, outputDuration >= 0.1, outputDuration <= 86_400 else { return nil }
        guard bitRateKbps >= 1, bitRateKbps <= 1_000_000 else { return nil }
        guard bitRateKbps <= Int.max / 1000 else { return nil }
        return ExportSettings(
            width: outputWidth,
            height: outputHeight,
            framesPerSecond: outputFPS,
            duration: outputDuration,
            averageBitRate: bitRateKbps * 1000
        )
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

    static func sanitizedOutputDuration(_ value: TimeInterval) -> TimeInterval {
        let finiteValue = value.isFinite ? value : 0.1
        return min(86_400, max(0.1, finiteValue))
    }

    static func sanitizedBitRateKbps(_ value: Int) -> Int {
        min(1_000_000, max(1, value))
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

    private func finiteTime(_ time: TimeInterval) -> TimeInterval {
        time.isFinite ? time : 0
    }

    private func nonNegativeTime(_ time: TimeInterval) -> TimeInterval {
        max(0, finiteTime(time))
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
