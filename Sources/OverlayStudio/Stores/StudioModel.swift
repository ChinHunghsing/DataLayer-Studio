import AppKit
import AVFoundation
import Foundation
import OverlayCore
import UniformTypeIdentifiers

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
    @Published var distanceUnit: OverlayDistanceUnit = .kilometers

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
    @Published var layout: OverlayLayout = .default
    @Published var selectedElementID: String? = OverlayLayout.default.elements.first { $0.kind == .speed }?.id

    @Published var showGrid = false
    @Published var gridColumns = 12
    @Published var gridRows = 8
    @Published var snapGaugeToGrid = false

    @Published var status = "Choose a video and a FIT file."
    @Published var isExporting = false
    @Published var exportProgress = 0.0

    private let videoFrameService = VideoFrameService()
    private let previewRenderer = OverlayPreviewRenderer()
    private var timeObserverToken: Any?
    private var previewRenderGeneration = 0
    private var lastOverlayRefresh = Date.distantPast
    private var draggedElementID: String?

    var canPreview: Bool {
        videoURL != nil && series != nil
    }

    var canExport: Bool {
        canPreview && outputURL != nil && outputWidth > 0 && outputHeight > 0 && outputFPS > 0 && outputDuration > 0 && bitRateKbps > 0
    }

    var selectedElement: OverlayElement? {
        guard let selectedElementID else { return layout.elements.first }
        return layout.elements.first { $0.id == selectedElementID } ?? layout.elements.first
    }

    var timeSync: TelemetryTimeSync {
        switch syncMode {
        case .offset:
            return .legacyOffset(offsetSeconds)
        case .fitStart:
            return TelemetryTimeSync(videoSyncTime: 0, fitSyncTime: fitStartSeconds)
        case .syncPoint:
            return TelemetryTimeSync(videoSyncTime: syncVideoSeconds, fitSyncTime: syncFITSeconds)
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
        let panel = NSOpenPanel()
        panel.title = "Choose source video"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setVideo(url)
    }

    func chooseFIT() {
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
        let panel = NSSavePanel()
        panel.title = "Save transparent overlay video"
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.nameFieldStringValue = "overlay.mov"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
    }

    func applyResolutionPreset(id: String) {
        if id == OutputResolutionPreset.sourceID, let sourceDimensions {
            outputWidth = sourceDimensions.width
            outputHeight = sourceDimensions.height
            return
        }

        guard let preset = OutputResolutionPreset.fixed.first(where: { $0.id == id }) else { return }
        outputWidth = preset.width
        outputHeight = preset.height
    }

    func applyFrameRatePreset(id: String) {
        if id == OutputFrameRatePreset.sourceID, let sourceFrameRate {
            outputFPS = sourceFrameRate
            return
        }

        guard let preset = OutputFrameRatePreset.fixed.first(where: { $0.id == id }) else { return }
        outputFPS = preset.framesPerSecond
    }

    func setVideo(_ url: URL) {
        stopPlayback()
        videoURL = url
        do {
            let loaded = try VideoMetadata.load(from: url)
            metadata = loaded
            outputWidth = max(2, Int(loaded.size.width.rounded()))
            outputHeight = max(2, Int(loaded.size.height.rounded()))
            outputFPS = loaded.framesPerSecond
            outputDuration = loaded.duration
            previewTime = 0
            configurePlayer(url: url)
            status = "Loaded video: \(url.lastPathComponent)"
            refreshPreview()
        } catch {
            status = "Video error: \(error.localizedDescription)"
        }
    }

    func configurePlayer(url: URL) {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }

        let player = AVPlayer(url: url)
        self.player = player
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.10, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let seconds = CMTimeGetSeconds(time)
                guard seconds.isFinite else { return }
                self.previewTime = min(max(0, seconds), max(0, self.outputDuration))
                self.refreshOverlayOnly()
                if self.outputDuration > 0, self.previewTime >= self.outputDuration {
                    self.pausePlayback()
                }
            }
        }
    }

    func togglePlayback() {
        isPlaying ? pausePlayback() : startPlayback()
    }

    func startPlayback() {
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
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        self.player = nil
    }

    func seekPreview(to time: TimeInterval) {
        let clamped = min(max(0, time), max(outputDuration, 0))
        previewTime = clamped
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        refreshPreview()
    }

    func markSportStart() {
        syncMode = .syncPoint
        syncVideoSeconds = previewTime
        syncFITSeconds = 0
        status = "运动开始 set at video \(formatTime(previewTime)); FIT starts at 0.000s."
        refreshPreview()
    }

    func setFIT(_ url: URL) {
        fitURL = url
        do {
            series = try FITParser().parse(url: url)
            status = "Loaded FIT: \(url.lastPathComponent)"
            refreshPreview()
        } catch let error as FITError {
            status = "FIT error: \(error.description)"
        } catch {
            status = "FIT error: \(error.localizedDescription)"
        }
    }

    func refreshPreview() {
        guard draggedElementID == nil else { return }
        guard let videoURL else {
            backgroundImage = nil
            overlayImage = nil
            dragBaseOverlayImage = nil
            return
        }

        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        previewRenderGeneration += 1
        let generation = previewRenderGeneration
        let time = previewTime
        let outputSize = CGSize(width: outputWidth, height: outputHeight)
        let currentSeries = series
        let currentSync = timeSync
        let currentLayout = layout
        let currentDistanceUnit = distanceUnit

        Task.detached { [videoFrameService, previewRenderer] in
            let background = try? videoFrameService.frameImage(videoURL: videoURL, time: time)
            let overlay: NSImage?
            if let currentSeries {
                overlay = try? NSImage(
                    cgImage: previewRenderer.renderOverlayImage(
                        series: currentSeries,
                        size: outputSize,
                        videoTime: time,
                        timeSync: currentSync,
                        layout: currentLayout,
                        distanceUnit: currentDistanceUnit
                    ),
                    size: NSSize(width: outputSize.width, height: outputSize.height)
                )
            } else {
                overlay = nil
            }

            await MainActor.run {
                guard self.previewRenderGeneration == generation else { return }
                self.backgroundImage = background
                self.overlayImage = overlay
            }
        }
    }

    func refreshOverlayOnly(previewSize: CGSize? = nil, minimumInterval: TimeInterval = 0) {
        guard draggedElementID == nil else { return }
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        guard videoURL != nil else {
            overlayImage = nil
            return
        }
        guard let currentSeries = series else {
            overlayImage = nil
            return
        }

        let now = Date()
        if minimumInterval > 0, now.timeIntervalSince(lastOverlayRefresh) < minimumInterval {
            return
        }
        lastOverlayRefresh = now
        previewRenderGeneration += 1
        let generation = previewRenderGeneration

        let time = previewTime
        let renderSize: CGSize
        if let previewSize {
            renderSize = CGSize(
                width: max(2, previewSize.width.rounded()),
                height: max(2, previewSize.height.rounded())
            )
        } else {
            renderSize = CGSize(width: outputWidth, height: outputHeight)
        }
        let currentSync = timeSync
        let currentLayout = layout
        let currentDistanceUnit = distanceUnit

        Task.detached { [previewRenderer] in
            let overlay = try? NSImage(
                cgImage: previewRenderer.renderOverlayImage(
                    series: currentSeries,
                    size: renderSize,
                    videoTime: time,
                    timeSync: currentSync,
                    layout: currentLayout,
                    distanceUnit: currentDistanceUnit
                ),
                size: NSSize(width: renderSize.width, height: renderSize.height)
            )

            await MainActor.run {
                guard self.previewRenderGeneration == generation else { return }
                self.overlayImage = overlay
            }
        }
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

        draggedElementID = id
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        Task.detached { [previewRenderer] in
            let baseOverlay = try? Self.renderOverlayImage(
                previewRenderer: previewRenderer,
                series: currentSeries,
                size: renderSize,
                videoTime: time,
                timeSync: currentSync,
                layout: baseLayout,
                distanceUnit: currentDistanceUnit
            )

            await MainActor.run {
                guard self.previewRenderGeneration == generation else { return }
                self.dragBaseOverlayImage = baseOverlay
            }

            let dragOverlay = try? Self.renderOverlayImage(
                previewRenderer: previewRenderer,
                series: currentSeries,
                size: renderSize,
                videoTime: time,
                timeSync: currentSync,
                layout: dragLayout,
                distanceUnit: currentDistanceUnit
            )

            await MainActor.run {
                guard self.previewRenderGeneration == generation else { return }
                self.dragOverlayImage = dragOverlay
            }
        }
    }

    func endElementDrag() {
        draggedElementID = nil
        overlayImage = nil
        dragBaseOverlayImage = nil
        dragOverlayImage = nil
        refreshOverlayOnly()
    }

    private func sanitizedPreviewSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, size.width.rounded()),
            height: max(2, size.height.rounded())
        )
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

    func addElement(kind: OverlayComponentID) {
        let existingCount = layout.elements.filter { $0.kind == kind }.count
        var element = OverlayElement.defaultElement(kind: kind, id: "\(kind.rawValue)-\(UUID().uuidString)")
        let offset = min(0.20, Double(existingCount) * 0.035)
        element.frame.x = PreviewLayoutLimits.clampPosition(element.frame.x + offset)
        element.frame.y = PreviewLayoutLimits.clampPosition(element.frame.y + offset)
        layout.elements.append(element)
        selectedElementID = element.id
        refreshPreview()
    }

    func duplicateSelectedElement() {
        guard var element = selectedElement else { return }
        element.id = "\(element.kind.rawValue)-\(UUID().uuidString)"
        element.frame.x = PreviewLayoutLimits.clampPosition(element.frame.x + 0.035)
        element.frame.y = PreviewLayoutLimits.clampPosition(element.frame.y + 0.035)
        layout.elements.append(element)
        selectedElementID = element.id
        refreshPreview()
    }

    func deleteSelectedElement() {
        guard let selectedElementID else { return }
        layout.removeElement(id: selectedElementID)
        self.selectedElementID = layout.elements.first?.id
        refreshPreview()
    }

    func updateElement(_ id: String, refreshPreview shouldRefreshPreview: Bool = true, _ update: (inout OverlayElement) -> Void) {
        layout.updateElement(id: id, update)
        if !layout.elements.contains(where: { $0.id == selectedElementID }) {
            selectedElementID = layout.elements.first?.id
        }
        if shouldRefreshPreview {
            refreshOverlayOnly()
        }
    }

    func updateComponent(_ id: OverlayComponentID, _ update: (inout OverlayComponentFrame) -> Void) {
        layout.updateFirstElement(kind: id) { element in
            update(&element.frame)
        }
        refreshPreview()
    }

    func export() {
        if outputURL == nil {
            chooseOutput()
        }
        guard let outputURL, let series else { return }

        isExporting = true
        exportProgress = 0
        status = "Exporting..."

        let config = TransparentVideoWriterConfig(
            width: outputWidth,
            height: outputHeight,
            framesPerSecond: outputFPS,
            duration: outputDuration,
            averageBitRate: bitRateKbps * 1000,
            timeSync: timeSync,
            codec: codec,
            overlayLayout: layout,
            distanceUnit: distanceUnit,
            progressHandler: { [weak self] completed, total in
                Task { @MainActor in
                    self?.exportProgress = Double(completed) / Double(total)
                }
            }
        )

        Task.detached {
            do {
                try TransparentVideoWriter(outputURL: outputURL, series: series, config: config).write()
                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = 1
                    self.status = "Wrote \(outputURL.path)"
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.status = "Export error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        String(format: "%.3f", time)
    }

    private var sourceDimensions: (width: Int, height: Int)? {
        guard let metadata else { return nil }
        return (
            width: max(2, Int(metadata.size.width.rounded())),
            height: max(2, Int(metadata.size.height.rounded()))
        )
    }

    private var sourceFrameRate: Double? {
        guard let metadata else { return nil }
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
}
