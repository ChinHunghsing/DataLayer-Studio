import AVFoundation
import CoreGraphics
import Foundation
import OverlayCore
import OverlayStudioKit

/// iPad 端会话模型：素材导入、对表、布局编辑、预览渲染调度与导出执行。
/// 平台中立（不依赖 UIKit/SwiftUI），可在 macOS 上跑单元测试。
@MainActor
public final class TouchStudioModel: ObservableObject {
    public static let playerTimeObserverInterval: TimeInterval = 1.0 / 12.0
    public static let playbackOverlayRefreshInterval: TimeInterval = 0.20
    nonisolated public static let dragMaximumPreviewRenderDimension: CGFloat = 1_600
    private static let maximumPreviewRenderDimension: CGFloat = 3_200
    private static let exportETASampleWindow: TimeInterval = 10
    private static let minimumTrimDuration: TimeInterval = 0.1
    private static let maximumUndoDepth = 100
    private static let preferencesKey = "run.libo.datalayer-studio.touch.preferences.v1"

    // MARK: - 素材

    @Published public private(set) var videoURL: URL?
    @Published public private(set) var activityURL: URL?
    @Published public private(set) var metadata: VideoMetadata?
    @Published public private(set) var series: TelemetrySeries?
    @Published public private(set) var sourceDuration: TimeInterval = 0
    @Published public private(set) var videoLoadFailure: TouchSourceLoadFailure?
    @Published public private(set) var activityLoadFailure: TouchSourceLoadFailure?
    @Published public private(set) var statusMessage = TouchMessage("status.chooseVideoAndFit")

    // MARK: - 对表

    @Published public var syncMode: TouchSyncMode = .syncPoint
    @Published public var offsetSeconds = 0.0
    @Published public var fitStartSeconds = 0.0
    @Published public var syncVideoSeconds = 0.0
    @Published public var syncFITSeconds = 0.0

    // MARK: - 预览

    @Published public private(set) var previewTime: TimeInterval = 0
    @Published public private(set) var player: AVPlayer?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var overlayImage: CGImage?
    @Published public private(set) var previewWarning: TouchMessage?

    // MARK: - 布局

    @Published public var layout: OverlayLayout
    @Published public var selectedElementID: String?
    @Published public private(set) var layoutPresets: [LayoutPreset]
    @Published public private(set) var defaultLayoutPresetID: String?
    @Published public private(set) var presetSyncStatus: TouchPresetSyncStatus = .localOnly
    @Published public private(set) var canUndoLayout = false
    @Published public private(set) var canRedoLayout = false

    // MARK: - 导出参数

    @Published public private(set) var outputWidth = 1920
    @Published public private(set) var outputHeight = 1080
    @Published public private(set) var outputFPS = 30.0
    @Published public private(set) var bitRateKbps = 12_000
    /// iPad 版只导出最终成片：移动端剪辑场景不需要透明浮层中间产物，浮层供给由 Mac 版承担。
    public let exportMode: OverlayExportMode = .video
    @Published public var codec: OverlayVideoCodec = .hevc
    @Published public var distanceUnit: OverlayDistanceUnit = .kilometers {
        didSet { persistPreferences() }
    }
    @Published public private(set) var exportTrimStartSeconds: TimeInterval = 0
    @Published public private(set) var exportTrimEndSeconds: TimeInterval = 0
    @Published public private(set) var activityTrim: ActivityTrim = .none

    // MARK: - 导出执行

    @Published public private(set) var isExporting = false
    @Published public private(set) var exportProgress = 0.0
    @Published public private(set) var exportETASeconds: TimeInterval?
    @Published public private(set) var lastExportedURL: URL?
    @Published public private(set) var lastExportElapsedSeconds: TimeInterval?
    @Published public private(set) var lastExportErrorMessage: String?
    @Published public private(set) var lastExportWasCancelled = false
    @Published public private(set) var subscriptionPaywallRequestID = 0
    @Published public private(set) var thermalStateIsSerious = false

    private let previewRenderer = OverlayPreviewRenderer()
    private let layoutPresetStore: LayoutPresetStore
    private let runtimeGuard: TouchExportRuntimeGuarding
    private let subscriptionEntitlement: any SubscriptionEntitlementProviding
    private var layoutPresetCloudObserver: NSObjectProtocol?
    private var thermalStateObserver: NSObjectProtocol?
    private var playerTimeObserverToken: Any?

    private var videoLoadGeneration = 0
    private var activityLoadGeneration = 0
    private var videoLoadTask: Task<Void, Never>?
    private var activityLoadTask: Task<Void, Never>?

    private var previewRenderGeneration = 0
    private var previewRenderTask: Task<Void, Never>?
    private var pendingOverlayRefresh = false
    private var lastOverlayRefresh = Date.distantPast
    private var previewOverlayRenderSize: CGSize?
    private var isDragInteractionActive = false

    private var exportTask: Task<Void, Never>?
    private var exportCancellationToken: TouchExportCancellationToken?
    private var exportProgressSamples: [(date: Date, progress: Double)] = []

    private var scopedVideoAccess: ScopedResourceAccess?
    private var activeTemporaryVideoURL: URL?
    private var ownedTemporaryVideoURLs: Set<URL> = []
    private var undoStack: [LayoutSnapshot] = []
    private var redoStack: [LayoutSnapshot] = []

    public init(
        layoutPresetStore: LayoutPresetStore = LayoutPresetStore(),
        runtimeGuard: TouchExportRuntimeGuarding = TouchExportRuntimeNoopGuard(),
        subscriptionEntitlement: (any SubscriptionEntitlementProviding)? = nil
    ) {
        self.layoutPresetStore = layoutPresetStore
        self.runtimeGuard = runtimeGuard
        self.subscriptionEntitlement = subscriptionEntitlement ?? TouchSubscriptionBypass.shared
        let presetState = layoutPresetStore.load()
        let validDefaultPresetID = presetState.presets.contains { $0.id == presetState.defaultPresetID } ? presetState.defaultPresetID : nil
        self.layoutPresets = presetState.presets
        self.defaultLayoutPresetID = validDefaultPresetID
        self.layout = presetState.presets.first { $0.id == validDefaultPresetID }?.layout.sanitized ?? .default
        self.selectedElementID = layout.elements.first { $0.frame.isVisible }?.id ?? layout.elements.first?.id
        restorePreferences()
        observeLayoutPresetCloudChanges()
        observeThermalState()
    }

    deinit {
        if let layoutPresetCloudObserver {
            NotificationCenter.default.removeObserver(layoutPresetCloudObserver)
        }
        if let thermalStateObserver {
            NotificationCenter.default.removeObserver(thermalStateObserver)
        }
        videoLoadTask?.cancel()
        activityLoadTask?.cancel()
        previewRenderTask?.cancel()
        exportCancellationToken?.cancel()
        exportTask?.cancel()
        runtimeGuard.exportDidEnd()
        scopedVideoAccess = nil
        for url in ownedTemporaryVideoURLs {
            TouchTemporaryMovieStore.release(url)
        }
    }

    // MARK: - 素材导入

    public func setVideo(_ url: URL, isSecurityScoped: Bool) {
        guard !isExporting else { return }
        stopPlayback()
        cancelPreviewRenderTasks()
        videoLoadTask?.cancel()
        videoLoadGeneration += 1
        let loadGeneration = videoLoadGeneration
        let candidateScopedAccess = isSecurityScoped ? ScopedResourceAccess(url: url) : nil
        let isTemporaryImport = TouchTemporaryMovieStore.isManaged(url)
        if isTemporaryImport {
            TouchTemporaryMovieStore.retain(url)
            ownedTemporaryVideoURLs.insert(url)
        }
        if let failedURL = videoLoadFailure?.url,
           failedURL != activeTemporaryVideoURL,
           failedURL != url,
           ownedTemporaryVideoURLs.remove(failedURL) != nil {
            TouchTemporaryMovieStore.release(failedURL)
        }

        videoLoadFailure = nil
        setStatus("status.loadingVideo", url.lastPathComponent)

        videoLoadTask = Task.detached { [candidateScopedAccess] in
            do {
                let loaded = try await VideoMetadata.loadAsync(from: url)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.videoLoadGeneration == loadGeneration else { return }
                    let previousTemporaryVideoURL = self.activeTemporaryVideoURL
                    self.scopedVideoAccess = candidateScopedAccess
                    self.videoURL = url
                    self.metadata = loaded
                    self.setOutputWidth(Int(loaded.size.width.rounded()))
                    self.setOutputHeight(Int(loaded.size.height.rounded()))
                    self.setOutputFPS(loaded.framesPerSecond)
                    if let sourceBitRateKbps = Self.sourceVideoBitRateKbps(from: loaded) {
                        self.setBitRateKbps(sourceBitRateKbps)
                    }
                    self.sourceDuration = Self.sanitizedSourceDuration(loaded.duration)
                    self.resetExportTrimRangeToFullDuration()
                    self.previewTime = 0
                    self.configurePlayer(url: url)
                    self.setStatus("status.loadedVideo", url.lastPathComponent)
                    self.refreshOverlayOnly()
                    self.videoLoadTask = nil
                    self.activeTemporaryVideoURL = isTemporaryImport ? url : nil
                    if let previousTemporaryVideoURL,
                       previousTemporaryVideoURL != self.activeTemporaryVideoURL {
                        self.ownedTemporaryVideoURLs.remove(previousTemporaryVideoURL)
                        TouchTemporaryMovieStore.release(previousTemporaryVideoURL)
                    }
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, self.videoLoadGeneration == loadGeneration else { return }
                    self.videoLoadTask = nil
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    guard let self, self.videoLoadGeneration == loadGeneration else { return }
                    self.videoLoadFailure = TouchSourceLoadFailure(
                        url: url,
                        isSecurityScoped: isSecurityScoped,
                        isTemporaryImport: isTemporaryImport,
                        messageKey: "status.videoError",
                        detail: message
                    )
                    self.setStatus("status.videoError", message)
                    self.videoLoadTask = nil
                }
            }
        }
    }

    public func setActivityFile(_ url: URL, isSecurityScoped: Bool) {
        guard !isExporting else { return }
        cancelPreviewRenderTasks()
        activityLoadTask?.cancel()
        activityLoadGeneration += 1
        let loadGeneration = activityLoadGeneration
        activityLoadFailure = nil
        setStatus("status.loadingFit", url.lastPathComponent)

        activityLoadTask = Task.detached {
            do {
                let didStartAccessing = isSecurityScoped && url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let parsedSeries = try TelemetryFileParser().parse(url: url)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.activityLoadGeneration == loadGeneration else { return }
                    self.activityURL = url
                    self.series = parsedSeries
                    self.activityTrim = .none
                    self.overlayImage = nil
                    self.previewWarning = nil
                    if self.videoURL == nil {
                        self.resetExportTrimRangeToFullDuration()
                    }
                    self.setStatus("status.loadedFit", url.lastPathComponent)
                    self.refreshOverlayOnly()
                    self.activityLoadTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, self.activityLoadGeneration == loadGeneration else { return }
                    self.activityLoadTask = nil
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
                    guard let self, self.activityLoadGeneration == loadGeneration else { return }
                    self.activityLoadFailure = TouchSourceLoadFailure(
                        url: url,
                        isSecurityScoped: isSecurityScoped,
                        messageKey: "status.fitError",
                        detail: message
                    )
                    self.setStatus("status.fitError", message)
                    self.activityLoadTask = nil
                    self.refreshOverlayOnly()
                }
            }
        }
    }

    public func openIncomingFile(_ url: URL, isSecurityScoped: Bool = true) {
        switch url.pathExtension.lowercased() {
        case "fit", "gpx":
            setActivityFile(url, isSecurityScoped: isSecurityScoped)
        case "mov", "mp4", "m4v":
            setVideo(url, isSecurityScoped: isSecurityScoped)
        default:
            break
        }
    }

    public func retryVideoLoad() {
        guard let failure = videoLoadFailure else { return }
        setVideo(failure.url, isSecurityScoped: failure.isSecurityScoped)
    }

    public func retryActivityLoad() {
        guard let failure = activityLoadFailure else { return }
        setActivityFile(failure.url, isSecurityScoped: failure.isSecurityScoped)
    }

    // MARK: - 播放与时间轴

    public var canPreview: Bool {
        series != nil
    }

    public var previewDuration: TimeInterval {
        if sourceDuration > 0 {
            return sourceDuration
        }
        return series?.duration ?? 0
    }

    public var previewTimeRange: ClosedRange<TimeInterval> {
        let duration = max(0, previewDuration)
        guard duration > 0 else { return 0...0 }
        let lowerBound = min(duration, max(0, effectiveExportTrimStart))
        let upperBound = max(lowerBound, min(duration, effectiveExportTrimEnd))
        return lowerBound...upperBound
    }

    public var previewFrameRate: Double {
        Self.sanitizedOutputFrameRate(metadata?.framesPerSecond ?? outputFPS)
    }

    public var previewFrameDuration: TimeInterval {
        1 / previewFrameRate
    }

    public func togglePlayback() {
        isPlaying ? pausePlayback() : startPlayback()
    }

    public func startPlayback() {
        guard !isExporting, let player else { return }
        if previewTime < previewTimeRange.lowerBound || previewTime >= previewTimeRange.upperBound {
            seekPreview(to: previewTimeRange.lowerBound)
        }
        isPlaying = true
        player.play()
    }

    public func pausePlayback() {
        isPlaying = false
        player?.pause()
    }

    public func stopPlayback() {
        pausePlayback()
        removePlayerTimeObserver()
        player = nil
    }

    public func seekPreview(to time: TimeInterval) {
        seekPreview(to: time, isScrubbing: false)
    }

    public func scrubPreview(to time: TimeInterval) {
        seekPreview(to: time, isScrubbing: true)
    }

    public func stepPreviewFrame(by frameOffset: Int) {
        guard frameOffset != 0 else { return }
        pausePlayback()
        seekPreview(to: previewTime + Double(frameOffset) * previewFrameDuration)
    }

    private func seekPreview(to time: TimeInterval, isScrubbing: Bool) {
        guard !isExporting else { return }
        let clamped = clampedPreviewTime(time)
        if isScrubbing, abs(previewTime - clamped) < 0.000_5 {
            return
        }
        previewTime = clamped
        if let player {
            let targetTime = CMTime(seconds: clamped, preferredTimescale: 600)
            if isScrubbing {
                player.currentItem?.cancelPendingSeeks()
                let tolerance = CMTime(seconds: min(0.08, max(1.0 / 120.0, previewFrameDuration)), preferredTimescale: 600)
                player.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
            } else {
                player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    private func clampedPreviewTime(_ time: TimeInterval) -> TimeInterval {
        let range = previewTimeRange
        let finiteTime = time.isFinite ? time : range.lowerBound
        return min(range.upperBound, max(range.lowerBound, finiteTime))
    }

    private func configurePlayer(url: URL) {
        removePlayerTimeObserver()
        let player = AVPlayer(url: url)
        player.isMuted = true
        self.player = player
        playerTimeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: Self.playerTimeObserverInterval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isPlaying else { return }
                let seconds = CMTimeGetSeconds(time)
                guard seconds.isFinite else { return }
                let clamped = self.clampedPreviewTime(seconds)
                self.previewTime = clamped
                self.refreshOverlayOnly(
                    minimumInterval: Self.playbackOverlayRefreshInterval,
                    coalesceIfBusy: true
                )
                if seconds >= self.previewTimeRange.upperBound {
                    self.pausePlayback()
                    self.player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
                }
            }
        }
    }

    private func removePlayerTimeObserver() {
        if let playerTimeObserverToken, let player {
            player.removeTimeObserver(playerTimeObserverToken)
        }
        playerTimeObserverToken = nil
    }

    // MARK: - 对表

    public var timeSync: TelemetryTimeSync {
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

    public func markSportStart() {
        guard !isExporting else { return }
        syncMode = .syncPoint
        syncVideoSeconds = previewTime
        syncFITSeconds = 0
        setStatus("status.sportStartSet", Self.formatSeconds(previewTime))
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func applySyncChange() {
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func displayTelemetrySample(forVideoTime videoTime: TimeInterval) -> TelemetrySample {
        let rawActivityTime = timeSync.fitElapsed(forVideoTime: videoTime)
        let displayElapsed = activityTrim.displayElapsed(
            forRawElapsed: rawActivityTime,
            sourceDuration: series?.duration ?? 0
        )
        return series?.trimmed(by: activityTrim).sample(at: displayElapsed) ?? TelemetrySample(elapsed: displayElapsed)
    }

    // MARK: - 布局编辑

    public var selectedElement: OverlayElement? {
        guard let selectedElementID else { return layout.elements.first }
        return layout.elements.first { $0.id == selectedElementID } ?? layout.elements.first
    }

    public func selectElement(_ id: String?) {
        guard selectedElementID != id else { return }
        selectedElementID = id
    }

    public func updateElement(_ id: String, refreshPreview: Bool = true, recordUndo: Bool = true, _ update: (inout OverlayElement) -> Void) {
        guard !isExporting else { return }
        if recordUndo {
            recordLayoutSnapshot()
        }
        layout.updateElement(id: id, update)
        if refreshPreview {
            refreshOverlayOnly(coalesceIfBusy: true)
        }
    }

    public func addElement(kind: OverlayComponentID) {
        guard !isExporting else { return }
        recordLayoutSnapshot()
        let existingCount = layout.elements.filter { $0.kind == kind }.count
        var element = OverlayElement.defaultElement(kind: kind, id: "\(kind.rawValue)-\(UUID().uuidString)")
        let offset = min(0.20, Double(existingCount) * 0.035)
        element.frame.x = TouchLayoutLimits.clampPosition(element.frame.x + offset)
        element.frame.y = TouchLayoutLimits.clampPosition(element.frame.y + offset)
        layout.elements.append(element)
        selectedElementID = element.id
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func duplicateSelectedElement() {
        guard !isExporting, var element = selectedElement else { return }
        recordLayoutSnapshot()
        element.id = "\(element.kind.rawValue)-\(UUID().uuidString)"
        element.frame.x = TouchLayoutLimits.clampPosition(element.frame.x + 0.035)
        element.frame.y = TouchLayoutLimits.clampPosition(element.frame.y + 0.035)
        layout.elements.append(element)
        selectedElementID = element.id
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func deleteSelectedElement() {
        guard !isExporting, let selectedElementID else { return }
        recordLayoutSnapshot()
        layout.removeElement(id: selectedElementID)
        self.selectedElementID = layout.elements.first?.id
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func moveSelectedElement(by offset: Int) {
        guard !isExporting, let selectedElementID else { return }
        recordLayoutSnapshot()
        layout.moveElement(id: selectedElementID, by: offset)
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func nudgeSelectedElement(deltaX: Double, deltaY: Double) {
        guard let selectedElementID else { return }
        updateElement(selectedElementID) { element in
            element.frame.x = TouchLayoutLimits.clampPosition(element.frame.x + deltaX)
            element.frame.y = TouchLayoutLimits.clampPosition(element.frame.y + deltaY)
        }
    }

    public func beginDragInteraction() {
        guard !isDragInteractionActive else { return }
        isDragInteractionActive = true
        recordLayoutSnapshot()
    }

    public func endDragInteraction() {
        guard isDragInteractionActive else { return }
        isDragInteractionActive = false
        guard !isExporting, series != nil else { return }
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func canAddElement(kind: OverlayComponentID) -> Bool {
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

    // MARK: - 布局撤销

    private struct LayoutSnapshot {
        var layout: OverlayLayout
        var selectedElementID: String?
    }

    private func recordLayoutSnapshot() {
        undoStack.append(LayoutSnapshot(layout: layout, selectedElementID: selectedElementID))
        if undoStack.count > Self.maximumUndoDepth {
            undoStack.removeFirst(undoStack.count - Self.maximumUndoDepth)
        }
        redoStack.removeAll()
        updateUndoAvailability()
    }

    public func undoLayoutChange() {
        guard !isExporting, let snapshot = undoStack.popLast() else { return }
        redoStack.append(LayoutSnapshot(layout: layout, selectedElementID: selectedElementID))
        layout = snapshot.layout
        selectedElementID = snapshot.selectedElementID
        updateUndoAvailability()
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func redoLayoutChange() {
        guard !isExporting, let snapshot = redoStack.popLast() else { return }
        undoStack.append(LayoutSnapshot(layout: layout, selectedElementID: selectedElementID))
        layout = snapshot.layout
        selectedElementID = snapshot.selectedElementID
        updateUndoAvailability()
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    private func updateUndoAvailability() {
        canUndoLayout = !undoStack.isEmpty
        canRedoLayout = !redoStack.isEmpty
    }

    // MARK: - 预设

    public var layoutPresetsForDisplay: [LayoutPreset] {
        layoutPresets.sorted { lhs, rhs in
            if lhs.id == defaultLayoutPresetID { return true }
            if rhs.id == defaultLayoutPresetID { return false }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    @discardableResult
    public func saveLayoutPreset(named rawName: String) -> Bool {
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

    public func applyLayoutPreset(id: String) {
        guard !isExporting else { return }
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        recordLayoutSnapshot()
        layout = preset.layout.sanitized
        selectedElementID = layout.elements.first { $0.frame.isVisible }?.id ?? layout.elements.first?.id
        setStatus("status.appliedPreset", preset.name)
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func setDefaultLayoutPreset(id: String) {
        guard layoutPresets.contains(where: { $0.id == id }) else { return }
        defaultLayoutPresetID = id
        persistLayoutPresets()
    }

    public func deleteLayoutPreset(id: String) {
        guard let preset = layoutPresets.first(where: { $0.id == id }) else { return }
        layoutPresets.removeAll { $0.id == id }
        if defaultLayoutPresetID == id {
            defaultLayoutPresetID = nil
        }
        persistLayoutPresets()
        setStatus("status.deletedPreset", preset.name)
    }

    private func persistLayoutPresets() {
        let state = LayoutPresetState(presets: layoutPresets, defaultPresetID: defaultLayoutPresetID)
        layoutPresetStore.save(state)
        presetSyncStatus = layoutPresetStore.synchronizeCloud()
            ? .uploadRequested(Date())
            : .localOnly
    }

    private func observeLayoutPresetCloudChanges() {
        presetSyncStatus = layoutPresetStore.synchronizeCloud() ? .ready : .localOnly
        let key = layoutPresetStore.cloudNotificationKey
        layoutPresetCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            guard changedKeys?.contains(key) ?? true else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let presetState = self.layoutPresetStore.load()
                let validDefaultPresetID = presetState.presets.contains { $0.id == presetState.defaultPresetID }
                    ? presetState.defaultPresetID
                    : nil
                self.layoutPresets = presetState.presets
                self.defaultLayoutPresetID = validDefaultPresetID
                self.presetSyncStatus = .receivedUpdate(Date())
            }
        }
    }

    // MARK: - 预览渲染

    public func updatePreviewOverlayRenderSize(_ size: CGSize) {
        let sanitized = sanitizedPreviewSize(size)
        guard sanitized.width.isFinite, sanitized.height.isFinite,
              sanitized.width > 0, sanitized.height > 0 else {
            return
        }
        if let previewOverlayRenderSize,
           abs(previewOverlayRenderSize.width - sanitized.width) < 1,
           abs(previewOverlayRenderSize.height - sanitized.height) < 1 {
            return
        }
        previewOverlayRenderSize = sanitized
        guard !isExporting else { return }
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    public func refreshOverlayOnly(minimumInterval: TimeInterval = 0, coalesceIfBusy: Bool = false) {
        guard !isExporting else { return }
        guard let currentSeries = series else {
            overlayImage = nil
            previewWarning = nil
            return
        }
        if coalesceIfBusy, previewRenderTask != nil {
            pendingOverlayRefresh = true
            return
        }
        pendingOverlayRefresh = false

        let now = Date()
        if minimumInterval > 0, now.timeIntervalSince(lastOverlayRefresh) < minimumInterval {
            return
        }
        lastOverlayRefresh = now
        previewRenderGeneration += 1
        let generation = previewRenderGeneration

        let time = previewTime
        let renderSize = currentOverlayRenderSize()
        let currentSync = timeSync
        let currentLayout = layout
        let currentDistanceUnit = distanceUnit
        let currentActivityTrim = activityTrim

        previewRenderTask?.cancel()
        previewRenderTask = Task.detached(priority: .userInitiated) { [previewRenderer] in
            guard !Task.isCancelled else { return }
            var overlay: CGImage?
            var warning: TouchMessage?
            do {
                overlay = try previewRenderer.renderOverlayImage(
                    series: currentSeries,
                    size: renderSize,
                    videoTime: time,
                    timeSync: currentSync,
                    layout: currentLayout,
                    distanceUnit: currentDistanceUnit,
                    activityTrim: currentActivityTrim
                )
            } catch is CancellationError {
                return
            } catch {
                warning = TouchMessage("status.previewOverlayFailed", [Self.errorDescription(error)])
            }
            guard !Task.isCancelled else { return }
            let resolvedOverlay = overlay
            let resolvedWarning = warning

            await MainActor.run { [weak self] in
                guard let self, self.previewRenderGeneration == generation else { return }
                self.overlayImage = resolvedOverlay
                self.previewWarning = resolvedWarning
                self.previewRenderTask = nil
                if self.pendingOverlayRefresh {
                    self.pendingOverlayRefresh = false
                    self.refreshOverlayOnly(coalesceIfBusy: true)
                }
            }
        }
    }

    private func currentOverlayRenderSize() -> CGSize {
        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        var resolvedSize = outputSize
        if let previewOverlayRenderSize {
            let outputAspect = outputSize.width / max(1, outputSize.height)
            let previewAspect = previewOverlayRenderSize.width / max(1, previewOverlayRenderSize.height)
            if abs(outputAspect - previewAspect) <= max(0.01, outputAspect * 0.02) {
                resolvedSize = previewOverlayRenderSize
            }
        }
        guard isDragInteractionActive else { return resolvedSize }
        let longestSide = max(resolvedSize.width, resolvedSize.height)
        guard longestSide > Self.dragMaximumPreviewRenderDimension else { return resolvedSize }
        let scale = Self.dragMaximumPreviewRenderDimension / longestSide
        return CGSize(width: resolvedSize.width * scale, height: resolvedSize.height * scale)
    }

    private func sanitizedPreviewSize(_ size: CGSize) -> CGSize {
        var width = size.width.isFinite && size.width > 0 ? size.width : CGFloat(outputWidth)
        var height = size.height.isFinite && size.height > 0 ? size.height : CGFloat(outputHeight)
        let longestSide = max(width, height)
        if longestSide > Self.maximumPreviewRenderDimension {
            let scale = Self.maximumPreviewRenderDimension / longestSide
            width *= scale
            height *= scale
        }
        return CGSize(width: max(2, width.rounded()), height: max(2, height.rounded()))
    }

    private func cancelPreviewRenderTasks() {
        previewRenderGeneration += 1
        previewRenderTask?.cancel()
        previewRenderTask = nil
        pendingOverlayRefresh = false
    }

    // MARK: - 导出参数

    public func setOutputWidth(_ value: Int) {
        outputWidth = Self.sanitizedOutputDimension(value)
    }

    public func setOutputHeight(_ value: Int) {
        outputHeight = Self.sanitizedOutputDimension(value)
    }

    public func setOutputFPS(_ value: Double) {
        outputFPS = Self.sanitizedOutputFrameRate(value)
    }

    public func setBitRateKbps(_ value: Int) {
        bitRateKbps = min(1_000_000, max(1, value))
    }

    public var availableCodecs: [OverlayVideoCodec] {
        OverlayVideoCodec.allCases.filter { $0.exportMode == .video }
    }

    public var sourceDimensions: (width: Int, height: Int)? {
        guard let metadata else { return nil }
        let width = Int(metadata.size.width.rounded())
        let height = Int(metadata.size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    public var selectedResolutionPresetID: String {
        if let sourceDimensions,
           outputWidth == sourceDimensions.width,
           outputHeight == sourceDimensions.height {
            return TouchResolutionPreset.sourceID
        }
        if let preset = TouchResolutionPreset.fixed.first(where: { $0.width == outputWidth && $0.height == outputHeight }) {
            return preset.id
        }
        return TouchResolutionPreset.customID
    }

    public func applyResolutionPreset(id: String) {
        guard !isExporting else { return }
        if id == TouchResolutionPreset.sourceID, let sourceDimensions {
            setOutputWidth(sourceDimensions.width)
            setOutputHeight(sourceDimensions.height)
            return
        }
        guard let preset = TouchResolutionPreset.fixed.first(where: { $0.id == id }) else { return }
        setOutputWidth(preset.width)
        setOutputHeight(preset.height)
    }

    public var selectedFrameRatePresetID: String {
        if let sourceFrameRate = metadata?.framesPerSecond, Self.frameRatesMatch(outputFPS, sourceFrameRate) {
            return TouchFrameRatePreset.sourceID
        }
        if let preset = TouchFrameRatePreset.fixed.first(where: { Self.frameRatesMatch(outputFPS, $0.framesPerSecond) }) {
            return preset.id
        }
        return TouchFrameRatePreset.customID
    }

    public func applyFrameRatePreset(id: String) {
        guard !isExporting else { return }
        if id == TouchFrameRatePreset.sourceID, let sourceFrameRate = metadata?.framesPerSecond {
            setOutputFPS(sourceFrameRate)
            return
        }
        guard let preset = TouchFrameRatePreset.fixed.first(where: { $0.id == id }) else { return }
        setOutputFPS(preset.framesPerSecond)
    }

    // MARK: - 导出区间

    public var exportTrimSourceDuration: TimeInterval {
        let duration = videoURL == nil ? series?.duration ?? 0 : sourceDuration
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(duration, 86_400)
    }

    private var exportTrimEditingDuration: TimeInterval {
        let duration = exportTrimSourceDuration > 0 ? exportTrimSourceDuration : previewDuration
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(duration, 86_400)
    }

    public var effectiveExportTrimStart: TimeInterval {
        sanitizedTrimStart(exportTrimStartSeconds, sourceDuration: exportTrimEditingDuration)
    }

    public var effectiveExportTrimEnd: TimeInterval {
        sanitizedTrimEnd(exportTrimEndSeconds, start: effectiveExportTrimStart, sourceDuration: exportTrimEditingDuration)
    }

    public var effectiveExportTrimDuration: TimeInterval {
        max(0, effectiveExportTrimEnd - effectiveExportTrimStart)
    }

    public func setExportTrimStart(_ value: TimeInterval) {
        guard !isExporting else { return }
        let sourceDuration = exportTrimEditingDuration
        exportTrimStartSeconds = sanitizedTrimStart(value, sourceDuration: sourceDuration)
        exportTrimEndSeconds = sanitizedTrimEnd(exportTrimEndSeconds, start: exportTrimStartSeconds, sourceDuration: sourceDuration)
        clampPreviewToExportTrimRange()
    }

    public func setExportTrimEnd(_ value: TimeInterval) {
        guard !isExporting else { return }
        exportTrimEndSeconds = sanitizedTrimEnd(value, start: effectiveExportTrimStart, sourceDuration: exportTrimEditingDuration)
        clampPreviewToExportTrimRange()
    }

    public func resetExportTrimRange() {
        guard !isExporting else { return }
        resetExportTrimRangeToFullDuration()
    }

    private func resetExportTrimRangeToFullDuration() {
        exportTrimStartSeconds = 0
        exportTrimEndSeconds = exportTrimEditingDuration
    }

    private func clampPreviewToExportTrimRange() {
        let clamped = clampedPreviewTime(previewTime)
        guard abs(previewTime - clamped) >= 0.000_5 else { return }
        seekPreview(to: clamped)
    }

    private func sanitizedTrimStart(_ value: TimeInterval, sourceDuration: TimeInterval) -> TimeInterval {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return 0 }
        let upperBound = max(0, sourceDuration - Self.minimumTrimDuration)
        let finiteValue = value.isFinite ? value : 0
        return min(upperBound, max(0, finiteValue))
    }

    private func sanitizedTrimEnd(_ value: TimeInterval, start: TimeInterval, sourceDuration: TimeInterval) -> TimeInterval {
        guard sourceDuration.isFinite, sourceDuration > 0 else { return 0 }
        let fallbackEnd = value.isFinite && value > 0 ? value : sourceDuration
        let minimumEnd = min(sourceDuration, start + Self.minimumTrimDuration)
        return min(sourceDuration, max(minimumEnd, fallbackEnd))
    }

    // MARK: - 导出执行

    public var canExport: Bool {
        exportReadinessMessageKey == nil
    }

    public var exportReadinessMessage: TouchMessage? {
        exportReadinessMessageKey.map { TouchMessage($0) }
    }

    private var exportReadinessMessageKey: String? {
        if series == nil {
            return "status.chooseFitFile"
        }
        if videoURL == nil {
            return "status.chooseVideoForCompositedExport"
        }
        if outputWidth < 2 || outputWidth > 16_384 || outputWidth % 2 != 0 {
            return "status.outputSizeInvalid"
        }
        if outputHeight < 2 || outputHeight > 16_384 || outputHeight % 2 != 0 {
            return "status.outputSizeInvalid"
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
        return nil
    }

    private var exportDuration: TimeInterval? {
        let duration = max(0, effectiveExportTrimEnd - effectiveExportTrimStart)
        guard duration.isFinite, duration >= 0.1, duration <= 86_400 else { return nil }
        return duration
    }

    public var hasExportResult: Bool {
        lastExportedURL != nil || lastExportErrorMessage != nil || lastExportWasCancelled
    }

    public func clearExportResult() {
        guard !isExporting else { return }
        lastExportedURL = nil
        lastExportElapsedSeconds = nil
        lastExportErrorMessage = nil
        lastExportWasCancelled = false
    }

    public var exportsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    public func export() {
        guard !isExporting else { return }
        if let exportReadinessMessageKey {
            setStatus(exportReadinessMessageKey)
            return
        }
        guard subscriptionEntitlement.hasActiveExportEntitlement else {
            setStatus("status.exportNeedsSubscription")
            subscriptionPaywallRequestID += 1
            return
        }
        guard let series, let duration = exportDuration else {
            setStatus("status.checkOutputSettings")
            return
        }

        let outputURL = makeUniqueOutputURL()
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
        runtimeGuard.exportDidStart { [weak self] in
            Task { @MainActor in
                self?.cancelExport()
            }
        }

        let cancellationToken = TouchExportCancellationToken()
        exportCancellationToken = cancellationToken

        let currentCodec = codec
        let currentTimeSync = timeSync
        let currentLayout = layout
        let currentDistanceUnit = distanceUnit
        let currentActivityTrim = activityTrim
        let sourceVideoURL = videoURL
        let width = outputWidth
        let height = outputHeight
        let fps = outputFPS
        let startTime = effectiveExportTrimStart
        let averageBitRate = bitRateKbps * 1000
        let progressHandler: (Int, Int) -> Void = { [weak self] completed, total in
            Task { @MainActor in
                self?.updateExportProgress(total > 0 ? Double(completed) / Double(total) : 0)
            }
        }

        exportTask = Task.detached {
            do {
                guard let sourceVideoURL else {
                    throw OverlayVideoError.invalidConfiguration("Choose a source video before exporting composited video.")
                }
                try CompositedVideoWriter(
                    outputURL: outputURL,
                    sourceVideoURL: sourceVideoURL,
                    series: series,
                    config: CompositedVideoWriterConfig(
                        width: width,
                        height: height,
                        framesPerSecond: fps,
                        startTime: startTime,
                        duration: duration,
                        averageBitRate: averageBitRate,
                        timeSync: currentTimeSync,
                        codec: currentCodec,
                        overlayLayout: currentLayout,
                        distanceUnit: currentDistanceUnit,
                        activityTrim: currentActivityTrim,
                        progressHandler: progressHandler,
                        cancellationHandler: { cancellationToken.isCancelled }
                    )
                ).write()
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.finishExport(startedAt: exportStartedAt) {
                        self.exportProgress = 1
                        self.lastExportedURL = outputURL
                        self.setStatus("status.wroteFile", outputURL.lastPathComponent)
                    }
                }
            } catch OverlayVideoError.cancelled {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.finishExport(startedAt: exportStartedAt) {
                        self.exportProgress = 0
                        self.lastExportWasCancelled = true
                        self.setStatus("status.exportCancelled")
                    }
                }
            } catch {
                let message = Self.errorDescription(error)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.finishExport(startedAt: exportStartedAt) {
                        self.lastExportErrorMessage = message
                        self.setStatus("status.exportError", message)
                    }
                }
            }
        }
    }

    public func cancelExport() {
        guard isExporting else { return }
        exportCancellationToken?.cancel()
        setStatus("status.cancellingExport")
    }

    private func finishExport(startedAt: Date, _ applyResult: () -> Void) {
        isExporting = false
        exportETASeconds = nil
        lastExportElapsedSeconds = Date().timeIntervalSince(startedAt)
        exportTask = nil
        exportCancellationToken = nil
        applyResult()
        runtimeGuard.exportDidEnd()
        refreshOverlayOnly(coalesceIfBusy: true)
    }

    private func updateExportProgress(_ progress: Double, at date: Date = Date()) {
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

    private func makeUniqueOutputURL() -> URL {
        let baseName: String
        if let videoURL {
            baseName = videoURL.deletingPathExtension().lastPathComponent
        } else if let activityURL {
            baseName = activityURL.deletingPathExtension().lastPathComponent
        } else {
            baseName = "datalayer"
        }
        let suffix = "composited"
        let directory = exportsDirectory
        var candidate = directory.appendingPathComponent("\(baseName)-\(suffix).mov")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix)-\(counter).mov")
            counter += 1
        }
        return candidate
    }

    // MARK: - 偏好与状态

    private func restorePreferences() {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.preferencesKey) else { return }
        if let rawUnit = stored["distanceUnit"] as? String,
           let unit = OverlayDistanceUnit(rawValue: rawUnit) {
            distanceUnit = unit
        }
    }

    private func persistPreferences() {
        UserDefaults.standard.set(["distanceUnit": distanceUnit.rawValue], forKey: Self.preferencesKey)
    }

    private func observeThermalState() {
        thermalStateIsSerious = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let isSerious = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.thermalStateIsSerious = isSerious
            }
        }
    }

    private func setStatus(_ key: String, _ arguments: String...) {
        statusMessage = TouchMessage(key, arguments)
    }

    // MARK: - 工具

    private func finiteTime(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? value : 0
    }

    private func nonNegativeTime(_ value: TimeInterval) -> TimeInterval {
        max(0, finiteTime(value))
    }

    nonisolated private static func sanitizedOutputDimension(_ value: Int) -> Int {
        var sanitized = min(16_384, max(2, value))
        if sanitized % 2 != 0 {
            sanitized -= 1
        }
        return max(2, sanitized)
    }

    nonisolated private static func sanitizedOutputFrameRate(_ value: Double) -> Double {
        guard value.isFinite else { return 30 }
        return min(240, max(1, value))
    }

    nonisolated private static func sanitizedSourceDuration(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, 86_400)
    }

    nonisolated private static func sourceVideoBitRateKbps(from metadata: VideoMetadata) -> Int? {
        guard let bitRate = metadata.bitRateBitsPerSecond, bitRate.isFinite, bitRate > 0 else { return nil }
        let kbps = Int((bitRate / 1000).rounded())
        return min(1_000_000, max(1, kbps))
    }

    nonisolated private static func frameRatesMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.005
    }

    nonisolated private static func errorDescription(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return error.localizedDescription
    }

    nonisolated public static func formatSeconds(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private final class TouchExportCancellationToken: @unchecked Sendable {
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

/// 持有 security-scoped 资源访问权，析构时释放。
/// 应用容器内的文件 `startAccessing` 会返回 false，此时无需持有也能访问。
private final class ScopedResourceAccess {
    private let url: URL
    private let isActive: Bool

    init(url: URL) {
        self.url = url
        self.isActive = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if isActive {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
